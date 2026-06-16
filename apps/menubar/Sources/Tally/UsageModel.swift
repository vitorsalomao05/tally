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
        var isError: Bool { if case .error = self { return true } else { return false } }
    }

    @Published private(set) var metrics: [UsageMetric] = []
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var state: State = .loading

    private let provider: any UsageProvider
    let refreshInterval: TimeInterval
    private var timer: Timer?
    private var inFlight = false

    init(provider: any UsageProvider = ClaudeOAuthProvider(), refreshInterval: TimeInterval = 60) {
        self.provider = provider
        self.refreshInterval = refreshInterval
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

    /// Start the immediate fetch + repeating 60s timer. Idempotent.
    func start() {
        guard timer == nil else { return }
        refreshNow()
        let t = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            // Hop back onto the main actor; the Timer block itself is non-isolated.
            Task { @MainActor in self?.refreshNow() }
        }
        t.tolerance = 5 // let the OS coalesce wake-ups; we don't need sub-second accuracy
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// Fetch once now. Safe to call from the Refresh button or the timer.
    func refreshNow() {
        guard !inFlight else { return }
        inFlight = true
        if metrics.isEmpty { state = .loading } // only show the spinner before first data

        Task { @MainActor in
            defer { self.inFlight = false }
            do {
                let fresh = try await provider.fetch()
                self.metrics = fresh
                self.lastUpdated = Date()
                self.state = .ok
            } catch {
                // Last-good cache: keep `metrics`/`lastUpdated`; just flag the reason.
                self.state = .error(UsageModel.message(for: error))
            }
        }
    }

    /// Human-readable, token-safe error text. Credential/auth failures get a clear
    /// "expired / not found" message instead of a number.
    static func message(for error: Error) -> String {
        if let providerError = error as? ProviderError {
            switch providerError {
            case .authExpired:
                return "Claude token expired / not found — re-authenticate Claude Code."
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
