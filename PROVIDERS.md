# Provider adapters

Every data source implements one protocol. The UI never special-cases a provider; it reads capability flags and renders whatever metrics come back.

## Contract

```swift
protocol UsageProvider {
    var id: String { get }                       // "claude", "anthropic-console", "openai-platform", "chatgpt-plus"
    var displayName: String { get }
    var authMethod: AuthMethod { get }           // .keychainOAuth | .sessionCookie | .adminApiKey
    var capabilities: Capabilities { get }        // what this provider can actually supply
    var refreshInterval: TimeInterval { get }     // 30–120s typical

    func fetch() async throws -> [UsageMetric]
}

struct Capabilities: OptionSet {
    static let usagePct      = Capabilities(rawValue: 1 << 0)
    static let resetTimer    = Capabilities(rawValue: 1 << 1)
    static let dollarBalance = Capabilities(rawValue: 1 << 2)
}

struct UsageMetric {
    let label: String        // "5-hour", "Weekly", "Opus weekly", "API cost (today)"
    var pct: Double?         // 0–100
    var used: Double?
    var limit: Double?
    var resetAt: Date?
    var dollars: Double?
    let providerId: String
}

enum AuthMethod { case keychainOAuth, sessionCookie, adminApiKey }
```

Cross-cutting services in `FetcherCore`: `CredentialStore` (Keychain), `Scheduler` (interval + jitter + backoff), `Cache` (last-good value).

---

## claude (Pro/Max) — FLAGSHIP, build first
- **Capabilities:** `usagePct`, `resetTimer` (+ `dollarBalance` if "Claude Extra" overage).
- **Primary auth:** `.keychainOAuth` — reuse the **Claude Code OAuth token** from Keychain (item commonly named `Claude Code`; CLI also writes `~/.claude`). The user already runs Claude Code, so this needs zero new login.
- **Primary endpoint:** `GET https://api.anthropic.com/api/oauth/usage`
  - Headers: `Authorization: Bearer <token>` **and** `User-Agent: claude-code/<version>` (always send it — a missing UA **may cause throttling under sustained use**; the code keeps it for safety).
  - Returns 5-hour / 7-day / Opus-7-day utilization.
- **Fallback auth:** `.sessionCookie` — `sessionKey` cookie (`sk-ant-sid01-…`) from an embedded WebView login. Then:
  - `GET https://claude.ai/api/organizations` → read `org_id`.
  - `GET https://claude.ai/api/organizations/{org_id}/usage` → fields: `five_hour.utilization_pct`, `five_hour.reset_at`, `seven_day.utilization_pct`, `seven_day_opus.utilization_pct`, `extra_usage.current_spending`, `extra_usage.budget_limit`.
- **Fragility:** medium (undocumented). **Risk:** low (own account, low-frequency).
- **Reference:** `github.com/ttar-p/claude-usage-widget`, `github.com/hamed-elfayome/Claude-Usage-Tracker`.

## anthropic-console (API usage/cost) — secondary
- **Capabilities:** `dollarBalance` (cost), usage tokens. NOT remaining prepaid balance via API.
- **Auth:** `.adminApiKey` — `sk-ant-admin…` (org accounts only; unavailable for individual accounts).
- **Endpoints:** `GET https://api.anthropic.com/v1/organizations/usage_report/messages`, `…/cost_report`. Headers `x-api-key`, `anthropic-version: 2023-06-01`.

## openai-platform (API usage/cost) — secondary
- **Capabilities:** `dollarBalance` (cost), usage. NOT remaining credit balance (legacy `credit_grants` returns 401/403 in 2025–2026).
- **Auth:** `.adminApiKey` — `sk-admin-…` (Bearer).
- **Endpoints:** `GET https://api.openai.com/v1/organization/usage/*`, `GET https://api.openai.com/v1/organization/costs`.

## chatgpt-plus (consumer quota) — EXPERIMENTAL, label clearly
- **Capabilities:** at best `resetTimer` when throttled. No reliable continuous %.
- **Auth:** `.sessionCookie` (dashboard).
- **Reality:** OpenAI exposes no clean per-user "remaining messages" counter; only implicit "limit reached / resets at X". Implement as best-effort; show "limited / OK" state, not a fake gauge.

---

## Build order
1. `claude` via `.keychainOAuth` (validate the number against the real account using `houdini`).
2. `claude` `.sessionCookie` fallback (covers users without Claude Code).
3. `openai-platform` + `anthropic-console` admin-API adapters.
4. `chatgpt-plus` experimental.
