# Houdini — see your AI usage and spend, revealed

> A local-first **macOS app** that reveals your AI usage and spend — in your menu bar and on your desktop.
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
offers (never forces) launch at login and the desktop widget, and is safe to
re-run. Read it first — it's at [`install.sh`](install.sh).

Houdini is **one app** with two co-equal, user-facing features (the website brands
neither separately — see ADR-010/011):

1. **Menu bar** — your tightest limit, always visible; popover with every window. True 60s refresh.
2. **Desktop widget** — the same gauges on your wallpaper. True 60s refresh. *(Übersicht-powered
   today — `apps/ubersicht`; a native build is a later round. The installer offers it as part of setup.)*

A glanceable **Notification Center widget** (WidgetKit, `apps/widget`) also exists in the repo;
Apple caps its refresh at ~15 min (ADR-002), so it's an architecture surface, not advertised on the site.

## The core idea (read this first)

The naive approach is "open a logged-in page in a background browser, reload every minute, scrape the number." We researched this and found a **much better path**: most AI usage numbers are backed by a **JSON endpoint**, not just rendered HTML. So instead of driving a browser, Houdini reads the user's existing credential (Keychain OAuth token or session cookie) and calls the JSON endpoint directly. This is lighter (~6 MB native vs hundreds of MB of bundled Chromium), more robust (no DOM breakage), and far easier to sign/notarize.

The background-browser scrape survives only as a **last-resort fallback adapter** for providers that genuinely have no readable endpoint.

## Providers

| Provider | Source | Method | Status |
|---|---|---|---|
| **Claude (Pro/Max)** | `api.anthropic.com/api/oauth/usage` (Claude Code OAuth token in Keychain) **or** `claude.ai/api/organizations/{org}/usage` (session cookie) | JSON | **Live** |
| **OpenAI Platform** (API usage/cost) | `/v1/organization/usage/*`, `/v1/organization/costs` | JSON (admin key) | Planned |
| **Google Gemini** (API usage/cost) | API usage endpoints | JSON (API key) | Planned |
| **Anthropic Console** (API usage/cost) | Admin API `usage_report` / `cost_report` | JSON (admin key) | Planned |

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
