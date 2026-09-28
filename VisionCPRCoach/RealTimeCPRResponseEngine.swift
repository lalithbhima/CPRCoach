import Foundation
import CoreGraphics

struct CPRCoachResponse {
    let messageKey: String
    let priority: Int
    let shouldSpeak: Bool
    let isPacingCue: Bool
    let isRepeatCorrection: Bool
    let isCompressionMetric: Bool
    let allowsContinuousRepeat: Bool

    init(
        messageKey: String,
        priority: Int,
        shouldSpeak: Bool,
        isPacingCue: Bool,
        isRepeatCorrection: Bool,
        isCompressionMetric: Bool = false,
        allowsContinuousRepeat: Bool = false
    ) {
        self.messageKey = messageKey
        self.priority = priority
        self.shouldSpeak = shouldSpeak
        self.isPacingCue = isPacingCue
        self.isRepeatCorrection = isRepeatCorrection
        self.isCompressionMetric = isCompressionMetric
        self.allowsContinuousRepeat = allowsContinuousRepeat
    }
}

/// Sequential setup (hands → elbows → hips → wrist stack) then live rate/depth + posture monitoring.
final class RealTimeCPRResponseEngine {

    private enum SetupStep {
        case centerHands
        case straightElbows
        case hipPosition
        case wristOverlap
        case complete
    }

    private enum IssueID: String {
        case placement
        case elbows
        case hipsHigh
        case hipsLow
        case wristsApart
        case speedSlow
        case speedFast
        case depthShallow
        case depthDeep
    }

    private struct LiveIssue {
        let id: IssueID
        let messageKey: String
        let repeatKey: String
        let priority: Int
        let firstThresholdMet: Bool
        let repeatThresholdMet: Bool
    }

    private var lastMessageKey: String = ""
    private var lastMessageTime: Date = .distantPast
    private var setupStep: SetupStep = .centerHands
    private var setupStartedAt: Date?
    private var stepStableFrames: Int = 0
    private var placementLocked = false

    private var issueStableFrames: Int = 0
    private var issueClearFrames: Int = 0
    private var trackedIssueID: IssueID?
    private var spokenIssueIDs: Set<IssueID> = []
    private var lastSpokenTimeByIssue: [IssueID: Date] = [:]

    private let maxSetupDuration: TimeInterval = 12.0
    private let setupStableRequired = 3

    private let compressIssueStableRequired = 3
    private let compressIssueRepeatStableRequired = 5
    private let compressCorrectionCooldown: TimeInterval = 2.8
    private let compressRepeatCooldown: TimeInterval = 4.5
    private let goodFormCooldown: TimeInterval = 2.2

    private let livePostureStableRequired = 3
    private let livePostureRepeatStableRequired = 5
    private let livePostureCooldown: TimeInterval = 2.8
    private let livePostureRepeatCooldown: TimeInterval = 4.5

    private let issueClearRequired = 10

    var isSetupComplete: Bool { setupStep == .complete }

    func reset() {
        lastMessageKey = ""
        lastMessageTime = .distantPast
        setupStep = .centerHands
        setupStartedAt = nil
        stepStableFrames = 0
        placementLocked = false
        issueStableFrames = 0
        issueClearFrames = 0
        trackedIssueID = nil
        spokenIssueIDs = []
        lastSpokenTimeByIssue = [:]
    }

    func response(
        joints: BodyJoints,
        metrics: CPRMetrics,
        scene: CPRSceneAnalysis,
        action: ActionRecognitionResult
    ) -> CPRCoachResponse {
        _ = action
        let now = Date()

        guard scene.isReadyForCoaching, scene.overlayRescuer != nil, scene.patient != nil else {
            return silentHold()
        }

        let candidate = chooseBestCue(
            joints: joints,
            metrics: metrics,
            scene: scene
        )

        guard candidate.shouldSpeak else {
            return candidate
        }

        let cooldown: TimeInterval
        if candidate.isPacingCue {
            cooldown = goodFormCooldown
        } else if candidate.isCompressionMetric {
            cooldown = candidate.isRepeatCorrection ? compressRepeatCooldown : compressCorrectionCooldown
        } else if candidate.allowsContinuousRepeat {
            cooldown = candidate.isRepeatCorrection ? livePostureRepeatCooldown : livePostureCooldown
        } else if candidate.isRepeatCorrection {
            cooldown = livePostureRepeatCooldown
        } else {
            cooldown = livePostureCooldown
        }

        let enoughTimePassed = now.timeIntervalSince(lastMessageTime) >= cooldown
        let changedMessage = candidate.messageKey != lastMessageKey

        let shouldSpeak: Bool
        if candidate.isPacingCue || candidate.isCompressionMetric || candidate.allowsContinuousRepeat {
            shouldSpeak = enoughTimePassed
        } else if candidate.isRepeatCorrection {
            shouldSpeak = enoughTimePassed
        } else {
            shouldSpeak = enoughTimePassed && changedMessage
        }

        if shouldSpeak {
            lastMessageKey = candidate.messageKey
            lastMessageTime = now
        }

        return CPRCoachResponse(
            messageKey: candidate.messageKey,
            priority: candidate.priority,
            shouldSpeak: shouldSpeak,
            isPacingCue: candidate.isPacingCue,
            isRepeatCorrection: candidate.isRepeatCorrection,
            isCompressionMetric: candidate.isCompressionMetric,
            allowsContinuousRepeat: candidate.allowsContinuousRepeat
        )
    }

    private func chooseBestCue(
        joints: BodyJoints,
        metrics: CPRMetrics,
        scene: CPRSceneAnalysis
    ) -> CPRCoachResponse {

        let visibility = min(scene.detectionQuality, metrics.confidence)
        let snapshot = JointCPRCoachAnalyzer.snapshot(joints: joints, patient: scene.patient)

        if visibility < 0.20 {
            return issueCorrection(
                LiveIssue(
                    id: .placement,
                    messageKey: "adjust_camera",
                    repeatKey: "adjust_camera",
                    priority: 100,
                    firstThresholdMet: true,
                    repeatThresholdMet: true
                ),
                compressionMetric: false
            )
        }

        if setupStep != .complete {
            return setupCue(joints: joints, snapshot: snapshot, scene: scene)
        }

        return liveCoachingCue(joints: joints, metrics: metrics, snapshot: snapshot, scene: scene)
    }

    // MARK: - Setup (quick sequential checks)

    private func setupCue(
        joints: BodyJoints,
        snapshot: JointCPRCoachAnalyzer.JointSnapshot,
        scene: CPRSceneAnalysis
    ) -> CPRCoachResponse {
        if setupStartedAt == nil {
            setupStartedAt = Date()
        }

        let elapsed = Date().timeIntervalSince(setupStartedAt ?? Date())

        switch setupStep {
        case .centerHands:
            if snapshot.isOnChestZone {
                stepStableFrames += 1
                if stepStableFrames >= setupStableRequired {
                    placementLocked = true
                    setupStep = .straightElbows
                    stepStableFrames = 0
                    return speakOnce("setup_position_correct", priority: 98)
                }
                return silentHold()
            }

            stepStableFrames = 0
            if let direction = JointCPRCoachAnalyzer.directionalPlacementHint(
                joints: joints,
                patient: scene.patient
            ) {
                return issueCorrection(livePlacementIssue(for: direction), compressionMetric: false)
            }

            if elapsed > 1.0, scene.patient != nil {
                return issueCorrection(
                    LiveIssue(
                        id: .placement,
                        messageKey: "move_hands_center",
                        repeatKey: "move_hands_center",
                        priority: 92,
                        firstThresholdMet: true,
                        repeatThresholdMet: true
                    ),
                    compressionMetric: false
                )
            }

            return silentHold()

        case .straightElbows:
            if snapshot.minElbowAngle >= CPRGuidelines.setupElbowAngleMin {
                stepStableFrames += 1
                if stepStableFrames >= setupStableRequired {
                    setupStep = .hipPosition
                    stepStableFrames = 0
                    return silentHold()
                }
                return silentHold()
            }

            stepStableFrames = 0
            if elapsed >= maxSetupDuration {
                setupStep = .hipPosition
                return silentHold()
            }

            return issueCorrection(liveElbowIssue(snapshot: snapshot), compressionMetric: false)

        case .hipPosition:
            if snapshot.hipPosture == nil {
                stepStableFrames += 1
                if stepStableFrames >= setupStableRequired {
                    setupStep = .wristOverlap
                    stepStableFrames = 0
                    return silentHold()
                }
                return silentHold()
            }

            stepStableFrames = 0
            if let hipIssue = liveHipIssue(snapshot: snapshot) {
                return issueCorrection(hipIssue, compressionMetric: false)
            }

            if elapsed >= maxSetupDuration {
                setupStep = .wristOverlap
                return silentHold()
            }

            return silentHold()

        case .wristOverlap:
            if JointCPRCoachAnalyzer.wristsStackedForSetup(joints: joints) {
                stepStableFrames += 1
                if stepStableFrames >= setupStableRequired {
                    setupStep = .complete
                    return speakOnce("setup_begin_compress", priority: 98)
                }
                return silentHold()
            }

            stepStableFrames = 0
            if elapsed >= maxSetupDuration, snapshot.isOnChestZone {
                setupStep = .complete
                return speakOnce("setup_begin_compress", priority: 98)
            }

            return issueCorrection(liveWristStackIssue(snapshot: snapshot, joints: joints), compressionMetric: false)

        case .complete:
            break
        }

        return silentHold()
    }

    // MARK: - Live CPR

    private func liveCoachingCue(
        joints: BodyJoints,
        metrics: CPRMetrics,
        snapshot: JointCPRCoachAnalyzer.JointSnapshot,
        scene: CPRSceneAnalysis
    ) -> CPRCoachResponse {

        if isActivelyCompressing(metrics),
           let metric = evaluateCompressionMetricIssue(metrics: metrics) {
            trackIssuePresence(metric.id)
            return issueCorrection(metric, compressionMetric: true, livePhase: true)
        }

        if let posture = evaluatePostureIssue(joints: joints, snapshot: snapshot, scene: scene) {
            trackIssuePresence(posture.id)
            return issueCorrection(posture, compressionMetric: false, livePhase: true)
        }

        trackIssueCleared()
        lastTrackedIssueClearedForPacing()

        if isActivelyCompressing(metrics) {
            return goodPacingCue()
        }

        if snapshot.isOnChestZone {
            return keepCompressingCue()
        }

        return silentHold()
    }

    private func isActivelyCompressing(_ metrics: CPRMetrics) -> Bool {
        metrics.compressionActive || metrics.compressionsPerMinute >= 10
    }

    private func evaluatePostureIssue(
        joints: BodyJoints,
        snapshot: JointCPRCoachAnalyzer.JointSnapshot,
        scene: CPRSceneAnalysis
    ) -> LiveIssue? {
        if placementLocked,
           let drastic = JointCPRCoachAnalyzer.drasticMisplacement(joints: joints, patient: scene.patient) {
            return livePlacementIssue(for: drastic)
        }

        if snapshot.minElbowAngle < CPRGuidelines.targetElbowAngleMin {
            return liveElbowIssue(snapshot: snapshot)
        }

        if let hip = liveHipIssue(snapshot: snapshot) {
            return hip
        }

        if snapshot.wristStack == .tooFarApart {
            return liveWristStackIssue(snapshot: snapshot, joints: joints)
        }

        return nil
    }

    private func evaluateCompressionMetricIssue(metrics: CPRMetrics) -> LiveIssue? {
        guard isActivelyCompressing(metrics) else { return nil }

        let handsCentered = metrics.handPlacement == .centered
        let depthReady = metrics.depthConfidence >= 0.40 && handsCentered
        let rateReady = metrics.rateConfidence >= 0.40
            || (metrics.compressionActive && metrics.compressionsPerMinute >= 10)

        if depthReady,
           metrics.depthQuality == .tooShallow,
           metrics.estimatedDepthCm > 0,
           metrics.estimatedDepthCm < CPRGuidelines.depthCoachBelowMinCm {
            return LiveIssue(
                id: .depthShallow,
                messageKey: "push_deeper",
                repeatKey: "still_push_deeper",
                priority: 82,
                firstThresholdMet: true,
                repeatThresholdMet: metrics.estimatedDepthCm < CPRGuidelines.depthCoachBelowMinCm - 0.3
            )
        }

        if depthReady,
           (metrics.depthQuality == .tooDeep || metrics.estimatedDepthCm > CPRGuidelines.depthCoachAboveMaxCm),
           metrics.estimatedDepthCm > CPRGuidelines.depthCoachAboveMaxCm {
            return LiveIssue(
                id: .depthDeep,
                messageKey: "push_lighter",
                repeatKey: "still_push_lighter",
                priority: 80,
                firstThresholdMet: true,
                repeatThresholdMet: metrics.estimatedDepthCm > CPRGuidelines.depthCoachAboveMaxCm + 0.3
            )
        }

        if rateReady,
           metrics.compressionsPerMinute >= 10,
           metrics.compressionsPerMinute < CPRGuidelines.rateCoachBelowMin {
            return LiveIssue(
                id: .speedSlow,
                messageKey: "push_faster",
                repeatKey: "still_push_faster",
                priority: 78,
                firstThresholdMet: true,
                repeatThresholdMet: metrics.compressionsPerMinute < CPRGuidelines.rateCoachBelowMin - 5
            )
        }

        if rateReady,
           metrics.compressionsPerMinute > CPRGuidelines.rateCoachAboveMax {
            return LiveIssue(
                id: .speedFast,
                messageKey: "push_slower",
                repeatKey: "still_push_slower",
                priority: 78,
                firstThresholdMet: true,
                repeatThresholdMet: metrics.compressionsPerMinute > CPRGuidelines.rateCoachAboveMax + 5
            )
        }

        return nil
    }

    private func livePlacementIssue(for placement: HandPlacement) -> LiveIssue {
        LiveIssue(
            id: .placement,
            messageKey: JointCPRCoachAnalyzer.placementCorrectionKey(for: placement),
            repeatKey: JointCPRCoachAnalyzer.placementCorrectionKey(for: placement),
            priority: 95,
            firstThresholdMet: true,
            repeatThresholdMet: true
        )
    }

    private func liveElbowIssue(snapshot: JointCPRCoachAnalyzer.JointSnapshot) -> LiveIssue {
        LiveIssue(
            id: .elbows,
            messageKey: "straighten_arms",
            repeatKey: "elbows_still_bent",
            priority: 88,
            firstThresholdMet: snapshot.minElbowAngle < CPRGuidelines.targetElbowAngleMin,
            repeatThresholdMet: JointCPRCoachAnalyzer.isConfidentlyBentElbows(snapshot: snapshot)
        )
    }

    private func liveHipIssue(snapshot: JointCPRCoachAnalyzer.JointSnapshot) -> LiveIssue? {
        switch snapshot.hipPosture {
        case .tooHigh:
            return LiveIssue(
                id: .hipsHigh,
                messageKey: "lower_hip_position",
                repeatKey: "hips_still_high",
                priority: 84,
                firstThresholdMet: true,
                repeatThresholdMet: JointCPRCoachAnalyzer.isConfidentHipHigh(snapshot: snapshot)
            )
        case .tooLow:
            return LiveIssue(
                id: .hipsLow,
                messageKey: "raise_hip_position",
                repeatKey: "hips_still_low",
                priority: 84,
                firstThresholdMet: true,
                repeatThresholdMet: JointCPRCoachAnalyzer.isConfidentHipLow(snapshot: snapshot)
            )
        case nil:
            return nil
        }
    }

    private func liveWristStackIssue(
        snapshot: JointCPRCoachAnalyzer.JointSnapshot,
        joints: BodyJoints
    ) -> LiveIssue {
        LiveIssue(
            id: .wristsApart,
            messageKey: "setup_hands_stack",
            repeatKey: "hands_too_far_apart",
            priority: 86,
            firstThresholdMet: snapshot.wristStack == .tooFarApart,
            repeatThresholdMet: JointCPRCoachAnalyzer.isConfidentWristsApart(snapshot: snapshot, joints: joints)
        )
    }

    // MARK: - Issue tracking

    private func issueCorrection(
        _ issue: LiveIssue,
        compressionMetric: Bool,
        livePhase: Bool = false
    ) -> CPRCoachResponse {
        let isRepeat = spokenIssueIDs.contains(issue.id)
        let thresholdMet = isRepeat ? issue.repeatThresholdMet : issue.firstThresholdMet

        guard thresholdMet else {
            return silentHold()
        }

        if trackedIssueID == issue.id {
            issueStableFrames += 1
            issueClearFrames = 0
        } else {
            trackedIssueID = issue.id
            issueStableFrames = 1
            issueClearFrames = 0
        }

        let alreadySpoken = spokenIssueIDs.contains(issue.id)
        let requiredFrames: Int
        let perIssueCooldown: TimeInterval
        if compressionMetric {
            requiredFrames = alreadySpoken
                ? compressIssueRepeatStableRequired
                : compressIssueStableRequired
            perIssueCooldown = alreadySpoken ? compressRepeatCooldown : compressCorrectionCooldown
        } else if livePhase {
            requiredFrames = alreadySpoken
                ? livePostureRepeatStableRequired
                : livePostureStableRequired
            perIssueCooldown = alreadySpoken ? livePostureRepeatCooldown : livePostureCooldown
        } else {
            requiredFrames = alreadySpoken ? livePostureRepeatStableRequired : livePostureStableRequired
            perIssueCooldown = alreadySpoken ? livePostureRepeatCooldown : livePostureCooldown
        }

        guard issueStableFrames >= requiredFrames else {
            return silentHold()
        }

        let now = Date()
        if let last = lastSpokenTimeByIssue[issue.id],
           now.timeIntervalSince(last) < perIssueCooldown {
            return silentHold()
        }

        spokenIssueIDs.insert(issue.id)
        lastSpokenTimeByIssue[issue.id] = now

        let messageKey = alreadySpoken ? issue.repeatKey : issue.messageKey

        return CPRCoachResponse(
            messageKey: messageKey,
            priority: issue.priority,
            shouldSpeak: true,
            isPacingCue: false,
            isRepeatCorrection: alreadySpoken,
            isCompressionMetric: compressionMetric,
            allowsContinuousRepeat: livePhase && !compressionMetric
        )
    }

    private func trackIssuePresence(_ id: IssueID) {
        if trackedIssueID != id {
            issueClearFrames = 0
        }
    }

    private func trackIssueCleared() {
        issueStableFrames = 0
        trackedIssueID = nil
        issueClearFrames += 1

        if issueClearFrames >= issueClearRequired {
            spokenIssueIDs.removeAll()
            lastSpokenTimeByIssue.removeAll()
        }
    }

    private func lastTrackedIssueClearedForPacing() {
        issueStableFrames = 0
        trackedIssueID = nil
    }

    private func goodPacingCue() -> CPRCoachResponse {
        CPRCoachResponse(
            messageKey: "good_form",
            priority: 50,
            shouldSpeak: true,
            isPacingCue: true,
            isRepeatCorrection: false
        )
    }

    private func keepCompressingCue() -> CPRCoachResponse {
        CPRCoachResponse(
            messageKey: "keep_compressing",
            priority: 52,
            shouldSpeak: true,
            isPacingCue: true,
            isRepeatCorrection: false
        )
    }

    private func speakOnce(_ key: String, priority: Int) -> CPRCoachResponse {
        CPRCoachResponse(
            messageKey: key,
            priority: priority,
            shouldSpeak: true,
            isPacingCue: false,
            isRepeatCorrection: false
        )
    }

    private func silentHold(preferredKey: String = "") -> CPRCoachResponse {
        CPRCoachResponse(
            messageKey: preferredKey.isEmpty ? lastMessageKey : preferredKey,
            priority: 0,
            shouldSpeak: false,
            isPacingCue: false,
            isRepeatCorrection: false
        )
    }
}

extension ActionRecognitionResult {
    var responseLabelKey: String {
        primary.localizationKey
    }

    var responseConfidence: Double {
        confidence
    }
}
