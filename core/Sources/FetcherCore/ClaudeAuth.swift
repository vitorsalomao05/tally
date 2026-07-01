import Foundation

/// Which credential is driving the Claude provider right now.
public enum ClaudeAuthKind: String, Sendable {
    case oauth   // Claude Code OAuth token (no new login required)
    case cookie  // claude.ai session cookie captured via the WebView login
    case none    // signed out — neither credential available
}

/// Decides *which* Claude credential to use, and builds the matching provider.
///
/// Preference order (PROVIDERS.md: OAuth is primary, cookie is the fallback):
///   1. a usable Claude Code OAuth token  → `ClaudeOAuthProvider`
///   2. else a captured claude.ai cookie  → `ClaudeCookieProvider`
///   3. else signed out                   → `nil`
///
/// `preferCookie` (a Settings escape hatch for testing the cookie path) flips 1↔2,
/// but still falls back to OAuth if no cookie exists yet — so toggling it never
/// strands a working Claude Code user with no data.
///
/// All Keychain reads are best-effort: any failure (missing item, denied access)
/// is treated as "credential absent", never thrown — resolution must not crash the
/// poll loop. OAuth presence is checked via the silent `security` CLI path; the
/// cookie via Houdini's own native item. The OAuth check runs first in the default
/// order, so a Claude Code user never triggers a read of the cookie item.
public struct ClaudeAuthResolver: Sendable {
    private let store: CredentialStore
    private let oauthSource: ClaudeOAuthCredentialSource
    private let cookiePresent: @Sendable () -> Bool

    public init(store: CredentialStore = CredentialStore()) {
        self.store = store
        self.oauthSource = ClaudeOAuthCredentialSource(store: store)
        self.cookiePresent = { Self.readCookiePresence(store: store) }
    }

    /// Injection seam (tests / `houdini-selftest`): supply the OAuth source and a
    /// cookie-presence check directly, so resolution can be exercised without touching
    /// the Keychain. `store` still backs `makeProvider`'s concrete providers.
    public init(oauthSource: ClaudeOAuthCredentialSource,
                cookiePresent: @escaping @Sendable () -> Bool,
                store: CredentialStore = CredentialStore()) {
        self.store = store
        self.oauthSource = oauthSource
        self.cookiePresent = cookiePresent
    }

    /// True when a usable Claude Code OAuth token exists — present and either unexpired,
    /// or expired-but-refreshable (a `refreshToken` is available *and* a refresher is
    /// wired). Discovery spans the ordered Keychain items plus the on-disk fallback (see
    /// ``ClaudeOAuthCredentialSource``). Unknown/unparseable expiry is treated as
    /// still-valid so we never wrongly demote a working token.
    public func hasUsableOAuthToken() -> Bool {
        oauthSource.hasUsableToken()
    }

    /// True when Houdini has a non-empty captured `sessionKey` cookie in its Keychain.
    public func hasSessionCookie() -> Bool {
        cookiePresent()
    }

    /// The active auth kind under the current preference.
    public func resolve(preferCookie: Bool = false) -> ClaudeAuthKind {
        if preferCookie {
            if hasSessionCookie() { return .cookie }
            return hasUsableOAuthToken() ? .oauth : .none
        }
        if hasUsableOAuthToken() { return .oauth }
        return hasSessionCookie() ? .cookie : .none
    }

    /// The concrete provider to poll, or `nil` when signed out.
    public func makeProvider(preferCookie: Bool = false) -> (any UsageProvider)? {
        switch resolve(preferCookie: preferCookie) {
        // Hand the OAuth provider the *same* source this resolver gated on, so its discovery
        // + refresh config always matches the `.oauth` verdict (identical to `store`-built in
        // production where no refresher is wired; keeps them consistent once slice (c) wires one).
        case .oauth:  return ClaudeOAuthProvider(source: oauthSource)
        case .cookie: return ClaudeCookieProvider(store: store)
        case .none:   return nil
        }
    }

    /// Non-empty captured `sessionKey` cookie in Houdini's own Keychain item? Best-effort.
    private static func readCookiePresence(store: CredentialStore) -> Bool {
        guard let data = try? store.nativeReadGenericPassword(
            service: ClaudeCookieProvider.keychainService,
            account: ClaudeCookieProvider.keychainAccount
        ) else { return false }
        let value = (String(data: data, encoding: .utf8) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return !value.isEmpty
    }
}
