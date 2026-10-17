import Foundation

/// The version stamped into Unplug.app's Info.plist by scripts/build-app.sh.
public enum UnplugVersion {
    /// "0.1.0", or "dev" when run outside the app bundle (e.g. `swift run`).
    public static var current: String {
        info["CFBundleShortVersionString"] as? String ?? "dev"
    }

    /// The build number (commit count), if known.
    public static var build: String? {
        info["CFBundleVersion"] as? String
    }

    /// Works for the app itself and for the CLI at Contents/Helpers/unplug,
    /// including through a symlink on the PATH.
    private static var info: [String: Any] {
        if Bundle.main.bundleURL.pathExtension == "app", let info = Bundle.main.infoDictionary {
            return info
        }
        let executable = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        let app = executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return Bundle(url: app)?.infoDictionary ?? [:]
    }
}
