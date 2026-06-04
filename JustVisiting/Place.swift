import Foundation
import CoreLocation

// Represents the settlement hierarchy used by OpenStreetMap.
// The raw string values match the OSM "place" tag exactly, so JSON decoding works automatically.
enum PlaceType: String, Codable, CaseIterable, Hashable {
    case hamlet, village, town, city

    // How close the user needs to be (in metres) for a visit to count.
    var radiusMeters: Double {
        switch self {
        case .hamlet:  return 250
        case .village: return 500
        case .town:    return 1500
        case .city:    return 4500
        }
    }

    // SF Symbol name used in the Stats view to give each type a visual identity.
    var icon: String {
        switch self {
        case .city:    return "building.2"
        case .town:    return "building"
        case .village: return "house"
        case .hamlet:  return "house.lodge"
        }
    }
}

// A single named settlement fetched from the Overpass API.
// Stored as a flat struct so it serialises cheaply to/from JSON for the on-disk cache.
struct Place: Codable, Identifiable, Hashable {
    let id: Int64       // OSM node ID — globally unique and stable across refreshes
    let name: String
    let lat: Double
    let lon: Double
    let type: PlaceType

    // Convenience wrappers so callers don't have to construct these manually.
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    var clLocation: CLLocation {
        CLLocation(latitude: lat, longitude: lon)
    }

    // Identity and hashing are based purely on OSM ID so two Place values
    // for the same node are always considered equal regardless of other fields.
    static func == (lhs: Place, rhs: Place) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - Overpass API response shapes

// Top-level wrapper returned by the Overpass API in JSON mode.
struct OverpassResponse: Decodable {
    let elements: [OverpassElement]
}

// One OSM node from the Overpass response.
// We only care about a small subset of fields — everything else is ignored by the decoder.
struct OverpassElement: Decodable {
    let id: Int64
    let lat: Double
    let lon: Double
    let tags: [String: String]  // OSM key-value tags; we read "name" and "place" from here
}
