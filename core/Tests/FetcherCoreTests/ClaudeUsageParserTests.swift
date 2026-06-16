import Testing
import Foundation
@testable import FetcherCore

/// Proves the tolerant parser maps BOTH usage dialects — the OAuth endpoint's
/// field names and the claude.ai cookie endpoint's field names — to the *same*
/// normalized `[UsageMetric]`. This is the requirement-D guarantee: the cookie
/// fallback produces numbers indistinguishable from the OAuth path.
///
/// (Uses swift-testing rather than XCTest: this machine has CommandLineTools only,
/// which ships `Testing.framework` but not `XCTest.framework`.)
@Suite struct ClaudeUsageParserTests {

    private func fixture(_ name: String) throws -> Data {
        let url = try #require(
            Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"),
            "missing fixture \(name).json"
        )
        return try Data(contentsOf: url)
    }

    private func iso(_ s: String) -> Date {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)!
    }

    /// The single source of truth both fixtures must normalize to.
    private var expected: [UsageMetric] {
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
    }

    @Test func oauthDialectMapsToExpectedMetrics() throws {
        let metrics = try ClaudeUsageParser.parse(fixture("oauth_usage"), providerId: "claude")
        #expect(metrics == expected)
    }

    @Test func cookieDialectMapsToExpectedMetrics() throws {
        let metrics = try ClaudeUsageParser.parse(fixture("cookie_usage"), providerId: "claude")
        #expect(metrics == expected)
    }

    /// The heart of the requirement: both dialects are interchangeable.
    @Test func bothDialectsAreEquivalent() throws {
        let oauth = try ClaudeUsageParser.parse(fixture("oauth_usage"), providerId: "claude")
        let cookie = try ClaudeUsageParser.parse(fixture("cookie_usage"), providerId: "claude")
        #expect(oauth == cookie)
    }

    /// A plan that lacks Opus/Sonnet/extra-usage just yields fewer metrics — no throw.
    @Test func missingWindowsAreSkippedNotFatal() throws {
        let json = Data(#"{ "five_hour": { "utilization": 7 } }"#.utf8)
        let metrics = try ClaudeUsageParser.parse(json, providerId: "claude")
        #expect(metrics == [UsageMetric(label: "5-hour", pct: 7, providerId: "claude")])
    }

    @Test func emptyObjectYieldsNoMetrics() throws {
        let metrics = try ClaudeUsageParser.parse(Data("{}".utf8), providerId: "claude")
        #expect(metrics.isEmpty)
    }

    @Test func malformedJSONThrowsParse() {
        do {
            _ = try ClaudeUsageParser.parse(Data("not json".utf8), providerId: "claude")
            Issue.record("expected ProviderError.parse to be thrown")
        } catch ProviderError.parse {
            // expected
        } catch {
            Issue.record("expected ProviderError.parse, got \(error)")
        }
    }

    // MARK: - Reset-date tolerance

    @Test func resetDateToleratesMicroseconds() {
        let micros = ClaudeUsageParser.parseResetDate("2026-06-16T11:39:59.602994+00:00")
        let millis = ClaudeUsageParser.parseResetDate("2026-06-16T11:39:59.602+00:00")
        #expect(micros != nil)
        #expect(micros == millis, "microsecond precision should normalize to milliseconds")
    }

    @Test func resetDateParsesPlainAndNil() {
        #expect(ClaudeUsageParser.parseResetDate("2026-06-22T05:59:59+00:00") != nil)
        #expect(ClaudeUsageParser.parseResetDate(nil) == nil)
        #expect(ClaudeUsageParser.parseResetDate("") == nil)
    }

    // MARK: - Error surface

    @Test func needsLoginHasClearDescription() {
        #expect(ProviderError.needsLogin.description.contains("Claude.ai"))
    }
}
