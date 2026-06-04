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

The app has two manager classes and a view layer. There is no backend — everything is local.

### Managers (created in `JustVisitingApp`, injected via `.environment()`)

**`PlacesManager`** — owns all place data and visit history.
- On init: loads visited IDs from disk synchronously, then async-loads places from the JSON cache or Overpass API.
- `checkLocation(_:)` is the hot path — called on every GPS update. Uses a two-stage filter (bounding-box cull → `CLLocation.distance()`) to detect visits without iterating all ~60 k places each time.
- Persists two JSON files in the app's Documents directory: `places.json` (Overpass cache) and `visited.json` (Set of visited OSM node IDs).

**`LocationManager`** — thin wrapper around `CLLocationManager`.
- `distanceFilter = 30 m` and `pausesLocationUpdatesAutomatically = false` are intentional.
- `allowsBackgroundLocationUpdates` is only set if `UIBackgroundModes: location` is present in the compiled Info.plist — checked at runtime to avoid a crash.
- Exposes `onLocationUpdate: ((CLLocation) -> Void)?`. The closure is set in `JustVisitingApp.onAppear` to call `placesManager.checkLocation(_:)` — this keeps the two managers decoupled.

### Data model (`Place.swift`)

`PlaceType` raw values (`hamlet`, `village`, `town`, `city`) match OSM `place=` tags exactly so Codable works without custom mapping. Each type has a `radiusMeters` threshold used in visit detection.

`Place.id` is the OSM node ID (Int64) — stable across Overpass refreshes and used as the persistence key in `visited.json`.

### View layer

`ContentView` is a `TabView` (Map / Stats). `MapView` is the primary screen. Because the full place list can be ~60 k entries, `MapView.updateVisiblePlaces()` filters to the current camera region plus a 60 % buffer and caps at 400 annotations — this runs on every `onMapCameraChange` event.

### Adding new Swift files

The project uses `PBXFileSystemSynchronizedRootGroup` — any `.swift` file dropped into the `JustVisiting/` directory is automatically included in the build target. **Do not modify `project.pbxproj` to register source files.**

### Info.plist / build settings

Location permission strings and `UIBackgroundModes = location` are declared as `INFOPLIST_KEY_*` build settings in `project.pbxproj` (both Debug and Release target configs). Do not add a custom `Info.plist` file inside `JustVisiting/` — the file-system sync group would include it as a resource and produce a "multiple commands produce Info.plist" build error.

### Concurrency notes

CLLocationManagerDelegate methods must be `nonisolated` (Swift 6 + default MainActor isolation conflicts with the ObjC protocol). They hop back with `Task { @MainActor in ... }`. `Task.detached` is used for background disk writes to avoid blocking the main actor.
