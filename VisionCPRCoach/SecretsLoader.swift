import Foundation

/// Loads OPENROUTER_API_KEY from bundled `secret.ts` (same format you edit in Config/secret.ts).
enum SecretsLoader {
  private static let cachedKey: String = resolveAPIKey()

  static var openRouterAPIKey: String { cachedKey }

  static var isConfigured: Bool {
    !cachedKey.isEmpty
  }

  private static func resolveAPIKey() -> String {
    let fromSwift = Secrets.openRouterAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
    if !fromSwift.isEmpty { return fromSwift }

    if let fromJSON = loadKeyFromBundledJSON() {
      return fromJSON
    }

    if let fromBundle = loadKeyFromSecretTS() {
      return fromBundle
    }

    return ""
  }

  private static func loadKeyFromBundledJSON() -> String? {
    guard let url = Bundle.main.url(forResource: "openrouter_secret", withExtension: "json"),
          let data = try? Data(contentsOf: url),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let key = object["OPENROUTER_API_KEY"] as? String else {
      return nil
    }
    let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  private static func loadKeyFromSecretTS() -> String? {
    guard let url = Bundle.main.url(forResource: "secret", withExtension: "ts"),
          let text = try? String(contentsOf: url, encoding: .utf8) else {
      return nil
    }
    return parseAPIKey(from: text)
  }

  /// Parses: export const OPENROUTER_API_KEY = "sk-or-...";
  static func parseAPIKey(from text: String) -> String? {
    let pattern = #"OPENROUTER_API_KEY\s*=\s*\"([^\"]+)\""#
    guard let regex = try? NSRegularExpression(pattern: pattern),
          let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
          match.numberOfRanges > 1,
          let range = Range(match.range(at: 1), in: text) else {
      return nil
    }
    let key = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
    return key.isEmpty ? nil : key
  }
}
