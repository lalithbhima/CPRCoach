import Foundation
import NaturalLanguage

/// On-device RAG pipeline: embedding similarity search over AHA knowledge chunks.
final class RAGRetriever {
    static let shared = RAGRetriever()

    private let embedding = NLEmbedding.sentenceEmbedding(for: .english)
    private var chunks: [CPRKnowledgeChunk] = []
    private var chunkVectors: [[Double]] = []

    private init() {
        loadKnowledge()
        precomputeEmbeddings()
    }

    func retrieve(for query: String, limit: Int = 5) -> [CPRKnowledgeChunk] {
        guard let embedding, !chunkVectors.isEmpty else {
            return CPRKnowledgeBase.keywordRetrieve(for: query, limit: limit)
        }

        guard let queryVector = embedding.vector(for: query) else {
            return CPRKnowledgeBase.keywordRetrieve(for: query, limit: limit)
        }

        let qv = queryVector.map { Double($0) }

        let scored = zip(chunks, chunkVectors).map { chunk, vector -> (CPRKnowledgeChunk, Double) in
            (chunk, cosineSimilarity(qv, vector))
        }
        .sorted { $0.1 > $1.1 }

        return Array(scored.prefix(limit).map(\.0))
    }

    func retrieveForMetrics(_ metrics: CPRMetrics, joints: BodyJoints?) -> [CPRKnowledgeChunk] {
        var queries: [String] = []

        if metrics.handPlacement != .centered {
            queries.append("hand placement center sternum CPR")
        }
        if metrics.compressionsPerMinute < CPRGuidelines.targetRateMin {
            queries.append("compression rate too slow 100-120")
        }
        if metrics.compressionsPerMinute > CPRGuidelines.targetRateMax {
            queries.append("compression rate too fast slow down")
        }
        if metrics.depthQuality == .tooShallow {
            queries.append("compression depth too shallow push deeper 5cm")
        }
        if metrics.depthQuality == .tooDeep {
            queries.append("compression depth too deep reduce")
        }
        if metrics.elbowAngle < CPRGuidelines.targetElbowAngleMin {
            queries.append("straight arms elbows locked CPR posture")
        }
        if metrics.recoilQuality == .incomplete {
            queries.append("chest recoil full release between compressions")
        }
        if let joints, joints.averageConfidence < 0.4 {
            queries.append("camera position CPR training setup")
        }

        if queries.isEmpty {
            queries.append("high quality CPR technique metrics")
        }

        var merged: [CPRKnowledgeChunk] = []
        var seen = Set<String>()
        for q in queries {
            for chunk in retrieve(for: q, limit: 2) where !seen.contains(chunk.id) {
                seen.insert(chunk.id)
                merged.append(chunk)
            }
        }
        return Array(merged.prefix(5))
    }

    private func loadKnowledge() {
        if let url = Bundle.main.url(forResource: "cpr_knowledge", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([CPRKnowledgeChunkDTO].self, from: data) {
            chunks = decoded.map { CPRKnowledgeChunk(id: $0.id, topic: $0.topic, content: $0.content, keywords: $0.keywords) }
        } else {
            chunks = CPRKnowledgeBase.chunks
        }
    }

    private func precomputeEmbeddings() {
        guard let embedding else { return }
        chunkVectors = chunks.compactMap { chunk in
            let text = "\(chunk.topic). \(chunk.content)"
            return embedding.vector(for: text)?.map { Double($0) }
        }
    }

    private func cosineSimilarity(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        let dot = zip(a, b).map(*).reduce(0, +)
        let magA = sqrt(a.map { $0 * $0 }.reduce(0, +))
        let magB = sqrt(b.map { $0 * $0 }.reduce(0, +))
        guard magA > 0, magB > 0 else { return 0 }
        return dot / (magA * magB)
    }

    private struct CPRKnowledgeChunkDTO: Decodable {
        let id: String
        let topic: String
        let content: String
        let keywords: [String]
    }
}
