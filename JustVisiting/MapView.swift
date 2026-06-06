import SwiftUI
import MapKit
import UIKit

// The main screen. Shows a clustered MapKit map with a marker for every settlement,
// a start/stop tracking button, and a banner when a new place is visited.
struct MapView: View {
    @Environment(PlacesManager.self) private var placesManager
    @Environment(LocationManager.self) private var locationManager

    @AppStorage("filter.showCities")    private var showCities    = true
    @AppStorage("filter.showTowns")     private var showTowns     = true
    @AppStorage("filter.showVillages")  private var showVillages  = true
    @AppStorage("filter.showHamlets")   private var showHamlets   = true
    @AppStorage("filter.localOnly")     private var localOnly     = false
    @AppStorage("filter.visitedStatus") private var visitedFilter = 0  // 0=All, 1=Visited, 2=Not Visited
    @AppStorage("filter.county")        private var countyFilter  = ""
    @AppStorage("map.mapType")          private var mapType       = 0

    private var enabledTypes: Set<PlaceType> {
        var types = Set<PlaceType>()
        if showCities   { types.insert(.city) }
        if showTowns    { types.insert(.town) }
        if showVillages { types.insert(.village) }
        if showHamlets  { types.insert(.hamlet) }
        return types
    }

    @State private var selectedPlace: Place?
    @State private var showingFilters = false

    private var activeFilterCount: Int {
        let typesFiltered = (!showCities || !showTowns || !showVillages || !showHamlets) ? 1 : 0
        return (visitedFilter != 0 ? 1 : 0) + (countyFilter.isEmpty ? 0 : 1) + typesFiltered
    }

    private var availableCounties: [String] {
        Array(Set(placesManager.places.compactMap { $0.county.isEmpty ? nil : $0.county })).sorted()
    }

    // Drives "recenter on me": the location button sets .follow; MapKit resets it to
    // .none as soon as the user pans, and the delegate syncs that back here.
    @State private var userTrackingMode: MKUserTrackingMode = .none

    // Controls the "Visited X!" banner at the top of the screen.
    @State private var showingNewVisitBanner = false
    @State private var newVisitName = ""

    var body: some View {
        ZStack(alignment: .bottom) {

            // MARK: Map
            // MKMapView (via the representable below) clusters the ~60 k markers natively,
            // recycles annotation views, and only renders what's on screen — so there's no
            // per-frame filtering or thousands of live SwiftUI views to diff.
            ClusteredMapView(
                places: placesManager.places,
                visitedIds: placesManager.visitedIds,
                enabledTypes: enabledTypes,
                localCenter: localOnly ? locationManager.lastLocation : nil,
                visitedFilter: visitedFilter,
                countyFilter: countyFilter,
                mapType: mapType,
                selectedPlace: $selectedPlace,
                userTrackingMode: $userTrackingMode
            )
            .ignoresSafeArea()

            // MARK: Overlay controls

            VStack(spacing: 0) {

                // Visit banner slides in from the top and auto-dismisses after 3 seconds.
                if showingNewVisitBanner {
                    NewVisitBanner(name: newVisitName)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .padding(.top, 8)
                }

                Spacer()

                // Show loading/error state just above the tracking button.
                if placesManager.isLoading {
                    LoadingPill()
                        .padding(.bottom, 12)
                } else if let error = placesManager.loadError {
                    RetryButton(error: error) {
                        Task { await placesManager.fetchFromOverpass() }
                    }
                    .padding(.bottom, 12)
                }

                // Permission prompt or denied warning — only visible when relevant.
                LocationPermissionBanner(status: locationManager.authorizationStatus) {
                    locationManager.requestPermission()
                }

                // Bottom row: tracking button | recenter-on-me button.
                // (The compass and scale are now native MKMapView controls.)
                HStack(alignment: .center, spacing: 12) {
                    Spacer()

                    Button {
                        showingFilters = true
                    } label: {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                                .foregroundStyle(.blue)
                                .frame(width: 50, height: 50)
                                .background(.regularMaterial, in: Circle())
                                .shadow(radius: 4)
                            if activeFilterCount > 0 {
                                Circle()
                                    .fill(.red)
                                    .frame(width: 16, height: 16)
                                    .overlay(
                                        Text("\(activeFilterCount)")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundStyle(.white)
                                    )
                                    .offset(x: 4, y: -4)
                            }
                        }
                    }

                    TrackingButton(isTracking: locationManager.isTracking) {
                        if locationManager.isTracking {
                            locationManager.stopTracking()
                        } else {
                            locationManager.startTracking()
                        }
                    }

                    Button {
                        userTrackingMode = .follow
                    } label: {
                        Image(systemName: "location.fill")
                            .foregroundStyle(.blue)
                            .frame(width: 50, height: 50)
                            .background(.regularMaterial, in: Circle())
                            .shadow(radius: 4)
                    }

                    Spacer()
                }
                .padding(.bottom, 12)
                .padding(.top, 8)
            }
        }

        .sheet(item: $selectedPlace) { place in
            PlaceDetailSheet(place: place)
        }
        .sheet(isPresented: $showingFilters) {
            MapFilterSheet(
                visitedFilter: $visitedFilter,
                countyFilter: $countyFilter,
                showCities: $showCities,
                showTowns: $showTowns,
                showVillages: $showVillages,
                showHamlets: $showHamlets,
                availableCounties: availableCounties
            )
        }

        // Show the visit banner whenever PlacesManager reports new visits.
        // Keyed to visitEventId (a UUID) rather than recentlyVisited array contents so the
        // banner fires even when the same place is re-visited after being un-marked.
        .onChange(of: placesManager.visitEventId) {
            guard let first = placesManager.recentlyVisited.first else { return }
            // Condense multiple simultaneous visits into a single message.
            newVisitName = placesManager.recentlyVisited.count == 1
                ? first.name
                : "\(first.name) and \(placesManager.recentlyVisited.count - 1) more"
            withAnimation(.spring) { showingNewVisitBanner = true }
            Task {
                try? await Task.sleep(for: .seconds(3))
                withAnimation { showingNewVisitBanner = false }
            }
        }
    }
}

// MARK: - Clustered map (MKMapView)

// An MKAnnotation wrapper around a Place. Holds the visited flag so the delegate can
// colour the marker without going back to PlacesManager on every view request.
final class PlaceAnnotation: NSObject, MKAnnotation {
    let place: Place
    var isVisited: Bool

    init(place: Place, isVisited: Bool) {
        self.place = place
        self.isVisited = isVisited
    }

    var coordinate: CLLocationCoordinate2D { place.coordinate }
    var title: String? { place.name }
}

// Wraps a native MKMapView so we get MapKit's built-in marker clustering and annotation-view
// recycling. This scales to tens of thousands of points where individual SwiftUI annotations
// would not, and gives the polished split/merge animation as you zoom.
struct ClusteredMapView: UIViewRepresentable {
    var places: [Place]
    var visitedIds: Set<Int64>
    var enabledTypes: Set<PlaceType>
    var localCenter: CLLocation?
    var visitedFilter: Int   // 0=All, 1=Visited only, 2=Not visited only
    var countyFilter: String // "" = all counties
    var mapType: Int
    @Binding var selectedPlace: Place?
    @Binding var userTrackingMode: MKUserTrackingMode

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.showsCompass = true
        mapView.showsScale = true

        // Start centred on the UK with a span wide enough to show the whole country.
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 54.0, longitude: -2.0),
            span: MKCoordinateSpan(latitudeDelta: 8, longitudeDelta: 8)
        )
        mapView.setRegion(region, animated: false)

        // Push the legal attribution label above the bottom control bar.
        // The bar is ~70 pt (50 pt buttons + 8 pt top pad + 12 pt bottom pad).
        mapView.layoutMargins.bottom = 70

        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self

        // When the places list first loads (or is refreshed), populate the markers
        // for the current viewport. We never hand MapKit all ~60 k at once — see
        // refreshAnnotations for why.
        // Re-filter if the local-center window changed by more than 1 km (not every 30 m GPS tick).
        let localCenterMoved: Bool = {
            switch (coordinator.loadedLocalCenter, localCenter) {
            case (nil, nil):                    return false
            case (nil, _), (_, nil):            return true
            case let (.some(old), .some(new)):  return old.distance(from: new) > 1000
            }
        }()

        let filterChanged = coordinator.loadedVisitedFilter != visitedFilter
            || coordinator.loadedCountyFilter != countyFilter

        if coordinator.loadedPlacesCount != places.count
            || coordinator.loadedEnabledTypes != enabledTypes
            || localCenterMoved
            || filterChanged {
            coordinator.loadedPlacesCount = places.count
            coordinator.loadedVisited = visitedIds
            coordinator.loadedEnabledTypes = enabledTypes
            coordinator.loadedLocalCenter = localCenter
            coordinator.loadedVisitedFilter = visitedFilter
            coordinator.loadedCountyFilter = countyFilter
            coordinator.refreshAnnotations(on: mapView)
        } else if coordinator.loadedVisited != visitedIds {
            if visitedFilter != 0 {
                // Visited filter is active: which markers appear depends on visited state,
                // so a membership change requires a full refresh rather than just recoloring.
                coordinator.loadedVisited = visitedIds
                coordinator.refreshAnnotations(on: mapView)
            } else {
                // No visited filter: recolour only the affected markers on the map.
                let changed = coordinator.loadedVisited.symmetricDifference(visitedIds)
                var toRefresh: [PlaceAnnotation] = []
                for id in changed {
                    guard let annotation = coordinator.annotationsOnMap[id] else { continue }
                    annotation.isVisited = visitedIds.contains(id)
                    if let view = mapView.view(for: annotation) as? MKMarkerAnnotationView {
                        view.markerTintColor = annotation.isVisited ? .systemGreen : .systemRed
                    } else {
                        toRefresh.append(annotation)
                    }
                }
                if !toRefresh.isEmpty {
                    mapView.removeAnnotations(toRefresh)
                    mapView.addAnnotations(toRefresh)
                }
                coordinator.loadedVisited = visitedIds

                if visitedIds.isEmpty {
                    let all = Array(coordinator.annotationsOnMap.values)
                    mapView.removeAnnotations(all)
                    mapView.addAnnotations(all)
                }
            }
        }

        // Apply map style change.
        let desiredMapType = MKMapType(rawValue: UInt(mapType)) ?? .standard
        if mapView.mapType != desiredMapType {
            mapView.mapType = desiredMapType
        }

        // Apply a recenter request from the location button.
        if mapView.userTrackingMode != userTrackingMode {
            mapView.setUserTrackingMode(userTrackingMode, animated: true)
        }

        // Remove the visit-radius circle when the detail sheet is dismissed.
        if selectedPlace == nil, let circle = coordinator.radiusOverlay {
            mapView.removeOverlay(circle)
            coordinator.radiusOverlay = nil
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: ClusteredMapView
        // The annotations currently added to the map, keyed by OSM id. Only ever a
        // bounded subset of all places (visible region, capped at maxAnnotations).
        var annotationsOnMap: [Int64: PlaceAnnotation] = [:]
        var loadedPlacesCount = -1
        var loadedVisited: Set<Int64> = []
        var loadedEnabledTypes: Set<PlaceType> = []
        var loadedLocalCenter: CLLocation?
        var loadedVisitedFilter: Int = 0
        var loadedCountyFilter: String = ""
        private var pendingRefresh: DispatchWorkItem?
        var radiusOverlay: MKCircle?

        // Hard ceiling on simultaneous annotations. Highest-ranked types are kept when trimming.
        static let maxAnnotations = 1500

        // Places sorted ascending by latitude. Built once when the place list loads and reused
        // for all bounding-box queries. Lets us binary-search to the lat range and then scan
        // only the relevant slice instead of scanning all 60 k places every time.
        private var placesSortedByLat: [Place] = []

        init(_ parent: ClusteredMapView) { self.parent = parent }

        // Binary-search range query over the lat-sorted index. Much faster than a linear scan
        // over parent.places for tight cluster bounding boxes.
        private func placesInBounds(minLat: Double, maxLat: Double,
                                    minLon: Double, maxLon: Double,
                                    types: Set<PlaceType>) -> [Place] {
            guard !placesSortedByLat.isEmpty else { return [] }
            var lo = 0, hi = placesSortedByLat.count
            while lo < hi {
                let mid = (lo + hi) >> 1
                if placesSortedByLat[mid].lat < minLat { lo = mid + 1 } else { hi = mid }
            }
            var result: [Place] = []
            var i = lo
            while i < placesSortedByLat.count {
                let p = placesSortedByLat[i]
                guard p.lat <= maxLat else { break }
                if p.lon >= minLon && p.lon <= maxLon && types.contains(p.type) {
                    result.append(p)
                }
                i += 1
            }
            return result
        }

        // Which settlement types to load at a given zoom level (latitude span in degrees).
        // Thresholds are intentionally conservative: each new type only appears when you're
        // zoomed in enough that adding it won't spike the annotation count. Accuracy of cluster
        // counts is unaffected because viewFor computes totals from the full place list.
        static func allowedTypes(forLatitudeDelta delta: Double) -> Set<PlaceType> {
            switch delta {
            case 2.0...:     return [.city]
            case 0.5..<2.0:  return [.city, .town]
            case 0.1..<0.5:  return [.city, .town, .village]
            default:         return [.city, .town, .village, .hamlet]
            }
        }

        private func rank(_ type: PlaceType) -> Int {
            switch type {
            case .city:    return 3
            case .town:    return 2
            case .village: return 1
            case .hamlet:  return 0
            }
        }

        // Reconciles the annotations on the map with what should be visible right now:
        // places inside the current region (+ buffer) whose type is allowed at this zoom,
        // capped at maxAnnotations. Runs on load and whenever the region settles — cheap,
        // because it only diffs the bounded desired set against what's already shown.
        func refreshAnnotations(on mapView: MKMapView) {
            // Rebuild the lat-sorted index whenever the place list changes.
            if placesSortedByLat.count != parent.places.count {
                placesSortedByLat = parent.places.sorted { $0.lat < $1.lat }
            }

            let region = mapView.region
            guard region.span.latitudeDelta.isFinite, region.span.longitudeDelta.isFinite else { return }

            // Half-span plus a 50 % buffer so markers exist just beyond the edges.
            let latExtent = region.span.latitudeDelta * 0.75
            let lonExtent = region.span.longitudeDelta * 0.75
            var minLat = region.center.latitude - latExtent
            var maxLat = region.center.latitude + latExtent
            var minLon = region.center.longitude - lonExtent
            var maxLon = region.center.longitude + lonExtent

            // If "nearby only" is on, clamp to a 30-mile (~48 km) bounding box around the
            // user's last known position. This keeps candidate counts low even when the map
            // is zoomed far out, which is the main source of hamlet-density slowdowns.
            if let center = parent.localCenter {
                let lat0 = center.coordinate.latitude
                let lon0 = center.coordinate.longitude
                let latMargin = 48.28 / 111.0
                let lonMargin = 48.28 / (111.0 * cos(lat0 * .pi / 180))
                minLat = max(minLat, lat0 - latMargin)
                maxLat = min(maxLat, lat0 + latMargin)
                minLon = max(minLon, lon0 - lonMargin)
                maxLon = min(maxLon, lon0 + lonMargin)
            }

            let allowed = Self.allowedTypes(forLatitudeDelta: region.span.latitudeDelta)
                .intersection(parent.enabledTypes)

            var candidates = placesInBounds(minLat: minLat, maxLat: maxLat,
                                            minLon: minLon, maxLon: maxLon,
                                            types: allowed)

            // Apply visited/county filters.
            switch parent.visitedFilter {
            case 1: candidates = candidates.filter { parent.visitedIds.contains($0.id) }
            case 2: candidates = candidates.filter { !parent.visitedIds.contains($0.id) }
            default: break
            }
            if !parent.countyFilter.isEmpty {
                candidates = candidates.filter { $0.county == parent.countyFilter }
            }

            // If still too dense, keep the most significant settlements.
            if candidates.count > Self.maxAnnotations {
                candidates.sort { rank($0.type) > rank($1.type) }
                candidates = Array(candidates.prefix(Self.maxAnnotations))
            }

            let desiredIds = Set(candidates.map(\.id))

            // Remove annotations that are no longer wanted.
            let stale = annotationsOnMap.filter { !desiredIds.contains($0.key) }
            if !stale.isEmpty {
                mapView.removeAnnotations(Array(stale.values))
                for id in stale.keys { annotationsOnMap[id] = nil }
            }

            // Add annotations that are newly wanted.
            var toAdd: [PlaceAnnotation] = []
            for place in candidates where annotationsOnMap[place.id] == nil {
                let annotation = PlaceAnnotation(place: place, isVisited: parent.visitedIds.contains(place.id))
                annotationsOnMap[place.id] = annotation
                toAdd.append(annotation)
            }
            if !toAdd.isEmpty { mapView.addAnnotations(toAdd) }
        }

        // Re-evaluate which markers should be present whenever the viewport settles.
        // Debounced: rapid zoom/pan fires this delegate many times per second, so we
        // cancel any in-flight work and wait until the map has been still for 200 ms.
        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            pendingRefresh?.cancel()
            let work = DispatchWorkItem { [weak self, weak mapView] in
                guard let self, let mapView else { return }
                self.refreshAnnotations(on: mapView)
            }
            pendingRefresh = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            // Let MapKit draw the user's blue location dot itself.
            if annotation is MKUserLocation { return nil }

            // Cluster bubble. The bounding-box count is only trustworthy when all enabled
            // types are actually loaded at this zoom level; at coarser zoom the box around
            // a handful of cities misses the surrounding hamlets and would show a misleading
            // total. In that case we show only the visited count (always accurate) and let
            // the colour convey relative progress.
            if let cluster = annotation as? MKClusterAnnotation {
                let id = "cluster"
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView
                    ?? MKMarkerAnnotationView(annotation: cluster, reuseIdentifier: id)
                view.annotation = cluster

                let coords = cluster.memberAnnotations.map(\.coordinate)
                let minLat = coords.map(\.latitude).min() ?? 0
                let maxLat = coords.map(\.latitude).max() ?? 0
                let minLon = coords.map(\.longitude).min() ?? 0
                let maxLon = coords.map(\.longitude).max() ?? 0
                var placesInArea = placesInBounds(minLat: minLat, maxLat: maxLat,
                                                  minLon: minLon, maxLon: maxLon,
                                                  types: parent.enabledTypes)
                if !parent.countyFilter.isEmpty {
                    placesInArea = placesInArea.filter { $0.county == parent.countyFilter }
                }
                let total = placesInArea.count
                let visited = placesInArea.filter { parent.visitedIds.contains($0.id) }.count
                let fraction = total > 0 ? Double(visited) / Double(total) : 0
                view.markerTintColor = UIColor(hue: CGFloat(fraction) * 0.33, saturation: 0.8, brightness: 0.75, alpha: 1)

                let zoomTypes = Self.allowedTypes(forLatitudeDelta: mapView.region.span.latitudeDelta)
                    .intersection(parent.enabledTypes)
                let allTypesLoaded = zoomTypes == parent.enabledTypes
                view.glyphText = allTypesLoaded ? "\(visited)/\(total)" : (visited > 0 ? "\(visited)✓" : "")
                view.displayPriority = .required
                return view
            }

            guard let place = annotation as? PlaceAnnotation else { return nil }

            let id = "place"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView
                ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: id)
            view.annotation = annotation

            // This is what turns dense markers into clusters.
            view.clusteringIdentifier = "place"
            view.markerTintColor = place.isVisited ? .systemGreen : .systemRed
            view.glyphImage = UIImage(systemName: place.place.type.icon)
            view.animatesWhenAdded = true

            // Prioritise larger settlements when markers would overlap, so the map reads
            // cleanly at every zoom level (cities survive, hamlets cluster/drop first).
            switch place.place.type {
            case .city:    view.displayPriority = .required
            case .town:    view.displayPriority = .defaultHigh
            case .village: view.displayPriority = .defaultLow
            case .hamlet:  view.displayPriority = MKFeatureDisplayPriority(rawValue: 200)
            }
            return view
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            // Tapping a cluster zooms in to reveal its members.
            if let cluster = view.annotation as? MKClusterAnnotation {
                let rect = cluster.memberAnnotations.reduce(MKMapRect.null) { rect, member in
                    let point = MKMapPoint(member.coordinate)
                    return rect.union(MKMapRect(x: point.x, y: point.y, width: 0, height: 0))
                }
                let padding = UIEdgeInsets(top: 60, left: 60, bottom: 60, right: 60)
                mapView.setVisibleMapRect(rect, edgePadding: padding, animated: true)
                mapView.deselectAnnotation(view.annotation, animated: false)
                return
            }

            // Tapping a single place shows a radius circle and opens the detail sheet.
            if let annotation = view.annotation as? PlaceAnnotation {
                if let existing = radiusOverlay { mapView.removeOverlay(existing) }
                let circle = MKCircle(center: annotation.place.coordinate,
                                      radius: annotation.place.type.radiusMeters)
                radiusOverlay = circle
                mapView.addOverlay(circle, level: .aboveRoads)
                parent.selectedPlace = annotation.place
                mapView.deselectAnnotation(view.annotation, animated: false)
            }
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let circle = overlay as? MKCircle else { return MKOverlayRenderer(overlay: overlay) }
            let renderer = MKCircleRenderer(circle: circle)
            renderer.fillColor = UIColor.systemGray.withAlphaComponent(0.12)
            renderer.strokeColor = UIColor.systemGray.withAlphaComponent(0.55)
            renderer.lineWidth = 1.5
            return renderer
        }

        func mapView(_ mapView: MKMapView, didChange mode: MKUserTrackingMode, animated: Bool) {
            // Keep the SwiftUI state in step when the user pans out of follow mode.
            if parent.userTrackingMode != mode {
                parent.userTrackingMode = mode
            }
        }
    }
}

// Pill-shaped button at the bottom of the map that starts and stops GPS tracking.
struct TrackingButton: View {
    let isTracking: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(
                isTracking ? "Stop Tracking" : "Start Tracking",
                systemImage: isTracking ? "stop.circle.fill" : "record.circle"
            )
            .fontWeight(.semibold)
            .foregroundStyle(.white)
            .padding(.horizontal, 28)
            .padding(.vertical, 14)
            .background(isTracking ? Color.red : Color.accentColor)
            .clipShape(Capsule())
            .shadow(radius: 4)
        }
    }
}

// Temporary banner that slides in from the top when a new settlement is detected.
struct NewVisitBanner: View {
    let name: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "mappin.circle.fill")
                .foregroundStyle(.green)
            Text("Visited \(name)!")
                .fontWeight(.semibold)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        // .regularMaterial gives a frosted-glass background that works on any map tile colour.
        .background(.regularMaterial, in: Capsule())
        .shadow(radius: 4)
        .padding(.horizontal)
    }
}

// Shown above the tracking button while the Overpass API fetch is in progress.
struct LoadingPill: View {
    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
            Text("Loading places…")
                .font(.subheadline)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .shadow(radius: 2)
    }
}

// Shown if the Overpass fetch fails. Tapping it retries the fetch.
struct RetryButton: View {
    let error: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Retry loading places", systemImage: "arrow.clockwise")
                .font(.subheadline)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.regularMaterial, in: Capsule())
                .shadow(radius: 2)
        }
        .foregroundStyle(.primary)
    }
}

// Shows a location permission prompt or a "denied" warning above the tracking button.
// Renders nothing when permission is already granted.
struct LocationPermissionBanner: View {
    let status: CLAuthorizationStatus
    let onRequest: () -> Void

    var body: some View {
        if status == .denied || status == .restricted {
            Label("Location access denied — go to Settings to enable it", systemImage: "location.slash")
                .font(.caption)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal)
                .padding(.bottom, 8)
        } else if status == .notDetermined {
            Button(action: onRequest) {
                Label("Enable location access", systemImage: "location")
                    .font(.subheadline)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
            }
            .foregroundStyle(.primary)
            .padding(.bottom, 8)
        }
    }
}

// Bottom sheet that appears when the user taps a place marker.
// Shows the settlement name and type, and lets the user manually toggle its visited state.
struct PlaceDetailSheet: View {
    let place: Place
    @Environment(PlacesManager.self) private var placesManager
    @Environment(\.dismiss) private var dismiss

    @State private var showingDirectionsDialog = false

    var isVisited: Bool { placesManager.isVisited(place) }

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 4) {
                Text(place.name)
                    .font(.title2)
                    .fontWeight(.bold)
                Label(place.type.rawValue.capitalized, systemImage: place.type.icon)
                    .foregroundStyle(.secondary)
                if !place.county.isEmpty {
                    Text(place.county)
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.top, 24)

            Button {
                placesManager.toggleVisited(place)
                dismiss()
            } label: {
                Label(
                    isVisited ? "Mark as Not Visited" : "Mark as Visited",
                    systemImage: isVisited ? "xmark.circle" : "checkmark.circle"
                )
                .frame(maxWidth: .infinity)
                .padding()
                .background(isVisited ? Color.red : Color.green)
                .foregroundStyle(.white)
                .fontWeight(.semibold)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal)

            Button {
                showingDirectionsDialog = true
            } label: {
                Label("Get Directions", systemImage: "arrow.triangle.turn.up.right.circle")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .fontWeight(.semibold)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal)

            Spacer()
        }
        .presentationDetents([.fraction(0.38)])
        .presentationDragIndicator(.visible)
        .confirmationDialog("Get Directions to \(place.name)", isPresented: $showingDirectionsDialog, titleVisibility: .visible) {
            Button("Apple Maps") { openInAppleMaps() }
            Button("Google Maps") { openInApp(scheme: "comgooglemaps://?daddr=\(place.coordinate.latitude),\(place.coordinate.longitude)&directionsmode=driving") }
            Button("Waze") { openInApp(scheme: "waze://?ll=\(place.coordinate.latitude),\(place.coordinate.longitude)&navigate=yes") }
        }
    }

    private func openInAppleMaps() {
        let item = MKMapItem(location: CLLocation(latitude: place.coordinate.latitude, longitude: place.coordinate.longitude), address: nil)
        item.name = place.name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
    }

    private func openInApp(scheme: String) {
        guard let url = URL(string: scheme) else { return }
        UIApplication.shared.open(url) { success in
            if !success { openInAppleMaps() }
        }
    }
}

// MARK: - Map Filter Sheet

struct MapFilterSheet: View {
    @Binding var visitedFilter: Int
    @Binding var countyFilter: String
    @Binding var showCities: Bool
    @Binding var showTowns: Bool
    @Binding var showVillages: Bool
    @Binding var showHamlets: Bool
    let availableCounties: [String]

    private var hasActiveFilters: Bool {
        visitedFilter != 0 || !countyFilter.isEmpty || !showCities || !showTowns || !showVillages || !showHamlets
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Place Types") {
                    Toggle(isOn: $showCities)   { Label("Cities",   systemImage: PlaceType.city.icon) }
                    Toggle(isOn: $showTowns)    { Label("Towns",    systemImage: PlaceType.town.icon) }
                    Toggle(isOn: $showVillages) { Label("Villages", systemImage: PlaceType.village.icon) }
                    Toggle(isOn: $showHamlets)  { Label("Hamlets",  systemImage: PlaceType.hamlet.icon) }
                }

                Section("Status") {
                    Picker("Show", selection: $visitedFilter) {
                        Text("All").tag(0)
                        Text("Visited").tag(1)
                        Text("Not Visited").tag(2)
                    }
                    .pickerStyle(.segmented)
                }

                Section("County") {
                    NavigationLink {
                        CountyPickerView(selection: $countyFilter, counties: availableCounties)
                    } label: {
                        HStack {
                            Text("County")
                            Spacer()
                            Text(countyFilter.isEmpty ? "All" : countyFilter)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    Button("Reset Filters") {
                        visitedFilter = 0
                        countyFilter = ""
                        showCities = true
                        showTowns = true
                        showVillages = true
                        showHamlets = true
                    }
                    .foregroundStyle(hasActiveFilters ? .red : .secondary)
                    .disabled(!hasActiveFilters)
                }
            }
            .navigationTitle("Filter Map")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

struct CountyPickerView: View {
    @Binding var selection: String
    let counties: [String]
    @State private var searchText = ""
    @Environment(\.dismiss) private var dismiss

    private var filtered: [String] {
        searchText.isEmpty ? counties : counties.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        List {
            Button {
                selection = ""
                dismiss()
            } label: {
                HStack {
                    Text("All Counties")
                        .foregroundStyle(.primary)
                    Spacer()
                    if selection.isEmpty {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.blue)
                    }
                }
            }

            ForEach(filtered, id: \.self) { county in
                Button {
                    selection = county
                    dismiss()
                } label: {
                    HStack {
                        Text(county)
                            .foregroundStyle(.primary)
                        Spacer()
                        if selection == county {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.blue)
                        }
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search counties")
        .navigationTitle("County")
    }
}
