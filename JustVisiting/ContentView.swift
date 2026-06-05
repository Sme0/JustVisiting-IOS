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
            if carPlayDetector.shouldShowDrivingMode {
                DrivingModeView()
                    .transition(.opacity)
            } else {
                ZStack(alignment: .top) {
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

                    // Shown when CarPlay is still connected but the user exited driving mode.
                    if carPlayDetector.isConnected {
                        Button {
                            withAnimation(.easeInOut(duration: 0.4)) {
                                carPlayDetector.userDismissedDrivingMode = false
                            }
                        } label: {
                            Label("Return to Driving Mode", systemImage: "car.fill")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(.regularMaterial, in: Capsule())
                                .shadow(radius: 4)
                        }
                        .foregroundStyle(.primary)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: carPlayDetector.shouldShowDrivingMode)
        .animation(.spring, value: carPlayDetector.isConnected)
        .onAppear {
            if locationManager.authorizationStatus == .notDetermined {
                locationManager.requestPermission()
            }
        }
    }
}
