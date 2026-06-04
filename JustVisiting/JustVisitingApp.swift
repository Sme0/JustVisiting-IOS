import SwiftUI

@main
struct JustVisitingApp: App {

    // Both managers live here at the top of the hierarchy so they outlive any individual view.
    // @State on a class works with @Observable — SwiftUI holds a reference and won't recreate them.
    @State private var placesManager = PlacesManager()
    @State private var locationManager = LocationManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                // Inject both managers into the environment so any descendant view can read them
                // with @Environment(PlacesManager.self) without prop-drilling through every layer.
                .environment(placesManager)
                .environment(locationManager)
                .onAppear {
                    // Wire the location pipeline: GPS update → visit check.
                    // Done here rather than inside either manager to keep them decoupled —
                    // LocationManager doesn't need to know PlacesManager exists, and vice versa.
                    // [weak placesManager] prevents a retain cycle since the closure is stored
                    // on locationManager which is itself owned by this App struct.
                    locationManager.onLocationUpdate = { [weak placesManager] location in
                        placesManager?.checkLocation(location)
                    }
                }
        }
    }
}
