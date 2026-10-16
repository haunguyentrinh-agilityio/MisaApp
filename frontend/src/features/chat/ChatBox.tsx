import { useEffect, useRef, useState, type FormEvent, type KeyboardEvent } from 'react'
import { buildHistory, chatApi, MAX_MESSAGE_LENGTH, type ChatMessage } from './chatApi'
import { clearChat, loadChat, saveChat } from './chatStorage'
import './ChatBox.css'

// Not crypto.randomUUID: it is missing outside secure contexts (e.g. http://frontend in E2E).
let messageCounter = 0
function createMessageId() {
  messageCounter += 1
  return `${Date.now()}-${messageCounter}`
}

export function ChatBox() {
  const [messages, setMessages] = useState<ChatMessage[]>(loadChat)
  const [draft, setDraft] = useState('')
  const [pending, setPending] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const logRef = useRef<HTMLOListElement>(null)

  useEffect(() => {
    logRef.current?.lastElementChild?.scrollIntoView?.({ block: 'end' })
  }, [messages, pending])

  async function send() {
    const text = draft.trim()
    if (!text || pending) return

    // The server keeps nothing, so every request carries the earlier turns.
    const history = buildHistory(messages)
    // Nothing else changes the chat while a send is pending (Send and New chat are disabled).
    const withQuestion: ChatMessage[] = [...messages, { id: createMessageId(), role: 'user', content: text }]
    setMessages(withQuestion)
    setDraft('')
    setError(null)
    setPending(true)

    try {
      const reply = await chatApi.sendMessage(text, history)
      const withReply: ChatMessage[] = [...withQuestion, { id: createMessageId(), role: 'assistant', content: reply }]
      setMessages(withReply)
      saveChat(withReply)
    } catch (err) {
      // Roll back so the user can edit and retry; the stored chat is untouched.
      setMessages(messages)
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
    clearChat()
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
