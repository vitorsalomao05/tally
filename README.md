# Houdini — see your AI usage and spend, revealed

> A local-first **macOS menu bar app** that reveals your AI usage and spend.
> Repo: [`vitorsalomao05/houdini`](https://github.com/vitorsalomao05/houdini) ·
> Site: **[houdini.salomao.org](https://houdini.salomao.org)** ·
> Target: **macOS 14+ / Apple Silicon**.

Houdini is a multi-provider platform for AI usage + cost on macOS. **Claude
(Pro/Max) is live today** — your 5-hour and weekly limits, reset timers, and
any extra-usage spend, refreshed about **every 60 seconds**. OpenAI, Gemini, and
the Anthropic Console are on the roadmap. No account, no server; credentials stay
in your Keychain.

## Install (macOS 14+, Apple Silicon)

```sh
curl -fsSL https://raw.githubusercontent.com/vitorsalomao05/houdini/v0.2.0/install.sh | bash
```

Downloads the ad-hoc-signed `Houdini.app` + the `houdini` CLI from the pinned
[`v0.2.0` release](https://github.com/vitorsalomao05/houdini/releases/tag/v0.2.0),
**verifies their SHA-256** against `SHASUMS256.txt`, then installs without `sudo`
(app → `~/Applications`, CLI → `~/.local/bin`) — with no Gatekeeper prompt. It
offers (never forces) launch at login and the Übersicht widget, and is safe to
re-run. Read it first — it's at [`install.sh`](install.sh). A notarized DMG is the
next milestone.

It ships in surfaces, all installable from the landing site:

1. **Menu bar app** (flagship) — always visible, true 60s refresh.
2. **Übersicht desktop widget** — single `.jsx`, true 60s refresh.
3. **Notification Center widget (WidgetKit)** — glanceable, ~15 min refresh (Apple limitation, see `DECISIONS.md`).

## The core idea (read this first)

The naive approach is "open a logged-in page in a background browser, reload every minute, scrape the number." We researched this and found a **much better path**: most AI usage numbers are backed by a **JSON endpoint**, not just rendered HTML. So instead of driving a browser, Houdini reads the user's existing credential (Keychain OAuth token or session cookie) and calls the JSON endpoint directly. This is lighter (~6 MB native vs hundreds of MB of bundled Chromium), more robust (no DOM breakage), and far easier to sign/notarize.

The background-browser scrape survives only as a **last-resort fallback adapter** for providers that genuinely have no readable endpoint.

## Providers

| Provider | Source | Method | Status |
|---|---|---|---|
| **Claude (Pro/Max)** | `api.anthropic.com/api/oauth/usage` (Claude Code OAuth token in Keychain) **or** `claude.ai/api/organizations/{org}/usage` (session cookie) | JSON | **Live** |
| **OpenAI Platform** (API usage/cost) | `/v1/organization/usage/*`, `/v1/organization/costs` | JSON (admin key) | Soon |
| **Google Gemini** (API usage/cost) | API usage endpoints | JSON (API key) | Soon |
| **Anthropic Console** (API usage/cost) | Admin API `usage_report` / `cost_report` | JSON (admin key) | Soon |

See `PROVIDERS.md` for the full adapter contract and per-provider specs (including the experimental ChatGPT-Plus path), and `ARCHITECTURE.md` for the system design.

## Repo layout

```
houdini/
├── README.md            ← this file
├── ARCHITECTURE.md      ← system design + diagram
├── DECISIONS.md         ← ADRs (why menu bar, why no 60s widget, the rebrand…)
├── PROVIDERS.md         ← provider-adapter contract + per-provider specs
├── ROADMAP.md           ← phased plan
├── core/                ← FetcherCore Swift package (shared data layer) + `houdini` CLI
├── apps/
│   ├── menubar/         ← SwiftUI MenuBarExtra app (flagship)
│   ├── widget/          ← WidgetKit extension (glanceable)
│   └── ubersicht/       ← single .jsx desktop widget
├── site/                ← Astro + Tailwind landing page
├── install.sh           ← one-liner installer (verified download from Releases)
└── scripts/             ← release automation
```

## Privacy posture

Credentials never leave the device. Tokens/cookies live in the macOS Keychain. No Houdini server ever sees them — there is none. Requests go straight from your Mac to each provider's own endpoint. The landing site has a dedicated trust/privacy section because the app touches logins.
