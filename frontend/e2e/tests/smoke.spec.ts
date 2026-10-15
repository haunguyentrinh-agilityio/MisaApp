import { expect, test } from '@playwright/test'

// Post-deploy smoke tests (PW_SMOKE=1). They never send a chat message, so they don't spend
// Gemini quota or write to the database. In the full suite EXPECTED_* are unset.
const expectedCommit = process.env.EXPECTED_COMMIT
const expectedEnvironment = process.env.EXPECTED_ENVIRONMENT

test.describe('smoke', { tag: '@smoke' }, () => {
  test('page loads with the chat box', async ({ page }) => {
    await page.goto('/')
    await expect(page.getByRole('heading', { name: 'MisaApp' })).toBeVisible()
    await expect(page.getByRole('region', { name: 'Chat' })).toBeVisible()
  })

  test('API reports healthy', async ({ request }) => {
    const response = await request.get('/api/health')
    expect(response.status()).toBe(200)
    expect(await response.text()).toBe('Healthy')
  })

  test('API reports the deployed version', async ({ request }) => {
    const response = await request.get('/api/version')
    expect(response.status()).toBe(200)
    const body = (await response.json()) as { commit: string; environment: string }
    expect(body.commit).not.toBe('')
    expect(body.environment).not.toBe('')
    if (expectedCommit) expect(body.commit).toBe(expectedCommit)
    if (expectedEnvironment) expect(body.environment).toBe(expectedEnvironment)
  })
})
