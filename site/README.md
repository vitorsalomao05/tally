# Houdini — landing site

Static landing page for Houdini. **Astro + Tailwind CSS v4**, dark Linear-style with
an electric-blue accent. Builds to `dist/`, deployed to **Vercel** at
**[houdini.salomao.org](https://houdini.salomao.org)**.

## Develop

```sh
cd site
npm install
npm run dev      # local dev server (http://localhost:4321)
npm run build    # static build → dist/
npm run preview  # serve the built dist/ locally
```

## Structure

- `src/pages/index.astro` — composes the single page.
- `src/components/*.astro` — one component per section (Hero, Surfaces, Install, …).
- `src/styles/global.css` — design tokens (`@theme`) + base + motion utilities.
- `src/config.ts` — **all external URLs in one place.** Search `TODO(phase 6)` for the
  links distribution must fill in (GitHub repo, signed DMG, changelog, OG image, domain).
- `src/assets/` — real product screenshots (optimized to webp at build).
- `docs/screenshots/` — rendered home page captures (desktop 1440 + mobile 390).

## Notes

- Accessible by design: WCAG AA contrast, visible keyboard focus, `prefers-reduced-motion`
  respected, on-scroll reveals gated behind `html.js` so the page is fully visible without JS.
- Honest copy: no fabricated social proof; "coming soon" states for the signed DMG, Apple
  notarization, the Notification Center widget, and non-Claude providers.
- Deploy: **Vercel** — root directory `site`, framework Astro, build `npm run build`,
  output `dist`. Live at https://houdini.salomao.org. Production deploys with
  `vercel --prod` from `site/`.
- OG card: `node scripts/og/build.mjs` regenerates `public/og.png` (1200×630, rendered
  with headless Chrome from an inlined HTML template).
