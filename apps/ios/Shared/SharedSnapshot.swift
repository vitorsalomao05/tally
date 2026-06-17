import Foundation
import FetcherCore

/// The bridge between the app and the widget: the app fetches and writes the
/// latest `UsageSnapshot` into the **App Group** container; the widget reads that
/// cached snapshot on its (Apple-budgeted) timeline refresh. `UsageSnapshot` is
/// `Codable` and already lives in `FetcherCore`, so nothing new is modeled here.
///
/// Used by BOTH targets (it's in the shared `Shared/` source group), so the App
/// Group id is defined once.
enum SharedSnapshot {
    /// TODO(xcode): this must match the App Group capability enabled on BOTH the
    /// app and widget targets (see `project.yml`). Confirmed only after enrolling
    /// in the Apple Developer Program ($99/yr) and picking a real Team ID.
    static let appGroupID = "group.org.salomao.tally"

    private static let fileName = "last-snapshot.json"

    private static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent(fileName)
    }

    /// App side: persist the freshest reading after a successful fetch.
    static func write(_ snapshot: UsageSnapshot) {
        guard let url = fileURL, let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// Widget side (and app cold-start): the last good reading, or `nil` if the
    /// user has never fetched. The widget renders this with "updated X min ago"
    /// copy — never a faked live value.
    static func read() -> UsageSnapshot? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(UsageSnapshot.self, from: data)
    }
}
