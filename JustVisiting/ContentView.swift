import SwiftUI
import CoreLocation

// Root view. Switches between the normal TabView and a minimal driving UI when
// CarPlay is connected.
struct ContentView: View {
    @Environment(LocationManager.self) private var locationManager
    @Environment(PlacesManager.self) private var placesManager
    @Environment(CarPlayDetector.self) private var carPlayDetector
    @Environment(AchievementsManager.self) private var achievementsManager
    @AppStorage("appearance") private var appearance = 0
    @State private var completedSession: Session?
    @State private var showingAchievementBanner = false
    @State private var displayedAchievement: AchievementDefinition?

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

                        AchievementsView()
                            .tabItem {
                                Label("Achievements", systemImage: "trophy.fill")
                            }

                        SessionsHistoryView()
                            .tabItem {
                                Label("History", systemImage: "calendar")
                            }

                        SettingsView()
                            .tabItem {
                                Label("Settings", systemImage: "gearshape.fill")
                            }
                    }
                    .preferredColorScheme(preferredColorScheme)

                    if let achievement = displayedAchievement {
                        AchievementBanner(achievement: achievement) {
                            achievementsManager.dismissBanner()
                        }
                        .offset(y: showingAchievementBanner ? 0 : -180)
                        .opacity(showingAchievementBanner ? 1 : 0)
                        .allowsHitTesting(showingAchievementBanner)
                        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: showingAchievementBanner)
                    }

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
        .onChange(of: achievementsManager.recentlyUnlocked) { _, newValue in
            if let newValue {
                displayedAchievement = newValue
                showingAchievementBanner = true
            } else {
                showingAchievementBanner = false
            }
        }
        .onAppear {
            if locationManager.authorizationStatus == .notDetermined {
                locationManager.requestPermission()
            }
            achievementsManager.evaluate(against: placesManager)
        }
        .onChange(of: placesManager.visitedIds.count) { _, _ in
            achievementsManager.evaluate(against: placesManager)
        }
        .onChange(of: placesManager.sessionHistory.count) { _, _ in
            achievementsManager.evaluate(against: placesManager)
        }
        .onChange(of: locationManager.isTracking) { _, isTracking in
            if isTracking {
                placesManager.startSession()
            } else {
                placesManager.endSession()
                if let session = placesManager.currentSession, !session.places.isEmpty {
                    completedSession = session
                }
            }
        }
        .sheet(item: $completedSession) { session in
            SessionSummaryView(session: session, isNew: true)
        }
    }
}

// MARK: - Achievement unlock banner

private struct AchievementBanner: View {
    let achievement: AchievementDefinition
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: achievement.icon)
                .font(.title3.weight(.semibold))
                .foregroundStyle(achievement.color)
                .frame(width: 42, height: 42)
                .background(achievement.color.opacity(0.15), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text("Achievement Unlocked!")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(achievement.title)
                    .font(.subheadline.weight(.bold))
            }

            Spacer()

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
}
