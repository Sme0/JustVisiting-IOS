import Foundation

struct Session: Identifiable, Codable {
    let id: UUID
    let startDate: Date
    private(set) var endDate: Date?
    private(set) var places: [Place]           // most recent first; new visits and revisits
    private(set) var revisitedIds: Set<Int64>  // IDs of places already visited before this session

    var isActive: Bool { endDate == nil }

    var newPlaceCount: Int { places.count - revisitedIds.count }
    var revisitCount: Int { revisitedIds.count }

    func isNewVisit(_ place: Place) -> Bool {
        !revisitedIds.contains(place.id)
    }

    var duration: TimeInterval? {
        guard let end = endDate else { return nil }
        return end.timeIntervalSince(startDate)
    }

    init() {
        id = UUID()
        startDate = Date()
        endDate = nil
        places = []
        revisitedIds = []
    }

    mutating func record(newPlaces: [Place], revisitedPlaces: [Place]) {
        for place in (newPlaces + revisitedPlaces).reversed() {
            places.insert(place, at: 0)
        }
        for place in revisitedPlaces {
            revisitedIds.insert(place.id)
        }
    }

    mutating func end() {
        endDate = Date()
    }
}
