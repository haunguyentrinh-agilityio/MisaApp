import { expect, test } from '@playwright/test'

test('API health endpoint is reachable through the frontend proxy', async ({ request }) => {
  const response = await request.get('/api/health')
  expect(response.ok()).toBeTruthy()
  expect(await response.text()).toBe('Healthy')
})
