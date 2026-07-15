import CoreLocation
import Combine

/// Tracks speed and cumulative distance for the current trip.
final class TripTracker: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var speedMPH: Double = 0
    @Published var distanceMiles: Double = 0
    @Published var authorized = false
    /// Most recent fix, for region awareness (reverse geocoding).
    private(set) var currentLocation: CLLocation?

    /// Fired when speed crosses a callout threshold (rising edge only).
    var onThresholdCrossed: ((Int) -> Void)?

    /// Fired on hard acceleration (rate-limited).
    var onHardAcceleration: (() -> Void)?

    /// True within 60s of the last hard-acceleration event (trigger context).
    var hardAccelRecently: Bool { Date().timeIntervalSince(lastThrusterFire) < 60 }

    private var lastSpeedSample: (mph: Double, time: Date)?
    private var lastThrusterFire = Date.distantPast
    private let hardAccelMPHPerSec = 4.5
    private let thrusterCooldown: TimeInterval = 12

    private let manager = CLLocationManager()
    private var lastLocation: CLLocation?
    private var announcedThresholds: Set<Int> = []
    private let thresholds = [45, 60, 75]

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.activityType = .automotiveNavigation
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = false
    }

    func start() {
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
    }

    /// One-shot fix while on standby (e.g. SET HOME HERE).
    private var oneShotCompletion: ((CLLocation?) -> Void)?
    func requestFix(completion: @escaping (CLLocation?) -> Void) {
        if let current = currentLocation, Date().timeIntervalSince(current.timestamp) < 60 {
            completion(current)
            return
        }
        oneShotCompletion = completion
        manager.requestWhenInUseAuthorization()
        manager.requestLocation()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        oneShotCompletion?(nil)
        oneShotCompletion = nil
    }

    func stop() {
        manager.stopUpdatingLocation()
        speedMPH = 0
        lastLocation = nil
        announcedThresholds = []
    }

    func resetTrip() {
        distanceMiles = 0
        announcedThresholds = []
    }

    /// Crash-recovery: continue an interrupted trip's odometer.
    func restoreDistance(_ miles: Double) {
        distanceMiles = miles
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorized = manager.authorizationStatus == .authorizedWhenInUse
            || manager.authorizationStatus == .authorizedAlways
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last, loc.horizontalAccuracy >= 0 else { return }

        currentLocation = loc
        oneShotCompletion?(loc)
        oneShotCompletion = nil
        let mph = max(0, loc.speed) * 2.23694
        speedMPH = mph

        if let last = lastLocation, loc.speed > 0 {
            distanceMiles += loc.distance(from: last) / 1609.34
        }
        lastLocation = loc

        if let last = lastSpeedSample {
            let dt = loc.timestamp.timeIntervalSince(last.time)
            if dt > 0.2, (mph - last.mph) / dt >= hardAccelMPHPerSec,
               Date().timeIntervalSince(lastThrusterFire) > thrusterCooldown {
                lastThrusterFire = Date()
                onHardAcceleration?()
            }
        }
        lastSpeedSample = (mph, loc.timestamp)

        // Each threshold announces at most once per trip (field feedback:
        // repeated callouts around town speeds got old fast).
        for t in thresholds where mph >= Double(t) && !announcedThresholds.contains(t) {
            announcedThresholds.insert(t)
            onThresholdCrossed?(t)
        }
    }
}
