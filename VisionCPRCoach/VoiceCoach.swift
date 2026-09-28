import Foundation
import AVFoundation
import Combine

@MainActor
final class VoiceCoach: NSObject, AVSpeechSynthesizerDelegate {
    enum Priority {
        case normal
        case coaching
        case urgent
        case emergency
    }

    private struct QueuedSpeech {
        let text: String
        let priority: Priority
    }

    private let synthesizer = AVSpeechSynthesizer()
    private var queue: [QueuedSpeech] = []
    private var lastSpokenText = ""
    private var lastSpokenTime = Date.distantPast
    private let duplicateCooldown: TimeInterval = 4.0
    private let coachingDuplicateCooldown: TimeInterval = 0.85

    var languageCode: String = "en-US"
    @Published var isSpeaking = false
    /// Called when the synthesizer finishes and the speech queue is empty.
    var onFinishedSpeaking: (() -> Void)?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Queue speech — never cuts off the current utterance unless `stop()` is called.
    func speak(_ text: String, priority: Priority = .normal) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let now = Date()
        let repeatCooldown = (priority == .coaching) ? coachingDuplicateCooldown : duplicateCooldown
        if trimmed == lastSpokenText, now.timeIntervalSince(lastSpokenTime) < repeatCooldown {
            return
        }

        if priority == .coaching || priority == .urgent {
            queue.removeAll { $0.priority == .coaching || $0.priority == .urgent }
        }

        if synthesizer.isSpeaking {
            if let last = queue.last, last.text == trimmed { return }
            queue.append(QueuedSpeech(text: trimmed, priority: priority))
            return
        }

        if queue.contains(where: { $0.text == trimmed }) { return }
        speakNow(trimmed, priority: priority)
    }

    func stop() {
        queue.removeAll()
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isSpeaking = false
            self.dequeueNext()
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isSpeaking = false
            self.notifyIfIdle()
        }
    }

    private func dequeueNext() {
        guard !synthesizer.isSpeaking, !queue.isEmpty else {
            notifyIfIdle()
            return
        }
        let next = queue.removeFirst()
        speakNow(next.text, priority: next.priority)
    }

    private func notifyIfIdle() {
        guard !synthesizer.isSpeaking, queue.isEmpty else { return }
        onFinishedSpeaking?()
    }

    private func speakNow(_ trimmed: String, priority: Priority) {
        configureAudioSessionForSpeech(priority: priority)

        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * rateMultiplier(for: priority)
        utterance.pitchMultiplier = 1.0
        utterance.volume = volume(for: priority)
        if priority == .emergency || priority == .urgent {
            if #available(iOS 17.0, *) {
                utterance.prefersAssistiveTechnologySettings = false
            }
        }
        if priority == .emergency {
            utterance.preUtteranceDelay = 0
            utterance.postUtteranceDelay = 0
        } else {
            utterance.preUtteranceDelay = 0.04
            utterance.postUtteranceDelay = 0.06
        }

        if let voice = AVSpeechSynthesisVoice(language: languageCode) {
            utterance.voice = voice
        } else if let fallback = AVSpeechSynthesisVoice(language: String(languageCode.prefix(2))) {
            utterance.voice = fallback
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        }

        lastSpokenText = trimmed
        lastSpokenTime = Date()
        isSpeaking = true
        synthesizer.speak(utterance)
    }

    private func rateMultiplier(for priority: Priority) -> Float {
        switch priority {
        case .emergency: return 0.92
        case .urgent: return 0.90
        case .coaching: return 0.88
        case .normal: return 0.86
        }
    }

    private func volume(for priority: Priority) -> Float {
        switch priority {
        case .emergency: return 1.0
        case .urgent: return 0.95
        case .coaching: return 0.9
        case .normal: return 0.72
        }
    }

    private func configureAudioSessionForSpeech(priority: Priority) {
        let session = AVAudioSession.sharedInstance()
        do {
            // Playback through the speaker is louder than playAndRecord (used when the mic is open).
            // Emergency switches back to playAndRecord in SpeechRecognitionManager after TTS finishes.
            let mode: AVAudioSession.Mode
            if #available(iOS 16.0, *) {
                mode = (priority == .emergency || priority == .urgent) ? .voicePrompt : .spokenAudio
            } else {
                mode = .spokenAudio
            }
            try session.setCategory(.playback, mode: mode, options: [.duckOthers, .defaultToSpeaker])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            try session.overrideOutputAudioPort(.speaker)
        } catch {
            print("VoiceCoach audio session error: \(error)")
        }
    }
}
