import type { FullConfig } from '@playwright/test'

/** Waits for the whole stack (frontend → API) to report healthy before any test runs. */
export default async function globalSetup(config: FullConfig) {
  const baseURL = config.projects[0]?.use.baseURL
  if (!baseURL) throw new Error('baseURL is not configured')

  const healthUrl = new URL('/api/health', baseURL).toString()
  const deadline = Date.now() + 60_000
  let lastError = ''

  while (Date.now() < deadline) {
    try {
      const response = await fetch(healthUrl)
      if (response.ok) return
      lastError = `HTTP ${response.status}`
    } catch (error) {
      lastError = error instanceof Error ? error.message : String(error)
    }
    await new Promise((resolve) => setTimeout(resolve, 2_000))
  }

  throw new Error(`Stack not healthy at ${healthUrl} after 60s: ${lastError}`)
}
