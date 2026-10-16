import { afterEach, describe, expect, it, vi } from 'vitest'
import type { ChatMessage } from './chatApi'
import {
  CHAT_STORAGE_KEY,
  clearChat,
  LEGACY_CONVERSATION_KEY,
  loadChat,
  MAX_STORED_MESSAGES,
  saveChat,
} from './chatStorage'

function messages(count: number): ChatMessage[] {
  return Array.from({ length: count }, (_, i) => ({
    id: `m-${i}`,
    role: i % 2 === 0 ? 'user' : 'assistant',
    content: `turn ${i}`,
  }))
}

afterEach(() => {
  vi.restoreAllMocks()
})

describe('chatStorage', () => {
  it('round-trips a saved chat', () => {
    saveChat(messages(2))

    expect(loadChat()).toEqual(messages(2))
  })

  it('keeps only the most recent messages', () => {
    saveChat(messages(MAX_STORED_MESSAGES + 3))

    const stored = loadChat()
    expect(stored).toHaveLength(MAX_STORED_MESSAGES)
    expect(stored[0].id).toBe('m-3')
  })

  it('lets the last save win', () => {
    saveChat(messages(4))
    saveChat(messages(1))

    expect(loadChat()).toEqual(messages(1))
  })

  it.each([
    ['invalid JSON', '{not json'],
    ['a non-array', '{"id":"a"}'],
    ['a bad role', '[{"id":"a","role":"system","content":"x"}]'],
    ['non-string content', '[{"id":"a","role":"user","content":5}]'],
    ['a non-string id', '[{"id":1,"role":"user","content":"x"}]'],
  ])('discards a stored chat with %s', (_, value) => {
    localStorage.setItem(CHAT_STORAGE_KEY, value)

    expect(loadChat()).toEqual([])
    expect(localStorage.getItem(CHAT_STORAGE_KEY)).toBeNull()
  })

  it('removes the conversation id from the previous version', () => {
    localStorage.setItem(LEGACY_CONVERSATION_KEY, '3f2b8c1e-0000-0000-0000-000000000000')

    expect(loadChat()).toEqual([])
    expect(localStorage.getItem(LEGACY_CONVERSATION_KEY)).toBeNull()
  })

  it('clears the stored chat', () => {
    saveChat(messages(2))

    clearChat()

    expect(localStorage.getItem(CHAT_STORAGE_KEY)).toBeNull()
  })

  it('keeps working when storage is unavailable', () => {
    vi.spyOn(Storage.prototype, 'getItem').mockImplementation(() => {
      throw new Error('denied')
    })
    vi.spyOn(Storage.prototype, 'setItem').mockImplementation(() => {
      throw new Error('quota exceeded')
    })
    vi.spyOn(Storage.prototype, 'removeItem').mockImplementation(() => {
      throw new Error('denied')
    })

    expect(() => saveChat(messages(1))).not.toThrow()
    expect(() => clearChat()).not.toThrow()
    expect(loadChat()).toEqual([])
  })
})
