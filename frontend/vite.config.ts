/// <reference types="vitest/config" />
import react from '@vitejs/plugin-react'
import { defineConfig } from 'vite'

// In Docker the API is reachable as http://backend:8080; locally it's the `dotnet run` port.
const apiTarget = process.env.API_PROXY_TARGET ?? 'http://localhost:5056'

// https://vite.dev/config/
export default defineConfig({
  plugins: [react()],
  server: {
    host: true,
    port: 5173,
    // `frontend` is the compose service name Playwright uses to reach the dev server.
    allowedHosts: ['frontend'],
    proxy: {
      '/api': { target: apiTarget, changeOrigin: true },
    },
    // Bind-mounted Windows folders don't emit inotify events inside Linux containers.
    watch: process.env.VITE_USE_POLLING === 'true' ? { usePolling: true, interval: 300 } : undefined,
  },
  test: {
    environment: 'jsdom',
    setupFiles: ['./src/test/setup.ts'],
    include: ['src/**/*.test.{ts,tsx}'],
    css: true,
  },
})
