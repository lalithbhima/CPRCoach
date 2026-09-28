import Foundation

/// Permanent append-only archive of every completed live CPR Coach session.
/// Stored on device as `cpr_training_sessions.json` for training / research export.
struct CPRTrainingArchive: Codable, Equatable {
    var version: Int
    var updatedAt: Date
    var sessions: [CPRPracticeSession]
}

@MainActor
final class CPRTrainingArchiveStore {
    static let shared = CPRTrainingArchiveStore()

    static let fileName = "cpr_training_sessions.json"

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private init() {}

    func append(_ session: CPRPracticeSession) {
        var archive = load() ?? CPRTrainingArchive(version: 1, updatedAt: Date(), sessions: [])
        guard !archive.sessions.contains(where: { $0.id == session.id }) else { return }

        archive.sessions.append(session)
        archive.updatedAt = Date()
        archive.version = 1
        save(archive)
    }

    func allSessions() -> [CPRPracticeSession] {
        load()?.sessions ?? []
    }

    private func load() -> CPRTrainingArchive? {
        let url = documentsURL(Self.fileName)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            return try decoder.decode(CPRTrainingArchive.self, from: data)
        } catch {
            print("CPRTrainingArchiveStore load failed: \(error)")
            return nil
        }
    }

    private func save(_ archive: CPRTrainingArchive) {
        do {
            let data = try encoder.encode(archive)
            try data.write(to: documentsURL(Self.fileName), options: .atomic)
        } catch {
            print("CPRTrainingArchiveStore save failed: \(error)")
        }
    }

    private func documentsURL(_ fileName: String) -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(fileName)
    }
}
