import Foundation
import Speech
import AVFoundation

@MainActor
final class SpeechRecognitionManager: ObservableObject {
    @Published var transcript = ""
    @Published var isListening = false
    @Published var authorizationStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined
    @Published private(set) var activeLocaleIdentifier: String = "en-US"
    @Published private(set) var isRecognizerReady = false

    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    private var pauseToEndSeconds: TimeInterval?
    private var lastTranscriptChange = Date.distantPast
    private var hasReceivedSpeech = false
    private var utteranceDelivered = false
    private var silenceMonitorTask: Task<Void, Never>?
    private var pendingListenPauseSeconds: TimeInterval?
    private var pendingListenReuseSession = false
    private var hasMicPermission = false

    var localeIdentifier: String = "en-US" {
        didSet { configureRecognizer(for: localeIdentifier) }
    }

    var onFinalTranscript: ((String) -> Void)?

    init() {
        configureRecognizer(for: localeIdentifier)
        refreshMicPermission()
    }

    private func configureRecognizer(for identifier: String) {
        activeLocaleIdentifier = identifier
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: identifier))
        isRecognizerReady = speechRecognizer?.isAvailable == true
    }

    func requestAuthorization() {
        requestSpeechAuthorization()
        requestMicrophoneAccess()
    }

    /// Ensures speech + microphone access before the first listen.
    func ensurePermissions() async -> Bool {
        if authorizationStatus == .notDetermined {
            await requestSpeechAuthorizationAsync()
        }
        if !hasMicPermission {
            await requestMicrophoneAccessAsync()
        }
        return authorizationStatus == .authorized && hasMicPermission
    }

    private func requestSpeechAuthorization() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            Task { @MainActor in
                guard let self else { return }
                self.authorizationStatus = status
                self.resumePendingListenIfReady()
            }
        }
    }

    private func requestSpeechAuthorizationAsync() async {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { [weak self] status in
                Task { @MainActor in
                    self?.authorizationStatus = status
                    continuation.resume()
                }
            }
        }
    }

    private func requestMicrophoneAccess() {
        AVAudioApplication.requestRecordPermission { [weak self] granted in
            Task { @MainActor in
                self?.hasMicPermission = granted
                self?.resumePendingListenIfReady()
            }
        }
    }

    private func requestMicrophoneAccessAsync() async {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { [weak self] granted in
                Task { @MainActor in
                    self?.hasMicPermission = granted
                    continuation.resume()
                }
            }
        }
    }

    private func refreshMicPermission() {
        hasMicPermission = AVAudioApplication.shared.recordPermission == .granted
    }

    private func resumePendingListenIfReady() {
        guard let pause = pendingListenPauseSeconds else { return }
        guard authorizationStatus == .authorized, hasMicPermission else { return }
        pendingListenPauseSeconds = nil
        let reuse = pendingListenReuseSession
        pendingListenReuseSession = false
        startListening(pauseToEndSeconds: pause, reuseSession: reuse)
    }

    /// Pre-configure the shared play-and-record session used during emergency voice turns.
    func prepareListeningSession() {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(
                .playAndRecord,
                mode: .voiceChat,
                options: [.duckOthers, .defaultToSpeaker, .allowBluetooth]
            )
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("Audio session prepare error: \(error)")
        }
    }

    /// Stop capture for TTS without tearing down the audio session (faster resume).
    func pauseForSpeech() {
        cancelSilenceMonitor()
        pauseToEndSeconds = nil

        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        isListening = false
    }

    /// Start listening. When `pauseToEndSeconds` is set (e.g. 3), a pause that long after speech
    /// ends the utterance and fires `onFinalTranscript`.
    func startListening(pauseToEndSeconds: TimeInterval? = nil, reuseSession: Bool = false) {
        guard !isListening else { return }

        refreshMicPermission()

        guard authorizationStatus == .authorized, hasMicPermission else {
            pendingListenPauseSeconds = pauseToEndSeconds
            pendingListenReuseSession = reuseSession
            requestAuthorization()
            return
        }

        guard let speechRecognizer, speechRecognizer.isAvailable else {
            print("Speech recognizer unavailable for \(activeLocaleIdentifier)")
            return
        }

        pendingListenPauseSeconds = nil
        pendingListenReuseSession = false

        if reuseSession {
            pauseForSpeech()
        } else {
            stopListening()
        }

        self.pauseToEndSeconds = pauseToEndSeconds
        utteranceDelivered = false
        hasReceivedSpeech = false
        lastTranscriptChange = Date()
        transcript = ""

        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(
                .playAndRecord,
                mode: .voiceChat,
                options: [.duckOthers, .defaultToSpeaker, .allowBluetooth]
            )
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            try audioSession.overrideOutputAudioPort(.speaker)
        } catch {
            print("Audio session error: \(error)")
            return
        }

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest else { return }
        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.taskHint = .confirmation
        if speechRecognizer.supportsOnDeviceRecognition {
            recognitionRequest.requiresOnDeviceRecognition = true
        }

        let inputNode = audioEngine.inputNode
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    let updated = result.bestTranscription.formattedString
                    if updated != self.transcript {
                        self.transcript = updated
                        self.lastTranscriptChange = Date()
                        if !updated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            self.hasReceivedSpeech = true
                        }
                    }
                    if result.isFinal {
                        self.deliverTranscript(self.transcript)
                    }
                }
                if error != nil {
                    self.deliverTranscript(self.transcript)
                }
            }
        }

        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 512, format: format) { buffer, _ in
            recognitionRequest.append(buffer)
        }

        do {
            audioEngine.prepare()
            try audioEngine.start()
            isListening = true
            startSilenceMonitorIfNeeded()
        } catch {
            stopListening()
        }
    }

    func stopListening() {
        cancelSilenceMonitor()
        pauseToEndSeconds = nil
        pendingListenPauseSeconds = nil
        pendingListenReuseSession = false

        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        isListening = false

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func startSilenceMonitorIfNeeded() {
        cancelSilenceMonitor()
        guard let pause = pauseToEndSeconds, pause > 0 else { return }

        silenceMonitorTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard let self, self.isListening, !self.utteranceDelivered else { continue }
                guard self.hasReceivedSpeech else { continue }

                let silence = Date().timeIntervalSince(self.lastTranscriptChange)
                if silence >= pause {
                    self.deliverTranscript(self.transcript)
                    break
                }
            }
        }
    }

    private func cancelSilenceMonitor() {
        silenceMonitorTask?.cancel()
        silenceMonitorTask = nil
    }

    private func deliverTranscript(_ text: String) {
        guard !utteranceDelivered else { return }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        utteranceDelivered = true
        cancelSilenceMonitor()
        stopListening()
        onFinalTranscript?(trimmed)
    }
}
