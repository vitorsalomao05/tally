import AppKit
import WebKit

/// A small `WKWebView` window that signs the user into claude.ai and captures the
/// `sessionKey` cookie (`sk-ant-sid01-…`). The cookie is handed to `onSuccess` —
/// which stores it in the Keychain — and the window closes itself. The value is
/// never logged and never leaves the device (ADR-005).
@MainActor
final class ClaudeLoginWindowController: NSObject {
    private static let loginURL = URL(string: "https://claude.ai/login")!
    private static let cookieName = "sessionKey"
    private static let cookiePrefix = "sk-ant-sid01"

    private var window: NSWindow?
    private var webView: WKWebView?
    private var onSuccess: ((String) -> Void)?
    private var onClose: (() -> Void)?
    private var captured = false

    /// Open the login window. `onSuccess` fires once with the captured cookie value;
    /// `onClose` fires when the window goes away (success or user-cancelled).
    func present(onSuccess: @escaping (String) -> Void, onClose: @escaping () -> Void) {
        // Already open → just bring it forward.
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        self.onSuccess = onSuccess
        self.onClose = onClose
        self.captured = false

        let config = WKWebViewConfiguration()
        // EPHEMERAL store, deliberately: the captured cookie must live in the
        // Keychain only (ADR-005), never in WebKit's on-disk jar. A fresh in-memory
        // store per login also means (a) "Sign out" can't be undone by a residual
        // WebKit cookie, and (b) re-sign-in always starts logged-out — so account
        // switching works and an expired cookie can't be silently re-captured.
        // Redirect-based SSO still completes within this single window session.
        config.websiteDataStore = .nonPersistent()

        let webView = WKWebView(
            frame: NSRect(x: 0, y: 0, width: 480, height: 680),
            configuration: config
        )
        webView.navigationDelegate = self
        webView.uiDelegate = self
        config.websiteDataStore.httpCookieStore.add(self)
        self.webView = webView

        let window = NSWindow(
            contentRect: webView.frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Sign in to Claude.ai"
        window.contentView = webView
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        self.window = window

        webView.load(URLRequest(url: Self.loginURL))
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    // MARK: - Cookie capture

    private func checkForSessionCookie() {
        guard !captured, let store = webView?.configuration.websiteDataStore.httpCookieStore else { return }
        store.getAllCookies { [weak self] cookies in
            guard let self else { return }
            guard let cookie = cookies.first(where: {
                $0.name == Self.cookieName && $0.value.hasPrefix(Self.cookiePrefix)
            }) else { return }
            self.capture(cookie.value)
        }
    }

    private func capture(_ value: String) {
        guard !captured else { return }
        captured = true
        onSuccess?(value)
        closeWindow()
    }

    func closeWindow() {
        webView?.configuration.websiteDataStore.httpCookieStore.remove(self)
        window?.close()        // triggers windowWillClose → cleanup + onClose
    }
}

// MARK: - Navigation / popups

extension ClaudeLoginWindowController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Backstop in case the cookie-store observer doesn't fire for a given write.
        checkForSessionCookie()
    }
}

extension ClaudeLoginWindowController: WKUIDelegate {
    // Some SSO buttons try to open a new window; load such requests in-place so the
    // flow stays inside this single webview.
    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
            webView.load(URLRequest(url: url))
        }
        return nil
    }
}

// MARK: - Cookie store observer

extension ClaudeLoginWindowController: WKHTTPCookieStoreObserver {
    nonisolated func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
        Task { @MainActor in self.checkForSessionCookie() }
    }
}

// MARK: - Window lifecycle

extension ClaudeLoginWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        webView?.configuration.websiteDataStore.httpCookieStore.remove(self)
        webView?.navigationDelegate = nil
        webView?.uiDelegate = nil
        webView = nil
        window = nil
        let close = onClose
        onClose = nil
        onSuccess = nil
        close?()
    }
}
