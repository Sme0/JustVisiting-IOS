import SwiftUI

struct DrivingModeView: View {
    @Environment(LocationManager.self) private var locationManager
    @Environment(PlacesManager.self) private var placesManager
    @Environment(CarPlayDetector.self) private var carPlayDetector

    @State private var showingVisitBanner = false
    @State private var visitBannerName = ""
    @State private var sessionVisits: [Place] = []

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
                    if sessionVisits.isEmpty {
                        Text(locationManager.isTracking
                             ? "No places visited yet this session"
                             : "Start tracking to record visits")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .center)
                    } else {
                        ForEach(sessionVisits) { place in
                            HStack(spacing: 12) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
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
                    Text("Visited \(visitBannerName)!")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(.green.opacity(0.25), in: Capsule())
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding(.bottom, 8)
                }

                VStack(spacing: 10) {
                    #if DEBUG
                    Button("Exit Driving Mode") {
                        carPlayDetector.debugForceConnected = false
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    #endif

                    Text("\(placesManager.visitedIds.count) places visited total")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.bottom, 36)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            if !locationManager.isTracking { sessionVisits = [] }
        }
        .onChange(of: locationManager.isTracking) { _, isTracking in
            if isTracking { sessionVisits = [] }
        }
        .onChange(of: placesManager.recentlyVisited) {
            guard !placesManager.recentlyVisited.isEmpty else { return }

            for place in placesManager.recentlyVisited.reversed() {
                sessionVisits.insert(place, at: 0)
            }
            sessionVisits = Array(sessionVisits.prefix(3))

            let first = placesManager.recentlyVisited[0]
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
