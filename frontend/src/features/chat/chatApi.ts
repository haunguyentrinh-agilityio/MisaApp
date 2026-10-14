import { apiRequest } from '../../lib/api'

export type ChatRole = 'user' | 'assistant'

export interface ChatMessage {
  id: number
  role: ChatRole
  content: string
  createdAtUtc: string
}

export interface SendMessageResponse {
  conversationId: string
  userMessage: ChatMessage
  reply: ChatMessage
}

export interface Conversation {
  id: string
  title: string
  messages: ChatMessage[]
}

export const MAX_MESSAGE_LENGTH = 4000

export const chatApi = {
  sendMessage: (message: string, conversationId: string | null) =>
    apiRequest<SendMessageResponse>('/api/chat/messages', {
      method: 'POST',
      body: JSON.stringify({ message, conversationId }),
    }),

  getConversation: (id: string) => apiRequest<Conversation>(`/api/chat/conversations/${id}`),
}
