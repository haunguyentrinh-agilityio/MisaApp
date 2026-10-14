import { useEffect, useRef, useState, type FormEvent, type KeyboardEvent } from 'react'
import { ApiError } from '../../lib/api'
import { chatApi, MAX_MESSAGE_LENGTH, type ChatMessage } from './chatApi'
import './ChatBox.css'

export const CONVERSATION_STORAGE_KEY = 'chat.conversationId'

export function ChatBox() {
  const [conversationId, setConversationId] = useState<string | null>(() =>
    localStorage.getItem(CONVERSATION_STORAGE_KEY),
  )
  const [messages, setMessages] = useState<ChatMessage[]>([])
  const [draft, setDraft] = useState('')
  const [pending, setPending] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const logRef = useRef<HTMLOListElement>(null)

  // Restore the previous conversation after a reload.
  useEffect(() => {
    const storedId = localStorage.getItem(CONVERSATION_STORAGE_KEY)
    if (!storedId) return

    let cancelled = false
    chatApi
      .getConversation(storedId)
      .then((conversation) => {
        if (!cancelled) setMessages(conversation.messages)
      })
      .catch((err: unknown) => {
        if (cancelled) return
        if (err instanceof ApiError && err.status === 404) {
          localStorage.removeItem(CONVERSATION_STORAGE_KEY)
          setConversationId(null)
        } else {
          setError('Could not load the previous conversation.')
        }
      })
    return () => {
      cancelled = true
    }
  }, [])

  useEffect(() => {
    logRef.current?.lastElementChild?.scrollIntoView?.({ block: 'end' })
  }, [messages, pending])

  async function send() {
    const text = draft.trim()
    if (!text || pending) return

    const optimistic: ChatMessage = {
      id: -Date.now(),
      role: 'user',
      content: text,
      createdAtUtc: new Date().toISOString(),
    }
    setMessages((current) => [...current, optimistic])
    setDraft('')
    setError(null)
    setPending(true)

    try {
      const response = await chatApi.sendMessage(text, conversationId)
      setMessages((current) => [
        ...current.filter((m) => m.id !== optimistic.id),
        response.userMessage,
        response.reply,
      ])
      setConversationId(response.conversationId)
      localStorage.setItem(CONVERSATION_STORAGE_KEY, response.conversationId)
    } catch (err) {
      // Roll back so the user can edit and retry.
      setMessages((current) => current.filter((m) => m.id !== optimistic.id))
      setDraft(text)
      setError(err instanceof Error ? err.message : 'Something went wrong.')
    } finally {
      setPending(false)
    }
  }

  function handleSubmit(event: FormEvent) {
    event.preventDefault()
    void send()
  }

  function handleKeyDown(event: KeyboardEvent<HTMLTextAreaElement>) {
    if (event.key === 'Enter' && !event.shiftKey && !event.nativeEvent.isComposing) {
      event.preventDefault()
      void send()
    }
  }

  function startNewChat() {
    localStorage.removeItem(CONVERSATION_STORAGE_KEY)
    setConversationId(null)
    setMessages([])
    setError(null)
  }

  return (
    <section className="chat" aria-label="Chat">
      <header className="chat__header">
        <h2>Assistant</h2>
        <button type="button" onClick={startNewChat} disabled={pending || messages.length === 0}>
          New chat
        </button>
      </header>

      <ol className="chat__log" ref={logRef} role="log" aria-live="polite" aria-label="Messages">
        {messages.length === 0 && !pending && (
          <li className="chat__empty">Ask anything to start a conversation.</li>
        )}
        {messages.map((message) => (
          <li key={message.id} className={`chat__message chat__message--${message.role}`}>
            <span className="visually-hidden">{message.role === 'user' ? 'You' : 'Assistant'}: </span>
            {message.content}
          </li>
        ))}
        {pending && (
          <li className="chat__message chat__message--assistant chat__message--pending">Thinking…</li>
        )}
      </ol>

      {error && (
        <p className="chat__error" role="alert">
          {error}
        </p>
      )}

      <form className="chat__composer" onSubmit={handleSubmit}>
        <label htmlFor="chat-input" className="visually-hidden">
          Message
        </label>
        <textarea
          id="chat-input"
          value={draft}
          onChange={(event) => setDraft(event.target.value)}
          onKeyDown={handleKeyDown}
          placeholder="Type a message… (Shift+Enter for a new line)"
          maxLength={MAX_MESSAGE_LENGTH}
          rows={2}
        />
        <button type="submit" disabled={pending || draft.trim().length === 0}>
          Send
        </button>
      </form>
    </section>
  )
}
