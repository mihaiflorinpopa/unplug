import Combine
import Foundation
import Sparkle

/// Automatic updates through Sparkle, from the appcast published with each
/// GitHub release. Updates are verified with Unplug's own EdDSA key rather than
/// Apple notarization. Builds without a public key (SUPublicEDKey) leave it off.
@MainActor
@Observable
final class Updater: NSObject {
    @ObservationIgnored private var controller: SPUStandardUpdaterController?
    @ObservationIgnored private var canCheckObservation: AnyCancellable?
    private(set) var canCheck = false
    /// A scheduled check found an update the user hasn't looked at yet, so the
    /// menu shows "Update Available…" (Sparkle's gentle reminders).
    private(set) var updateAvailable = false

    var isAvailable: Bool { controller != nil }

    override init() {
        super.init()
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
        controller = key.isEmpty ? nil : SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: nil, userDriverDelegate: self)
        // Sparkle's SwiftUI example uses assign(to: &$canCheck), which needs @Published.
        canCheckObservation = controller?.updater.publisher(for: \.canCheckForUpdates)
            .sink { [weak self] in self?.canCheck = $0 }
        // Sparkle's own schedule checks once a day, so also check at launch (that is,
        // at login). Sparkle allows this right after starting, before the next run loop.
        if controller?.updater.automaticallyChecksForUpdates == true {
            controller?.updater.checkForUpdatesInBackground()
        }
    }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }

    var automaticallyChecks: Bool {
        get {
            access(keyPath: \.automaticallyChecks)
            return controller?.updater.automaticallyChecksForUpdates ?? false
        }
        set { withMutation(keyPath: \.automaticallyChecks) { controller?.updater.automaticallyChecksForUpdates = newValue } }
    }
}

/// A menu bar app has no Dock icon, so Sparkle won't bring a scheduled update
/// alert to the front, and it can go unnoticed. Sparkle calls these on the main
/// thread. https://sparkle-project.org/documentation/gentle-reminders
extension Updater: @MainActor SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState
    ) {
        if !state.userInitiated { updateAvailable = true }
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        updateAvailable = false
    }

    func standardUserDriverWillFinishUpdateSession() {
        updateAvailable = false
    }
}
