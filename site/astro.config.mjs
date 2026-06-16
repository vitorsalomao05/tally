// @ts-check
import { defineConfig } from "astro/config";
import tailwindcss from "@tailwindcss/vite";

// Static build → dist/, ready for Cloudflare Pages.
export default defineConfig({
  // TODO(phase 6): set the real production domain (used for canonical + OG URLs).
  site: "https://tally.app",
  vite: {
    plugins: [tailwindcss()],
  },
});
