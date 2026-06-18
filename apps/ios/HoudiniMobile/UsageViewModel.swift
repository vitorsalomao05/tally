import Foundation
import FetcherCore
import WidgetKit

/// The app screen's model. Thin wrapper over `FetcherCore`'s **cookie** path —
/// there is no Claude Code OAuth token on a phone (ADR-008), so we resolve the
/// provider with `preferCookie: true`. Unlike the macOS menu bar app there is **no
/// 60s timer**: an iOS app can't run continuously, so we refresh on open /
/// foreground / pull-to-refresh and keep the last good reading otherwise
/// (`ARCHITECTURE.md` "never flash empty").
@MainActor
final class UsageViewModel: ObservableObject {
    enum State: Equatable {
        case loading
        case ok
        case error(String)
        case signedOut          // no captured cookie yet → show the Sign-in CTA
    }

    @Published private(set) var metrics: [UsageMetric] = []
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var state: State = .loading

    private let resolver: ClaudeAuthResolver
    private let store: CredentialStore
    private var fetchTask: Task<Void, Never>?

    init(resolver: ClaudeAuthResolver = ClaudeAuthResolver(),
         store: CredentialStore = CredentialStore()) {
        self.resolver = resolver
        self.store = store
    }

    /// Is a cookie present? Drives first paint (CTA vs. spinner).
    var isSignedIn: Bool { resolver.hasSessionCookie() }

    /// Fetch once now. Safe to call from `.onAppear`, scene-foreground, or the
    /// pull-to-refresh handle. One fetch in flight at a time.
    func refresh() {
        // Cookie-only on iOS: prefer the cookie provider, fall back to none.
        guard let provider = resolver.makeProvider(preferCookie: true) else {
            metrics = []
            lastUpdated = nil
            state = .signedOut
            return
        }
        guard fetchTask == nil else { return }
        if metrics.isEmpty { state = .loading }

        fetchTask = Task { @MainActor in
            defer { fetchTask = nil }
            do {
                let fresh = try await provider.snapshot()
                metrics = fresh.metrics
                lastUpdated = fresh.capturedAt
                state = .ok
                // Hand the widget the freshest value + nudge it (Apple still
                // throttles the actual reload — see PLAN.md §3).
                SharedSnapshot.write(fresh)
                WidgetCenter.shared.reloadAllTimelines()
            } catch {
                // Last-good cache: keep whatever we already showed; flag the reason.
                state = .error(Self.message(for: error))
            }
        }
    }

    /// Called after the WebView login captures a cookie: fetch immediately.
    func didSignIn() { refresh() }

    /// Clear the captured cookie and reset to the signed-out CTA (ADR-005: the
    /// Keychain item is the only copy, so deleting it is a true sign-out).
    func signOut() {
        try? store.nativeDeleteGenericPassword(
            service: ClaudeCookieProvider.keychainService,
            account: ClaudeCookieProvider.keychainAccount
        )
        fetchTask?.cancel()
        fetchTask = nil
        metrics = []
        lastUpdated = nil
        state = .signedOut
        SharedSnapshot.write(UsageSnapshot(
            providerId: "claude-cookie", displayName: "Claude (Pro/Max)",
            capturedAt: Date(), metrics: []
        ))
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Token-safe, human error text. Reuses the typed `ProviderError` surface.
    static func message(for error: Error) -> String {
        if let e = error as? ProviderError {
            switch e {
            case .needsLogin: return "Claude.ai session expired — sign in again."
            case .rateLimited: return "Rate limited — try again in a bit."
            case .network(let d): return "Network error: \(d)"
            default: return e.description
            }
        }
        return error.localizedDescription
    }
}
