// @ts-check
import { defineConfig } from "astro/config";
import tailwindcss from "@tailwindcss/vite";

// Static build → dist/, deployed to Vercel at the apex of its own subdomain.
// The site lives at the domain root, so `base` is "/" (Astro's default) and every
// internal link/asset resolves straight off the root via import.meta.env.BASE_URL.
export default defineConfig({
  site: "https://houdini.salomao.org",
  vite: {
    plugins: [tailwindcss()],
  },
});
