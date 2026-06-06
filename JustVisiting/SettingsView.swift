import SwiftUI
import CoreLocation
import UserNotifications

struct SettingsView: View {
    @Environment(LocationManager.self)   private var locationManager
    @Environment(PlacesManager.self)     private var placesManager
    @Environment(CarPlayDetector.self)   private var carPlayDetector

    @AppStorage("filter.localOnly")      private var localOnly           = false
    @AppStorage("map.mapType")           private var mapType             = 0
    @AppStorage("appearance")            private var appearance          = 0
    @AppStorage("tracking.autoEnabled") private var autoTrackingEnabled = false

    private enum ResetAction { case clearVisits, allData }
    @State private var pendingReset: ResetAction?

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

                #if DEBUG
                Section("Debug") {
                    Toggle(isOn: Bindable(carPlayDetector).debugForceConnected) {
                        Label("Simulate CarPlay", systemImage: "car")
                    }
                }
                #endif

                Section {
                    Button(role: .destructive) {
                        withAnimation(.easeInOut(duration: 0.2)) { pendingReset = .clearVisits }
                    } label: {
                        Label("Clear Visited Places", systemImage: "mappin.slash")
                    }
                } footer: {
                    Text("Marks all places as unvisited. Your session history is kept.")
                }

                Section {
                    Button(role: .destructive) {
                        withAnimation(.easeInOut(duration: 0.2)) { pendingReset = .allData }
                    } label: {
                        Label("Reset All Data", systemImage: "trash")
                    }
                } footer: {
                    Text("Permanently clears all visited places and session history. This cannot be undone.")
                }
            }
            .navigationTitle("Settings")
            .overlay {
                if pendingReset != nil {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                        .transition(.opacity)
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.2)) { pendingReset = nil }
                        }

                    resetCard
                        .transition(.scale(scale: 0.92).combined(with: .opacity))
                }
            }
        }
    }

    @ViewBuilder
    private var resetCard: some View {
        let n = placesManager.visitedCount
        switch pendingReset {
        case .clearVisits:
            ResetConfirmationCard(
                title: "Clear Visited Places?",
                message: "This will mark all \(n) \(n == 1 ? "place" : "places") as unvisited. Your session history will be kept.",
                confirmLabel: "Clear Visited Places"
            ) {
                placesManager.resetVisitedPlaces()
                withAnimation(.easeInOut(duration: 0.2)) { pendingReset = nil }
            } onCancel: {
                withAnimation(.easeInOut(duration: 0.2)) { pendingReset = nil }
            }
        case .allData:
            ResetConfirmationCard(
                title: "Reset All Data?",
                message: "This will permanently clear your \(n) visited \(n == 1 ? "place" : "places") and all session history. This cannot be undone.",
                confirmLabel: "Reset All Data"
            ) {
                placesManager.resetProgress()
                withAnimation(.easeInOut(duration: 0.2)) { pendingReset = nil }
            } onCancel: {
                withAnimation(.easeInOut(duration: 0.2)) { pendingReset = nil }
            }
        case nil:
            EmptyView()
        }
    }
}

struct ResetConfirmationCard: View {
    let title: String
    let message: String
    let confirmLabel: String
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "trash.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(.red)
                .shadow(color: .red.opacity(0.3), radius: 8, y: 4)

            VStack(spacing: 8) {
                Text(title)
                    .font(.title3)
                    .fontWeight(.bold)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 10) {
                Button(action: onConfirm) {
                    Text(confirmLabel)
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
