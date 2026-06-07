import Foundation
import CoreLocation
import Observation
import UIKit
import UserNotifications

// Central store for all place data and visit history.
// Handles fetching from the Overpass API, caching to disk, and real-time visit detection.
@Observable
final class PlacesManager {

    // The full list of UK settlements loaded from cache or the Overpass API (~60 k entries).
    var places: [Place] = []

    // OSM node IDs of every place the user has visited. Stored as a Set for O(1) lookup
    // during the hot path in checkLocation(), which runs on every GPS update.
    var visitedIds: Set<Int64> = []

    // OSM node IDs the user has explicitly hidden. Hidden places are excluded from the map
    // and from automatic visit detection, but their data is preserved in the places list.
    var hiddenIds: Set<Int64> = []

    var isLoading = false
    var loadError: String?

    // Set when a location update triggers visits; observed by views to show banners.
    var recentlyVisited: [Place] = []
    // Subset of recentlyVisited that are genuinely new (not previously visited).
    private(set) var recentlyNewPlaceIds: Set<Int64> = []
    // Incremented on every visit event so onChange fires even for repeat visits.
    private(set) var visitEventId: UUID = UUID()

    // The tracking session in progress, or the most recently completed one.
    // Nil only before the first session ever starts.
    private(set) var currentSession: Session?

    // All completed sessions that had at least one visit, newest first.
    private(set) var sessionHistory: [Session] = []

    func startSession() {
        currentSession = Session()
    }

    func endSession() {
        currentSession?.end()
        if let session = currentSession, !session.places.isEmpty {
            sessionHistory.insert(session, at: 0)
            saveSessions()
        }
    }

    // Paths to the JSON files in the app's Documents directory.
    private let placesURL: URL    // cached Overpass response — rebuilt if missing or on refresh
    private let visitedURL: URL   // persisted set of visited OSM IDs
    private let sessionsURL: URL  // completed session history
    private let hiddenURL: URL    // persisted set of hidden OSM IDs

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        placesURL = docs.appendingPathComponent("places.json")
        visitedURL = docs.appendingPathComponent("visited.json")
        sessionsURL = docs.appendingPathComponent("sessions.json")
        hiddenURL = docs.appendingPathComponent("hidden.json")

        // Load visited IDs synchronously so the map is correct the instant it appears.
        loadVisited()
        loadHidden()
        loadSessions()

        // Places are loaded async because the cache read (or network fetch) can take a moment.
        Task { await loadPlaces() }
    }

    // MARK: - Computed stats (used by StatsView)

    var visitedCount: Int { visitedIds.count }
    var totalCount: Int { places.count }

    var completionPercentage: Double {
        guard totalCount > 0 else { return 0 }
        return Double(visitedCount) / Double(totalCount) * 100
    }

    func isVisited(_ place: Place) -> Bool {
        visitedIds.contains(place.id)
    }

    func isHidden(_ place: Place) -> Bool {
        hiddenIds.contains(place.id)
    }

    // MARK: - Loading places

    // 1. On-disk cache (written after the first Overpass fetch or a manual refresh).
    // 2. Bundled places.json shipped with the app — instant on first launch, no network needed.
    // 3. Live Overpass fetch — only if both of the above are somehow missing.
    func loadPlaces() async {
        if let data = try? Data(contentsOf: placesURL),
           let decoded = try? JSONDecoder().decode([Place].self, from: data) {
            places = decoded
            return
        }
        if let url = Bundle.main.url(forResource: "places", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([Place].self, from: data) {
            places = decoded
            return
        }
        await fetchFromOverpass()
    }

    // Deletes the cache and re-fetches fresh data. Exposed as the "Refresh" button in StatsView.
    func refreshPlaces() async {
        try? FileManager.default.removeItem(at: placesURL)
        await fetchFromOverpass()
    }

    // Downloads all named cities, towns, villages and hamlets in the UK bounding box
    // from the OpenStreetMap Overpass API and caches the result to disk.
    func fetchFromOverpass() async {
        isLoading = true
        loadError = nil

        // Overpass QL query:
        //   [out:json]          — return JSON (not XML)
        //   [timeout:180]       — server-side timeout in seconds
        //   node[...](bbox)     — OSM nodes with a "place" tag inside the UK bounding box
        //                         bbox format is south,west,north,east
        let query = """
        [out:json][timeout:180];
        (
          node["place"~"^(city|town|village|hamlet)$"](49.9,-8.6,60.9,1.8);
        );
        out body;
        """

        do {
            guard let url = URL(string: "https://overpass-api.de/api/interpreter") else { return }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"          // Overpass requires POST for queries
            request.httpBody = query.data(using: .utf8)
            request.timeoutInterval = 200        // client-side timeout, slightly longer than server

            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(OverpassResponse.self, from: data)

            // Filter out any OSM nodes that lack a name or have an unrecognised place type.
            let fetched: [Place] = response.elements.compactMap { el in
                guard let name = el.tags["name"],
                      let typeStr = el.tags["place"],
                      let type = PlaceType(rawValue: typeStr) else { return nil }
                return Place(id: el.id, name: name, lat: el.lat, lon: el.lon, type: type, county: "")
            }

            places = fetched

            // Write the cache on a background thread so we don't block the UI.
            // We capture the URL value (not self) to avoid a reference to a MainActor-isolated type.
            let cacheURL = placesURL
            Task.detached(priority: .background) {
                if let encoded = try? JSONEncoder().encode(fetched) {
                    try? encoded.write(to: cacheURL)
                }
            }
        } catch {
            loadError = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - Visit detection

    // Called on every GPS update while tracking is active.
    // Uses a two-stage approach for performance:
    //   1. Cheap bounding-box filter to discard the vast majority of places instantly.
    //   2. Accurate CLLocation.distance() for the small set of candidates that pass stage 1.
    func checkLocation(_ location: CLLocation) {
        let lat = location.coordinate.latitude
        let lon = location.coordinate.longitude

        // The widest radius (city = 4 500 m). 1 degree of latitude ≈ 111 km,
        // so dividing converts metres to degrees for the bounding-box filter.
        let maxDeg = PlaceType.city.radiusMeters / 111_000.0

        // Places already recorded this session — each place is recorded at most once per session.
        let sessionPlaceIds = Set(currentSession?.places.map(\.id) ?? [])

        // Stage 1: throw away anything clearly outside the largest possible radius.
        // Longitude degrees are narrower at higher latitudes, so we widen that axis by 1.5×
        // to avoid false negatives near the edges.
        // Unlike before, we include already-visited places so revisits appear in the session.
        let candidates = places.filter { p in
            !hiddenIds.contains(p.id) &&
            !sessionPlaceIds.contains(p.id) &&
            abs(p.lat - lat) < maxDeg &&
            abs(p.lon - lon) < maxDeg * 1.5
        }

        // Stage 2: precise distance check using each place's actual radius threshold.
        var newVisits: [Place] = []
        var revisits: [Place] = []
        for place in candidates {
            if location.distance(from: place.clLocation) <= place.type.radiusMeters {
                if visitedIds.contains(place.id) {
                    revisits.append(place)
                } else {
                    visitedIds.insert(place.id)
                    newVisits.append(place)
                }
            }
        }

        let allVisited = newVisits + revisits
        if !allVisited.isEmpty {
            recentlyVisited = allVisited
            recentlyNewPlaceIds = Set(newVisits.map(\.id))
            visitEventId = UUID()
            currentSession?.record(newPlaces: newVisits, revisitedPlaces: revisits)
            if !newVisits.isEmpty {
                saveVisited()
                sendBackgroundNotification(for: newVisits)
            }
        }
    }

    private func sendBackgroundNotification(for places: [Place]) {
        guard UIApplication.shared.applicationState != .active else { return }
        let content = UNMutableNotificationContent()
        content.title = places.count == 1 ? "New place visited!" : "New places visited!"
        content.body = places.count == 1
            ? "You visited \(places[0].name)"
            : "You visited \(places[0].name) and \(places.count - 1) more"
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        )
    }

    // Marks all places as unvisited; session history is kept.
    func resetVisitedPlaces() {
        visitedIds = []
        try? FileManager.default.removeItem(at: visitedURL)
    }

    // Clears visited places and all session history.
    func resetProgress() {
        visitedIds = []
        sessionHistory = []
        try? FileManager.default.removeItem(at: visitedURL)
        try? FileManager.default.removeItem(at: sessionsURL)
    }

    // Hides or unhides a place. Hidden places don't appear on the map or trigger auto-visits.
    func toggleHidden(_ place: Place) {
        if hiddenIds.contains(place.id) {
            hiddenIds.remove(place.id)
        } else {
            hiddenIds.insert(place.id)
        }
        saveHidden()
    }

    func unhideAll() {
        hiddenIds = []
        try? FileManager.default.removeItem(at: hiddenURL)
    }

    // All currently hidden places, sorted by name. Used by HiddenPlacesView.
    var hiddenPlaces: [Place] {
        let ids = hiddenIds
        return places.filter { ids.contains($0.id) }.sorted { $0.name < $1.name }
    }

    // Lets the user manually flip a place's visited status by tapping it on the map.
    func toggleVisited(_ place: Place) {
        if visitedIds.contains(place.id) {
            visitedIds.remove(place.id)
        } else {
            visitedIds.insert(place.id)
        }
        saveVisited()
    }

    // MARK: - Per-type stats (used by StatsView)

    func visitedPlaces(of type: PlaceType) -> Int {
        places.filter { $0.type == type && visitedIds.contains($0.id) }.count
    }

    func totalPlaces(of type: PlaceType) -> Int {
        places.filter { $0.type == type }.count
    }

    // MARK: - Per-county stats (used by StatsView)

    struct CountyStat: Identifiable {
        let id: String  // county name
        let visited: Int
        let total: Int
        var fraction: Double { total > 0 ? Double(visited) / Double(total) : 0 }
    }

    var countyStats: [CountyStat] {
        var totals:   [String: Int] = [:]
        var visited:  [String: Int] = [:]
        for place in places where !place.county.isEmpty {
            totals[place.county, default: 0]  += 1
            if visitedIds.contains(place.id) {
                visited[place.county, default: 0] += 1
            }
        }
        return totals.map { county, total in
            CountyStat(id: county, visited: visited[county, default: 0], total: total)
        }.sorted { $0.id < $1.id }
    }

    // MARK: - Persistence

    // Loads visited IDs from disk. Called synchronously in init() so state is ready immediately.
    private func loadVisited() {
        guard let data = try? Data(contentsOf: visitedURL),
              let ids = try? JSONDecoder().decode(Set<Int64>.self, from: data) else { return }
        visitedIds = ids
    }

    // Persists visited IDs after every change so progress survives a force-quit.
    private func saveVisited() {
        if let encoded = try? JSONEncoder().encode(visitedIds) {
            try? encoded.write(to: visitedURL)
        }
    }

    private func loadHidden() {
        guard let data = try? Data(contentsOf: hiddenURL),
              let ids = try? JSONDecoder().decode(Set<Int64>.self, from: data) else { return }
        hiddenIds = ids
    }

    private func saveHidden() {
        let url = hiddenURL
        let ids = hiddenIds
        Task.detached(priority: .background) {
            if let encoded = try? JSONEncoder().encode(ids) {
                try? encoded.write(to: url)
            }
        }
    }

    private func loadSessions() {
        guard let data = try? Data(contentsOf: sessionsURL),
              let decoded = try? JSONDecoder().decode([Session].self, from: data) else { return }
        sessionHistory = decoded
    }

    private func saveSessions() {
        let url = sessionsURL
        let history = sessionHistory
        Task.detached(priority: .background) {
            if let encoded = try? JSONEncoder().encode(history) {
                try? encoded.write(to: url)
            }
        }
    }
}
