# Tally — your AI usage, always in sight

> Working codename: **Tally** (changeable). Repo: `claude-credits-widget`.
> Target: **macOS 14+ / Apple Silicon only**. June 2026.

Tally is a lightweight macOS app that keeps your **AI subscription usage / remaining credits** visible at a glance and refreshes about **every 60 seconds**. It ships in three surfaces, all installable from the landing site:

1. **Menu bar app** (flagship) — always visible, true 60s refresh.
2. **Übersicht desktop widget** — single `.jsx`, true 60s refresh.
3. **Notification Center widget (WidgetKit)** — glanceable, ~15 min refresh (Apple limitation, see `DECISIONS.md`).

## The core idea (read this first)

The naive approach is "open a logged-in page in a background browser, reload every minute, scrape the number." We researched this and found a **much better path**: most AI usage numbers are backed by a **JSON endpoint**, not just rendered HTML. So instead of driving a browser, Tally reads the user's existing credential (Keychain OAuth token or session cookie) and calls the JSON endpoint directly. This is lighter (~6 MB native vs hundreds of MB of bundled Chromium), more robust (no DOM breakage), and far easier to sign/notarize.

The background-browser scrape survives only as a **last-resort fallback adapter** for providers that genuinely have no readable endpoint.

## Providers (v1 scope)

| Provider | Source | Method | Status |
|---|---|---|---|
| **Claude (Pro/Max)** | `api.anthropic.com/api/oauth/usage` (Claude Code OAuth token in Keychain) **or** `claude.ai/api/organizations/{org}/usage` (session cookie) | JSON | **Flagship — build first** |
| **Anthropic Console (API usage/cost)** | Admin API `usage_report` / `cost_report` | JSON (admin key) | Secondary, org accounts only |
| **OpenAI Platform (API usage/cost)** | `/v1/organization/usage/*`, `/v1/organization/costs` | JSON (admin key) | Secondary |
| **OpenAI ChatGPT Plus (quota)** | no clean endpoint | best-effort / fallback scrape | Experimental, clearly labeled |

See `PROVIDERS.md` for the adapter contract and `ARCHITECTURE.md` for the system design.

## Repo layout

```
claude-credits-widget/
├── README.md            ← this file
├── ARCHITECTURE.md      ← system design + diagram
├── DECISIONS.md         ← ADRs (why menu bar, why no 60s widget, distribution…)
├── PROVIDERS.md         ← provider-adapter contract + per-provider specs
├── ROADMAP.md           ← phased plan (what we delegate, in order)
├── WORKFLOW.md          ← the Brain ⇄ Claude Code delegation loop
├── core/                ← FetcherCore Swift package (shared data layer) + CLI
├── apps/
│   ├── menubar/         ← SwiftUI MenuBarExtra app (flagship)
│   ├── widget/          ← WidgetKit extension (glanceable)
│   └── ubersicht/       ← single .jsx desktop widget
├── site/                ← Astro + Tailwind landing page
└── scripts/             ← sign/notarize, install.sh, release automation
```

## Privacy posture

Credentials never leave the device. Tokens/cookies live in the macOS Keychain. No Tally server ever sees them. The landing site has a dedicated trust/privacy section because the app touches logins.
