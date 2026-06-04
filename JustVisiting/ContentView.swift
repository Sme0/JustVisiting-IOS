import SwiftUI
import CoreLocation

// Root view. Just a TabView that switches between the map and the stats screen.
// Location permission is requested here on first launch so the prompt appears
// immediately rather than only when the user taps "Start Tracking".
struct ContentView: View {
    @Environment(LocationManager.self) private var locationManager
    @AppStorage("appearance") private var appearance = 0

    private var preferredColorScheme: ColorScheme? {
        switch appearance {
        case 1: return .light
        case 2: return .dark
        default: return nil
        }
    }

    var body: some View {
        TabView {
            MapView()
                .tabItem {
                    Label("Map", systemImage: "map")
                }

            StatsView()
                .tabItem {
                    Label("Stats", systemImage: "chart.bar.fill")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
        }
        .preferredColorScheme(preferredColorScheme)
        .onAppear {
            // Only prompt if the user hasn't answered yet — avoids re-prompting on
            // subsequent app launches or scene re-activations.
            if locationManager.authorizationStatus == .notDetermined {
                locationManager.requestPermission()
            }
        }
    }
}
