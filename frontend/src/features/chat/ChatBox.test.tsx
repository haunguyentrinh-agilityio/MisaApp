import { render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, expect, it, vi } from 'vitest'
import { ChatBox, CONVERSATION_STORAGE_KEY } from './ChatBox'
import type { ChatMessage, SendMessageResponse } from './chatApi'

function message(id: number, role: ChatMessage['role'], content: string): ChatMessage {
  return { id, role, content, createdAtUtc: '2026-01-01T00:00:00Z' }
}

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  })
}

function deferred<T>() {
  let resolve!: (value: T) => void
  const promise = new Promise<T>((r) => (resolve = r))
  return { promise, resolve }
}

describe('ChatBox', () => {
  it('sends a message and shows the reply', async () => {
    const reply = deferred<Response>()
    const fetchMock = vi.fn().mockReturnValue(reply.promise)
    vi.stubGlobal('fetch', fetchMock)
    const user = userEvent.setup()
    render(<ChatBox />)

    await user.type(screen.getByLabelText('Message'), 'Hello')
    await user.click(screen.getByRole('button', { name: 'Send' }))

    expect(screen.getByText('Hello')).toBeInTheDocument()
    expect(screen.getByText('Thinking…')).toBeInTheDocument()
    expect(screen.getByLabelText('Message')).toHaveValue('')

    const body: SendMessageResponse = {
      conversationId: 'c-1',
      userMessage: message(1, 'user', 'Hello'),
      reply: message(2, 'assistant', 'Hi! How can I help?'),
    }
    reply.resolve(jsonResponse(body))

    expect(await screen.findByText('Hi! How can I help?')).toBeInTheDocument()
    expect(screen.queryByText('Thinking…')).not.toBeInTheDocument()
    expect(localStorage.getItem(CONVERSATION_STORAGE_KEY)).toBe('c-1')
    expect(fetchMock).toHaveBeenCalledWith(
      '/api/chat/messages',
      expect.objectContaining({
        method: 'POST',
        body: JSON.stringify({ message: 'Hello', conversationId: null }),
      }),
    )
  })

  it('sends on Enter but not on Shift+Enter', async () => {
    const fetchMock = vi.fn().mockResolvedValue(
      jsonResponse({
        conversationId: 'c-1',
        userMessage: message(1, 'user', 'line one\nline two'),
        reply: message(2, 'assistant', 'ok'),
      }),
    )
    vi.stubGlobal('fetch', fetchMock)
    const user = userEvent.setup()
    render(<ChatBox />)

    const input = screen.getByLabelText('Message')
    await user.type(input, 'line one{Shift>}{Enter}{/Shift}line two')
    expect(fetchMock).not.toHaveBeenCalled()

    await user.type(input, '{Enter}')
    expect(fetchMock).toHaveBeenCalledOnce()
    expect(await screen.findByText('ok')).toBeInTheDocument()
  })

  it('shows the error and restores the draft when the request fails', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn().mockResolvedValue(jsonResponse({ title: 'Chat model unavailable', detail: 'Upstream failed.' }, 502)),
    )
    const user = userEvent.setup()
    render(<ChatBox />)

    await user.type(screen.getByLabelText('Message'), 'Will fail{Enter}')

    expect(await screen.findByRole('alert')).toHaveTextContent('Upstream failed.')
    expect(screen.getByLabelText('Message')).toHaveValue('Will fail')
    expect(within(screen.getByRole('log')).queryByText('Will fail')).not.toBeInTheDocument()
  })

  it('restores the stored conversation on load', async () => {
    localStorage.setItem(CONVERSATION_STORAGE_KEY, 'c-9')
    const fetchMock = vi.fn().mockResolvedValue(
      jsonResponse({
        id: 'c-9',
        title: 'Earlier',
        messages: [message(1, 'user', 'Earlier question'), message(2, 'assistant', 'Earlier answer')],
      }),
    )
    vi.stubGlobal('fetch', fetchMock)

    render(<ChatBox />)

    expect(await screen.findByText('Earlier answer')).toBeInTheDocument()
    expect(fetchMock).toHaveBeenCalledWith('/api/chat/conversations/c-9', expect.anything())
  })

  it('forgets a stored conversation that no longer exists', async () => {
    localStorage.setItem(CONVERSATION_STORAGE_KEY, 'gone')
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue(new Response(null, { status: 404 })))

    render(<ChatBox />)

    await waitFor(() => expect(localStorage.getItem(CONVERSATION_STORAGE_KEY)).toBeNull())
    expect(screen.queryByRole('alert')).not.toBeInTheDocument()
  })
})
