import { create } from 'zustand';
import type { Conversation, Message } from '../types';
import messageService from '../services/message.service';
import socketService from '../services/socket.service';

interface MessageState {
  conversations: Conversation[];
  activeConversation: Conversation | null;
  messages: Message[];
  unreadCount: number;
  isLoading: boolean;
  
  loadConversations: () => Promise<void>;
  loadMessages: (conversationId: string) => Promise<void>;
  sendMessage: (conversationId: string, content: string) => Promise<void>;
  setActiveConversation: (conversation: Conversation | null) => void;
  markAsRead: (conversationId: string) => Promise<void>;
  addNewMessage: (message: Message) => void;
  loadUnreadCount: () => Promise<void>;
}

export const useMessageStore = create<MessageState>((set, get) => ({
  conversations: [],
  activeConversation: null,
  messages: [],
  unreadCount: 0,
  isLoading: false,

  loadConversations: async () => {
    set({ isLoading: true });
    try {
      const response = await messageService.getConversations();
      // Handle various response formats
      const conversations = (response as any).conversations || (response as any).data?.conversations || (response as any).data || [];
      set({ conversations: Array.isArray(conversations) ? conversations : [], isLoading: false });
    } catch (error) {
      set({ isLoading: false });
    }
  },

  loadMessages: async (conversationId: string) => {
    set({ isLoading: true });
    try {
      const response = await messageService.getMessages(conversationId);
      // Handle various response formats: { messages: [...] } or { data: { messages: [...] } }
      const messages = response.messages || (response as any).data?.messages || [];
      set({ messages: Array.isArray(messages) ? messages : [], isLoading: false });
    } catch (error) {
      set({ isLoading: false });
    }
  },

  sendMessage: async (conversationId: string, content: string) => {
    try {
      const message = await messageService.sendMessage(conversationId, content);
      set((state) => ({ messages: [...state.messages, message] }));
      
      // Update conversation's last message
      set((state) => ({
        conversations: state.conversations.map((conv) =>
          conv.id === conversationId
            ? { ...conv, last_message: message, last_message_at: message.created_at }
            : conv
        ),
      }));
    } catch (error) {
      console.error('Failed to send message:', error);
    }
  },

  setActiveConversation: (conversation) => {
    set({ activeConversation: conversation });
    if (conversation) {
      socketService.joinConversation(conversation.id);
    }
  },

  markAsRead: async (conversationId: string) => {
    try {
      await messageService.markConversationAsRead(conversationId);
      set((state) => ({
        conversations: state.conversations.map((conv) =>
          conv.id === conversationId ? { ...conv, unread_count: 0 } : conv
        ),
      }));
      get().loadUnreadCount();
    } catch (error) {
      console.error('Failed to mark as read:', error);
    }
  },

  addNewMessage: (message: Message) => {
    const { activeConversation, messages } = get();
    
    // Add message to current conversation if active
    if (activeConversation?.id === message.conversation_id) {
      set({ messages: [...messages, message] });
    }
    
    // Update conversation's last message and unread count
    set((state) => ({
      conversations: state.conversations.map((conv) => {
        if (conv.id === message.conversation_id) {
          return {
            ...conv,
            last_message: message,
            last_message_at: message.created_at,
            unread_count: activeConversation?.id === message.conversation_id 
              ? conv.unread_count 
              : (conv.unread_count || 0) + 1,
          };
        }
        return conv;
      }),
    }));
    
    get().loadUnreadCount();
  },

  loadUnreadCount: async () => {
    try {
      const count = await messageService.getUnreadCount();
      set({ unreadCount: count });
    } catch (error) {
      console.error('Failed to load unread count:', error);
    }
  },
}));

