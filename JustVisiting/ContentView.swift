import SwiftUI
import CoreLocation

// Root view. Switches between the normal TabView and a minimal driving UI when
// CarPlay is connected.
struct ContentView: View {
    @Environment(LocationManager.self) private var locationManager
    @Environment(CarPlayDetector.self) private var carPlayDetector
    @AppStorage("appearance") private var appearance = 0

    private var preferredColorScheme: ColorScheme? {
        switch appearance {
        case 1: return .light
        case 2: return .dark
        default: return nil
        }
    }

    var body: some View {
        ZStack {
            if carPlayDetector.isConnected {
                DrivingModeView()
                    .transition(.opacity)
            } else {
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
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: carPlayDetector.isConnected)
        .onAppear {
            if locationManager.authorizationStatus == .notDetermined {
                locationManager.requestPermission()
            }
        }
    }
}
