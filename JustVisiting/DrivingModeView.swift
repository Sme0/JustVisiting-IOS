import SwiftUI

struct DrivingModeView: View {
    @Environment(LocationManager.self) private var locationManager
    @Environment(PlacesManager.self) private var placesManager
    @Environment(CarPlayDetector.self) private var carPlayDetector

    @State private var showingVisitBanner = false
    @State private var visitBannerName = ""
    @State private var visitBannerIsNew = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                Button {
                    if locationManager.isTracking {
                        locationManager.stopTracking()
                    } else {
                        locationManager.startTracking()
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(locationManager.isTracking ? Color.red : Color.accentColor)
                            .frame(width: 180, height: 180)
                            .shadow(
                                color: (locationManager.isTracking ? Color.red : Color.accentColor).opacity(0.5),
                                radius: 24
                            )
                        Image(systemName: locationManager.isTracking ? "stop.fill" : "record.circle")
                            .font(.system(size: 64))
                            .foregroundStyle(.white)
                    }
                }
                .buttonStyle(.plain)

                Text(locationManager.isTracking ? "Tracking" : "Tap to Start")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .padding(.top, 20)

                Spacer()

                // Session visits
                VStack(alignment: .leading, spacing: 14) {
                    if placesManager.currentSession?.places.isEmpty ?? true {
                        Text(locationManager.isTracking
                             ? "No places visited yet this session"
                             : "Start tracking to record visits")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .center)
                    } else {
                        ForEach(Array((placesManager.currentSession?.places ?? []).prefix(3))) { place in
                            let isNew = placesManager.currentSession?.isNewVisit(place) ?? true
                            HStack(spacing: 12) {
                                Image(systemName: isNew ? "star.fill" : "checkmark.circle.fill")
                                    .foregroundStyle(isNew ? Color.yellow : Color.green)
                                Text(place.name)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.white)
                                Spacer()
                                Text(place.type.rawValue.capitalized)
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
                .padding(.horizontal, 32)
                .frame(minHeight: 90)
                .padding(.bottom, 12)

                if showingVisitBanner {
                    Text(visitBannerIsNew ? "Discovered \(visitBannerName)!" : "Back in \(visitBannerName)!")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(visitBannerIsNew ? Color.yellow.opacity(0.30) : Color.green.opacity(0.25), in: Capsule())
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding(.bottom, 8)
                }

                VStack(spacing: 10) {
                    Button("Exit Driving Mode") {
                        carPlayDetector.userDismissedDrivingMode = true
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                    Text("\(placesManager.visitedIds.count) places visited total")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.bottom, 36)
            }
        }
        .preferredColorScheme(.dark)
        .onChange(of: placesManager.visitEventId) {
            guard !placesManager.recentlyVisited.isEmpty else { return }

            let hasNew = !placesManager.recentlyNewPlaceIds.isEmpty
            // Prefer leading with a new discovery if one exists
            let first = hasNew
                ? (placesManager.recentlyVisited.first { placesManager.recentlyNewPlaceIds.contains($0.id) } ?? placesManager.recentlyVisited[0])
                : placesManager.recentlyVisited[0]
            visitBannerIsNew = hasNew
            visitBannerName = placesManager.recentlyVisited.count == 1
                ? first.name
                : "\(first.name) and \(placesManager.recentlyVisited.count - 1) more"
            withAnimation(.spring) { showingVisitBanner = true }
            Task {
                try? await Task.sleep(for: .seconds(4))
                withAnimation { showingVisitBanner = false }
            }
        }
    }
}
