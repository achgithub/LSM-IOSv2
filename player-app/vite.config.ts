import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import { VitePWA } from 'vite-plugin-pwa';

// The web manifest is NOT generated here. Each player link is served under
// /s/<token> and needs a manifest naming the manager ("LSM Andy") so the
// saved home-screen icon is distinguishable across managers — that's handled
// per-request by functions/s/[token]/manifest.webmanifest.js. This plugin
// only owns the service worker (precache + push), not the manifest.
export default defineConfig({
  server: {
    // worker-api's CORS only allows the production origin
    // (https://submit.sportsmanager.site) — proxying here makes the browser
    // see a same-origin request during `npm run dev`, sidestepping CORS
    // entirely rather than touching the shared backend allowlist.
    proxy: {
      '/api': {
        target: 'https://api.uk.sportsmanager.site',
        changeOrigin: true,
        rewrite: (path) => path.replace(/^\/api/, ''),
      },
    },
  },
  plugins: [
    react(),
    VitePWA({
      manifest: false,
      strategies: 'injectManifest',
      srcDir: 'src',
      filename: 'sw.ts',
      registerType: 'autoUpdate',
      injectManifest: {
        // Deliberately excludes background.png/logo.png (~1.8MB combined) —
        // they're decorative, not needed for the app shell to function
        // offline, and would otherwise get precached on every SW install.
        globPatterns: ['**/*.{js,css,html,svg}'],
      },
    }),
  ],
});
