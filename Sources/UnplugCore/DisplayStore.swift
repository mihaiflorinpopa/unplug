import Foundation

/// Remembers displays Unplug disconnected. A disconnected display disappears from
/// every public display list, so without this record there is no way to find it
/// again. Shared by the CLI and the menu bar app.
struct DisplayStore {
    let fileURL: URL

    static let shared = DisplayStore(
        fileURL: FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Unplug", isDirectory: true)
            .appendingPathComponent("disconnected.json")
    )

    func load() -> [Display] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode([Display].self, from: data)) ?? []
    }

    func save(_ displays: [Display]) {
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(displays) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    func remember(_ display: Display) {
        var all = load().filter { $0.uuid != display.uuid }
        var stored = display
        stored.isConnected = false
        all.append(stored)
        save(all)
    }

    func forget(uuid: String) {
        save(load().filter { $0.uuid != uuid })
    }
}
