import SwiftUI
import CoreLocation
import UserNotifications

struct SettingsView: View {
    @Environment(LocationManager.self) private var locationManager
    @Environment(PlacesManager.self)   private var placesManager

    @AppStorage("filter.showCities")     private var showCities          = true
    @AppStorage("filter.showTowns")      private var showTowns           = true
    @AppStorage("filter.showVillages")   private var showVillages        = true
    @AppStorage("filter.showHamlets")    private var showHamlets         = true
    @AppStorage("filter.localOnly")      private var localOnly           = false
    @AppStorage("map.mapType")           private var mapType             = 0
    @AppStorage("appearance")            private var appearance          = 0
    @AppStorage("tracking.autoEnabled") private var autoTrackingEnabled = false

    @State private var showingResetConfirmation = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(isOn: $autoTrackingEnabled) {
                        Label("Background Visit Detection", systemImage: "location.fill.viewfinder")
                    }
                    .onChange(of: autoTrackingEnabled) { _, enabled in
                        if enabled {
                            locationManager.startAutoTracking()
                            Task {
                                try? await UNUserNotificationCenter.current()
                                    .requestAuthorization(options: [.alert, .sound])
                            }
                        } else {
                            locationManager.stopAutoTracking()
                        }
                    }
                } footer: {
                    Text("Keeps location running in the background and sends a notification when you visit a new place. Uses more battery than manual tracking.")
                }

                Section("Appearance") {
                    Picker("Theme", selection: $appearance) {
                        Label("System", systemImage: "circle.lefthalf.filled").tag(0)
                        Label("Light",  systemImage: "sun.max").tag(1)
                        Label("Dark",   systemImage: "moon").tag(2)
                    }
                    .pickerStyle(.navigationLink)
                }

                Section("Map Style") {
                    Picker("Map Type", selection: $mapType) {
                        Label("Standard",  systemImage: "map").tag(0)
                        Label("Satellite", systemImage: "globe").tag(1)
                        Label("Hybrid",    systemImage: "map.fill").tag(2)
                    }
                    .pickerStyle(.navigationLink)
                }

                Section("Map Filters") {
                    Toggle(isOn: $showCities)   { Label("Cities",   systemImage: PlaceType.city.icon) }
                    Toggle(isOn: $showTowns)    { Label("Towns",    systemImage: PlaceType.town.icon) }
                    Toggle(isOn: $showVillages) { Label("Villages", systemImage: PlaceType.village.icon) }
                    Toggle(isOn: $showHamlets)  { Label("Hamlets",  systemImage: PlaceType.hamlet.icon) }
                }

                Section {
                    Toggle(isOn: $localOnly) {
                        Label("Nearby places only", systemImage: "location.circle")
                    }
                    if localOnly && locationManager.lastLocation == nil {
                        Label("No location available — start tracking on the Map tab first.", systemImage: "location.slash")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                } footer: {
                    Text("Shows places within approximately 30 miles of your last known location.")
                }

                Section {
                    Button {
                        Task { await placesManager.refreshPlaces() }
                    } label: {
                        Label("Refresh Place Data", systemImage: "arrow.clockwise")
                    }
                } footer: {
                    Text("Place data is sourced from OpenStreetMap and cached locally. Refresh if you think data is outdated.")
                }

                Section {
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Label("Permissions", systemImage: "hand.raised")
                    }
                }

                Section {
                    Button(role: .destructive) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showingResetConfirmation = true
                        }
                    } label: {
                        Label("Reset All Progress", systemImage: "trash")
                    }
                } footer: {
                    Text("Permanently clears all visited places. This cannot be undone.")
                }
            }
            .navigationTitle("Settings")
            .overlay {
                if showingResetConfirmation {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                        .transition(.opacity)
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showingResetConfirmation = false
                            }
                        }

                    ResetConfirmationCard(visitedCount: placesManager.visitedCount) {
                        placesManager.resetProgress()
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showingResetConfirmation = false
                        }
                    } onCancel: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showingResetConfirmation = false
                        }
                    }
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
                }
            }
        }
    }
}

struct ResetConfirmationCard: View {
    let visitedCount: Int
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "trash.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(.red)
                .shadow(color: .red.opacity(0.3), radius: 8, y: 4)

            VStack(spacing: 8) {
                Text("Reset All Progress?")
                    .font(.title3)
                    .fontWeight(.bold)
                Text("This will permanently clear your entire visit history — \(visitedCount) \(visitedCount == 1 ? "place" : "places"). This cannot be undone.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 10) {
                Button(action: onConfirm) {
                    Text("Reset Progress")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(Color.red, in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(.white)
                }

                Button(action: onCancel) {
                    Text("Cancel")
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .foregroundStyle(.primary)
                }
                .glassEffect(in: RoundedRectangle(cornerRadius: 14))
            }
        }
        .padding(28)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24))
        .padding(.horizontal, 28)
        .shadow(color: .black.opacity(0.2), radius: 30, y: 12)
    }
}
