import SwiftUI

enum AchievementCategory: String, CaseIterable {
    case exploration = "Exploration"
    case placeTypes  = "Place Types"
    case trips       = "Trips"
    case counties    = "Counties"

    var icon: String {
        switch self {
        case .exploration: return "figure.hiking"
        case .placeTypes:  return "building.2"
        case .trips:       return "car.fill"
        case .counties:    return "map.fill"
        }
    }
}

struct AchievementDefinition {
    let id: String
    let title: String
    let description: String
    let icon: String
    let color: Color
    let category: AchievementCategory
    let check: (PlacesManager) -> Bool

    static let all: [AchievementDefinition] = [
        // MARK: Exploration
        .init(id: "visits_1",    title: "First Step",  description: "Visit your first place",   icon: "mappin.circle.fill", color: .green,  category: .exploration, check: { $0.visitedCount >= 1 }),
        .init(id: "visits_10",   title: "Explorer",    description: "Visit 10 places",          icon: "figure.walk",        color: .blue,   category: .exploration, check: { $0.visitedCount >= 10 }),
        .init(id: "visits_50",   title: "Adventurer",  description: "Visit 50 places",          icon: "figure.hiking",      color: .orange, category: .exploration, check: { $0.visitedCount >= 50 }),
        .init(id: "visits_100",  title: "Centurion",   description: "Visit 100 places",         icon: "star.fill",          color: .yellow, category: .exploration, check: { $0.visitedCount >= 100 }),
        .init(id: "visits_250",  title: "Trailblazer", description: "Visit 250 places",         icon: "flame.fill",         color: .orange, category: .exploration, check: { $0.visitedCount >= 250 }),
        .init(id: "visits_500",  title: "Wanderer",    description: "Visit 500 places",         icon: "wind",               color: .teal,   category: .exploration, check: { $0.visitedCount >= 500 }),
        .init(id: "visits_1000", title: "Legend",      description: "Visit 1,000 places",       icon: "crown.fill",         color: .yellow, category: .exploration, check: { $0.visitedCount >= 1000 }),

        // MARK: Place Types
        .init(id: "city_1",    title: "City Dweller",        description: "Visit a city",                                    icon: "building.2.fill",  color: .indigo,                                      category: .placeTypes, check: { $0.visitedPlaces(of: .city) >= 1 }),
        .init(id: "city_5",    title: "City Slicker",        description: "Visit 5 cities",                                  icon: "building.2.fill",  color: .indigo,                                      category: .placeTypes, check: { $0.visitedPlaces(of: .city) >= 5 }),
        .init(id: "hamlet_10", title: "Off the Beaten Track", description: "Visit 10 hamlets",                               icon: "house.lodge.fill", color: Color(red: 0.63, green: 0.42, blue: 0.20),    category: .placeTypes, check: { $0.visitedPlaces(of: .hamlet) >= 10 }),
        .init(id: "all_types", title: "Well-Rounded",        description: "Visit a hamlet, village, town, and city",        icon: "square.grid.2x2.fill", color: .purple,                                  category: .placeTypes, check: { pm in PlaceType.allCases.allSatisfy { pm.visitedPlaces(of: $0) >= 1 } }),

        // MARK: Trips
        .init(id: "trip_1",     title: "First Trip",  description: "Complete your first trip",          icon: "car.fill",  color: .blue,   category: .trips, check: { !$0.sessionHistory.isEmpty }),
        .init(id: "trip_10",    title: "Day Tripper", description: "Complete 10 trips",                 icon: "car.fill",  color: .cyan,   category: .trips, check: { $0.sessionHistory.count >= 10 }),
        .init(id: "session_10", title: "Big Day Out", description: "Visit 10 places in a single trip",  icon: "bolt.fill", color: .yellow, category: .trips, check: { ($0.sessionHistory.map(\.places.count).max() ?? 0) >= 10 }),
        .init(id: "session_20", title: "Marathon",    description: "Visit 20 places in a single trip",  icon: "bolt.fill", color: .orange, category: .trips, check: { ($0.sessionHistory.map(\.places.count).max() ?? 0) >= 20 }),

        // MARK: Counties
        .init(id: "counties_5",  title: "County Hopper",    description: "Explore 5 counties",           icon: "map.fill",            color: .teal,  category: .counties, check: { $0.countyStats.filter { $0.visited > 0 }.count >= 5 }),
        .init(id: "counties_10", title: "County Collector",  description: "Explore 10 counties",         icon: "map.fill",            color: .cyan,  category: .counties, check: { $0.countyStats.filter { $0.visited > 0 }.count >= 10 }),
        .init(id: "county_done", title: "County Champion",   description: "Complete 100% of any county", icon: "checkmark.seal.fill", color: .green, category: .counties, check: { $0.countyStats.contains { $0.fraction >= 1.0 && $0.total > 0 } }),
    ]
}

extension AchievementDefinition: Equatable {
    static func == (lhs: AchievementDefinition, rhs: AchievementDefinition) -> Bool {
        lhs.id == rhs.id
    }
}

struct AchievementRecord: Codable {
    let id: String
    let unlockedAt: Date
}
