import { expect, test, type Page } from '@playwright/test'

// Assertions are on structure only: the reply may come from Gemini or the echo fallback.
const REPLY_TIMEOUT = 60_000

function assistantReplies(page: Page) {
  return page.getByRole('log', { name: 'Messages' }).locator('.chat__message--assistant:not(.chat__message--pending)')
}

async function send(page: Page, message: string) {
  const request = page.waitForRequest((r) => r.url().endsWith('/api/chat/messages') && r.method() === 'POST')
  await page.getByRole('textbox', { name: 'Message' }).fill(message)
  await page.getByRole('button', { name: 'Send' }).click()
  return (await request).postDataJSON() as { message: string; history: { role: string; content: string }[] }
}

test.describe('chat', () => {
  test('sends a message and receives a reply', async ({ page }) => {
    await page.goto('/')
    const log = page.getByRole('log', { name: 'Messages' })
    const message = `E2E hello ${Date.now()}`

    await page.getByRole('textbox', { name: 'Message' }).fill(message)
    await page.getByRole('button', { name: 'Send' }).click()

    await expect(log.getByText(`You: ${message}`, { exact: true })).toBeVisible()
    await expect(assistantReplies(page)).toHaveCount(1, { timeout: REPLY_TIMEOUT })
    await expect(page.getByRole('alert')).toHaveCount(0)
  })

  test('a follow-up sends the earlier turns as history', async ({ page }) => {
    await page.goto('/')

    const first = await send(page, `E2E first ${Date.now()}`)
    expect(first.history).toEqual([])
    await expect(assistantReplies(page)).toHaveCount(1, { timeout: REPLY_TIMEOUT })

    const followUp = await send(page, 'E2E follow-up')
    expect(followUp.history.map((t) => t.role)).toEqual(['user', 'assistant'])
    expect(followUp.history[0].content).toBe(first.message)
    await expect(assistantReplies(page)).toHaveCount(2, { timeout: REPLY_TIMEOUT })
  })

  test('New chat clears the chat and the next message has no history', async ({ page }) => {
    await page.goto('/')
    const log = page.getByRole('log', { name: 'Messages' })
    const message = `E2E new chat ${Date.now()}`

    await send(page, message)
    await expect(assistantReplies(page)).toHaveCount(1, { timeout: REPLY_TIMEOUT })

    await page.getByRole('button', { name: 'New chat' }).click()
    await expect(log.getByText(`You: ${message}`, { exact: true })).toHaveCount(0)
    await expect(log.getByText('Ask anything to start a conversation.')).toBeVisible()

    const next = await send(page, 'E2E after new chat')
    expect(next.history).toEqual([])
  })

  test('shows an error and restores the draft when the model fails', async ({ page }) => {
    await page.route('**/api/chat/messages', (route) =>
      route.fulfill({
        status: 502,
        contentType: 'application/problem+json',
        body: JSON.stringify({ title: 'Chat model unavailable', detail: 'E2E simulated model failure.' }),
      }),
    )
    await page.goto('/')
    const message = `E2E failure ${Date.now()}`

    await send(page, message)

    await expect(page.getByRole('alert')).toHaveText('E2E simulated model failure.')
    await expect(page.getByRole('textbox', { name: 'Message' })).toHaveValue(message)
    await expect(page.getByRole('log', { name: 'Messages' }).getByText(`You: ${message}`)).toHaveCount(0)
  })

  test('rejects empty and over-long messages', async ({ page }) => {
    await page.goto('/')
    const input = page.getByRole('textbox', { name: 'Message' })
    const sendButton = page.getByRole('button', { name: 'Send' })

    await expect(input).toHaveAttribute('maxlength', '4000')
    await expect(sendButton).toBeDisabled()
    await input.fill('   ')
    await expect(sendButton).toBeDisabled()
  })

  test('keeps the chat after reload until New chat', async ({ page }) => {
    await page.goto('/')
    const log = page.getByRole('log', { name: 'Messages' })
    const message = `E2E reload ${Date.now()}`

    await send(page, message)
    await expect(assistantReplies(page)).toHaveCount(1, { timeout: REPLY_TIMEOUT })

    await page.reload()
    await expect(log.getByText(`You: ${message}`, { exact: true })).toBeVisible()
    await expect(assistantReplies(page)).toHaveCount(1)

    await page.getByRole('button', { name: 'New chat' }).click()
    await page.reload()
    await expect(log.getByText('Ask anything to start a conversation.')).toBeVisible()
  })

  test('ignores a conversation id from the previous version', async ({ page }) => {
    // Runs on every navigation, so the check below reads the key after the app has loaded.
    await page.addInitScript(() => {
      if (!sessionStorage.getItem('e2e.seeded')) {
        sessionStorage.setItem('e2e.seeded', '1')
        localStorage.setItem('chat.conversationId', '3f2b8c1e-0000-0000-0000-000000000000')
      }
    })
    await page.goto('/')

    await expect(page.getByRole('log', { name: 'Messages' }).getByText('Ask anything to start a conversation.')).toBeVisible()
    await expect(page.getByRole('alert')).toHaveCount(0)
    expect(await page.evaluate(() => localStorage.getItem('chat.conversationId'))).toBeNull()
  })
})
