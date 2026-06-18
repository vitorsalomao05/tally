import Foundation
import FetcherCore

/// Deterministic sample data for headless renders (`--snapshot`) and the self-test
/// modes (`--selftest`, `--metrictest`). Mirrors the shape the Claude adapter
/// returns so the views exercise every branch (percent windows + dollar overage).
enum PreviewData {
    static let providerId = "claude"

    /// A representative reading. `Weekly` is the tightest window (95%, red), while
    /// the dollar overage sits at $93/100 — so `auto` and an explicit `extraUsage`
    /// pick visibly different menu-bar text.
    static func sampleMetrics(now: Date = Date()) -> [UsageMetric] {
        [
            UsageMetric(label: "5-hour", pct: 32,
                        resetAt: now.addingTimeInterval(2 * 3600 + 14 * 60),
                        providerId: providerId),
            UsageMetric(label: "Weekly", pct: 95,
                        resetAt: now.addingTimeInterval(5 * 86400 + 3 * 3600),
                        providerId: providerId),
            UsageMetric(label: "Sonnet weekly", pct: 61,
                        resetAt: now.addingTimeInterval(5 * 86400 + 3 * 3600),
                        providerId: providerId),
            UsageMetric(label: "Extra usage ($)", pct: 93,
                        used: 93, limit: 100, dollars: 93,
                        providerId: providerId),
        ]
    }
}

/// An offline `UsageProvider` that returns `PreviewData` instantly. Used by the
/// self-test timer so cadence measurements aren't muddied by network latency.
struct StubProvider: UsageProvider {
    let id = "stub"
    let displayName = "Stub"
    let authMethod: AuthMethod = .keychainOAuth
    let capabilities: Capabilities = [.usagePct, .resetTimer, .dollarBalance]
    let refreshInterval: TimeInterval = 60
    var metrics: [UsageMetric] = PreviewData.sampleMetrics()

    func fetch() async throws -> [UsageMetric] { metrics }
}
