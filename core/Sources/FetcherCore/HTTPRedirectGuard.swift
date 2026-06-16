import Foundation

/// Per-request `URLSession` delegate that strips credential headers (`Cookie`,
/// `Authorization`) from any **cross-site** HTTP redirect. Foundation's default
/// redirect handling copies a manually-set `Cookie`/`Authorization` header onto
/// the redirected request even when it targets a different host — so a redirect
/// to an unexpected origin could leak the session cookie or bearer token. This
/// guard keeps headers on same-site redirects and removes them otherwise.
///
/// Use via `URLSession.shared.data(for:delegate:)`. Stateless → safe to share.
final class CredentialRedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    static let shared = CredentialRedirectGuard()

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        let originalHost = task.originalRequest?.url?.host
        let newHost = request.url?.host
        if let originalHost, let newHost, Self.sameSite(originalHost, newHost) {
            completionHandler(request) // same site → preserve headers
        } else {
            var stripped = request
            stripped.setValue(nil, forHTTPHeaderField: "Cookie")
            stripped.setValue(nil, forHTTPHeaderField: "Authorization")
            completionHandler(stripped)
        }
    }

    /// Same registrable site: identical hosts, or one a subdomain of the other.
    /// Conservative — anything else falls through to header stripping.
    static func sameSite(_ a: String, _ b: String) -> Bool {
        a == b || a.hasSuffix("." + b) || b.hasSuffix("." + a)
    }
}
