# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

This is a native iOS app built with Xcode. There is no CLI build step — open `JustVisiting.xcodeproj` in Xcode and use ⌘R to run on a simulator or device.

```bash
# Build from the command line (substitute a valid simulator UDID if needed)
xcodebuild -project JustVisiting.xcodeproj -scheme JustVisiting -destination 'platform=iOS Simulator,name=iPhone 16' build

# Run unit tests
xcodebuild -project JustVisiting.xcodeproj -scheme JustVisiting -destination 'platform=iOS Simulator,name=iPhone 16' test
```

No linter is configured. The project uses Swift 6 strict concurrency (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, `SWIFT_APPROACHABLE_CONCURRENCY = YES`) so all code is implicitly `@MainActor` unless explicitly opted out with `nonisolated`.

## Architecture

The app has three manager classes and a view layer. There is no backend — everything is local. All three managers use the `@Observable` macro (not `ObservableObject`); they are injected via `.environment()` and consumed with `@Environment(Type.self)` in views.

### Managers (created in `JustVisitingApp`, injected via `.environment()`)

**`PlacesManager`** — owns all place data and visit history.
- On init: loads visited IDs and session history from disk synchronously, then async-loads places from the on-disk JSON cache, the bundled `places.json` asset, or the Overpass API (in that priority order).
- `checkLocation(_:)` is the hot path — called on every GPS update. Uses a two-stage filter (bounding-box cull → `CLLocation.distance()`) to detect visits without iterating all ~60 k places each time. On a new visit it fires a `UNUserNotificationCenter` notification when the app is backgrounded.
- Persists three JSON files in the app's Documents directory: `places.json` (Overpass cache), `visited.json` (Set of visited OSM node IDs), `sessions.json` (completed session history).

**`LocationManager`** — thin wrapper around `CLLocationManager`.
- `distanceFilter = 30 m` and `pausesLocationUpdatesAutomatically = false` are intentional.
- `allowsBackgroundLocationUpdates` is only set if `UIBackgroundModes: location` is present in the compiled Info.plist — checked at runtime to avoid a crash.
- Exposes `onLocationUpdate: ((CLLocation) -> Void)?`. The closure is wired in `JustVisitingApp.init()` (not `.onAppear`) so it is never skipped when the scene is relaunched via CarPlay or a background location event.

**`CarPlayDetector`** — detects CarPlay connection using `AVAudioSession.routeChangeNotification`. When `shouldShowDrivingMode` is true, `ContentView` replaces the tab bar with `DrivingModeView`. `userDismissedDrivingMode` suppresses the auto-switch until CarPlay disconnects and reconnects.

### Sessions

A `Session` (value type, `Codable`) records a start date, optional end date, and a list of `Place` values visited during that session (most-recent first). Sessions are managed by `PlacesManager`:
- `startSession()` / `endSession()` are called from `ContentView.onChange(of: locationManager.isTracking)`.
- Only sessions with at least one visit are saved to `sessionHistory` and persisted to `sessions.json`.
- When a session ends with visits, `ContentView` presents `SessionSummaryView` as a sheet.
- Completed sessions are browsable in `SessionsHistoryView` (the History tab), grouped by day.

### Data model (`Place.swift`)

`PlaceType` raw values (`hamlet`, `village`, `town`, `city`) match OSM `place=` tags exactly so Codable works without custom mapping. Each type has a `radiusMeters` threshold used in visit detection (hamlet: 250 m, village: 500 m, town: 1 500 m, city: 4 500 m).

`Place.id` is the OSM node ID (Int64) — stable across Overpass refreshes and used as the persistence key in `visited.json`. `Place.county` stores the ONS county/unitary authority name (empty string for places outside UK boundaries); `decodeIfPresent` handles old cached JSON that pre-dates this field.

### View layer

`ContentView` switches between a `TabView` (normal use) and `DrivingModeView` (when CarPlay is connected). The tab bar has four tabs: Map, Stats, History, and Settings.

`MapView` is the primary screen. It hosts `ClusteredMapView`, a `UIViewRepresentable` that wraps a native `MKMapView`. Using `UIViewRepresentable` is intentional: MapKit's built-in annotation clustering and view recycling scales to tens of thousands of markers far better than individual SwiftUI views would.

**`ClusteredMapView.Coordinator`** owns annotation lifecycle:
- `placesSortedByLat` — a lat-sorted index built once on load; `refreshAnnotations` binary-searches it to avoid scanning all ~60 k places for each viewport query.
- `refreshAnnotations(on:)` — reconciles which `PlaceAnnotation` objects are on the map (viewport + 50 % buffer, capped at `maxAnnotations = 1500`). Debounced 350 ms via `DispatchWorkItem` so rapid pan/zoom doesn't fire it on every frame; called from `mapView(_:regionDidChangeAnimated:)`.
- `allowedTypes(forLatitudeDelta:)` — zoom-level gating: only cities are shown at `latDelta ≥ 2°`; all four types appear below `0.1°`. This keeps annotation counts manageable before the cap is hit.
- Cluster bubbles show `visited/total` when all enabled types are loaded for the current zoom; otherwise only the visited count is shown to avoid a misleading denominator.

**`@AppStorage` filter keys** (`filter.showCities`, `filter.showTowns`, `filter.showVillages`, `filter.showHamlets`, `filter.localOnly`) are read by both `MapView` and `SettingsView` — changes in Settings are immediately reflected on the map.

`StatsView` uses the Swift Charts framework (`import Charts`) to render a donut chart of top counties by visit count. County-level stats come from `PlacesManager.countyStats`, which groups `places` by the `county` field.

`DrivingModeView` is a full-screen dark UI with a large record/stop button. It shows the last three places visited in the current session and a banner notification (4 s auto-dismiss) on each new visit.

### Adding new Swift files

The project uses `PBXFileSystemSynchronizedRootGroup` — any `.swift` file dropped into the `JustVisiting/` directory is automatically included in the build target. **Do not modify `project.pbxproj` to register source files.**

### Info.plist / build settings

Location permission strings and `UIBackgroundModes = location` are declared as `INFOPLIST_KEY_*` build settings in `project.pbxproj` (both Debug and Release target configs). Do not add a custom `Info.plist` file inside `JustVisiting/` — the file-system sync group would include it as a resource and produce a "multiple commands produce Info.plist" build error.

### Concurrency notes

CLLocationManagerDelegate methods must be `nonisolated` (Swift 6 + default MainActor isolation conflicts with the ObjC protocol). They hop back with `Task { @MainActor in ... }`. `Task.detached` is used for background disk writes to avoid blocking the main actor. The same pattern applies to `CarPlayDetector.routeChanged`, which fires on a background thread via `NotificationCenter`.
