import type { ChatMessage } from './chatApi'

/** The chat lives only in this browser until "New chat"; the server stores nothing. */
export const CHAT_STORAGE_KEY = 'chat.messages'
/** Written by the previous version, which kept chats in a database. */
export const LEGACY_CONVERSATION_KEY = 'chat.conversationId'
export const MAX_STORED_MESSAGES = 100

// Every storage access is guarded: chatting must keep working when storage is unavailable or full.

function isChatMessage(value: unknown): value is ChatMessage {
  if (typeof value !== 'object' || value === null) return false
  const { id, role, content } = value as Record<string, unknown>
  return typeof id === 'string' && (role === 'user' || role === 'assistant') && typeof content === 'string'
}

function remove(key: string) {
  try {
    localStorage.removeItem(key)
  } catch {
    // Nothing to clean up if storage is unavailable.
  }
}

export function loadChat(): ChatMessage[] {
  remove(LEGACY_CONVERSATION_KEY)

  let raw: string | null
  try {
    raw = localStorage.getItem(CHAT_STORAGE_KEY)
  } catch {
    return []
  }
  if (raw === null) return []

  try {
    const parsed: unknown = JSON.parse(raw)
    if (Array.isArray(parsed) && parsed.every(isChatMessage)) return parsed.slice(-MAX_STORED_MESSAGES)
  } catch {
    // Unreadable: fall through and discard it.
  }
  remove(CHAT_STORAGE_KEY)
  return []
}

export function saveChat(messages: readonly ChatMessage[]) {
  try {
    const stored = messages.slice(-MAX_STORED_MESSAGES).map(({ id, role, content }) => ({ id, role, content }))
    localStorage.setItem(CHAT_STORAGE_KEY, JSON.stringify(stored))
  } catch {
    // The chat still works for this page; it just won't survive a reload.
  }
}

export function clearChat() {
  remove(CHAT_STORAGE_KEY)
}
