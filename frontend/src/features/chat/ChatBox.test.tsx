import { render, screen, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, expect, it, vi } from 'vitest'
import { ChatBox } from './ChatBox'

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

function requestBody(fetchMock: ReturnType<typeof vi.fn>, call: number) {
  const init = fetchMock.mock.calls[call][1] as RequestInit
  return JSON.parse(init.body as string) as { message: string; history: unknown[] }
}

describe('ChatBox', () => {
  it('sends a message with an empty history and shows the reply', async () => {
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

    reply.resolve(jsonResponse({ reply: 'Hi! How can I help?' }))

    expect(await screen.findByText('Hi! How can I help?')).toBeInTheDocument()
    expect(screen.queryByText('Thinking…')).not.toBeInTheDocument()
    expect(fetchMock).toHaveBeenCalledWith(
      '/api/chat/messages',
      expect.objectContaining({ method: 'POST', body: JSON.stringify({ message: 'Hello', history: [] }) }),
    )
  })

  it('sends the earlier turns with a follow-up', async () => {
    const fetchMock = vi
      .fn()
      .mockResolvedValueOnce(jsonResponse({ reply: 'First answer' }))
      .mockResolvedValueOnce(jsonResponse({ reply: 'Second answer' }))
    vi.stubGlobal('fetch', fetchMock)
    const user = userEvent.setup()
    render(<ChatBox />)

    await user.type(screen.getByLabelText('Message'), 'First question{Enter}')
    await screen.findByText('First answer')
    await user.type(screen.getByLabelText('Message'), 'Follow-up{Enter}')
    await screen.findByText('Second answer')

    expect(requestBody(fetchMock, 1)).toEqual({
      message: 'Follow-up',
      history: [
        { role: 'user', content: 'First question' },
        { role: 'assistant', content: 'First answer' },
      ],
    })
  })

  it('sends on Enter but not on Shift+Enter', async () => {
    const fetchMock = vi.fn().mockResolvedValue(jsonResponse({ reply: 'ok' }))
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

  it('treats a reply that is not text as an error', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue(jsonResponse({ reply: { content: 'old shape' } })))
    const user = userEvent.setup()
    render(<ChatBox />)

    await user.type(screen.getByLabelText('Message'), 'Hello{Enter}')

    expect(await screen.findByRole('alert')).toBeInTheDocument()
    expect(screen.getByLabelText('Message')).toHaveValue('Hello')
    expect(within(screen.getByRole('log')).queryByText('Hello')).not.toBeInTheDocument()
  })

  it('starts a new chat without earlier context', async () => {
    const fetchMock = vi
      .fn()
      .mockResolvedValueOnce(jsonResponse({ reply: 'First answer' }))
      .mockResolvedValueOnce(jsonResponse({ reply: 'Fresh answer' }))
    vi.stubGlobal('fetch', fetchMock)
    const user = userEvent.setup()
    render(<ChatBox />)

    await user.type(screen.getByLabelText('Message'), 'First question{Enter}')
    await screen.findByText('First answer')
    await user.click(screen.getByRole('button', { name: 'New chat' }))

    expect(screen.getByText('Ask anything to start a conversation.')).toBeInTheDocument()
    expect(screen.queryByText('First answer')).not.toBeInTheDocument()

    await user.type(screen.getByLabelText('Message'), 'Fresh start{Enter}')
    await screen.findByText('Fresh answer')
    expect(requestBody(fetchMock, 1)).toEqual({ message: 'Fresh start', history: [] })
  })

  it('limits the message length and disables Send for a blank draft', async () => {
    const user = userEvent.setup()
    render(<ChatBox />)
    const send = screen.getByRole('button', { name: 'Send' })

    expect(screen.getByLabelText('Message')).toHaveAttribute('maxLength', '4000')
    expect(send).toBeDisabled()
    await user.type(screen.getByLabelText('Message'), '   ')
    expect(send).toBeDisabled()
  })

  describe('after a reload', () => {
    const storedChat = [
      { id: 'a', role: 'user', content: 'Stored question' },
      { id: 'b', role: 'assistant', content: 'Stored answer' },
    ]

    function stored() {
      return JSON.parse(localStorage.getItem('chat.messages') ?? 'null') as unknown
    }

    it('shows the stored chat without a request and sends it as history', async () => {
      localStorage.setItem('chat.messages', JSON.stringify(storedChat))
      const fetchMock = vi.fn().mockResolvedValue(jsonResponse({ reply: 'Next answer' }))
      vi.stubGlobal('fetch', fetchMock)
      const user = userEvent.setup()
      render(<ChatBox />)

      expect(screen.getByText('Stored question')).toBeInTheDocument()
      expect(screen.getByText('Stored answer')).toBeInTheDocument()
      expect(fetchMock).not.toHaveBeenCalled()

      await user.type(screen.getByLabelText('Message'), 'Next{Enter}')
      await screen.findByText('Next answer')
      expect(requestBody(fetchMock, 0).history).toEqual([
        { role: 'user', content: 'Stored question' },
        { role: 'assistant', content: 'Stored answer' },
      ])
    })

    it('stores both turns after a successful reply', async () => {
      vi.stubGlobal('fetch', vi.fn().mockResolvedValue(jsonResponse({ reply: 'Hi!' })))
      const user = userEvent.setup()
      render(<ChatBox />)

      await user.type(screen.getByLabelText('Message'), 'Hello{Enter}')
      await screen.findByText('Hi!')

      expect(stored()).toEqual([
        expect.objectContaining({ role: 'user', content: 'Hello' }),
        expect.objectContaining({ role: 'assistant', content: 'Hi!' }),
      ])
    })

    it('leaves the stored chat unchanged when a send fails', async () => {
      localStorage.setItem('chat.messages', JSON.stringify(storedChat))
      vi.stubGlobal('fetch', vi.fn().mockResolvedValue(jsonResponse({ detail: 'Upstream failed.' }, 502)))
      const user = userEvent.setup()
      render(<ChatBox />)

      await user.type(screen.getByLabelText('Message'), 'Will fail{Enter}')
      await screen.findByRole('alert')

      expect(stored()).toEqual(storedChat)
    })

    it('removes the stored chat on New chat', async () => {
      localStorage.setItem('chat.messages', JSON.stringify(storedChat))
      const user = userEvent.setup()
      render(<ChatBox />)

      await user.click(screen.getByRole('button', { name: 'New chat' }))

      expect(localStorage.getItem('chat.messages')).toBeNull()
      expect(screen.getByText('Ask anything to start a conversation.')).toBeInTheDocument()
    })

    it('discards a conversation id from the previous version', () => {
      localStorage.setItem('chat.conversationId', '3f2b8c1e-0000-0000-0000-000000000000')
      const fetchMock = vi.fn()
      vi.stubGlobal('fetch', fetchMock)
      render(<ChatBox />)

      expect(localStorage.getItem('chat.conversationId')).toBeNull()
      expect(screen.queryByRole('alert')).not.toBeInTheDocument()
      expect(screen.getByText('Ask anything to start a conversation.')).toBeInTheDocument()
      expect(fetchMock).not.toHaveBeenCalled()
    })
  })
})
