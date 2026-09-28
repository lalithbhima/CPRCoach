import Foundation

/// Builds a shareable JSON export of all live CPR Coach sessions + per-frame metrics.
@MainActor
final class CPRSessionExportService {
    static let shared = CPRSessionExportService()

    enum ExportError: Error {
        case noSessions
    }

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    /// Merges Progress sessions + training archive, backfills archive, writes temp JSON file.
    func makeTrainingExportFile(progressStore: CPRProgressStore) throws -> URL {
        let archiveSessions = CPRTrainingArchiveStore.shared.allSessions()
        let merged = mergeSessions(progress: progressStore.sessions, archive: archiveSessions)

        guard !merged.isEmpty else { throw ExportError.noSessions }

        for session in progressStore.sessions {
            CPRTrainingArchiveStore.shared.append(session)
        }

        let export = CPRTrainingArchive(
            version: 1,
            updatedAt: Date(),
            sessions: merged.sorted { $0.startDate < $1.startDate }
        )

        let data = try encoder.encode(export)
        guard !data.isEmpty else { throw ExportError.noSessions }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cpr_training_sessions_\(UUID().uuidString).json")
        try data.write(to: url, options: .atomic)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ExportError.noSessions
        }
        return url
    }

    private func mergeSessions(
        progress: [CPRPracticeSession],
        archive: [CPRPracticeSession]
    ) -> [CPRPracticeSession] {
        var byID: [UUID: CPRPracticeSession] = [:]
        for session in archive {
            byID[session.id] = session
        }
        for session in progress {
            byID[session.id] = session
        }
        return Array(byID.values)
    }
}
