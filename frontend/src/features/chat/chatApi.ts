import { apiRequest } from '../../lib/api'

export type ChatRole = 'user' | 'assistant'

/** One earlier turn of the chat, as the API expects it (oldest first). */
export interface ChatTurn {
  role: ChatRole
  content: string
}

export interface SendMessageRequest {
  message: string
  history: ChatTurn[]
}

export interface SendMessageResponse {
  reply: string
}

/** A message shown in the chat log; the id exists only in the browser. */
export interface ChatMessage {
  id: string
  role: ChatRole
  content: string
}

export const MAX_MESSAGE_LENGTH = 4000
/** Server limits for `history`: number of turns and length of each turn. */
export const MAX_HISTORY_TURNS = 20
export const MAX_HISTORY_TURN_LENGTH = 8000

export function buildHistory(messages: readonly ChatMessage[]): ChatTurn[] {
  return messages.slice(-MAX_HISTORY_TURNS).map(({ role, content }) => ({
    role,
    content: content.slice(0, MAX_HISTORY_TURN_LENGTH),
  }))
}

export const chatApi = {
  async sendMessage(message: string, history: ChatTurn[]): Promise<string> {
    const body: SendMessageRequest = { message, history }
    const response = await apiRequest<SendMessageResponse>('/api/chat/messages', {
      method: 'POST',
      body: JSON.stringify(body),
    })
    // Guards against an older API version that answered with a message object.
    if (typeof response?.reply !== 'string') throw new Error('The assistant sent an unexpected response.')
    return response.reply
  },
}
