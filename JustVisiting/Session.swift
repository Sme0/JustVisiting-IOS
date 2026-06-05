import Foundation

struct Session: Identifiable, Codable {
    let id: UUID
    let startDate: Date
    private(set) var endDate: Date?
    private(set) var places: [Place]  // most recent first

    var isActive: Bool { endDate == nil }

    var duration: TimeInterval? {
        guard let end = endDate else { return nil }
        return end.timeIntervalSince(startDate)
    }

    init() {
        id = UUID()
        startDate = Date()
        endDate = nil
        places = []
    }

    mutating func record(_ newPlaces: [Place]) {
        for place in newPlaces.reversed() {
            places.insert(place, at: 0)
        }
    }

    mutating func end() {
        endDate = Date()
    }
}
