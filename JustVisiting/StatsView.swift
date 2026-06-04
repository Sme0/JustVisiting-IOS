import SwiftUI

// Shows progress statistics broken down by settlement type.
// Handles three states: loading, empty/error, and the normal stats list.
struct StatsView: View {
    @Environment(PlacesManager.self) private var placesManager

    var body: some View {
        NavigationStack {
            Group {
                if placesManager.isLoading {
                    // Overpass fetch in progress — show a friendly holding screen.
                    ContentUnavailableView {
                        Label("Loading Places", systemImage: "arrow.down.circle")
                    } description: {
                        Text("Fetching towns and villages from OpenStreetMap…")
                        ProgressView().padding(.top, 8)
                    }

                } else if placesManager.places.isEmpty {
                    // Fetch finished but came back empty (network error, timeout, etc.).
                    ContentUnavailableView {
                        Label("No Places Loaded", systemImage: "map.slash")
                    } description: {
                        Text("Could not load location data.")
                        Button("Try Again") {
                            Task { await placesManager.fetchFromOverpass() }
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.top, 8)
                    }

                } else {
                    List {
                        // Overall totals at the top.
                        Section {
                            OverallProgressRow(
                                visited: placesManager.visitedCount,
                                total: placesManager.totalCount,
                                percentage: placesManager.completionPercentage
                            )
                        }

                        // One row per settlement type in descending size order.
                        Section("By Type") {
                            ForEach(PlaceType.allCases, id: \.self) { type in
                                TypeStatRow(
                                    type: type,
                                    visited: placesManager.visitedPlaces(of: type),
                                    total: placesManager.totalPlaces(of: type)
                                )
                            }
                        }

                        // One row per county/unitary authority, sorted alphabetically.
                        Section("By County") {
                            ForEach(placesManager.countyStats) { stat in
                                CountyStatRow(stat: stat)
                            }
                        }


                    }
                }
            }
            .navigationTitle("Statistics")
        }
    }
}

// MARK: - Sub-views

// Large headline row showing the total visited count, total count, and a progress bar.
struct OverallProgressRow: View {
    let visited: Int
    let total: Int
    let percentage: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                // Big number draws the eye first.
                Text("\(visited)")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                Text("/ \(total)")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.1f%%", percentage))
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(.green)
            }
            Text("places visited")
                .foregroundStyle(.secondary)
            ProgressView(value: percentage / 100)   // ProgressView expects 0–1, not 0–100
                .tint(.green)
        }
        .padding(.vertical, 8)
    }
}

// One row in the "By County" section — name, count, and a mini progress bar.
struct CountyStatRow: View {
    let stat: PlacesManager.CountyStat

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(stat.id)
                Spacer()
                Text("\(stat.visited) / \(stat.total)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            ProgressView(value: stat.fraction)
                .tint(.green)
        }
        .padding(.vertical, 4)
    }
}

// One row in the "By Type" section — icon, name, count, and a mini progress bar.
struct TypeStatRow: View {
    let type: PlaceType
    let visited: Int
    let total: Int

    // 0.0–1.0 fraction for ProgressView.
    var fraction: Double {
        guard total > 0 else { return 0 }
        return Double(visited) / Double(total)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: type.icon)
                .frame(width: 22)           // fixed width keeps all rows left-aligned
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(type.rawValue.capitalized)
                    Spacer()
                    Text("\(visited) / \(total)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()  // prevents count from shifting as digits change
                }
                ProgressView(value: fraction)
                    .tint(.green)
            }
        }
        .padding(.vertical, 4)
    }
}
