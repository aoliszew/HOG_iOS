import Foundation
import CoreLocation

/// A multi-day journey: home → destination → (days there) → home.
/// Persisted across app launches so each drive knows which chapter it's in.
struct Voyage: Codable {
    enum Phase: String, Codable {
        case outbound       // heading to the destination
        case atDestination  // arrived; local driving doesn't advance the story
        case returning      // heading home
    }

    var destinationName: String
    var destinationLat: Double
    var destinationLon: Double
    var phase: Phase
    var startedAt: Date

    var destination: CLLocation {
        CLLocation(latitude: destinationLat, longitude: destinationLon)
    }

    /// 1-based day counter since the voyage began.
    var dayNumber: Int {
        (Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: startedAt),
                                         to: Calendar.current.startOfDay(for: .now)).day ?? 0) + 1
    }
}

/// Persistence for home base and the active voyage. All optional — nothing
/// downstream requires these to exist.
enum VoyageStore {
    private static let defaults = UserDefaults.standard

    static var home: CLLocation? {
        get {
            let lat = defaults.double(forKey: "homeLat"), lon = defaults.double(forKey: "homeLon")
            guard lat != 0 || lon != 0 else { return nil }
            return CLLocation(latitude: lat, longitude: lon)
        }
        set {
            defaults.set(newValue?.coordinate.latitude ?? 0, forKey: "homeLat")
            defaults.set(newValue?.coordinate.longitude ?? 0, forKey: "homeLon")
        }
    }

    static var current: Voyage? {
        get {
            guard let data = defaults.data(forKey: "voyage") else { return nil }
            return try? JSONDecoder().decode(Voyage.self, from: data)
        }
        set {
            if let newValue, let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: "voyage")
            } else {
                defaults.removeObject(forKey: "voyage")
            }
        }
    }
}
