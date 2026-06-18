import Foundation
import Combine
import FetcherCore

/// App-scoped view model. Polls a `UsageProvider` every `refreshInterval` seconds
/// and publishes the result. Keeps the last good reading on error (never flashes
/// empty), per ARCHITECTURE.md.
@MainActor
final class UsageModel: ObservableObject {
    enum State: Equatable {
        case loading
        case ok
        case error(String)
        case signedOut           // no Claude credential at all → prompt to sign in
        var isError: Bool { if case .error = self { return true } else { return false } }
        var isSignedOut: Bool { self == .signedOut }
    }

    @Published private(set) var metrics: [UsageMetric] = []
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var state: State = .loading
    /// True when the last failure was a claude.ai cookie expiry — drives the
    /// "Sign in to Claude" CTA off the typed error, not the message text.
    @Published private(set) var needsLogin = false

    private let provider: any UsageProvider
    /// When set, the active provider is resolved fresh on each fetch (so sign-in/out
    /// and the prefer-cookie toggle take effect immediately). `nil` → signed out.
    /// When unset, the fixed `provider` above is used (previews / self-tests).
    private let resolveProvider: (@MainActor () -> (any UsageProvider)?)?
    /// Live, not constant — Settings can change it and the timer reschedules.
    private(set) var refreshInterval: TimeInterval
    private var timer: Timer?
    /// The single in-flight fetch. A monotonic `fetchGeneration` stamps each one so
    /// a late-completing fetch (e.g. against a credential the user just removed)
    /// can never resurrect stale state after an auth change.
    private var fetchTask: Task<Void, Never>?
    private var fetchGeneration = 0
    private var cancellables = Set<AnyCancellable>()

    init(provider: any UsageProvider = ClaudeOAuthProvider(),
         refreshInterval: TimeInterval = 60,
         settings: AppSettings? = nil,
         resolveProvider: (@MainActor () -> (any UsageProvider)?)? = nil) {
        self.provider = provider
        self.resolveProvider = resolveProvider
        self.refreshInterval = settings?.refreshInterval ?? refreshInterval

        // Mirror the user's interval choice live: when Settings publishes a new
        // value, reschedule the running timer without restarting the app.
        settings?.$refreshInterval
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] interval in self?.setRefreshInterval(interval) }
            .store(in: &cancellables)
    }

    /// Build a model from pre-fetched data, for the headless `--snapshot` renderer.
    convenience init(previewResult: Result<[UsageMetric], Error>, refreshInterval: TimeInterval = 60) {
        self.init(refreshInterval: refreshInterval)
        switch previewResult {
        case .success(let m):
            metrics = m
            lastUpdated = Date()
            state = m.isEmpty ? .error("No usage metrics available") : .ok
        case .failure(let error):
            state = .error(UsageModel.message(for: error))
        }
    }

    /// Start the immediate fetch + repeating timer. Idempotent.
    func start() {
        guard timer == nil else { return }
        refreshNow()
        scheduleTimer()
    }

    /// Change the refresh cadence and reschedule the live timer (if running)
    /// without restarting the app. No-op when the value is unchanged.
    func setRefreshInterval(_ interval: TimeInterval) {
        guard interval != refreshInterval else { return }
        refreshInterval = interval
        guard timer != nil else { return } // not started yet → start() will pick it up
        timer?.invalidate()
        timer = nil
        scheduleTimer()
    }

    private func scheduleTimer() {
        let t = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            // Hop back onto the main actor; the Timer block itself is non-isolated.
            Task { @MainActor in self?.refreshNow() }
        }
        // Coalesce wake-ups proportionally (still sub-interval); we don't need
        // sub-second accuracy, but a 5s tolerance on a 30s timer is fine too.
        t.tolerance = min(5, refreshInterval * 0.1)
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// Fetch once now. Safe to call from the Refresh button or the timer.
    func refreshNow() {
        // Auth-aware: when a resolver is wired, pick the current provider each time
        // so sign-in/out and the prefer-cookie toggle apply without a restart.
        let activeProvider: (any UsageProvider)? = resolveProvider.map { $0() } ?? provider
        guard let activeProvider else {
            // No credential → signed out. Drop stale data; the UI shows the CTA.
            invalidateFetch()
            needsLogin = false
            state = .signedOut
            metrics = []
            lastUpdated = nil
            return
        }

        guard fetchTask == nil else { return } // one fetch in flight at a time
        if metrics.isEmpty { state = .loading } // only show the spinner before first data

        let generation = fetchGeneration
        fetchTask = Task { @MainActor in
            do {
                let fresh = try await activeProvider.fetch()
                guard generation == self.fetchGeneration else { return } // superseded → drop
                self.metrics = fresh
                self.lastUpdated = Date()
                self.needsLogin = false
                self.state = .ok
            } catch {
                guard generation == self.fetchGeneration else { return } // superseded → drop
                // Last-good cache: keep `metrics`/`lastUpdated`; just flag the reason.
                self.needsLogin = (error as? ProviderError).map { if case .needsLogin = $0 { true } else { false } } ?? false
                self.state = .error(UsageModel.message(for: error))
            }
            if generation == self.fetchGeneration { self.fetchTask = nil }
        }
    }

    /// Re-resolve auth and fetch immediately. Call after sign-in / sign-out / a
    /// prefer-cookie change so the menu bar reflects the new credential at once.
    func reloadAuth() {
        // Cancel + supersede any in-flight fetch so its (old-credential) result can
        // never land late and overwrite the new state.
        invalidateFetch()

        // Reflect a sign-out instantly, even if a fetch was still in flight.
        if let resolveProvider, resolveProvider() == nil {
            needsLogin = false
            state = .signedOut
            metrics = []
            lastUpdated = nil
            return
        }
        refreshNow()
    }

    /// Supersede the current fetch: bump the generation (so a late result is
    /// ignored), cancel the task, and clear the handle.
    private func invalidateFetch() {
        fetchGeneration &+= 1
        fetchTask?.cancel()
        fetchTask = nil
    }

    /// Human-readable, token-safe error text. Credential/auth failures get a clear
    /// "expired / not found" message instead of a number.
    static func message(for error: Error) -> String {
        if let providerError = error as? ProviderError {
            switch providerError {
            case .authExpired:
                return "Claude token expired / not found — re-authenticate Claude Code."
            case .needsLogin:
                return "Claude.ai session expired — sign in again."
            case .rateLimited:
                return "Rate limited — backing off, will retry."
            case .credential(let detail):
                return detail
            case .network(let detail):
                return "Network error: \(detail)"
            default:
                return providerError.description
            }
        }
        return error.localizedDescription
    }
}
