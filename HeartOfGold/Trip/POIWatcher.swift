import Foundation
import CoreLocation

/// A named place the ship comments on when the drive passes within range.
/// Route packs live in Content/pois/*.json — hand-curated for now; a MapKit
/// category search can feed the same pipeline later.
struct PointOfInterest: Decodable, Identifiable {
    let id: String
    let name: String
    let lat: Double
    let lon: Double
    let radiusMiles: Double
    let source: String
    let text: String

    var location: CLLocation { CLLocation(latitude: lat, longitude: lon) }
}

/// Loads POI packs and reports un-visited hits near the current position.
final class POIWatcher {
    private struct Pack: Decodable { let pois: [PointOfInterest] }

    private let pois: [PointOfInterest]
    private var visited: Set<String> = []
    private var lastCheck = Date.distantPast

    init(bundle: Bundle = .main) {
        var loaded: [PointOfInterest] = []
        if let root = bundle.resourceURL?.appendingPathComponent("Content/pois"),
           let files = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) {
            for url in files where url.pathExtension == "json" {
                if let data = try? Data(contentsOf: url),
                   let pack = try? JSONDecoder().decode(Pack.self, from: data) {
                    loaded.append(contentsOf: pack.pois)
                }
            }
        }
        pois = loaded
    }

    func resetTrip() {
        visited = []
    }

    /// Returns any newly-entered POI (at most one per call; rate-limited).
    func check(location: CLLocation) -> PointOfInterest? {
        guard Date().timeIntervalSince(lastCheck) > 10 else { return nil }
        lastCheck = Date()
        for poi in pois where !visited.contains(poi.id) {
            if location.distance(from: poi.location) / 1609.34 <= poi.radiusMiles {
                visited.insert(poi.id)
                return poi
            }
        }
        return nil
    }
}
