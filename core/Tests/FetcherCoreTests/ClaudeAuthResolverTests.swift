import Testing
import Foundation
@testable import FetcherCore

/// P1 slice (a): the broadened Claude OAuth login path — ordered Keychain discovery,
/// `~/.claude/.credentials.json` file fallback, and in-memory `refreshToken` refresh —
/// all behind ``ClaudeOAuthCredentialSource`` / ``ClaudeAuthResolver``.
///
/// Every seam (Keychain read, file read, refresher, clock) is injected, so no test ever
/// touches the real Keychain, disk, or network. All tokens are OBVIOUSLY-FAKE placeholders.
/// `houdini-selftest` mirrors these assertions so they're observable on a
/// CommandLineTools-only machine where `swift test`'s runner no-ops.
@Suite struct ClaudeAuthResolverTests {

    // MARK: - Fixtures & seams

    static let fixedNow = Date(timeIntervalSince1970: 1_750_000_000) // deterministic clock
    static var pastMs: Double { (fixedNow.timeIntervalSince1970 - 3600) * 1000 }
    static var futureMs: Double { (fixedNow.timeIntervalSince1970 + 3600) * 1000 }
    static let clock: @Sendable () -> Date = { fixedNow }
    static let fresh = "sk-ant-oat01-FRESH-FOR-TESTS"

    /// A Claude Code OAuth blob `{ "claudeAiOauth": { ... } }` carrying only the given keys.
    func blob(access: String?, expiresAt: Double? = nil, refresh: String? = nil) -> Data {
        var inner: [String: Any] = [:]
        if let access { inner["accessToken"] = access }
        if let expiresAt { inner["expiresAt"] = expiresAt }
        if let refresh { inner["refreshToken"] = refresh }
        return try! JSONSerialization.data(withJSONObject: ["claudeAiOauth": inner])
    }

    /// Injected Keychain read: yields data for `present` services, else `.notFound` (skip).
    func keychain(_ present: [String: Data]) -> @Sendable (String) throws -> Data {
        { service in
            guard let d = present[service] else { throw CredentialError.notFound(service: service) }
            return d
        }
    }

    /// A refresher that always returns a fresh, unexpired blob (echoing the refresh token).
    let refresher: ClaudeOAuthCredentialSource.Refresher = { rt in
        ClaudeOAuthCredentialSource.Blob(
            accessToken: ClaudeAuthResolverTests.fresh,
            expiresAt: ClaudeAuthResolverTests.futureMs,
            refreshToken: rt)
    }

    /// A single-item source (service "only") with an optional refresher.
    func source(_ blob: Data?, refresher: ClaudeOAuthCredentialSource.Refresher? = nil) -> ClaudeOAuthCredentialSource {
        ClaudeOAuthCredentialSource(
            services: ["only"],
            keychainRead: keychain(blob.map { ["only": $0] } ?? [:]),
            refresher: refresher,
            now: Self.clock)
    }

    func resolver(_ blob: Data?, refresher: ClaudeOAuthCredentialSource.Refresher? = nil, cookie: Bool) -> ClaudeAuthResolver {
        ClaudeAuthResolver(oauthSource: source(blob, refresher: refresher), cookiePresent: { cookie })
    }

    private func fixture(_ name: String) throws -> Data {
        let url = try #require(
            Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"),
            "missing fixture \(name).json")
        return try Data(contentsOf: url)
    }

    // MARK: - Ordered Keychain discovery

    @Test func discoveryFallsThroughToClassicClaudeCodeItem() async throws {
        let src = ClaudeOAuthCredentialSource(
            services: ["Claude Code-credentials", "Claude Code"],
            keychainRead: keychain(["Claude Code": blob(access: "sk-ant-oat01-FAKE-CLASSIC", expiresAt: Self.futureMs)]),
            now: Self.clock)
        #expect(try await src.resolveForFetch().accessToken == "sk-ant-oat01-FAKE-CLASSIC")
    }

    @Test func primaryCredentialsItemWinsWhenBothPresent() async throws {
        let src = ClaudeOAuthCredentialSource(
            services: ["Claude Code-credentials", "Claude Code"],
            keychainRead: keychain([
                "Claude Code-credentials": blob(access: "sk-ant-oat01-FAKE-PRIMARY", expiresAt: Self.futureMs),
                "Claude Code": blob(access: "sk-ant-oat01-FAKE-CLASSIC", expiresAt: Self.futureMs),
            ]),
            now: Self.clock)
        #expect(try await src.resolveForFetch().accessToken == "sk-ant-oat01-FAKE-PRIMARY")
    }

    // MARK: - On-disk fallback

    @Test func fileFallbackUsedWhenNoKeychainItem() async throws {
        let data = try fixture("oauth_credentials")
        let src = ClaudeOAuthCredentialSource(
            services: ["Claude Code-credentials", "Claude Code"],
            keychainRead: keychain([:]),
            fileRead: { data },
            now: Self.clock)
        #expect(try await src.resolveForFetch().accessToken == "sk-ant-oat01-FAKE-FOR-TESTS")
    }

    // MARK: - Usability semantics

    @Test func unexpiredTokenIsUsable() {
        #expect(source(blob(access: "sk-ant-oat01-FAKE", expiresAt: Self.futureMs)).hasUsableToken())
    }

    @Test func expiredButRefreshableIsUsable() {
        #expect(source(blob(access: "sk-ant-oat01-FAKE", expiresAt: Self.pastMs, refresh: "sk-ant-ort01-FAKE"),
                       refresher: refresher).hasUsableToken())
    }

    @Test func expiredRefreshableWithoutRefresherIsUnusable() {
        #expect(source(blob(access: "sk-ant-oat01-FAKE", expiresAt: Self.pastMs, refresh: "sk-ant-ort01-FAKE"))
            .hasUsableToken() == false)
    }

    @Test func expiredWithoutRefreshTokenIsUnusable() {
        #expect(source(blob(access: "sk-ant-oat01-FAKE", expiresAt: Self.pastMs)).hasUsableToken() == false)
    }

    @Test func absentCredentialIsUnusable() {
        #expect(source(nil).hasUsableToken() == false)
    }

    // MARK: - In-memory refresh

    @Test func expiredTokenRefreshesInMemoryToFreshToken() async throws {
        let src = source(blob(access: "sk-ant-oat01-FAKE-STALE", expiresAt: Self.pastMs, refresh: "sk-ant-ort01-FAKE"),
                         refresher: refresher)
        #expect(try await src.resolveForFetch().accessToken == Self.fresh)
    }

    @Test func unexpiredTokenUsedAsIsWithoutRefreshing() async throws {
        let src = source(blob(access: "sk-ant-oat01-FAKE-LIVE", expiresAt: Self.futureMs, refresh: "sk-ant-ort01-FAKE"),
                         refresher: refresher)
        #expect(try await src.resolveForFetch().accessToken == "sk-ant-oat01-FAKE-LIVE")
    }

    @Test func absentCredentialResolveForFetchThrows() async {
        await #expect(throws: ProviderError.self) {
            _ = try await source(nil).resolveForFetch()
        }
    }

    // MARK: - Resolver OAuth-vs-cookie preference

    @Test func absentCredentialResolvesToNoneAndNeverThrows() {
        let r = resolver(nil, cookie: false)
        #expect(r.hasUsableOAuthToken() == false)
        #expect(r.resolve() == .none)
    }

    @Test func cookieOnlyResolvesToCookie() {
        #expect(resolver(nil, cookie: true).resolve() == .cookie)
    }

    @Test func staleButRefreshableOAuthIsPreferredOverCookie() {
        let r = resolver(blob(access: "sk-ant-oat01-FAKE", expiresAt: Self.pastMs, refresh: "sk-ant-ort01-FAKE"),
                         refresher: refresher, cookie: true)
        #expect(r.resolve() == .oauth)
    }

    @Test func expiredNonRefreshableDemotesToCookie() {
        let r = resolver(blob(access: "sk-ant-oat01-FAKE", expiresAt: Self.pastMs), cookie: true)
        #expect(r.resolve() == .cookie)
    }
}
