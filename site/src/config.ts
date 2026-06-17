// Central configuration — every external URL the site links to lives here so
// distribution can plug in real artifacts without touching a single component.
// Search this file for "TODO(phase 6)" for the links a future milestone fills in.

export const site = {
  name: "Tally",
  // The product is focused on Claude today; copy stays honest about that.
  description:
    "A native macOS menu bar app that shows your Claude Pro/Max usage at a glance — refreshed every 60 seconds. Runs locally, credentials stay in your Keychain.",
  // Canonical origin (canonical + Open Graph): the Tally subdomain on Vercel.
  domain: "https://tally.salomao.org",
  // Real 1200×630 social card in public/og.png (see scripts/og/).
  // Path is relative to the site base — Layout.astro resolves it to an absolute URL.
  ogImage: "og.png",
};

export const links = {
  github: "https://github.com/vitorsalomao05/tally",
  // TODO(future): signed + notarized DMG (Apple Silicon) on GitHub Releases.
  //   null → the UI renders the honest "Signed DMG — coming soon" state.
  downloadDmg: null as string | null,
  // Releases / changelog page.
  changelog: "https://github.com/vitorsalomao05/tally/releases",
  // Public "follow development" thread for the in-progress iPhone app. No fake
  // App Store button — this links to the real tracking issue (ADR-008).
  iosTracking: "https://github.com/vitorsalomao05/tally/issues/1",
};

// The fastest path that WORKS TODAY for the menu bar app: a one-liner that
// downloads the ad-hoc-signed Tally.app + tally-cli from the pinned v0.1.1
// Release, verifies their SHA-256 against SHASUMS256.txt, then installs them
// (no sudo). Pinned to the tag, so the bytes you run are the bytes we shipped.
export const installOneLiner =
  "curl -fsSL https://raw.githubusercontent.com/vitorsalomao05/tally/v0.1.1/install.sh | bash";

// The install path that WORKS TODAY for the Übersicht desktop widget: clone the
// repo and run its idempotent installer (builds tally-cli + deploys the widget).
export const installUbersicht = [
  "git clone https://github.com/vitorsalomao05/tally",
  "cd tally/apps/ubersicht",
  "./install.sh",
].join("\n");

// Build-from-source path for the menu bar app — works today once the repo is
// cloned (an honest, copyable recipe rather than a deep link to a private blob).
export const installMenubar = [
  "git clone https://github.com/vitorsalomao05/tally",
  "cd tally/apps/menubar",
  "./build.sh",
].join("\n");

export const nav = [
  { label: "How it works", href: "#how" },
  { label: "Surfaces", href: "#surfaces" },
  { label: "Install", href: "#install" },
  { label: "Privacy", href: "#privacy" },
  { label: "FAQ", href: "#faq" },
];
