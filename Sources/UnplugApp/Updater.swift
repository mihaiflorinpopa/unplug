import Foundation
import Sparkle

/// Automatic updates through Sparkle, from the appcast published with each
/// GitHub release. Updates are verified with Unplug's own EdDSA key rather than
/// Apple notarization. Builds without a public key (SUPublicEDKey) leave it off.
@MainActor
final class Updater: ObservableObject {
    private let controller: SPUStandardUpdaterController?
    @Published private(set) var canCheck = false

    var isAvailable: Bool { controller != nil }

    init() {
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
        controller = key.isEmpty ? nil : SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        // As in Sparkle's SwiftUI example.
        controller?.updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheck)
    }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }

    var automaticallyChecks: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set {
            controller?.updater.automaticallyChecksForUpdates = newValue
            objectWillChange.send()
        }
    }
}
