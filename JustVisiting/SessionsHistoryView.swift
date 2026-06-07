import SwiftUI

struct SessionsHistoryView: View {
    @Environment(PlacesManager.self) private var placesManager
    @State private var selectedSession: Session?

    var body: some View {
        NavigationStack {
            Group {
                if placesManager.sessionHistory.isEmpty {
                    ContentUnavailableView {
                        Label("No Sessions Yet", systemImage: "clock.arrow.circlepath")
                    } description: {
                        Text("Complete a tracking session to see it here.")
                    }
                } else {
                    List {
                        ForEach(groupedSessions, id: \.day) { group in
                            Section(group.day) {
                                ForEach(group.sessions) { session in
                                    SessionRow(session: session)
                                        .contentShape(Rectangle())
                                        .onTapGesture { selectedSession = session }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("History")
            .sheet(item: $selectedSession) { session in
                SessionSummaryView(session: session)
            }
        }
    }

    private var groupedSessions: [(day: String, sessions: [Session])] {
        var groups: [(day: String, sessions: [Session])] = []
        for session in placesManager.sessionHistory {
            let label = dayLabel(for: session.startDate)
            if let idx = groups.firstIndex(where: { $0.day == label }) {
                groups[idx].sessions.append(session)
            } else {
                groups.append((day: label, sessions: [session]))
            }
        }
        return groups
    }

    private func dayLabel(for date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date)     { return "Today" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        let f = DateFormatter()
        f.dateFormat = "EEE d MMM"
        return f.string(from: date)
    }
}

// MARK: - Session row

private struct SessionRow: View {
    let session: Session

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }()

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text(timeRangeLabel)
                    .fontWeight(.medium)
                Text(placeSummary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                if let duration = session.duration {
                    Text(formattedDuration(duration))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }

    private var timeRangeLabel: String {
        let start = Self.timeFormatter.string(from: session.startDate)
        guard let end = session.endDate else { return start }
        return "\(start) – \(Self.timeFormatter.string(from: end))"
    }

    private var placeSummary: String {
        let total = session.places.count
        guard total > 0 else { return "No places" }
        if session.revisitCount > 0 {
            let newCount = session.newPlaceCount
            return "\(newCount) new · \(session.revisitCount) revisited"
        }
        let first = session.places[0].name
        return total == 1 ? first : "\(first) +\(total - 1) more"
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
