import { defineConfig, devices } from '@playwright/test'

// Inside docker compose the app is served by the `frontend` container; locally use `pnpm dev`.
const baseURL = process.env.BASE_URL ?? 'http://localhost:5173'
// PW_SMOKE=1: the post-deploy run, @smoke tests on Chromium only.
const smoke = !!process.env.PW_SMOKE

export default defineConfig({
  testDir: './tests',
  grep: smoke ? /@smoke/ : undefined,
  globalSetup: './global-setup.ts',
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  reporter: [['list'], ['html', { open: 'never', outputFolder: 'playwright-report' }]],
  outputDir: 'test-results',
  use: {
    baseURL,
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
  },
  projects: [
    { name: 'chromium', use: { ...devices['Desktop Chrome'] } },
    ...(smoke ? [] : [{ name: 'firefox', use: { ...devices['Desktop Firefox'] } }]),
  ],
})
