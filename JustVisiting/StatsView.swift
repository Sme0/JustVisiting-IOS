import SwiftUI
import Charts

// MARK: - View-only extensions

private extension PlaceType {
    var color: Color {
        switch self {
        case .city:    return .indigo
        case .town:    return .orange
        case .village: return Color(red: 0.18, green: 0.72, blue: 0.40)
        case .hamlet:  return Color(red: 0.63, green: 0.42, blue: 0.20)
        }
    }

    var plural: String {
        switch self {
        case .city:    return "Cities"
        case .town:    return "Towns"
        case .village: return "Villages"
        case .hamlet:  return "Hamlets"
        }
    }
}

private extension PlacesManager {
    var bestSessionPlaces: Int {
        sessionHistory.map(\.places.count).max() ?? 0
    }

    var totalTrackingTime: TimeInterval {
        sessionHistory.compactMap(\.duration).reduce(0, +)
    }

    var placesVisitedThisWeek: Int {
        let cutoff = Calendar.current.date(byAdding: .weekOfYear, value: -1, to: Date()) ?? Date()
        return sessionHistory
            .filter { $0.startDate >= cutoff }
            .reduce(0) { $0 + $1.places.count }
    }
}

// MARK: - Pie slice model

private struct CountySlice: Identifiable {
    let id: String
    let visited: Int
    let color: Color
}

// MARK: - Root view

struct StatsView: View {
    @Environment(PlacesManager.self) private var pm
    @State private var animate      = false
    @State private var showCounties = false

    var body: some View {
        NavigationStack {
            Group {
                if pm.isLoading {
                    ContentUnavailableView {
                        Label("Loading Places", systemImage: "arrow.down.circle")
                    } description: {
                        Text("Fetching towns and villages from OpenStreetMap…")
                        ProgressView().padding(.top, 8)
                    }

                } else if pm.places.isEmpty {
                    ContentUnavailableView {
                        Label("No Places Loaded", systemImage: "map.slash")
                    } description: {
                        Text("Could not load location data.")
                        Button("Try Again") { Task { await pm.fetchFromOverpass() } }
                            .buttonStyle(.borderedProminent)
                            .padding(.top, 8)
                    }

                } else {
                    let countyStats = pm.countyStats
                    let slices      = buildSlices(from: countyStats)

                    ScrollView {
                        VStack(spacing: 20) {
                            ProgressRingCard(pm: pm, animate: animate)

                            if !pm.sessionHistory.isEmpty {
                                JourneyStatsCard(pm: pm)
                            }

                            TypeBreakdownCard(pm: pm, animate: animate)

                            if !slices.isEmpty {
                                TopCountiesCard(slices: slices)
                                CountyHighlightsCard(stats: countyStats)
                            }

                            CountyListSection(stats: countyStats, expanded: $showCounties)
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 24)
                    }
                    .onAppear {
                        withAnimation(.easeOut(duration: 1.2).delay(0.1)) { animate = true }
                    }
                    .onDisappear { animate = false }
                }
            }
            .navigationTitle("Statistics")
        }
    }

    private func buildSlices(from stats: [PlacesManager.CountyStat]) -> [CountySlice] {
        let palette: [Color] = [
            Color(red: 0.28, green: 0.52, blue: 0.95),
            Color(red: 0.56, green: 0.35, blue: 0.95),
            Color(red: 0.93, green: 0.44, blue: 0.24),
            Color(red: 0.17, green: 0.76, blue: 0.57),
            Color(red: 0.95, green: 0.73, blue: 0.14),
            Color(red: 0.95, green: 0.33, blue: 0.63),
            Color(red: 0.33, green: 0.73, blue: 0.33),
            Color(red: 0.75, green: 0.50, blue: 0.28),
        ]
        return stats
            .filter { $0.visited > 0 }
            .sorted { $0.visited > $1.visited }
            .prefix(8)
            .enumerated()
            .map { i, stat in CountySlice(id: stat.id, visited: stat.visited, color: palette[i % palette.count]) }
    }
}

// MARK: - Big progress ring

private struct ProgressRingCard: View {
    let pm: PlacesManager
    let animate: Bool

    private var fraction: Double { pm.completionPercentage / 100 }

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.07), lineWidth: 20)
                    .frame(width: 190, height: 190)

                Circle()
                    .trim(from: 0, to: animate ? fraction : 0)
                    .stroke(
                        LinearGradient(
                            colors: [.green, Color(red: 0.25, green: 0.85, blue: 0.55)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 20, lineCap: .round)
                    )
                    .frame(width: 190, height: 190)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 1.2), value: animate)

                VStack(spacing: 4) {
                    Text(String(format: "%.1f%%", pm.completionPercentage))
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                    Text("complete")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 8)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(pm.visitedCount)")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                Text("of \(pm.totalCount) places visited")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
    }
}

// MARK: - Journey highlights

private struct JourneyStatsCard: View {
    let pm: PlacesManager

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Your Journey", systemImage: "car.fill")
                .font(.headline)
                .padding(.horizontal, 4)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                StatTile(value: "\(pm.sessionHistory.count)",   label: "Trips",        systemImage: "car.fill",   color: .blue)
                StatTile(value: "\(pm.bestSessionPlaces)",      label: "Best Trip",    systemImage: "star.fill",  color: .orange)
                StatTile(value: "\(pm.placesVisitedThisWeek)", label: "This Week",    systemImage: "calendar",   color: .green)
                StatTile(value: formatTime(pm.totalTrackingTime), label: "Time Tracked", systemImage: "clock.fill", color: .purple)
            }
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    private func formatTime(_ t: TimeInterval) -> String {
        let h = Int(t) / 3600
        let m = (Int(t) % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m" }
        return "—"
    }
}

private struct StatTile: View {
    let value: String
    let label: String
    let systemImage: String
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.callout)
                .foregroundStyle(color)
                .frame(width: 34, height: 34)
                .background(color.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(.headline, design: .rounded))
                    .fontWeight(.bold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Settlement type breakdown (2×2 mini rings)

private struct TypeBreakdownCard: View {
    let pm: PlacesManager
    let animate: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Settlement Types", systemImage: "building.2")
                .font(.headline)
                .padding(.horizontal, 4)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(Array(PlaceType.allCases.reversed()), id: \.self) { type in
                    TypeRingTile(
                        type: type,
                        visited: pm.visitedPlaces(of: type),
                        total:   pm.totalPlaces(of: type),
                        animate: animate
                    )
                }
            }
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
}

private struct TypeRingTile: View {
    let type: PlaceType
    let visited: Int
    let total: Int
    let animate: Bool

    private var fraction: Double { total > 0 ? Double(visited) / Double(total) : 0 }

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(type.color.opacity(0.15), lineWidth: 10)
                    .frame(width: 76, height: 76)

                Circle()
                    .trim(from: 0, to: animate ? fraction : 0)
                    .stroke(type.color, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .frame(width: 76, height: 76)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 1.2), value: animate)

                Image(systemName: type.icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(type.color)
            }

            VStack(spacing: 3) {
                Text(type.plural)
                    .font(.subheadline.weight(.semibold))
                Text("\(visited) / \(total)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Text(String(format: "%.0f%%", fraction * 100))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(type.color)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Top counties donut chart

private struct TopCountiesCard: View {
    let slices: [CountySlice]

    private var total: Int { slices.reduce(0) { $0 + $1.visited } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Top Counties", systemImage: "map")
                .font(.headline)
                .padding(.horizontal, 4)

            ZStack {
                Chart {
                    ForEach(slices) { slice in
                        SectorMark(
                            angle: .value("Visited", slice.visited),
                            innerRadius: .ratio(0.55),
                            angularInset: 2
                        )
                        .foregroundStyle(slice.color)
                    }
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .chartLegend(.hidden)
                .frame(height: 220)

                VStack(spacing: 4) {
                    Text("\(total)")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                    Text("visited")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                ForEach(slices) { slice in
                    HStack(spacing: 7) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(slice.color)
                            .frame(width: 10, height: 10)
                        Text(slice.id)
                            .font(.caption)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Text("\(slice.visited)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
}

// MARK: - County highlights

private struct CountyHighlightsCard: View {
    let stats: [PlacesManager.CountyStat]

    private var started: [PlacesManager.CountyStat] { stats.filter { $0.visited > 0 } }
    private var topVisited:  PlacesManager.CountyStat? { started.max(by: { $0.visited  < $1.visited  }) }
    private var topComplete: PlacesManager.CountyStat? { started.max(by: { $0.fraction < $1.fraction }) }
    private var completedCount: Int { stats.filter { $0.visited == $0.total && $0.total > 0 }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("County Highlights", systemImage: "map.fill")
                .font(.headline)
                .padding(.horizontal, 4)

            VStack(spacing: 8) {
                CountyHighlightRow(
                    systemImage: "crown.fill", color: .yellow,
                    label: "Most Visited",
                    value: topVisited?.id ?? "—",
                    detail: topVisited.map { "\($0.visited) places" }
                )
                CountyHighlightRow(
                    systemImage: "checkmark.seal.fill", color: .green,
                    label: "Most Complete",
                    value: topComplete?.id ?? "—",
                    detail: topComplete.map { String(format: "%.0f%%", $0.fraction * 100) }
                )
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    StatTile(
                        value: "\(started.count) / \(stats.count)",
                        label: "Explored",
                        systemImage: "flag.fill",
                        color: .blue
                    )
                    StatTile(
                        value: "\(completedCount)",
                        label: "Completed",
                        systemImage: "rosette",
                        color: .orange
                    )
                }
            }
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
}

private struct CountyHighlightRow: View {
    let systemImage: String
    let color: Color
    let label: String
    let value: String
    let detail: String?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.callout)
                .foregroundStyle(color)
                .frame(width: 34, height: 34)
                .background(color.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            Spacer(minLength: 0)
            if let detail {
                Text(detail)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Collapsible county list

private struct CountyListSection: View {
    let stats: [PlacesManager.CountyStat]
    @Binding var expanded: Bool

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) { expanded.toggle() }
            } label: {
                HStack {
                    Label("All Counties", systemImage: "list.bullet")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Spacer()
                    Text("\(stats.count)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(18)
            }
            .buttonStyle(.plain)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))

            if expanded {
                VStack(spacing: 0) {
                    ForEach(stats) { stat in
                        CountyRow(stat: stat)
                        Divider()
                            .padding(.leading, 12)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 8)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
                .padding(.top, 2)
                .transition(.opacity)
            }
        }
    }
}

private struct CountyRow: View {
    let stat: PlacesManager.CountyStat

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(stat.id)
                    .font(.subheadline)
                Spacer()
                Text("\(stat.visited) / \(stat.total)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            ProgressView(value: stat.fraction)
                .tint(.green)
        }
        .padding(.vertical, 8)
    }
}
