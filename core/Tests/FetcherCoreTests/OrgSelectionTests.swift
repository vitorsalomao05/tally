import Testing
import Foundation
@testable import FetcherCore

/// Org-selection rule for the cookie provider: prefer a paid/active org, else the
/// first listed. Documented in PROVIDERS.md and ClaudeCookieProvider.
@Suite struct OrgSelectionTests {

    private func fixture(_ name: String) throws -> Data {
        let url = try #require(
            Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"),
            "missing fixture \(name).json"
        )
        return try Data(contentsOf: url)
    }

    @Test func prefersPaidOrgOverFree() throws {
        let orgId = try ClaudeCookieProvider.selectOrganization(from: fixture("organizations"))
        #expect(orgId == "org-paid-0002")
    }

    @Test func fallsBackToFirstWhenNoneArePaid() throws {
        let orgId = try ClaudeCookieProvider.selectOrganization(from: fixture("organizations_all_free"))
        #expect(orgId == "org-first-9001")
    }

    @Test func toleratesIdKeyInsteadOfUuid() throws {
        let json = Data(#"[{ "id": "org-id-key-7", "capabilities": ["claude_max"] }]"#.utf8)
        #expect(try ClaudeCookieProvider.selectOrganization(from: json) == "org-id-key-7")
    }

    @Test func emptyOrgListThrows() {
        do {
            _ = try ClaudeCookieProvider.selectOrganization(from: Data("[]".utf8))
            Issue.record("expected an error for an empty org list")
        } catch {
            // expected
        }
    }
}
