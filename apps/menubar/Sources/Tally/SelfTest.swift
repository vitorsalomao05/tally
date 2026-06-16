import Foundation
import Combine
import FetcherCore

/// Headless `--selftest [interval] [duration]` mode: drives the *real* `UsageModel`
/// (same timer/fetch code as the app, only the interval differs) and logs every
/// time `lastUpdated` advances. Proves the scheduled timer actually fires.
enum SelfTest {
    static func run(interval: TimeInterval, duration: TimeInterval) {
        MainActor.assumeIsolated {
            let model = UsageModel(refreshInterval: interval)
            var cancellables = Set<AnyCancellable>()
            let start = Date()

            model.$lastUpdated
                .compactMap { $0 }
                .removeDuplicates()
                .sink { date in
                    let elapsed = String(format: "%.1f", Date().timeIntervalSince(start))
                    let primary = model.metrics.primary.map(Format.compactPrimary) ?? "—"
                    FileHandle.standardError.write(
                        Data("[t+\(elapsed)s] refresh → lastUpdated=\(date) primary=\(primary)\n".utf8)
                    )
                }
                .store(in: &cancellables)

            model.start()
            // Run the main run loop so the Timer fires and @MainActor fetch
            // continuations are serviced.
            RunLoop.main.run(until: Date().addingTimeInterval(duration))
            FileHandle.standardError.write(Data("selftest done\n".utf8))
            _ = cancellables
            exit(0)
        }
    }
}
