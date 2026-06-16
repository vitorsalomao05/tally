// Central configuration — every external URL the site links to lives here so
// Phase 6 (signed distribution) can plug in real artifacts without touching a
// single component. Search this file for "TODO(phase 6)".

export const site = {
  name: "Tally",
  // The product is focused on Claude today; copy stays honest about that.
  description:
    "A native macOS menu bar app that shows your Claude Pro/Max usage at a glance — refreshed every 60 seconds. Runs locally, credentials stay in your Keychain.",
  // TODO(phase 6): real production domain (canonical + Open Graph URLs).
  domain: "https://tally.app",
  // TODO(phase 6): generate and host a real social/OG image (1200×630).
  ogImage: "/og.png",
};

export const links = {
  // TODO(phase 6): replace OWNER with the real GitHub org/user once public.
  github: "https://github.com/OWNER/claude-credits-widget",
  // TODO(phase 6): signed + notarized DMG (Apple Silicon) on GitHub Releases.
  //   null → the UI renders the honest "Signed DMG — coming soon" state.
  downloadDmg: null as string | null,
  // TODO(phase 6): releases / changelog page.
  changelog: "https://github.com/OWNER/claude-credits-widget/releases",
};

// The install path that WORKS TODAY for the Übersicht desktop widget: clone the
// repo and run its idempotent installer (builds tally-cli + deploys the widget).
export const installUbersicht = [
  // TODO(phase 6): real clone URL.
  "git clone https://github.com/OWNER/claude-credits-widget",
  "cd claude-credits-widget/apps/ubersicht",
  "./install.sh",
].join("\n");

// Build-from-source path for the menu bar app — works today once the repo is
// cloned (an honest, copyable recipe rather than a deep link to a private blob).
export const installMenubar = [
  // TODO(phase 6): real clone URL.
  "git clone https://github.com/OWNER/claude-credits-widget",
  "cd claude-credits-widget/apps/menubar",
  "./build.sh",
].join("\n");

export const nav = [
  { label: "How it works", href: "#how" },
  { label: "Surfaces", href: "#surfaces" },
  { label: "Install", href: "#install" },
  { label: "Privacy", href: "#privacy" },
  { label: "FAQ", href: "#faq" },
];
