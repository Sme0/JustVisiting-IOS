import SwiftUI

@main
struct JustVisitingApp: App {

    // Both managers live here at the top of the hierarchy so they outlive any individual view.
    // @State on a class works with @Observable — SwiftUI holds a reference and won't recreate them.
    @State private var placesManager: PlacesManager
    @State private var locationManager: LocationManager
    @State private var carPlayDetector = CarPlayDetector()
    @State private var achievementsManager = AchievementsManager()

    init() {
        let placesManager = PlacesManager()
        let locationManager = LocationManager()

        // Wire the location pipeline: GPS update → visit check.
        // Done at construction (NOT in a view's .onAppear) so it can never be skipped:
        // a SwiftUI lifecycle hook isn't guaranteed to run when the scene comes up via
        // CarPlay or a background/location relaunch, which would silently break visit
        // detection even though GPS fixes keep arriving.
        // [weak placesManager] prevents a retain cycle since the closure is stored
        // on locationManager which is itself owned by this App struct.
        locationManager.onLocationUpdate = { [weak placesManager] location in
            placesManager?.checkLocation(location)
        }

        _placesManager = State(initialValue: placesManager)
        _locationManager = State(initialValue: locationManager)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                // Inject both managers into the environment so any descendant view can read them
                // with @Environment(PlacesManager.self) without prop-drilling through every layer.
                .environment(placesManager)
                .environment(locationManager)
                .environment(carPlayDetector)
                .environment(achievementsManager)
        }
    }
}
