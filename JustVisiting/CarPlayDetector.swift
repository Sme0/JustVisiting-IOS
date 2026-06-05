import AVFoundation
import Observation

@Observable
final class CarPlayDetector: NSObject {
    private var hardwareConnected = false

    // Set when the user explicitly dismisses driving mode while CarPlay is still connected.
    // Cleared automatically when CarPlay disconnects so the next connection auto-shows it.
    var userDismissedDrivingMode = false

    #if DEBUG
    var debugForceConnected = false
    #endif

    var isConnected: Bool {
        #if DEBUG
        hardwareConnected || debugForceConnected
        #else
        hardwareConnected
        #endif
    }

    // True when CarPlay is connected AND the user hasn't manually exited driving mode.
    var shouldShowDrivingMode: Bool {
        isConnected && !userDismissedDrivingMode
    }

    override init() {
        super.init()
        hardwareConnected = Self.checkConnected()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(routeChanged),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
    }

    nonisolated private static func checkConnected() -> Bool {
        AVAudioSession.sharedInstance().currentRoute.outputs
            .contains { $0.portType == .carAudio }
    }

    // routeChangeNotification fires on a background thread — hop to MainActor before mutating.
    @objc nonisolated private func routeChanged() {
        let connected = Self.checkConnected()
        Task { @MainActor in
            self.hardwareConnected = connected
            // Reset dismissal when CarPlay disconnects so the next connection auto-shows driving mode.
            if !connected {
                self.userDismissedDrivingMode = false
            }
        }
    }
}
