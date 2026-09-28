import Foundation

/// Local AHA-grounded knowledge for safe coaching without hallucination (RAG substitute on-device).
struct CPRKnowledgeChunk: Identifiable {
    let id: String
    let topic: String
    let content: String
    let keywords: [String]
}

enum CPRKnowledgeBase {
    static let chunks: [CPRKnowledgeChunk] = [
        CPRKnowledgeChunk(
            id: "responsive",
            topic: "Responsiveness",
            content: "Tap the person's shoulder and shout 'Are you okay?' If there is no response, they are unresponsive. Do not delay calling 911.",
            keywords: ["responsive", "unresponsive", "conscious", "wake", "shake"]
        ),
        CPRKnowledgeChunk(
            id: "breathing",
            topic: "Breathing Check",
            content: "Look for normal breathing for no more than 10 seconds. Gasping is not normal breathing. If not breathing normally, start CPR immediately.",
            keywords: ["breathing", "breath", "gasp", "airway", "pulse"]
        ),
        CPRKnowledgeChunk(
            id: "call911",
            topic: "Emergency Services",
            content: "Call 911 or ask a bystander to call. Put the phone on speaker. If an AED is available, send someone to get it.",
            keywords: ["911", "emergency", "ambulance", "aed", "help"]
        ),
        CPRKnowledgeChunk(
            id: "hand_placement",
            topic: "Hand Placement",
            content: "Place the heel of one hand on the center of the chest, lower half of the sternum. Place the other hand on top and interlace fingers. Keep arms straight.",
            keywords: ["hand", "placement", "chest", "sternum", "center", "position"]
        ),
        CPRKnowledgeChunk(
            id: "rate",
            topic: "Compression Rate",
            content: "Push hard and fast at 100 to 120 compressions per minute. Use a metronome rhythm of roughly 110 beats per minute.",
            keywords: ["rate", "speed", "fast", "slow", "rhythm", "cpm", "minute"]
        ),
        CPRKnowledgeChunk(
            id: "depth",
            topic: "Compression Depth",
            content: "Compress at least 2 inches (5 cm) but not more than 2.4 inches (6 cm) for adults. Allow full chest recoil between compressions.",
            keywords: ["depth", "deep", "shallow", "push", "pressure", "recoil"]
        ),
        CPRKnowledgeChunk(
            id: "technique",
            topic: "Technique",
            content: "Keep elbows straight, shoulders directly over hands, and compress straight down. Minimize interruptions. Switch rescuers every 2 minutes if possible.",
            keywords: ["elbow", "arm", "straight", "posture", "form", "technique"]
        ),
        CPRKnowledgeChunk(
            id: "when_cpr",
            topic: "When to Start CPR",
            content: "Start CPR if the person is unresponsive and not breathing normally. Do not check for a pulse for more than 10 seconds in bystander CPR.",
            keywords: ["start", "begin", "when", "cardiac", "arrest", "collapse"]
        ),
        CPRKnowledgeChunk(
            id: "infant",
            topic: "Infants",
            content: "For infants, use two fingers on the center of the chest. Depth about 1.5 inches (4 cm). Rate still 100–120 per minute.",
            keywords: ["baby", "infant", "child", "pediatric"]
        ),
        CPRKnowledgeChunk(
            id: "recovery",
            topic: "Recovery Position",
            content: "If breathing returns and the person is responsive, place them in the recovery position and monitor until EMS arrives.",
            keywords: ["recovery", "wake", "responsive again", "stop cpr"]
        ),
        CPRKnowledgeChunk(
            id: "aed",
            topic: "AED Use",
            content: "Turn on the AED and follow voice prompts. Apply pads as shown. Ensure nobody touches the person during shock delivery. Resume CPR immediately after.",
            keywords: ["aed", "defibrillator", "shock", "pads"]
        )
    ]

    static func retrieve(for query: String, limit: Int = 3) -> [CPRKnowledgeChunk] {
        keywordRetrieve(for: query, limit: limit)
    }

    static func keywordRetrieve(for query: String, limit: Int = 3) -> [CPRKnowledgeChunk] {
        let tokens = query.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 }

        let scored = chunks.map { chunk -> (CPRKnowledgeChunk, Int) in
            let score = chunk.keywords.reduce(0) { partial, keyword in
                partial + (tokens.contains(where: { keyword.contains($0) || $0.contains(keyword) }) ? 2 : 0)
            } + (tokens.contains(where: { chunk.content.lowercased().contains($0) }) ? 1 : 0)
            return (chunk, score)
        }
        .filter { $0.1 > 0 }
        .sorted { $0.1 > $1.1 }

        if scored.isEmpty {
            return Array(chunks.prefix(limit))
        }
        return Array(scored.prefix(limit).map(\.0))
    }
}
