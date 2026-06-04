import SwiftUI
import CoreLocation

struct SettingsView: View {
    @Environment(LocationManager.self) private var locationManager

    @AppStorage("filter.showCities")   private var showCities   = true
    @AppStorage("filter.showTowns")    private var showTowns    = true
    @AppStorage("filter.showVillages") private var showVillages = true
    @AppStorage("filter.showHamlets")  private var showHamlets  = true
    @AppStorage("filter.localOnly")    private var localOnly    = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Map Filters") {
                    Toggle(isOn: $showCities)   { Label("Cities",   systemImage: PlaceType.city.icon) }
                    Toggle(isOn: $showTowns)    { Label("Towns",    systemImage: PlaceType.town.icon) }
                    Toggle(isOn: $showVillages) { Label("Villages", systemImage: PlaceType.village.icon) }
                    Toggle(isOn: $showHamlets)  { Label("Hamlets",  systemImage: PlaceType.hamlet.icon) }
                }

                Section {
                    Toggle(isOn: $localOnly) {
                        Label("Nearby places only", systemImage: "location.circle")
                    }
                    if localOnly && locationManager.lastLocation == nil {
                        Label("No location available — start tracking on the Map tab first.", systemImage: "location.slash")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                } footer: {
                    Text("Shows places within approximately 30 miles of your last known location.")
                }
            }
            .navigationTitle("Settings")
        }
    }
}
