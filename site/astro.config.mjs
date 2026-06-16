// @ts-check
import { defineConfig } from "astro/config";
import tailwindcss from "@tailwindcss/vite";

// Static build → dist/, published to GitHub Project Pages.
// A project site lives under a sub-path, so `base` must be set and every internal
// link/asset has to respect it (use import.meta.env.BASE_URL — never a bare "/...").
export default defineConfig({
  site: "https://vitorsalomao05.github.io",
  base: "/tally",
  // Keep the canonical/OG URL coherent with how Pages serves the directory ("/tally/").
  trailingSlash: "always",
  vite: {
    plugins: [tailwindcss()],
  },
});
