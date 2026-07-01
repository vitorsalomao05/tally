# BACKLOG.md — Houdini

> Prioritized work for the Houdini monorepo. Pairs with [`CONTEXT.md`](CONTEXT.md) (why)
> and [`CLAUDE.md`](CLAUDE.md) (how we work). Framed 2026-06-30.
>
> **Legend:** `P1` now · `P2` next · `P3` later/ongoing · `[ ]` open · `[~]` in progress
> · `[x]` done. Priorities are **app-first**: login → polish → site + ongoing.

---

## P1 · App — Login / credential refactor  `[~]`

**Problem.** The Claude provider connects cleanly for **Claude Code CLI users** (OAuth
token in Keychain) but is **buggy/unclean for non-CLI users**, who have no smooth way to
connect their account.

**Goal.** A simple, reliable, secure login that works for **any** Claude Code user,
regardless of how they authenticate — without weakening the Keychain-only, no-server
security posture.

**Acceptance.**
- A non-CLI Claude user can connect in an obvious, documented way and see live data.
- Existing CLI-token users are unaffected (no regression).
- No credential ever leaves the device, hits disk, or lands in logs.
- The flow is least-privilege and passes a security review.

**Discovery-first sub-tasks.**
- [x] Map every credential source the app reads today — **done (FRAME survey).** Two sources:
      (1) OAuth token from Keychain `service="Claude Code-credentials"` (read via the `security`
      CLI in `CredentialStore.cliReadGenericPassword`) → `api.anthropic.com/api/oauth/usage`;
      (2) claude.ai `sessionKey` cookie in Houdini's own Keychain item `Houdini-claude-session`,
      captured by the WebView login → `claude.ai/api/organizations/{org}/usage`. Resolver picks
      OAuth → cookie → none (`ClaudeAuth.swift:63-79`). The CLI (`houdini`) uses OAuth only, no
      cookie fallback.
- [x] Reproduce and pinpoint the **exact** non-CLI failure — **done (FRAME survey).**
      - **Root cause A (dominant):** OAuth discovery is hardcoded to the single Keychain item
        `"Claude Code-credentials"` (`ClaudeOAuthProvider.swift:45`, consumed at `ClaudeAuth.swift:37`
        & `ClaudeOAuthProvider.swift:105`) — no alternate item names (the code even *notes* a classic
        `"Claude Code"` item but never queries it), no `~/.claude/.credentials.json` file fallback,
        no `refreshToken` use. Non-CLI users lack that exact item ⇒ OAuth is impossible by
        construction ⇒ they're forced onto the cookie path.
      - **Root cause B:** the cookie WebView uses an **ephemeral** store
        (`ClaudeLoginWindow.swift:40`) so it can't reuse the user's existing claude.ai browser
        session; the captured cookie is short-lived and **non-refreshable** → re-login loop on expiry.
      - **Root cause C:** even real CLI users silently lose OAuth when the access token expires
        (`expiresAt` past → unusable; `refreshToken` never used).
- [~] Design the unified login — **(a) IMPLEMENTED this pass; (c) remains the durable follow-on:**
      - **(a) Broaden OAuth/token discovery** — ordered item list (`"Claude Code-credentials"` +
        `"Claude Code"`), `~/.claude/.credentials.json` read fallback, use `refreshToken` to refresh
        a stale access token. *No ADR change; low risk; fixes A+C but not true non-CLI users.*
        **✅ IMPLEMENTED (P1 slice a)** behind one shared `ClaudeOAuthCredentialSource` seam
        (ordered Keychain discovery + read-only file fallback + in-memory `refreshToken` refresh).
        The refresh mechanism is built + tested via an injected refresher; the live refresh
        **endpoint is NOT wired** pending sign-off (see the "Newly surfaced" note below), so an
        expired token still degrades exactly as today until then.
      - **(b) Harden the claude.ai cookie flow** — persistent/shared WebView store or paste-session,
        proactive expiry re-auth. *Weaker (needs ADR-005 revision); interim bridge only.*
      - **(c) First-run OAuth PKCE "Connect"** — Houdini gets its own refreshable, revocable,
        Keychain-only Anthropic token, independent of the CLI. *Durable; higher effort; depends on a
        usable public OAuth client.*
      - **Recommendation:** ship **(a)** now (cheapest correctness win, no ADR touch) — **done**;
        pursue **(c) first-run OAuth PKCE** as the durable answer for true non-CLI Pro/Max users;
        use **(b) cookie-flow hardening** only if **(c)** is blocked.
- [~] Implement behind a clean, testable seam in `core/` (the `CredentialStore` /
      `ClaudeAuthResolver` boundary already isolates this well). **slice (a): ordered Keychain
      discovery + `~/.claude/.credentials.json` fallback + in-memory `refreshToken` refresh**,
      all in one `ClaudeOAuthCredentialSource` unit (collapsed the two old private blob structs
      + two read call-sites). Live refresh endpoint deferred to sign-off; cookie hardening (b)
      and OAuth PKCE (c) remain separate.
- [~] Test both user types end to end; add regression tests (extend `FetcherCoreTests`).
      **slice (a): added `ClaudeAuthResolverTests` (ordered discovery, first-item-wins, file
      fallback, refresh, absent) + a `houdini-selftest` mirror (29 checks PASS here).** Still
      open: end-to-end coverage for the non-CLI **cookie** user (part of (b)/(c)).
- [ ] Security review + update `PROVIDERS.md` / relevant ADR. *(Not done this pass; needed
      before the live refresh endpoint is wired — proposed refresh contract is in the report.)*

## P2 · App — Widget accessibility + visual polish  `[ ]`

**Goal.** The menu bar and desktop widget are accessible and visually polished end to end.

**Acceptance.**
- Keyboard + VoiceOver usable; clear, legible gauges and reset timers.
- Consistent visual language across menu bar popover and desktop panel.
- No rough edges (alignment, spacing, states, empty/error/loading).

**Sub-tasks.**
- [ ] Accessibility pass (labels, focus, Dynamic Type, contrast, reduced-motion).
- [ ] Visual polish pass on both surfaces; define shared visual tokens.
- [ ] Verify against real Claude Pro/Max data (limits, timers, overage).

## P3 · Site — Polish to zero-clutter + ongoing features  `[ ]`

**Goal.** A 100% clean site (zero visual clutter/pollution), strongly accessible, with one
clear install CTA — then a continuous stream of features and ideas.

**Blocked by:** the live visual + accessibility audit (pending Chrome-extension connection).

**Sub-tasks.**
- [ ] Run the Claude-in-Chrome visual + a11y audit; fold findings in here as P1/P2/P3.
- [ ] Tighten hero so the lead pitch + install CTA are unmistakable above the fold.
- [ ] Ensure a real product screenshot/demo is present and high quality.
- [ ] Make the trust/privacy section clearly communicate the Keychain-only, no-server story.
- [ ] Bring the site to WCAG 2.1 AA; remove any clutter that doesn't earn its place.
- [ ] Then: ongoing feature/idea stream (tracked in the Parking lot below).

---

## Cross-cutting

- [ ] **Security & trust:** keep the trust/privacy messaging accurate; review any future
      elevated permission (e.g. browser-scrape fallback) before it ships.
- [ ] **Accessibility baseline:** WCAG 2.1 AA across site and app UI; no regressions.
- [ ] **Installer integrity:** preserve SHA-256 verification, no-`sudo`, no-Gatekeeper,
      no forced launch-at-login as `install.sh` evolves.

## Discovery / open questions — resolved by the FRAME survey (2026-07-01)

- [~] Cleanest unified-login design — **candidates + recommendation captured in P1 above**
      (decision still needed before building).
- [x] Site deploy target + CI — **Vercel**, project `houdini`, manual prebuilt CLI (`vercel --prod`
      from `site/`); **no site CI** in `.github/workflows/`. `ROADMAP.md` Phase 7 ("Cloudflare Pages")
      is stale and should be corrected.
- [x] Test coverage/setup — `core/` has swift-testing (`FetcherCoreTests`) + a `houdini-selftest`
      runnable mirror; **no tests** in `apps/*` or `site/`.
- [x] Init script / `feature_list.json` — neither existed; **both created this pass**
      (`scripts/init.sh`, `feature_list.json`).

### Newly surfaced (flag for the user)

- [ ] **ADR-006 vs reality:** production ships ad-hoc-signed via `install.sh`/`curl|bash`, which
      ADR-006 demotes to a "developer-tester stopgap." Revise ADR-006 (or add an ADR) openly.
- [ ] **ROADMAP.md refresh:** Phase 7 "Cloudflare Pages" → Vercel; drop the ADR-010/011-forbidden
      "providers grid"; update stale ✅ markers / "← WE ARE HERE" now that v0.4.0 is live.
- [ ] **Gemini gap:** advertised in `README.md`/`CONTEXT.md` but absent from `PROVIDERS.md`/
      `ROADMAP.md` — spec it or drop the claim.
- [ ] **README/CLAUDE repo-layout:** `apps/ios/` was missing from the layout maps (added to
      `CLAUDE.md`; README updated). `apps/widget/` is a README-only placeholder, not a built target.

## Immediate next steps

1. [ ] Get **scope sign-off** on this doc set + these flags → then pull **P1 (login refactor)**
       into the build loop, starting from the confirmed root cause above.
2. [ ] Connect the **Claude in Chrome** extension → resume the queued site audit (feeds P3).

## Parking lot / ideas (ongoing)

- _(Add feature ideas here as they come up — the site is an evolving surface.)_
