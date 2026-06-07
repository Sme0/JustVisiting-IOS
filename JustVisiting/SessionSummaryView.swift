import SwiftUI

struct SessionSummaryView: View {
    let session: Session
    var isNew: Bool = false
    @Environment(\.dismiss) private var dismiss

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    header
                    statCards
                    if !session.places.isEmpty {
                        typeBreakdown
                        placesList
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(spacing: 8) {
            if isNew {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(.green)
                    .padding(.top, 16)
                Text("Session Complete")
                    .font(.title2.weight(.bold))
            } else {
                Image(systemName: "clock.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(.blue)
                    .padding(.top, 16)
                Text(dateTitleLabel)
                    .font(.title2.weight(.bold))
            }
            Text(timeRangeLabel)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var statCards: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                StatCard(
                    value: "\(session.places.count)",
                    label: session.places.count == 1 ? "Place Visited" : "Places Visited"
                )
                StatCard(
                    value: "\(session.newPlaceCount)",
                    label: session.newPlaceCount == 1 ? "New Discovery" : "New Discoveries",
                    valueColor: .yellow
                )
            }
            if let duration = session.duration {
                StatCard(value: formattedDuration(duration), label: "Duration")
            }
        }
    }

    private var typeBreakdown: some View {
        let visibleTypes: [PlaceType] = PlaceType.allCases.reversed().filter { type in
            session.places.contains { $0.type == type }
        }
        return GroupBox("Breakdown") {
            VStack(spacing: 0) {
                ForEach(visibleTypes.indices, id: \.self) { index in
                    let type = visibleTypes[index]
                    let count = session.places.filter { $0.type == type }.count
                    HStack(spacing: 12) {
                        Image(systemName: type.filledIcon)
                            .foregroundStyle(type.summaryColor)
                            .frame(width: 22)
                        Text(count == 1 ? type.rawValue.capitalized : type.rawValue.capitalized + "s")
                        Spacer()
                        Text("\(count)")
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                    if index < visibleTypes.count - 1 {
                        Divider()
                    }
                }
            }
        }
    }

    private var placesList: some View {
        GroupBox("Places Visited") {
            VStack(spacing: 0) {
                ForEach(session.places.indices, id: \.self) { index in
                    let place = session.places[index]
                    let isNew = session.isNewVisit(place)
                    HStack(spacing: 12) {
                        Image(systemName: isNew ? "star.fill" : place.type.icon)
                            .foregroundStyle(isNew ? Color.yellow : place.type.summaryColor)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(place.name)
                                .fontWeight(.medium)
                            if !place.county.isEmpty {
                                Text(place.county)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text(place.type.rawValue.capitalized)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 8)
                    if index < session.places.count - 1 {
                        Divider()
                            .padding(.leading, 34)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private var dateTitleLabel: String {
        let cal = Calendar.current
        if cal.isDateInToday(session.startDate) { return "Today" }
        if cal.isDateInYesterday(session.startDate) { return "Yesterday" }
        let f = DateFormatter()
        f.dateFormat = "EEE d MMM"
        return f.string(from: session.startDate)
    }

    private var timeRangeLabel: String {
        let start = Self.timeFormatter.string(from: session.startDate)
        if let end = session.endDate {
            return "\(start) – \(Self.timeFormatter.string(from: end))"
        }
        return "Started at \(start)"
    }

    private func formattedDuration(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        let h = total / 3600
        let m = (total % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m) min" }
        return "< 1 min"
    }
}

// MARK: - Subviews

private struct StatCard: View {
    let value: String
    let label: String
    var valueColor: Color = .primary

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title.weight(.bold))
                .foregroundStyle(valueColor)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - PlaceType helpers for summary

private extension PlaceType {
    var summaryColor: Color {
        switch self {
        case .city:    return .blue
        case .town:    return .indigo
        case .village: return .teal
        case .hamlet:  return .mint
        }
    }

    var filledIcon: String {
        switch self {
        case .city:    return "building.2.fill"
        case .town:    return "building.fill"
        case .village: return "house.fill"
        case .hamlet:  return "house.lodge.fill"
        }
    }
}
