import Foundation

@MainActor
final class CPRProgressStore: ObservableObject {
    static let shared = CPRProgressStore()

    @Published private(set) var sessions: [CPRPracticeSession] = []
    @Published private(set) var calibrationRecords: [CalibrationRecord] = []

    private let sessionsFileName = "cpr_sessions.json"
    private let calibrationsFileName = "cpr_calibrations.json"

    private init() {
        load()
    }

    var latestSession: CPRPracticeSession? { sessions.first }

    var aggregateScore: Double {
        let recent = sessions.prefix(5)
        guard !recent.isEmpty else { return 0 }
        return recent.map(\.overallScore).reduce(0, +) / Double(recent.count)
    }

    func improvementSincePrevious() -> Double? {
        guard sessions.count >= 2 else { return nil }
        return sessions[0].overallScore - sessions[1].overallScore
    }

    func add(_ session: CPRPracticeSession) {
        sessions.insert(session, at: 0)
        saveSessions()
        CPRTrainingArchiveStore.shared.append(session)
    }

    func updateAISummary(sessionID: UUID, summary: String) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        sessions[index].aiSummary = summary
        saveSessions()
    }

    func delete(_ session: CPRPracticeSession) {
        sessions.removeAll { $0.id == session.id }
        saveSessions()
    }

    func addCalibration(
        profile: CalibrationProfile,
        metrics: CPRMetrics
    ) {
        let record = CalibrationRecord(
            id: UUID(),
            date: Date(),
            baselineAmplitude: profile.baselineAmplitude,
            baselineDepthCm: profile.baselineDepthCm,
            cpmAtCalibration: metrics.compressionsPerMinute,
            depthCmAtCalibration: metrics.estimatedDepthCm,
            elbowAngleAtCalibration: metrics.elbowAngle,
            pressureScoreAtCalibration: metrics.pressureScore
        )
        calibrationRecords.insert(record, at: 0)
        saveCalibrations()
    }

    func deleteCalibration(_ record: CalibrationRecord) {
        calibrationRecords.removeAll { $0.id == record.id }
        saveCalibrations()
    }

    private func saveSessions() {
        persist(sessions, fileName: sessionsFileName)
    }

    private func saveCalibrations() {
        persist(calibrationRecords, fileName: calibrationsFileName)
    }

    private func load() {
        sessions = loadFile(sessionsFileName) ?? []
        calibrationRecords = loadFile(calibrationsFileName) ?? []
    }

    private func persist<T: Encodable>(_ value: T, fileName: String) {
        do {
            let data = try JSONEncoder().encode(value)
            try data.write(to: documentsURL(fileName), options: .atomic)
        } catch {
            print("CPRProgressStore save failed: \(error)")
        }
    }

    private func loadFile<T: Decodable>(_ fileName: String) -> T? {
        do {
            let data = try Data(contentsOf: documentsURL(fileName))
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            return nil
        }
    }

    private func documentsURL(_ fileName: String) -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(fileName)
    }
}
