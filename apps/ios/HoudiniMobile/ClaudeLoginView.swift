import SwiftUI
import WebKit
import FetcherCore

/// In-app claude.ai sign-in. A `WKWebView` (non-persistent data store) loads
/// `claude.ai/login`; once the `sessionKey` cookie (`sk-ant-sid01-…`) appears in
/// the **native** cookie store, we capture it, write it to the iOS Keychain, and
/// dismiss. This is the iOS port of `apps/menubar/.../ClaudeLoginWindow.swift`.
///
/// Why `WKWebView` and not `ASWebAuthenticationSession`: only the native
/// `WKHTTPCookieStore` can read the **httpOnly** `sessionKey` cookie; the auth
/// session API only returns a redirect callback URL (PLAN.md §1). The value is
/// never logged and never leaves the device (ADR-005).
struct ClaudeLoginView: View {
    /// Fires once after the cookie is captured + stored, so the caller can refetch.
    var onSuccess: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ClaudeLoginWebView(onCapture: { cookieValue in
                store(cookieValue)
                onSuccess()
                dismiss()
            })
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle("Sign in to Claude")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    /// Persist the captured cookie. Houdini owns this Keychain item, so it reads it
    /// back later (app + widget) without a prompt.
    private func store(_ value: String) {
        try? CredentialStore().nativeWriteGenericPassword(
            service: ClaudeCookieProvider.keychainService,
            account: ClaudeCookieProvider.keychainAccount,
            data: Data(value.utf8)
        )
    }
}

/// The `WKWebView` itself, bridged into SwiftUI.
private struct ClaudeLoginWebView: UIViewRepresentable {
    var onCapture: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onCapture: onCapture) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // EPHEMERAL store: the captured cookie must live in the Keychain only
        // (ADR-005), never in WebKit's on-disk jar. A fresh in-memory store also
        // means re-sign-in always starts logged-out, so account switching works.
        config.websiteDataStore = .nonPersistent()

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        config.websiteDataStore.httpCookieStore.add(context.coordinator)
        context.coordinator.webView = webView

        webView.load(URLRequest(url: Coordinator.loginURL))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.configuration.websiteDataStore.httpCookieStore.remove(coordinator)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKHTTPCookieStoreObserver {
        static let loginURL = URL(string: "https://claude.ai/login")!
        private static let cookieName = "sessionKey"
        private static let cookiePrefix = "sk-ant-sid01"

        weak var webView: WKWebView?
        private let onCapture: (String) -> Void
        private var captured = false

        init(onCapture: @escaping (String) -> Void) { self.onCapture = onCapture }

        // Observer path: fires whenever WebKit writes a cookie.
        func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
            check(cookieStore)
        }

        // Backstop in case the observer misses a write for a given navigation.
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            check(webView.configuration.websiteDataStore.httpCookieStore)
        }

        // Some SSO buttons open a new window; keep the flow in this one webview.
        func webView(_ webView: WKWebView,
                     createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
                webView.load(URLRequest(url: url))
            }
            return nil
        }

        private func check(_ store: WKHTTPCookieStore) {
            guard !captured else { return }
            store.getAllCookies { [weak self] cookies in
                guard let self, !self.captured else { return }
                guard let cookie = cookies.first(where: {
                    $0.name == Self.cookieName && $0.value.hasPrefix(Self.cookiePrefix)
                }) else { return }
                self.captured = true
                self.onCapture(cookie.value)
            }
        }
    }
}
