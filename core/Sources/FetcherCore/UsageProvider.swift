import Foundation

/// Every data source implements this one protocol (PROVIDERS.md / ADR-007).
public protocol UsageProvider: Sendable {
    var id: String { get }                   // "claude", "openai-platform", …
    var displayName: String { get }
    var authMethod: AuthMethod { get }
    var capabilities: Capabilities { get }
    var refreshInterval: TimeInterval { get } // 30–120s typical

    func fetch() async throws -> [UsageMetric]
}

public extension UsageProvider {
    /// Wrap a `fetch()` into a normalized, timestamped snapshot.
    func snapshot(now: Date = Date()) async throws -> UsageSnapshot {
        let metrics = try await fetch()
        return UsageSnapshot(
            providerId: id,
            displayName: displayName,
            capturedAt: now,
            metrics: metrics
        )
    }
}

/// Minimal provider registry. Frontends look a provider up by id and stay
/// agnostic to which concrete adapter answers (ADR-007).
public struct ProviderRegistry: Sendable {
    public let providers: [String: any UsageProvider]

    public init(_ providers: [any UsageProvider]) {
        self.providers = Dictionary(uniqueKeysWithValues: providers.map { ($0.id, $0) })
    }

    public func provider(id: String) -> (any UsageProvider)? { providers[id] }

    /// Default registry. `claude` is the OAuth (Claude Code) adapter — unchanged,
    /// so `tally-cli` (and `tally-cli claude`) keeps printing the real numbers.
    /// `claude-cookie` is the claude.ai session-cookie adapter, registered so it
    /// can be exercised live via `tally-cli claude-cookie` after a WebView login.
    public static func makeDefault() -> ProviderRegistry {
        ProviderRegistry([ClaudeOAuthProvider(), ClaudeCookieProvider()])
    }

    /// Auth-resolved registry for the app: a single `claude` provider chosen by
    /// `ClaudeAuthResolver` (OAuth → cookie → none). Empty when signed out.
    public static func makeResolved(preferCookie: Bool = false,
                                    resolver: ClaudeAuthResolver = ClaudeAuthResolver()) -> ProviderRegistry {
        guard let provider = resolver.makeProvider(preferCookie: preferCookie) else {
            return ProviderRegistry([])
        }
        return ProviderRegistry([provider])
    }
}
