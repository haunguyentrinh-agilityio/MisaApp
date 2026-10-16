import { describe, expect, it, vi } from 'vitest'
import { buildHistory, chatApi, MAX_HISTORY_TURN_LENGTH, MAX_HISTORY_TURNS, type ChatMessage } from './chatApi'

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  })
}

function messages(count: number): ChatMessage[] {
  return Array.from({ length: count }, (_, i) => ({
    id: `m-${i}`,
    role: i % 2 === 0 ? 'user' : 'assistant',
    content: `turn ${i}`,
  }))
}

describe('buildHistory', () => {
  it('maps messages to turns without ids, oldest first', () => {
    expect(buildHistory(messages(2))).toEqual([
      { role: 'user', content: 'turn 0' },
      { role: 'assistant', content: 'turn 1' },
    ])
  })

  it('keeps only the most recent turns', () => {
    const history = buildHistory(messages(MAX_HISTORY_TURNS + 5))

    expect(history).toHaveLength(MAX_HISTORY_TURNS)
    expect(history[0].content).toBe('turn 5')
    expect(history.at(-1)?.content).toBe(`turn ${MAX_HISTORY_TURNS + 4}`)
  })

  it('truncates long turns to the server limit', () => {
    const long: ChatMessage = { id: 'a', role: 'assistant', content: 'x'.repeat(MAX_HISTORY_TURN_LENGTH + 10) }

    expect(buildHistory([long])[0].content).toHaveLength(MAX_HISTORY_TURN_LENGTH)
  })
})

describe('chatApi.sendMessage', () => {
  it('posts the message with its history and returns the reply', async () => {
    const fetchMock = vi.fn().mockResolvedValue(jsonResponse({ reply: 'Hi!' }))
    vi.stubGlobal('fetch', fetchMock)
    const history = [{ role: 'user' as const, content: 'earlier' }]

    await expect(chatApi.sendMessage('Hello', history)).resolves.toBe('Hi!')
    expect(fetchMock).toHaveBeenCalledWith(
      '/api/chat/messages',
      expect.objectContaining({ method: 'POST', body: JSON.stringify({ message: 'Hello', history }) }),
    )
  })

  it('rejects a response without a text reply', async () => {
    // The previous API version answered with { conversationId, userMessage, reply: { ... } }.
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue(jsonResponse({ reply: { content: 'old shape' } })))

    await expect(chatApi.sendMessage('Hello', [])).rejects.toThrow()
  })
})
