# Release checklist

The rule (ADR-010): **production carries exactly one advertised version.** Every
production release bumps, publishes the new one, and **prunes every obsolete
release, tag, and installer**. The site, `README`, and the install one-liner
reference only the current version. No "coming soon" placeholders ship to
production — a surface is real and shown, or absent.

Replace `X.Y.Z` with the new version (and `P.Q.R` with the previous one).

---

## ▶ v0.3.0 go-live (Round B — PREPARED, NOT YET PUBLISHED)

Round B is staged on `master`: the **native desktop widget** (replaces Übersicht),
the **redesigned logo** (free web mark + new `.icns`), honest **providers copy**,
and the app bumped to **0.3.0** (`apps/menubar/Info.plist` → `CFBundleShortVersionString 0.3.0`,
build `4`). The published install one-liner is deliberately **still pointing at the
last shipped release** so nothing breaks before go-live:

- `site/src/config.ts` → `version = "0.3.0"` (display) but `installTag = "v0.2.0"`
  (the one-liner downloads the working v0.2.0 release).
- `install.sh` → `TAG="v0.2.0"` (unchanged).
- `README.md` install one-liner → `v0.2.0` (unchanged).

A **preview** Vercel deploy shows the new look; **production
(houdini.salomao.org) is untouched** (no `vercel --prod` was run).

To go live (do these in order, only when the visual is approved):

1. [ ] `site/src/config.ts` → set `installTag = "v0.3.0"` (or delete `installTag`
       and point `installOneLiner` back at `v${version}`).
2. [ ] `install.sh` → `TAG="v0.3.0"`.
3. [ ] `README.md` → install one-liner + release link → `v0.3.0`.
4. [ ] Commit: `chore(release): cut v0.3.0`.
5. [ ] Build artifacts + tag + publish (steps 3–4 below): `git tag v0.3.0 && git push origin v0.3.0`,
       then `gh release create v0.3.0 …` with `Houdini.app.zip`, `houdini`, `SHASUMS256.txt`.
6. [ ] **Delete the old release + tag:** `gh release delete v0.2.0 --yes --cleanup-tag`.
7. [ ] `cd site && vercel --prod` (production). Smoke-test home / `/install` / `/guide`.

(Do **not** do any of the above as part of Round B — they are the go-live step.)

---

## 1 · Pre-flight
- [ ] `master` is green and clean (`git status` empty, CI passing).
- [ ] Decide the bump (semver): patch / minor / major. Note it in the release notes.
- [ ] No "coming soon" / "Soon" / "next milestone" copy anywhere user-facing
      (`grep -rIni 'coming soon\|>soon<\|next milestone' site/src README.md`).

## 2 · Bump the version (single source of truth)
- [ ] `site/src/config.ts` → `export const version = "X.Y.Z"` (drives the install
      one-liner and every release link automatically).
- [ ] `README.md` install one-liner + release link → `vX.Y.Z`.
- [ ] Any other pinned reference to the old tag (`grep -rIn "vP.Q.R" . | grep -v node_modules`).
- [ ] Commit: `chore(release): bump to vX.Y.Z`.

## 3 · Build + verify artifacts
- [ ] Build the app + CLI; produce the installer artifacts and `SHASUMS256.txt`.
- [ ] `cd site && npm run build` passes.
- [ ] Sanity-run the one-liner against the **new** tag on a clean path.

## 4 · Publish the new release
- [ ] Tag and push: `git tag vX.Y.Z && git push origin vX.Y.Z`.
- [ ] `gh release create vX.Y.Z <artifacts> --title "Houdini vX.Y.Z" --notes "…"`.
- [ ] Confirm `install.sh` on the new tag fetches the new artifacts and checksums match.

## 5 · Prune obsolete releases + tags (the hygiene step)
- [ ] List what exists: `gh release list` and `git tag -l`.
- [ ] For every superseded version `P.Q.R`:
      `gh release delete vP.Q.R --yes --cleanup-tag` (deletes release **and** remote tag).
- [ ] Delete leftover local tags: `git tag -d vP.Q.R`.
- [ ] Re-check: `gh release list` shows **only** `vX.Y.Z`; `git tag -l` has no stale tags.

## 6 · Ship the site (production)
- [ ] Confirm the site references only `vX.Y.Z` (no old links, no "coming soon").
- [ ] If a feature shipped, the relevant section is **adapted** (re-framed), not a
      loose new block bolted on (ADR-010).
- [ ] Deploy production from `site/`: `vercel --prod`. (Preview deploys — `vercel deploy`
      with no `--prod` — are safe for review and do **not** touch production.)
- [ ] Smoke-test production: home, `/install`, `/guide` all 200; one-liner copies the
      `vX.Y.Z` command.

## 7 · Post-release
- [ ] Update `ROADMAP.md` / `DECISIONS.md` if the release changed direction.
- [ ] Announce only after production is verified.

---

**Never:** leave two advertised versions live · point the site at a deleted tag ·
publish a "Soon" placeholder · `vercel --prod` from an unreviewed build ·
put any provider API/admin key in the site, frontend, env bundle, or repo
(ADR-011 — keys live only in the user's Keychain).
