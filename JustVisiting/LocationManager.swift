import CoreLocation
import Observation
import os

private let locationLog = Logger(subsystem: "JustVisiting", category: "location")

// Wraps CLLocationManager and exposes a clean Observable interface to the rest of the app.
// The class is @Observable so SwiftUI views automatically re-render when its properties change.
@Observable
final class LocationManager: NSObject {

    // Published state that views can read directly
    var authorizationStatus: CLAuthorizationStatus = .notDetermined
    var lastLocation: CLLocation?
    var isTracking = false
    var isAutoTracking = false

    // Called on every location update while tracking is active.
    // PlacesManager wires itself in here (via JustVisitingApp) to check for new visits.
    var onLocationUpdate: ((CLLocation) -> Void)?

    private let clManager = CLLocationManager()

    override init() {
        super.init()
        clManager.delegate = self

        // kCLLocationAccuracyBest uses GPS+Wi-Fi+cell for the tightest fix.
        // This matters for small hamlets where the radius is only 250 m.
        clManager.desiredAccuracy = kCLLocationAccuracyBest

        // Only fire a new location event after moving at least 30 m.
        // Prevents hammering checkLocation() while stationary.
        clManager.distanceFilter = 30

        // Don't let iOS auto-pause updates when it thinks the user has stopped —
        // we want continuous tracking even during slow traffic or stops.
        clManager.pausesLocationUpdatesAutomatically = false

        // allowsBackgroundLocationUpdates crashes at launch if "location" isn't listed
        // under UIBackgroundModes in Info.plist, so we check first before setting it.
        if Self.hasBackgroundLocationMode {
            clManager.allowsBackgroundLocationUpdates = true
        }

        authorizationStatus = clManager.authorizationStatus
        // Seed from CoreLocation's system cache so the "nearby only" filter works
        // immediately, even before the user starts active tracking.
        lastLocation = clManager.location

        // If the user previously enabled background tracking, resume it automatically on launch.
        if UserDefaults.standard.bool(forKey: "tracking.autoEnabled") {
            isAutoTracking = true
            clManager.distanceFilter = 100
            clManager.startUpdatingLocation()
        }
    }

    // Checks the actual compiled Info.plist at runtime rather than assuming the build
    // setting was applied correctly. Guards against the NSInternalInconsistencyException
    // that CoreLocation throws if you set allowsBackgroundLocationUpdates without the mode declared.
    private static var hasBackgroundLocationMode: Bool {
        let modes = Bundle.main.infoDictionary?["UIBackgroundModes"] as? [String] ?? []
        return modes.contains("location")
    }

    // Triggers the iOS permission dialog asking for "Always" location access.
    // "Always" is needed so tracking continues when the screen locks while driving.
    func requestPermission() {
        clManager.requestAlwaysAuthorization()
    }

    func startTracking() {
        isTracking = true
        clManager.distanceFilter = 30
        clManager.startUpdatingLocation()
    }

    func stopTracking() {
        isTracking = false
        if isAutoTracking {
            // Auto tracking is still on — drop back to the battery-saving filter but keep running.
            clManager.distanceFilter = 100
        } else {
            clManager.stopUpdatingLocation()
        }
    }

    func startAutoTracking() {
        isAutoTracking = true
        if !isTracking {
            clManager.distanceFilter = 100
            clManager.startUpdatingLocation()
        }
    }

    func stopAutoTracking() {
        isAutoTracking = false
        if !isTracking {
            clManager.stopUpdatingLocation()
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationManager: CLLocationManagerDelegate {

    // CLLocationManager calls delegate methods on the thread it was created on (main thread here),
    // but with SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor the method must be nonisolated to satisfy
    // the Objective-C protocol requirement. We hop back to MainActor explicitly inside.
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // locations is an array — take the most recent fix only
        guard let location = locations.last else { return }
        Task { @MainActor in
            self.lastLocation = location
            // Diagnostic: confirms fixes are arriving AND that the visit pipeline is wired.
            // If "wired=false" ever appears here, onLocationUpdate was never set and no
            // visit would register no matter how good the GPS fix is.
            locationLog.info("fix lat=\(location.coordinate.latitude) lon=\(location.coordinate.longitude) acc=\(location.horizontalAccuracy) wired=\(self.onLocationUpdate != nil)")
            self.onLocationUpdate?(location)  // triggers PlacesManager.checkLocation(_:)
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.authorizationStatus = manager.authorizationStatus
        }
    }
}
