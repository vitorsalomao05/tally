// houdini.jsx — Übersicht desktop widget for Claude usage (Houdini, Phase 3).
//
// Second surface after the menu bar app; TRUE 60s refresh. Reuses the data layer
// via `houdini-usage.sh` (which runs houdini, or curls the endpoint as a
// documented fallback). Visual is intentionally coherent with the menu bar
// popover: one row per metric (label, %, threshold-colored bar), relative reset,
// and the "$used / $limit" overage line.
//
// ─────────────────────────────────────────────────────────────────────────────
// The CSS in `className` (CARD_CSS) and the rendering logic (THRESHOLDS / fmt*)
// are duplicated verbatim in preview.html — KEEP THE TWO IN SYNC. Threshold
// colors are applied as inline styles (data-driven), so the CSS itself stays
// pure layout/typography and identical between the two files.
// ─────────────────────────────────────────────────────────────────────────────

export const refreshFrequency = 60000; // 60s — the real requirement (ADR-002).

// Runs in /bin/bash. Absolute path keyed to the install location so it works
// regardless of Übersicht's working directory. install.sh copies the script
// here; manual installs must keep this folder name (see README).
export const command =
  'bash "$HOME/Library/Application Support/Übersicht/widgets/houdini/houdini-usage.sh"';

// ── Shared visual + formatting (keep in sync with preview.html) ──────────────

// Apple system colors (dark-mode variants) — vivid over any wallpaper.
const GREEN = "#30d158";
const ORANGE = "#ff9f0a";
const RED = "#ff453a";
const TEXT = "#e5e5ea"; // neutral light (mirrors popover "primary")

// <60 green, 60–85 amber, >85 red — identical thresholds to Formatting.swift.
function barColor(pct) {
  if (pct == null) return "rgba(235,235,245,0.3)";
  if (pct < 60) return GREEN;
  if (pct < 85) return ORANGE;
  return RED;
}
// Value text stays neutral when low (don't shout), then amber/red as it tightens.
function valueColor(pct) {
  if (pct == null) return TEXT;
  if (pct < 60) return TEXT;
  if (pct < 85) return ORANGE;
  return RED;
}

function fmtPct(pct) {
  if (pct == null) return "—";
  return pct === Math.round(pct) ? `${Math.round(pct)}%` : `${pct.toFixed(1)}%`;
}
function fmtDollars(v) {
  if (v == null) return "—";
  return `$${v.toFixed(2)}`;
}

// "resets in 2h 14m" / "resets in 14m" / "resets in 5d 3h" — mirrors Format.resetString.
function fmtReset(iso) {
  if (!iso) return null;
  const total = Math.floor((new Date(iso).getTime() - Date.now()) / 1000);
  if (Number.isNaN(total)) return null;
  if (total <= 0) return "resets now";
  const hours = Math.floor(total / 3600);
  const minutes = Math.floor((total % 3600) / 60);
  if (hours >= 24) return `resets in ${Math.floor(hours / 24)}d ${hours % 24}h`;
  if (hours > 0) return `resets in ${hours}h ${minutes}m`;
  return `resets in ${minutes}m`;
}

// "updated just now" / "updated 3m ago" / "updated 2h ago".
function fmtUpdated(iso) {
  if (!iso) return "updated —";
  const secs = Math.floor((Date.now() - new Date(iso).getTime()) / 1000);
  if (Number.isNaN(secs) || secs < 0) return "updated just now";
  if (secs < 45) return "updated just now";
  const mins = Math.round(secs / 60);
  if (mins < 60) return `updated ${mins}m ago`;
  return `updated ${Math.round(mins / 60)}h ago`;
}

// The right-hand value: dollar overage shows "$used / $limit"; percent windows
// show the percentage.
function metricValue(m) {
  if (m.dollars != null) {
    return m.limit != null
      ? `${fmtDollars(m.used != null ? m.used : m.dollars)} / ${fmtDollars(m.limit)}`
      : fmtDollars(m.used != null ? m.used : m.dollars);
  }
  return fmtPct(m.pct);
}

// ── CSS (CARD_CSS) — duplicated verbatim in preview.html, KEEP IN SYNC ────────
const CARD_CSS = `
  box-sizing: border-box;
  width: 280px;
  padding: 14px 16px;
  font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", sans-serif;
  -webkit-font-smoothing: antialiased;
  color: ${TEXT};
  background: rgba(28, 28, 30, 0.72);
  -webkit-backdrop-filter: blur(20px) saturate(170%);
  backdrop-filter: blur(20px) saturate(170%);
  border: 1px solid rgba(255, 255, 255, 0.10);
  border-radius: 16px;
  box-shadow: 0 12px 40px rgba(0, 0, 0, 0.45);

  .head { display: flex; align-items: center; gap: 7px; }
  .brand { font-size: 14px; font-weight: 600; letter-spacing: 0.2px; }
  .gauge { display: block; }
  .spacer { flex: 1; }
  .dot { width: 8px; height: 8px; border-radius: 50%; }
  .divider { height: 1px; background: rgba(255, 255, 255, 0.10); margin: 11px 0; border: 0; }

  .metric { margin: 10px 0; }
  .metric:first-of-type { margin-top: 0; }
  .metric:last-of-type { margin-bottom: 0; }
  .metric-top { display: flex; align-items: baseline; justify-content: space-between; margin-bottom: 5px; }
  .label { font-size: 13px; font-weight: 500; }
  .value { font-size: 12px; font-weight: 600; font-variant-numeric: tabular-nums; }

  .bar { position: relative; height: 6px; border-radius: 3px; background: rgba(255, 255, 255, 0.14); overflow: hidden; }
  .bar-fill { position: absolute; left: 0; top: 0; bottom: 0; border-radius: 3px; }
  .reset { margin-top: 5px; font-size: 11px; color: rgba(235, 235, 245, 0.6); }

  .foot { margin-top: 11px; font-size: 11px; color: rgba(235, 235, 245, 0.6); }

  .error-title { display: flex; align-items: center; gap: 6px; font-size: 13px; font-weight: 600; color: ${ORANGE}; }
  .error-msg { margin-top: 6px; font-size: 12px; line-height: 1.35; color: rgba(235, 235, 245, 0.6); }
`;

export const className = `
  top: 24px;
  right: 24px;
  ${CARD_CSS}
`;

// ── Render ───────────────────────────────────────────────────────────────────

const Gauge = () => (
  <svg className="gauge" width="16" height="16" viewBox="0 0 16 16" aria-hidden="true">
    <path d="M2.6 12 A6 6 0 1 1 13.4 12" fill="none" stroke="#5e9eff" strokeWidth="1.6" strokeLinecap="round" />
    <line x1="8" y1="9" x2="11" y2="5.4" stroke="#5e9eff" strokeWidth="1.4" strokeLinecap="round" />
    <circle cx="8" cy="9" r="1.35" fill="#5e9eff" />
  </svg>
);

const ErrorCard = ({ message }) => (
  <div>
    <div className="head">
      <Gauge />
      <span className="brand">Houdini</span>
    </div>
    <hr className="divider" />
    <div className="error-title">
      <span>⚠</span>
      <span>Can't read usage</span>
    </div>
    <div className="error-msg">{message}</div>
  </div>
);

const Metric = ({ m }) => {
  const pct = m.pct;
  const width = Math.max(0, Math.min(100, pct == null ? 0 : pct));
  const reset = fmtReset(m.resetAt);
  return (
    <div className="metric">
      <div className="metric-top">
        <span className="label">{m.label}</span>
        <span className="value" style={{ color: valueColor(pct) }}>{metricValue(m)}</span>
      </div>
      <div className="bar">
        <div className="bar-fill" style={{ width: `${width}%`, background: barColor(pct) }} />
      </div>
      {reset ? <div className="reset">{reset}</div> : null}
    </div>
  );
};

export const render = ({ output }) => {
  let snap;
  try {
    snap = JSON.parse(output);
  } catch (e) {
    if (!output || !output.trim()) return <div className="head"><Gauge /><span className="brand">Houdini</span><span className="spacer" /><span className="reset">starting…</span></div>;
    return <ErrorCard message="Couldn't parse the usage data from houdini-usage.sh." />;
  }

  if (snap && snap.error) return <ErrorCard message={snap.error} />;

  const metrics = (snap && snap.metrics) || [];
  if (metrics.length === 0) {
    return <ErrorCard message="No usage metrics available for this account yet." />;
  }

  return (
    <div>
      <div className="head">
        <Gauge />
        <span className="brand">Houdini</span>
        <span className="spacer" />
        <span className="dot" style={{ background: GREEN }} />
      </div>
      <hr className="divider" />
      {metrics.map((m, i) => <Metric key={i} m={m} />)}
      <div className="foot">{fmtUpdated(snap.capturedAt)}</div>
    </div>
  );
};
