import { expect, test } from '@playwright/test'

test.describe('chat', () => {
  test('sends a message and receives a reply', async ({ page }) => {
    await page.goto('/')
    const log = page.getByRole('log', { name: 'Messages' })
    const message = `E2E hello ${Date.now()}`

    await page.getByRole('textbox', { name: 'Message' }).fill(message)
    await page.getByRole('button', { name: 'Send' }).click()

    await expect(log.getByText(`You: ${message}`, { exact: true })).toBeVisible()
    // Provider-agnostic: works with the real Gemini model or the echo fallback.
    await expect(log.locator('.chat__message--assistant:not(.chat__message--pending)')).toHaveCount(1, {
      timeout: 60_000,
    })
    await expect(page.getByRole('alert')).toHaveCount(0)
  })

  test('restores the conversation after reload and can start a new chat', async ({ page }) => {
    await page.goto('/')
    const log = page.getByRole('log', { name: 'Messages' })
    const message = `E2E persist ${Date.now()}`

    await page.getByRole('textbox', { name: 'Message' }).fill(message)
    await page.keyboard.press('Enter')
    await expect(log.locator('.chat__message--assistant:not(.chat__message--pending)')).toHaveCount(1, {
      timeout: 60_000,
    })

    await page.reload()
    await expect(log.getByText(`You: ${message}`, { exact: true })).toBeVisible()

    await page.getByRole('button', { name: 'New chat' }).click()
    await expect(log.getByText(`You: ${message}`, { exact: true })).toHaveCount(0)
    await expect(log.getByText('Ask anything to start a conversation.')).toBeVisible()
  })
})
