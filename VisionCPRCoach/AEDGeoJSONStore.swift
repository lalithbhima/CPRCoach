import Foundation
import CoreLocation

/// Loads worldwide AED stations from bundled `Resources/WORLD.geojson`.
actor AEDGeoJSONStore {
    static let shared = AEDGeoJSONStore()

    private struct Station {
        let id: String
        let name: String
        let address: String
        let details: String
        let latitude: Double
        let longitude: Double
    }

    private var stations: [Station] = []
    private var isLoaded = false
    private var loadTask: Task<Void, Error>?

    func ensureLoaded() async throws {
        if isLoaded { return }
        if let loadTask {
            try await loadTask.value
            return
        }

        let task = Task<Void, Error> {
            try await self.loadFromBundle()
        }
        loadTask = task
        try await task.value
        loadTask = nil
    }

    /// All AED stations within `maxRadiusMeters`, sorted nearest first.
    func placesNear(
        _ location: CLLocation,
        maxRadiusMeters: Double = 50_000
    ) -> [HospitalPlace] {
        guard isLoaded, !stations.isEmpty else { return [] }

        let lat = location.coordinate.latitude
        let lon = location.coordinate.longitude
        let latDelta = maxRadiusMeters / 111_000.0
        let lonDelta = maxRadiusMeters / (111_000.0 * max(cos(lat * .pi / 180.0), 0.2))

        var matches: [(HospitalPlace, Double)] = []

        for station in stations {
            guard abs(station.latitude - lat) <= latDelta,
                  abs(station.longitude - lon) <= lonDelta else { continue }

            let stationLocation = CLLocation(latitude: station.latitude, longitude: station.longitude)
            let distance = location.distance(from: stationLocation)
            guard distance <= maxRadiusMeters else { continue }

            let place = HospitalPlace(
                id: station.id,
                name: station.name,
                address: station.address,
                latitude: station.latitude,
                longitude: station.longitude,
                distanceMeters: distance,
                detailText: station.details
            )
            matches.append((place, distance))
        }

        matches.sort { $0.1 < $1.1 }
        return matches.map(\.0)
    }

    var stationCount: Int {
        stations.count
    }

    private func loadFromBundle() async throws {
        let url = Self.bundleGeoJSONURL()
        guard let url else {
            throw AEDGeoJSONError.fileNotFound
        }

        let parsed = try await Task.detached(priority: .userInitiated) {
            try Self.parseStations(from: url)
        }.value

        stations = parsed
        isLoaded = true
    }

    private static func bundleGeoJSONURL() -> URL? {
        if let url = Bundle.main.url(forResource: "WORLD", withExtension: "geojson") {
            return url
        }
        if let url = Bundle.main.url(forResource: "world", withExtension: "geojson") {
            return url
        }
        if let resourceRoot = Bundle.main.resourceURL {
            let world = resourceRoot.appendingPathComponent("WORLD.geojson")
            if FileManager.default.fileExists(atPath: world.path) {
                return world
            }
        }
        return nil
    }

    private static func parseStations(from url: URL) throws -> [Station] {
        let data = try Data(contentsOf: url)
        let object = try JSONSerialization.jsonObject(with: data)
        guard let root = object as? [String: Any],
              let features = root["features"] as? [[String: Any]] else {
            throw AEDGeoJSONError.invalidFormat
        }

        var parsed: [Station] = []
        parsed.reserveCapacity(features.count)

        for feature in features {
            guard let geometry = feature["geometry"] as? [String: Any],
                  let geometryType = geometry["type"] as? String else { continue }

            let latitude: Double
            let longitude: Double

            if geometryType == "Point",
               let coordinates = geometry["coordinates"] as? [Double],
               coordinates.count >= 2 {
                longitude = coordinates[0]
                latitude = coordinates[1]
            } else {
                continue
            }

            let properties = feature["properties"] as? [String: Any] ?? [:]

            let name = displayName(from: properties)
            let address = displayAddress(from: properties)
            let details = displayDetails(
                from: properties,
                latitude: latitude,
                longitude: longitude
            )
            let id = stationID(from: properties, latitude: latitude, longitude: longitude)

            parsed.append(
                Station(
                    id: id,
                    name: name,
                    address: address,
                    details: details,
                    latitude: latitude,
                    longitude: longitude
                )
            )
        }

        return parsed
    }

    private static func displayName(from properties: [String: Any]) -> String {
        if let name = stringValue(properties["name"]), !name.isEmpty {
            return name
        }
        if let operatorName = stringValue(properties["operator"]), !operatorName.isEmpty {
            return "AED — \(operatorName)"
        }
        return "AED Station"
    }

    private static func displayAddress(from properties: [String: Any]) -> String {
        var parts: [String] = []

        let streetLine = [
            stringValue(properties["addr:housenumber"]),
            stringValue(properties["addr:street"])
        ].compactMap { $0 }.joined(separator: " ")

        if !streetLine.isEmpty { parts.append(streetLine) }

        let cityLine = [
            stringValue(properties["addr:city"]),
            stringValue(properties["addr:postcode"]),
            stringValue(properties["addr:state"])
        ].compactMap { $0 }.joined(separator: " ")

        if !cityLine.isEmpty { parts.append(cityLine) }

        if let country = stringValue(properties["addr:country"]), !country.isEmpty {
            parts.append(country)
        }

        return parts.joined(separator: " · ")
    }

    private static func displayDetails(
        from properties: [String: Any],
        latitude: Double,
        longitude: Double
    ) -> String {
        var lines: [String] = []

        lines.append(String(format: "Coordinates: %.5f, %.5f", latitude, longitude))

        let locationKeys = [
            "defibrillator:location",
            "defibrillator:location:de",
            "defibrillator:location:pl",
            "defibrillator:location:en"
        ]
        for key in locationKeys {
            if let value = stringValue(properties[key]) {
                lines.append("Location: \(value)")
                break
            }
        }

        let labeledFields: [(String, String)] = [
            ("operator", "Operator"),
            ("access", "Access"),
            ("opening_hours", "Hours"),
            ("phone", "Phone"),
            ("emergency:phone", "Emergency phone"),
            ("emergency", "Emergency type"),
            ("indoor", "Indoor"),
            ("level", "Level"),
            ("manufacturer", "Manufacturer"),
            ("model", "Model"),
            ("description", "Description"),
            ("check_date", "Last checked"),
            ("source", "Source"),
            ("ref:hjertestarterregister", "Registry ID")
        ]

        for (key, label) in labeledFields {
            if let value = stringValue(properties[key]) {
                lines.append("\(label): \(value)")
            }
        }

        let skipKeys = Set([
            "@osm_type", "@osm_id", "@osm_version",
            "name", "addr:housenumber", "addr:street", "addr:city",
            "addr:postcode", "addr:state", "addr:country"
        ] + locationKeys + labeledFields.map(\.0))

        for key in properties.keys.sorted() where !skipKeys.contains(key) {
            if let value = stringValue(properties[key]) {
                let label = key.replacingOccurrences(of: "_", with: " ").capitalized
                lines.append("\(label): \(value)")
            }
        }

        return lines.joined(separator: "\n")
    }

    private static func stationID(from properties: [String: Any], latitude: Double, longitude: Double) -> String {
        if let osmID = properties["@osm_id"] {
            return "aed-\(osmID)"
        }
        return "aed-\(latitude)-\(longitude)"
    }

    private static func stringValue(_ value: Any?) -> String? {
        switch value {
        case let string as String:
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        case let number as NSNumber:
            return number.stringValue
        case let boolean as Bool:
            return boolean ? "yes" : "no"
        default:
            return nil
        }
    }
}

enum AEDGeoJSONError: LocalizedError {
    case fileNotFound
    case invalidFormat

    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "AED database file not found."
        case .invalidFormat:
            return "AED database file could not be read."
        }
    }
}
