import CoreLocation

/// Knows which US state (or province) the ship is operating in, via occasional
/// reverse geocoding. Deliberately defensive: rate-limited, network failures
/// are silently ignored, and nothing downstream depends on it existing.
final class RegionAwareness {
    private let geocoder = CLGeocoder()
    private var lastAttempt = Date.distantPast
    private(set) var stateCode: String?

    /// Fired on the main queue when the state changes mid-trip (not on first fix).
    var onStateChange: ((_ code: String, _ name: String) -> Void)?

    func check(location: CLLocation) {
        guard Date().timeIntervalSince(lastAttempt) > 180, !geocoder.isGeocoding else { return }
        lastAttempt = Date()
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, _ in
            guard let self, let code = placemarks?.first?.administrativeArea, !code.isEmpty else { return }
            let previous = self.stateCode
            self.stateCode = code
            if let previous, previous != code {
                let name = Self.stateNames[code] ?? code
                DispatchQueue.main.async { self.onStateChange?(code, name) }
            }
        }
    }

    func reset() {
        stateCode = nil
    }

    private static let stateNames: [String: String] = [
        "AL": "Alabama", "AK": "Alaska", "AZ": "Arizona", "AR": "Arkansas", "CA": "California",
        "CO": "Colorado", "CT": "Connecticut", "DE": "Delaware", "FL": "Florida", "GA": "Georgia",
        "HI": "Hawaii", "ID": "Idaho", "IL": "Illinois", "IN": "Indiana", "IA": "Iowa",
        "KS": "Kansas", "KY": "Kentucky", "LA": "Louisiana", "ME": "Maine", "MD": "Maryland",
        "MA": "Massachusetts", "MI": "Michigan", "MN": "Minnesota", "MS": "Mississippi", "MO": "Missouri",
        "MT": "Montana", "NE": "Nebraska", "NV": "Nevada", "NH": "New Hampshire", "NJ": "New Jersey",
        "NM": "New Mexico", "NY": "New York", "NC": "North Carolina", "ND": "North Dakota", "OH": "Ohio",
        "OK": "Oklahoma", "OR": "Oregon", "PA": "Pennsylvania", "RI": "Rhode Island", "SC": "South Carolina",
        "SD": "South Dakota", "TN": "Tennessee", "TX": "Texas", "UT": "Utah", "VT": "Vermont",
        "VA": "Virginia", "WA": "Washington", "WV": "West Virginia", "WI": "Wisconsin", "WY": "Wyoming",
        "DC": "the District of Columbia",
    ]
}
