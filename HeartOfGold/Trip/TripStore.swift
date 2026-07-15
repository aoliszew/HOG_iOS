import Foundation

/// Crash-safe snapshot of an in-progress mission. Written debounced to disk;
/// if the app dies mid-drive, the next launch offers to resume with mileage,
/// story flags, and fired-event state intact.
/// (This is also the seed of the future save-slots/achievements system.)
struct TripSnapshot: Codable {
    var active: Bool
    var startedAt: Date
    var updatedAt: Date
    var mode: String
    var personality: String
    var distanceMiles: Double
    var flags: [String]
    var firedCounts: [String: Int]
    var lastFired: [String: Date]
    // Mission briefing (optional for backward compatibility)
    var planLength: String?
    var plannedStops: Int?
    var stopsCompleted: Int?
    // Unplayed message queue (field bug: held messages vanished on restart)
    var queuedMessages: [QueuedMessage]?
    var pendingBranchingID: String?

    struct QueuedMessage: Codable {
        var source: String
        var text: String
        var ambient: Bool
        var sfx: String?
        var startsBranching: Bool
    }
}

enum TripStore {
    private static var url: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("trip_state.json")
    }

    private static let queue = DispatchQueue(label: "com.oliszewski.heartofgold.tripstore", qos: .utility)
    private static var pending: TripSnapshot?
    private static var writeScheduled = false

    /// Debounced write — safe to call on every tick.
    static func save(_ snapshot: TripSnapshot) {
        queue.async {
            pending = snapshot
            guard !writeScheduled else { return }
            writeScheduled = true
            queue.asyncAfter(deadline: .now() + 2) {
                writeScheduled = false
                flush()
            }
        }
    }

    /// Immediate write (power down, app backgrounding).
    static func saveNow(_ snapshot: TripSnapshot) {
        queue.async {
            pending = snapshot
            flush()
        }
    }

    private static func flush() {
        guard let snapshot = pending else { return }
        if let data = try? JSONEncoder().encode(snapshot) {
            try? data.write(to: url, options: .atomic)
        }
    }

    /// A resumable trip: marked active and fresher than 6 hours.
    static func loadResumable() -> TripSnapshot? {
        guard let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(TripSnapshot.self, from: data),
              snapshot.active,
              Date().timeIntervalSince(snapshot.updatedAt) < 6 * 3600 else { return nil }
        return snapshot
    }

    static func clear() {
        queue.async {
            pending = nil
            try? FileManager.default.removeItem(at: url)
        }
    }
}
