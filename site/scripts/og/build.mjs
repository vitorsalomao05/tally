// Generates the real 1200×630 Open Graph card → site/public/og.png.
//
// Single reproducible command:  node scripts/og/build.mjs
//
// It inlines the brand font (Inter) and the dark product popover as data URIs
// into an HTML template, then renders it with headless Chrome at an exact
// 1200×630 viewport (device-scale-factor 1, so the PNG is pixel-exact).
//
// Chrome path is auto-detected; override with CHROME_BIN=/path/to/chrome.

import { readFileSync, writeFileSync, mkdtempSync, existsSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { tmpdir } from "node:os";
import { join, dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const siteRoot = resolve(here, "..", "..");

const WIDTH = 1200;
const HEIGHT = 630;

// ── Inlined assets ─────────────────────────────────────────────────────────
const fontPath = join(
  siteRoot,
  "node_modules/@fontsource-variable/inter/files/inter-latin-wght-normal.woff2",
);
const popoverPath = join(siteRoot, "src/assets/popover-dark.png");

const fontB64 = readFileSync(fontPath).toString("base64");
const popoverB64 = readFileSync(popoverPath).toString("base64");

// The signature gauge mark, lifted from src/components/Logo.astro.
const gauge = `
<svg width="52" height="52" viewBox="0 0 32 32" fill="none" aria-hidden="true">
  <defs>
    <linearGradient id="g" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#3B82F6"/><stop offset="1" stop-color="#7C5CFF"/>
    </linearGradient>
  </defs>
  <rect x="1" y="1" width="30" height="30" rx="8" fill="#14161B" stroke="#232733"/>
  <rect x="8" y="10" width="16" height="3" rx="1.5" fill="#232733"/>
  <rect x="8" y="10" width="11" height="3" rx="1.5" fill="url(#g)"/>
  <rect x="8" y="16" width="16" height="3" rx="1.5" fill="#232733"/>
  <rect x="8" y="16" width="6"  height="3" rx="1.5" fill="#34D399"/>
  <rect x="8" y="22" width="16" height="3" rx="1.5" fill="#232733"/>
  <rect x="8" y="22" width="14" height="3" rx="1.5" fill="#F5A623"/>
</svg>`;

const html = `<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<style>
  @font-face {
    font-family: "Inter";
    font-weight: 100 900;
    font-display: block;
    src: url(data:font/woff2;base64,${fontB64}) format("woff2");
  }
  * { margin: 0; padding: 0; box-sizing: border-box; }
  html, body {
    width: ${WIDTH}px; height: ${HEIGHT}px; overflow: hidden;
    background: #0a0b0e; color: #e7e9ee;
    font-family: "Inter", -apple-system, BlinkMacSystemFont, sans-serif;
    -webkit-font-smoothing: antialiased; text-rendering: geometricPrecision;
  }
  /* The hero's electric glow, anchored behind the headline. */
  .glow {
    position: absolute; inset: 0; pointer-events: none;
    background:
      radial-gradient(620px 460px at 14% 22%,
        color-mix(in oklab, #3b82f6 30%, transparent), transparent 70%),
      radial-gradient(540px 420px at 36% 4%,
        color-mix(in oklab, #7c5cff 20%, transparent), transparent 72%);
  }
  /* Faint grid texture so the dark field is not dead flat. */
  .grid {
    position: absolute; inset: 0; pointer-events: none; opacity: .5;
    background-image:
      linear-gradient(#ffffff0a 1px, transparent 1px),
      linear-gradient(90deg, #ffffff0a 1px, transparent 1px);
    background-size: 48px 48px;
    -webkit-mask-image: radial-gradient(900px 560px at 30% 40%, #000 30%, transparent 80%);
            mask-image: radial-gradient(900px 560px at 30% 40%, #000 30%, transparent 80%);
  }
  .wrap { position: relative; height: 100%; display: flex; align-items: stretch; }
  .left {
    position: relative; z-index: 2;
    width: 660px; padding: 70px 0 70px 76px;
    display: flex; flex-direction: column; justify-content: space-between;
  }
  .brand { display: flex; align-items: center; gap: 16px; }
  .brand .name { font-size: 30px; font-weight: 600; letter-spacing: -0.02em; color: #fff; }
  .brand .tag {
    margin-left: 6px; font-size: 14px; font-weight: 500; letter-spacing: .04em;
    text-transform: uppercase; color: #9aa3b2;
    padding: 6px 11px; border: 1px solid #232733; border-radius: 999px;
    background: #14161b;
  }
  h1 {
    font-size: 62px; line-height: 1.04; font-weight: 700; letter-spacing: -0.025em;
    color: #fff; max-width: 560px;
  }
  h1 .accent {
    background: linear-gradient(100deg, #5b9cff, #7c5cff);
    -webkit-background-clip: text; background-clip: text; color: transparent;
  }
  .sub {
    margin-top: 22px; font-size: 22px; line-height: 1.5; color: #9aa3b2;
    max-width: 530px; font-weight: 400;
  }
  .foot { display: flex; align-items: center; gap: 14px; }
  .chip {
    display: inline-flex; align-items: center; gap: 10px;
    padding: 10px 16px; border: 1px solid #232733; border-radius: 12px;
    background: #14161b; font-size: 19px; color: #e7e9ee;
    font-family: ui-monospace, "SF Mono", Menlo, monospace; letter-spacing: -0.01em;
  }
  .dot { width: 9px; height: 9px; border-radius: 999px; background: #34d399;
         box-shadow: 0 0 10px #34d399; }
  /* Product glimpse: the dark popover, bleeding off the right edge. */
  .right { position: relative; z-index: 1; flex: 1; }
  .card {
    position: absolute; top: 50%; right: -56px; transform: translateY(-50%) rotate(-1deg);
    width: 470px; border-radius: 22px; padding: 0; overflow: hidden;
    background:
      linear-gradient(#14161b, #14161b) padding-box,
      linear-gradient(135deg,
        color-mix(in oklab, #3b82f6 70%, transparent),
        color-mix(in oklab, #7c5cff 60%, transparent)) border-box;
    border: 1.5px solid transparent;
    box-shadow: 0 40px 90px -20px #000c, 0 0 80px -30px #3b82f6aa;
  }
  .card img { display: block; width: 100%; height: auto; }
</style></head>
<body>
  <div class="glow"></div>
  <div class="grid"></div>
  <div class="wrap">
    <div class="left">
      <div class="brand">
        ${gauge}
        <span class="name">Tally</span>
        <span class="tag">macOS menu bar</span>
      </div>
      <div>
        <h1>Know your <span class="accent">Claude usage</span> before you hit the limit</h1>
        <p class="sub">A native menu bar app that shows your Claude Pro/Max usage at a glance — refreshed every 60 seconds. Credentials stay in your Keychain.</p>
      </div>
      <div class="foot">
        <span class="chip"><span class="dot"></span>tally.salomao.org</span>
      </div>
    </div>
    <div class="right">
      <div class="card">
        <img src="data:image/png;base64,${popoverB64}" alt="">
      </div>
    </div>
  </div>
</body></html>`;

// ── Render with headless Chrome ─────────────────────────────────────────────
const tmp = mkdtempSync(join(tmpdir(), "tally-og-"));
const htmlFile = join(tmp, "og.html");
writeFileSync(htmlFile, html);

const out = join(siteRoot, "public", "og.png");

const candidates = [
  process.env.CHROME_BIN,
  "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
  "/Applications/Chromium.app/Contents/MacOS/Chromium",
  "/Applications/Google Chrome Canary.app/Contents/MacOS/Google Chrome Canary",
].filter(Boolean);
const chrome = candidates.find((p) => existsSync(p));
if (!chrome) {
  console.error("No Chrome/Chromium found. Set CHROME_BIN=/path/to/chrome.");
  process.exit(1);
}

execFileSync(
  chrome,
  [
    "--headless=new",
    "--disable-gpu",
    "--hide-scrollbars",
    "--force-device-scale-factor=1",
    `--window-size=${WIDTH},${HEIGHT}`,
    "--virtual-time-budget=2000",
    `--screenshot=${out}`,
    `file://${htmlFile}`,
  ],
  { stdio: "inherit" },
);

console.log(`Wrote ${out} (${WIDTH}×${HEIGHT}) using ${chrome}`);
