import Foundation
import FetcherCore

// tally-selftest — a runnable proof of the FetcherCore parser + org-selection
// logic, reading the SAME committed fixtures as Tests/FetcherCoreTests.
//
// Why this exists alongside the swift-testing suite: this machine has only
// CommandLineTools, which ships `Testing.framework` but whose SwiftPM async
// entry point no-ops under `swift test` (it executes normally on a full Xcode
// toolchain / CI). This executable lets us actually *observe* the assertions
// pass here. It mirrors the `--selftest` idiom already used by the menu bar app.
//
// Exit code: 0 if every check passes, 1 otherwise.

var failures = 0
var checks = 0

@MainActor
func check(_ name: String, _ passed: Bool, _ detail: @autoclosure () -> String = "") {
    checks += 1
    if passed {
        print("  ✔ \(name)")
    } else {
        failures += 1
        let d = detail()
        print("  ✘ \(name)\(d.isEmpty ? "" : " — \(d)")")
    }
}

// Locate the committed fixtures relative to this source file.
let fixturesDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()            // Sources/tally-selftest
    .deletingLastPathComponent()            // Sources
    .deletingLastPathComponent()            // core
    .appendingPathComponent("Tests/FetcherCoreTests/Fixtures")

func fixture(_ name: String) -> Data {
    let url = fixturesDir.appendingPathComponent("\(name).json")
    guard let data = try? Data(contentsOf: url) else {
        print("FATAL: cannot read fixture \(url.path)")
        exit(2)
    }
    return data
}

func iso(_ s: String) -> Date {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f.date(from: s)!
}

let expected: [UsageMetric] = {
    let fiveHourReset = iso("2026-06-16T11:39:59Z")
    let weeklyReset = iso("2026-06-22T05:59:59Z")
    return [
        UsageMetric(label: "5-hour", pct: 3, resetAt: fiveHourReset, providerId: "claude"),
        UsageMetric(label: "Weekly", pct: 15, resetAt: weeklyReset, providerId: "claude"),
        UsageMetric(label: "Opus weekly", pct: 42, resetAt: weeklyReset, providerId: "claude"),
        UsageMetric(label: "Sonnet weekly", pct: 0, resetAt: weeklyReset, providerId: "claude"),
        UsageMetric(label: "Extra usage ($)", pct: 93.07, used: 93.07, limit: 100,
                    dollars: 93.07, providerId: "claude"),
    ]
}()

print("=== tally-selftest: ClaudeUsageParser (2 fixtures) ===")

do {
    let oauth = try ClaudeUsageParser.parse(fixture("oauth_usage"), providerId: "claude")
    let cookie = try ClaudeUsageParser.parse(fixture("cookie_usage"), providerId: "claude")

    check("OAuth dialect → expected metrics", oauth == expected, "got \(oauth)")
    check("cookie dialect → expected metrics", cookie == expected, "got \(cookie)")
    check("both dialects are equivalent", oauth == cookie, "oauth=\(oauth)\n      cookie=\(cookie)")

    let partial = try ClaudeUsageParser.parse(Data(#"{ "five_hour": { "utilization": 7 } }"#.utf8),
                                              providerId: "claude")
    check("missing windows skipped (not fatal)",
          partial == [UsageMetric(label: "5-hour", pct: 7, providerId: "claude")])

    let empty = try ClaudeUsageParser.parse(Data("{}".utf8), providerId: "claude")
    check("empty object → no metrics", empty.isEmpty)
} catch {
    check("parser did not throw on valid fixtures", false, "\(error)")
}

do {
    _ = try ClaudeUsageParser.parse(Data("not json".utf8), providerId: "claude")
    check("malformed JSON throws .parse", false, "no error thrown")
} catch ProviderError.parse {
    check("malformed JSON throws .parse", true)
} catch {
    check("malformed JSON throws .parse", false, "wrong error: \(error)")
}

print("=== reset-date tolerance ===")
let micros = ClaudeUsageParser.parseResetDate("2026-06-16T11:39:59.602994+00:00")
let millis = ClaudeUsageParser.parseResetDate("2026-06-16T11:39:59.602+00:00")
check("microsecond precision normalizes to milliseconds", micros != nil && micros == millis)
check("plain timestamp parses", ClaudeUsageParser.parseResetDate("2026-06-22T05:59:59+00:00") != nil)
check("nil / empty → nil",
      ClaudeUsageParser.parseResetDate(nil) == nil && ClaudeUsageParser.parseResetDate("") == nil)

print("=== org selection ===")
do {
    let paid = try ClaudeCookieProvider.selectOrganization(from: fixture("organizations"))
    check("prefers paid org over free", paid == "org-paid-0002", "got \(paid)")

    let free = try ClaudeCookieProvider.selectOrganization(from: fixture("organizations_all_free"))
    check("falls back to first when none paid", free == "org-first-9001", "got \(free)")

    let idKey = try ClaudeCookieProvider.selectOrganization(
        from: Data(#"[{ "id": "org-id-key-7", "capabilities": ["claude_max"] }]"#.utf8))
    check("tolerates id key instead of uuid", idKey == "org-id-key-7", "got \(idKey)")
} catch {
    check("org selection did not throw on valid lists", false, "\(error)")
}
do {
    _ = try ClaudeCookieProvider.selectOrganization(from: Data("[]".utf8))
    check("empty org list throws", false, "no error thrown")
} catch {
    check("empty org list throws", true)
}

print("=== error surface ===")
check("needsLogin has a clear description",
      ProviderError.needsLogin.description.contains("Claude.ai"))

print("---")
if failures == 0 {
    print("PASS — \(checks) checks")
    exit(0)
} else {
    print("FAIL — \(failures)/\(checks) checks failed")
    exit(1)
}
