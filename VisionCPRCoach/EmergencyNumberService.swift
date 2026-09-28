import CoreLocation
import Foundation
import UIKit

/// Resolves the local emergency number from GPS (preferred) or device region.
@MainActor
final class EmergencyNumberService: NSObject, ObservableObject {
    static let shared = EmergencyNumberService()

    @Published private(set) var emergencyNumber = "911"
    @Published private(set) var countryCode = "US"

    private let geocoder = CLGeocoder()
    private let locationManager = CLLocationManager()
    private var isResolvingLocation = false

    /// ISO 3166-1 alpha-2 → primary ambulance / medical emergency number.
    /// India: 112 (national unified ERSS; legacy ambulance 102 still works in many areas).
    private static let numbersByCountry: [String: String] = [
        // A
        "AD": "112", "AE": "998", "AF": "119", "AG": "911", "AI": "911", "AL": "112",
        "AM": "112", "AO": "113", "AR": "107", "AS": "911", "AT": "112", "AU": "000",
        "AW": "911", "AZ": "112",
        // B
        "BA": "124", "BB": "511", "BD": "999", "BE": "112", "BF": "112", "BG": "112",
        "BH": "999", "BI": "112", "BJ": "112", "BM": "911", "BN": "991", "BO": "110",
        "BQ": "911", "BR": "192", "BS": "911", "BT": "112", "BW": "997", "BY": "103",
        "BZ": "911",
        // C
        "CA": "911", "CD": "112", "CF": "117", "CG": "118", "CH": "112", "CI": "185",
        "CK": "998", "CL": "131", "CM": "112", "CN": "120", "CO": "123", "CR": "911",
        "CU": "104", "CV": "132", "CW": "911", "CY": "112", "CZ": "112",
        // D
        "DE": "112", "DJ": "18", "DK": "112", "DM": "911", "DO": "911", "DZ": "14",
        // E
        "EC": "911", "EE": "112", "EG": "123", "ER": "114", "ES": "112", "ET": "907",
        // F
        "FI": "112", "FJ": "911", "FK": "999", "FM": "911", "FO": "112", "FR": "112",
        // G
        "GA": "18", "GB": "999", "GD": "911", "GE": "112", "GF": "15", "GG": "999",
        "GH": "112", "GI": "112", "GL": "112", "GM": "116", "GN": "442020", "GP": "15",
        "GQ": "112", "GR": "112", "GT": "128", "GU": "911", "GW": "112", "GY": "913",
        // H
        "HK": "999", "HN": "195", "HR": "112", "HT": "116", "HU": "112",
        // I
        "ID": "118", "IE": "112", "IL": "101", "IM": "999", "IN": "112", "IQ": "122",
        "IR": "115", "IS": "112", "IT": "112",
        // J
        "JE": "999", "JM": "911", "JO": "911", "JP": "119",
        // K
        "KE": "999", "KG": "103", "KH": "119", "KI": "994", "KM": "18", "KN": "911",
        "KP": "819", "KR": "119", "KW": "112", "KY": "911", "KZ": "103",
        // L
        "LA": "1195", "LB": "140", "LC": "911", "LI": "112", "LK": "1990", "LR": "911",
        "LS": "121", "LT": "112", "LU": "112", "LV": "112", "LY": "1515",
        // M
        "MA": "15", "MC": "112", "MD": "903", "ME": "112", "MG": "117", "MH": "911",
        "MK": "112", "ML": "15", "MM": "192", "MN": "103", "MO": "999", "MP": "911",
        "MQ": "15", "MR": "101", "MS": "911", "MT": "112", "MU": "114", "MV": "102",
        "MW": "998", "MX": "911", "MY": "999", "MZ": "117",
        // N
        "NA": "211111", "NC": "15", "NE": "15", "NF": "000", "NG": "112", "NI": "128",
        "NL": "112", "NO": "112", "NP": "102", "NR": "110", "NU": "999", "NZ": "111",
        // O
        "OM": "999",
        // P
        "PA": "911", "PE": "106", "PF": "15", "PG": "110", "PH": "911", "PK": "115",
        "PL": "112", "PM": "15", "PN": "999", "PR": "911", "PS": "101", "PT": "112",
        "PW": "911", "PY": "141",
        // Q
        "QA": "999",
        // R
        "RE": "15", "RO": "112", "RS": "194", "RU": "112", "RW": "912",
        // S
        "SA": "997", "SB": "911", "SC": "151", "SD": "999", "SE": "112", "SG": "995",
        "SH": "999", "SI": "112", "SK": "112", "SL": "999", "SM": "112", "SN": "15",
        "SO": "999", "SR": "113", "SS": "777", "ST": "112", "SV": "911", "SX": "911",
        "SY": "110", "SZ": "977",
        // T
        "TC": "911", "TD": "18", "TG": "8200", "TH": "1669", "TJ": "03", "TK": "999",
        "TL": "112", "TM": "03", "TN": "190", "TO": "911", "TR": "112", "TT": "811",
        "TV": "911", "TW": "119", "TZ": "114",
        // U
        "UA": "103", "UG": "112", "US": "911", "UY": "105", "UZ": "103",
        // V
        "VA": "112", "VC": "911", "VE": "171", "VG": "911", "VI": "911", "VN": "115",
        "VU": "112",
        // W
        "WF": "15", "WS": "999",
        // Y
        "YE": "191", "YT": "15",
        // Z
        "ZA": "10177", "ZM": "991", "ZW": "994",
    ]

    override private init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
        applyCountry(Locale.current.region?.identifier ?? "US")
    }

    func refreshFromLocale() {
        applyCountry(Locale.current.region?.identifier ?? countryCode)
    }

    func refreshFromLocationIfAuthorized() {
        guard !isResolvingLocation else { return }

        switch locationManager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            isResolvingLocation = true
            locationManager.requestLocation()
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        default:
            refreshFromLocale()
        }
    }

    func update(from location: CLLocation) async {
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            if let code = placemarks.first?.isoCountryCode {
                applyCountry(code)
                return
            }
        } catch {
            // Fall through to locale.
        }
        refreshFromLocale()
    }

    static func dial(_ number: String) {
        let digits = number.filter { $0.isNumber || $0 == "+" }
        guard !digits.isEmpty, let url = URL(string: "tel://\(digits)") else { return }
        UIApplication.shared.open(url)
    }

    private func applyCountry(_ code: String) {
        let upper = code.uppercased()
        countryCode = upper
        emergencyNumber = Self.numbersByCountry[upper] ?? Self.fallbackNumber(for: upper)
    }

    private static func fallbackNumber(for countryCode: String) -> String {
        // North American Numbering Plan territories default to 911; most others use 112 (GSM/ITU).
        let nanp: Set<String> = [
            "US", "CA", "MX", "PR", "DO", "JM", "BS", "BB", "AG", "AI", "AS", "GU", "MP",
            "VI", "VG", "KY", "BM", "TT", "GD", "LC", "VC", "KN", "DM", "TC", "MS", "SX",
            "CW", "BQ", "AW", "PA", "CR", "SV", "GT", "HN", "NI", "BZ", "HT", "JM"
        ]
        if nanp.contains(countryCode) { return "911" }
        return "112"
    }
}

extension EmergencyNumberService: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            isResolvingLocation = false
            await update(from: location)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            isResolvingLocation = false
            refreshFromLocale()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
                refreshFromLocationIfAuthorized()
            }
        }
    }
}
