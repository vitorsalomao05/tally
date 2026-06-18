// Central configuration — every external URL, version pin, and the honest
// "what's live vs soon" content model lives here, so a release bump or a new
// provider is a one-file edit. Components and the /guide page read from this.

export const version = "0.2.0";

export const site = {
  name: "Houdini",
  // The reveal — broad, multi-provider positioning, honest about today.
  tagline: "Never get trapped by your AI limits.",
  description:
    "Houdini is a local-first macOS menu bar app that reveals your AI usage and spend. Your Claude Pro/Max limits, live today — refreshed every 60 seconds. No account, no server; credentials stay in your Keychain.",
  // Canonical origin (canonical + Open Graph): the Houdini subdomain on Vercel.
  domain: "https://houdini.salomao.org",
  // Real 1200×630 social card in public/og.png (regenerate: node scripts/og/build.mjs).
  ogImage: "og.png",
};

export const links = {
  github: "https://github.com/vitorsalomao05/houdini",
  // Releases / changelog page.
  changelog: "https://github.com/vitorsalomao05/houdini/releases",
  // TODO(future): signed + notarized DMG (Apple Silicon) on GitHub Releases.
  //   null → the UI renders the honest "Notarized DMG — coming soon" state.
  downloadDmg: null as string | null,
  guide: "/guide",
};

// The fastest path that WORKS TODAY for the menu bar app: a one-liner that
// downloads the ad-hoc-signed Houdini.app + the `houdini` CLI from the pinned
// release, verifies their SHA-256 against SHASUMS256.txt, then installs them
// (no sudo, no Gatekeeper prompt). Pinned to the tag, so the bytes you run are
// the bytes we shipped.
export const installOneLiner = `curl -fsSL https://raw.githubusercontent.com/vitorsalomao05/houdini/v${version}/install.sh | bash`;

// The install path for the Übersicht desktop widget: clone + run its idempotent
// installer (builds the `houdini` CLI + deploys the widget).
export const installUbersicht = [
  "git clone https://github.com/vitorsalomao05/houdini",
  "cd houdini/apps/ubersicht",
  "./install.sh",
].join("\n");

// Build-from-source path for the menu bar app — works today once cloned.
export const installMenubar = [
  "git clone https://github.com/vitorsalomao05/houdini",
  "cd houdini/apps/menubar",
  "./build.sh",
].join("\n");

// Root-anchored so they work from /guide too.
export const nav = [
  { label: "How it works", href: "/#how" },
  { label: "Reveals", href: "/#reveals" },
  { label: "Surfaces", href: "/#surfaces" },
  { label: "Install", href: "/#install" },
  { label: "Guide", href: "/guide" },
  { label: "FAQ", href: "/#faq" },
];

// ── Providers ────────────────────────────────────────────────────────────────
// status: "live" renders now; "soon" is honest roadmap (no fake functionality).
export const providers = [
  {
    name: "Claude",
    plan: "Pro · Max",
    status: "live" as const,
    detail: "Subscription windows + extra-usage spend, read from your Keychain.",
  },
  {
    name: "OpenAI Platform",
    plan: "API",
    status: "soon" as const,
    detail: "Cost and token usage via an admin key.",
  },
  {
    name: "Google Gemini",
    plan: "API",
    status: "soon" as const,
    detail: "Cost and token usage via an API key.",
  },
  {
    name: "Anthropic Console",
    plan: "API · Admin",
    status: "soon" as const,
    detail: "Org-wide API spend and tokens via an admin key.",
  },
];

// ── What Houdini reveals (home strip) ────────────────────────────────────────
// Grounded in what the product actually surfaces. "live" = today, for Claude.
export const reveals = [
  {
    title: "Session window",
    body: "Your rolling 5-hour limit — how much is left before you're throttled.",
    status: "live" as const,
  },
  {
    title: "Weekly caps",
    body: "The 7-day window, plus the model-specific weekly (Sonnet / Opus).",
    status: "live" as const,
  },
  {
    title: "Reset timers",
    body: "Exactly when each window rolls back to zero.",
    status: "live" as const,
  },
  {
    title: "Extra-usage spend",
    body: "Dollars burned past your plan, when Claude Extra is on ($93 / 100).",
    status: "live" as const,
  },
  {
    title: "Threshold alerts",
    body: "Each gauge turns green → amber → red as you near a limit.",
    status: "live" as const,
  },
  {
    title: "API cost & tokens",
    body: "Per-provider dollars and token counts for OpenAI, Gemini, Console.",
    status: "soon" as const,
  },
];

// ── FAQ ──────────────────────────────────────────────────────────────────────
export const faqs = [
  {
    q: "Is the menu bar app really installable today?",
    a: "Yes. The one-liner installs the menu bar app right now — ad-hoc signed with a hardened runtime, so it opens with no Gatekeeper prompt. Only the notarized DMG is still coming. You're not waiting for anything to track Claude.",
  },
  {
    q: "Do my credentials ever leave my Mac?",
    a: "No. There is no Houdini account and no Houdini server. Houdini reads the credential already on your machine — your Claude Code OAuth token, or a claude.ai session you grant once — and calls the provider directly from your Mac. Tokens stay in your Keychain.",
  },
  {
    q: "Which providers work right now?",
    a: "Claude Pro and Max are live. OpenAI Platform, Google Gemini, and Anthropic Console are on the roadmap — shown as “Soon” here, never faked as working.",
  },
  {
    q: "How does it read my Claude usage?",
    a: "If you use Claude Code, Houdini reuses its OAuth token from the Keychain — zero new logins. Otherwise you sign in to claude.ai once in a native window and Houdini keeps the session in your Keychain. It then calls the same usage endpoint the official tools do.",
  },
  {
    q: "Does it really refresh every 60 seconds?",
    a: "The menu bar app does — a true 60-second timer, the headline number always current. The Übersicht desktop widget matches it. The upcoming Notification Center widget can't — Apple budgets widget refreshes to roughly every 15 minutes — so it'll say “updated a few minutes ago” rather than fake a live gauge.",
  },
  {
    q: "What does it cost?",
    a: "Nothing. Houdini is free and open-source. Read every line before you run it — the installer is pinned to a release tag and verifies checksums before touching your disk.",
  },
  {
    q: "macOS requirements?",
    a: "macOS 14 (Sonoma) or newer on Apple Silicon. No Intel build is shipped.",
  },
];
