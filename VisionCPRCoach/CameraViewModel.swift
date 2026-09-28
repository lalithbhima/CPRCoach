import Foundation
import SwiftUI
import AVFoundation
import Vision
import ARKit
import CoreVideo

@MainActor
final class CameraViewModel: NSObject, ObservableObject {
    let session = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "camera.session.queue")
    private let analysisQueue = DispatchQueue(label: "camera.analysis.queue")

    private let videoOutput = AVCaptureVideoDataOutput()
    private let sceneAnalyzer = MultiPersonPoseAnalyzer()
    private let metricsEngine = CPRMetricsEngine()
    private let actionEngine = CPRActionRecognitionEngine()
    private let responseEngine = RealTimeCPRResponseEngine()
    private let depth3DEstimator = CompressionDepth3DEstimator()
    private let lidarDepthSession = LiDARDepthSession()
    let voiceCoach = VoiceCoach()

    @Published var feedbackMessage: String = LanguageManager.shared.text("ready_begin")
    @Published var elbowAngle: Double = 0
    @Published var compressionsPerMinute: Double = 0
    @Published var handPlacement: String = HandPlacement.unknown.rawValue
    @Published var motionAmplitude: Double = 0
    @Published var estimatedDepthCm: Double = 0
    @Published var depthQuality: DepthEstimate = .unknown
    @Published var recoilQuality: RecoilQuality = .unknown
    @Published var overallQuality: CompressionQuality = .unknown
    @Published var pressureScore: Double = 0
    @Published var confidence: Double = 0
    @Published var isRunning: Bool = false
    @Published var flowState: CPRFlowState = .ready
    @Published var latestJoints: BodyJoints?
    @Published var overlayJoints: BodyJoints?
    @Published var latestMetrics: CPRMetrics?
    @Published var sceneAnalysis: CPRSceneAnalysis?
    @Published var actionResult: ActionRecognitionResult = .idle
    @Published var showAROverlay: Bool = true
    @Published var rhythmPhase: Double = 0
    @Published var lidarAvailable: Bool = LiDARDepthSession.isSupported
    @Published var lidarDepthActive: Bool = false
    @Published var usesARCameraPipeline: Bool = false
    @Published var detectionQuality: Double = 0
    @Published var aiModelActive: Bool = false

    lazy var emergencyFlow = EmergencyFlowEngine(voiceCoach: voiceCoach)
    lazy var aiCoach = AICoachService()
    lazy var voiceEngine = VoiceResponseEngine(voiceCoach: voiceCoach)
    lazy var speechRecognition = SpeechRecognitionManager()
    let sessionRecorder = CPRSessionRecorder()
    let progressStore = CPRProgressStore.shared

    private var lastSpokenFeedback = ""
    private var coachingVoiceUnlocked = false

    /// ARSession used for LiDAR depth + camera on Pro devices (read-only for views).
    var arSession: ARSession? { lidarDepthSession.session }

    func configure() {
        syncLanguage()
        aiModelActive = MoveNetPoseEstimator.shared.isModelLoaded
        metricsEngine.setCalibration(AppConfig.loadCalibration())
        checkCameraPermission()
        speechRecognition.requestAuthorization()
        emergencyFlow.setLiveContext { [weak self] in
            (self?.latestMetrics, self?.latestJoints)
        }

        usesARCameraPipeline = LiDARDepthSession.isSupported

        if usesARCameraPipeline {
            configureLiDARPipeline()
        } else {
            configureCaptureSession()
        }
    }

    private func configureLiDARPipeline() {
        lidarDepthSession.onFrame = { [weak self] frame in
            self?.handleARFrame(frame)
        }
        lidarDepthSession.start()
    }

    private func configureCaptureSession() {
        sessionQueue.async {
            self.session.beginConfiguration()
            self.session.sessionPreset = .high

            guard
                let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                let input = try? AVCaptureDeviceInput(device: device),
                self.session.canAddInput(input)
            else {
                print("Could not create camera input.")
                return
            }

            if self.session.inputs.isEmpty {
                self.session.addInput(input)
            }

            if self.session.outputs.isEmpty, self.session.canAddOutput(self.videoOutput) {
                self.videoOutput.setSampleBufferDelegate(self, queue: self.analysisQueue)
                self.videoOutput.alwaysDiscardsLateVideoFrames = true
                self.session.addOutput(self.videoOutput)
            }

            // NOTE: do NOT rotate the data-output connection. MoveNet (and the Vision fallback)
            // expect the native landscape buffer and rotate once via .oriented(.right). Forcing
            // .portrait here double-rotates the frame and wrecks joint detection/alignment.

            self.session.commitConfiguration()

            if !self.session.isRunning {
                self.session.startRunning()
            }
        }
    }

    func updateARViewportSize(_ size: CGSize) {
        arViewportSize = size
    }

    private nonisolated func handleARFrame(_ frame: ARFrame) {
        Task { @MainActor in
            self.latestARFrame = frame
            self.lidarDepthActive = frame.smoothedSceneDepth != nil || frame.sceneDepth != nil
        }

        guard Int(frame.timestamp * 30) % 2 == 0 else { return }
        guard let portrait = MoveNetCameraFrame.makePortraitBuffer(from: frame.capturedImage) else { return }

        sceneAnalyzer.processPortraitBuffer(portrait) { [weak self] scene in
            guard let self else { return }
            Task { @MainActor in
                self.processScene(scene)
            }
        }
    }

    func syncLanguage() {
        let lang = LanguageManager.shared
        voiceCoach.languageCode = lang.voiceLanguageCode
        speechRecognition.localeIdentifier = lang.resolvedSpeechCode
    }

    func refreshLocalizedStrings() {
        if isRunning {
            feedbackMessage = LanguageManager.shared.text("detecting")
        } else if flowState == .paused {
            feedbackMessage = LanguageManager.shared.text("session_stopped")
        } else {
            feedbackMessage = LanguageManager.shared.text("ready_begin")
        }
    }

    func startSession() {
        metricsEngine.reset()
        actionEngine.reset()
        responseEngine.reset()
        depth3DEstimator.reset()
        actionResult = .idle
        lastSpokenFeedback = ""
        coachingVoiceUnlocked = false
        sessionRecorder.start()

        isRunning = true
        flowState = .activeCoaching
        emergencyFlow.flowState = .activeCoaching
        sceneAnalyzer.resetTracking()
        feedbackMessage = LanguageManager.shared.text("searching_people")
        voiceEngine.isVoiceEnabled = true
        voiceEngine.lastSpokenText = ""
    }

    func stopSession() {
        if let saved = sessionRecorder.finish(calibration: AppConfig.loadCalibration()) {
            progressStore.add(saved)
        }

        isRunning = false
        flowState = .paused
        coachingVoiceUnlocked = false
        feedbackMessage = LanguageManager.shared.text("session_stopped")
        metricsEngine.reset()
        actionEngine.reset()
        responseEngine.reset()
        depth3DEstimator.reset()
        overlayJoints = nil
        latestJoints = nil
        actionResult = .idle
        voiceCoach.stop()
    }

    func resetFlow() {
        flowState = .ready
        coachingVoiceUnlocked = false
        feedbackMessage = LanguageManager.shared.text("ready_begin")
        elbowAngle = 0
        compressionsPerMinute = 0
        handPlacement = HandPlacement.unknown.rawValue
        motionAmplitude = 0
        estimatedDepthCm = 0
        depthQuality = .unknown
        recoilQuality = .unknown
        overallQuality = .unknown
        pressureScore = 0
        confidence = 0
        latestJoints = nil
        overlayJoints = nil
        latestMetrics = nil
        actionResult = .idle
        metricsEngine.reset()
        actionEngine.reset()
        responseEngine.reset()
        depth3DEstimator.reset()
        voiceCoach.stop()
        emergencyFlow.reset()
    }

    func calibrate(with metrics: CPRMetrics) {
        var profile = AppConfig.loadCalibration()
        profile.baselineAmplitude = max(metrics.motionAmplitude, 0.02)
        profile.baselineDepthCm = max(metrics.estimatedDepthCm, 5.0)
        profile.isCalibrated = true
        AppConfig.saveCalibration(profile)
        metricsEngine.setCalibration(profile)
        progressStore.addCalibration(profile: profile, metrics: metrics)
        feedbackMessage = LanguageManager.shared.text("calibration_saved")
        voiceCoach.speak(feedbackMessage, priority: .coaching)
    }

    func bindSpeechToEmergencyFlow() {
        speechRecognition.onFinalTranscript = { [weak self] text in
            self?.emergencyFlow.processVoiceInput(text)
        }
    }

    func toggleEmergencyVoiceAI() {
        emergencyFlow.toggleVoiceAI(speech: speechRecognition)
    }

    private func checkCameraPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                print("Camera permission granted: \(granted)")
            }
        case .denied, .restricted:
            print("Camera permission denied or restricted.")
        @unknown default:
            break
        }
    }

    private func processScene(_ scene: CPRSceneAnalysis) {
        sceneAnalysis = scene
        detectionQuality = scene.detectionQuality

        if let joints = scene.rescuerJoints {
            latestJoints = joints
            overlayJoints = joints
        } else if !isRunning {
            latestJoints = nil
            overlayJoints = nil
        }

        guard isRunning else { return }

        guard scene.isReadyForCoaching else {
            actionResult = .idle
            updateDetectionStatusMessage(scene: scene)
            return
        }

        unlockCoachingVoiceIfNeeded()

        guard let joints = scene.rescuerJoints ?? latestJoints else {
            actionResult = .idle
            feedbackMessage = LanguageManager.shared.text("detecting")
            return
        }

        let lidarDepth = lidarDepthCm(from: scene)
        let metrics = metricsEngine.update(with: joints, lidarDepthCm: lidarDepth, patient: scene.patient)
        processLiveCoaching(joints: joints, metrics: metrics, scene: scene)
    }

    private func updateDetectionStatusMessage(scene: CPRSceneAnalysis) {
        let hasRescuer = scene.overlayRescuer != nil
        let hasPatient = scene.patient != nil

        if !hasRescuer && !hasPatient {
            feedbackMessage = LanguageManager.shared.text("searching_people")
        } else if hasRescuer && !hasPatient {
            feedbackMessage = LanguageManager.shared.text("rescuer_detected")
        } else if hasPatient && !hasRescuer {
            feedbackMessage = LanguageManager.shared.text("patient_detected")
        } else {
            feedbackMessage = LanguageManager.shared.text("point_camera")
        }
    }

    private func unlockCoachingVoiceIfNeeded() {
        guard !coachingVoiceUnlocked else { return }
        coachingVoiceUnlocked = true
        let startMsg = LanguageManager.shared.text("coaching_started")
        feedbackMessage = startMsg
        voiceEngine.lastSpokenText = startMsg
        lastSpokenFeedback = startMsg
        voiceCoach.speak(startMsg, priority: .coaching)
    }

    /// True when the rescuer wrist midpoint and both wrists are inside the green chest target.
    private func wristsOnChestTarget(joints: BodyJoints, patient: PatientDetection?) -> Bool {
        guard let patient else { return false }

        let box = patient.boundingBox.insetBy(dx: -0.02, dy: -0.02)
        let wristMid = CGPoint(
            x: (joints.leftWrist.x + joints.rightWrist.x) / 2,
            y: (joints.leftWrist.y + joints.rightWrist.y) / 2
        )

        return box.contains(wristMid)
            && box.contains(joints.leftWrist)
            && box.contains(joints.rightWrist)
    }

    /// ARKit/LiDAR depth when an ARFrame is available (iPhone Pro). Falls back to 2D motion otherwise.
    private func lidarDepthCm(from scene: CPRSceneAnalysis) -> Double? {
        guard lidarAvailable,
              lidarDepthActive,
              let frame = latestARFrame,
              let patient = scene.patient,
              let joints = scene.rescuerJoints
        else { return nil }

        let viewport = arViewportSize
        guard viewport.width > 0, viewport.height > 0 else { return nil }

        let wristMid = CGPoint(
            x: (joints.leftWrist.x + joints.rightWrist.x) / 2,
            y: (joints.leftWrist.y + joints.rightWrist.y) / 2
        )

        // Vision bottom-left → UIKit screen (top-left) for ARKit hit testing.
        let sternumScreen = CGPoint(
            x: patient.sternumPoint.x * viewport.width,
            y: (1.0 - patient.sternumPoint.y) * viewport.height
        )
        let wristScreen = CGPoint(
            x: wristMid.x * viewport.width,
            y: (1.0 - wristMid.y) * viewport.height
        )

        return depth3DEstimator.update(
            frame: frame,
            sternumPoint2D: CGPoint(
                x: sternumScreen.x / viewport.width,
                y: sternumScreen.y / viewport.height
            ),
            wristMid2D: CGPoint(
                x: wristScreen.x / viewport.width,
                y: wristScreen.y / viewport.height
            ),
            viewportSize: viewport
        )
    }

    /// Optional ARSession feed for LiDAR depth (set when AR coaching view is active).
    var latestARFrame: ARFrame?
    var arViewportSize: CGSize = .zero

    private func processLiveCoaching(joints: BodyJoints, metrics: CPRMetrics, scene: CPRSceneAnalysis) {
        guard coachingVoiceUnlocked, scene.isReadyForCoaching else { return }

        let action = actionEngine.recognize(scene: scene, metrics: metrics, joints: joints)
        actionResult = action

        let response = responseEngine.response(
            joints: joints,
            metrics: metrics,
            scene: scene,
            action: action
        )

        let message = LanguageManager.shared.text(response.messageKey)

        latestMetrics = metrics
        elbowAngle = metrics.elbowAngle
        compressionsPerMinute = metrics.compressionsPerMinute
        handPlacement = metrics.handPlacement.rawValue
        motionAmplitude = metrics.motionAmplitude
        estimatedDepthCm = metrics.estimatedDepthCm
        depthQuality = metrics.depthQuality
        recoilQuality = metrics.recoilQuality
        overallQuality = metrics.overallQuality
        pressureScore = metrics.pressureScore
        confidence = metrics.confidence
        feedbackMessage = message

        updateRhythmPhase(cpm: metrics.compressionsPerMinute)

        voiceEngine.processLiveFrame(joints: joints, metrics: metrics, scene: scene)

        if response.shouldSpeak {
            voiceCoach.speak(message, priority: response.isPacingCue ? .coaching : .urgent)
            voiceEngine.lastSpokenText = message
            lastSpokenFeedback = message
        }

        let handsOnTarget = JointCPRCoachAnalyzer.snapshot(joints: joints, patient: scene.patient).isOnChestZone
        sessionRecorder.record(metrics: metrics, handsOnTarget: handsOnTarget)
    }

    private func updateRhythmPhase(cpm: Double) {
        guard cpm > 0 else {
            rhythmPhase = 0
            return
        }
        let beatsPerSecond = cpm / 60.0
        rhythmPhase = (Date().timeIntervalSince1970 * beatsPerSecond).truncatingRemainder(dividingBy: 1.0)
    }
}

extension CameraViewModel: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        sceneAnalyzer.processFrame(sampleBuffer) { [weak self] scene in
            guard let self else { return }

            Task { @MainActor in
                self.processScene(scene)
            }
        }
    }
}
