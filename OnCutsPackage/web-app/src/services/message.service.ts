import api from './api.service';
import type { Conversation, Message, PaginatedResponse } from '../types';

// Booking context for CampusCuts booking-centric conversations
interface BookingContext {
  bookingId?: string;
  serviceName?: string;
  servicePrice?: number;
  scheduledTime?: string;
  location?: string;
  locationDetails?: string;
  notes?: string;
  barberName?: string;
  consumerName?: string;
  barberProfilePicture?: string;
  consumerProfilePicture?: string;
}

interface CreateConversationData {
  other_user_id: string;
  booking_id?: string;
  // Booking context fields
  service_name?: string;
  service_price?: number;
  scheduled_time?: string;
  location?: string;
  location_details?: string;
  notes?: string;
  barber_name?: string;
  consumer_name?: string;
  barber_profile_picture?: string;
  consumer_profile_picture?: string;
}

class MessageService {
  async getConversations(page = 1, limit = 20): Promise<PaginatedResponse<Conversation>> {
    return await api.get<PaginatedResponse<Conversation>>('/messages/conversations', { page, limit });
  }

  async getConversationById(id: string): Promise<Conversation> {
    return await api.get<Conversation>(`/messages/conversations/${id}`);
  }

  async createConversation(data: CreateConversationData): Promise<Conversation> {
    return await api.post<Conversation>('/messages/conversations', data);
  }

  /**
   * Start a BOOKING-CENTRIC conversation with full service context
   * This is the primary way to create conversations in CampusCuts
   */
  async startBookingConversation(
    otherUserId: string, 
    bookingContext: BookingContext
  ): Promise<Conversation> {
    const data: CreateConversationData = {
      other_user_id: otherUserId,
      booking_id: bookingContext.bookingId,
      service_name: bookingContext.serviceName,
      service_price: bookingContext.servicePrice,
      scheduled_time: bookingContext.scheduledTime,
      location: bookingContext.location,
      location_details: bookingContext.locationDetails,
      notes: bookingContext.notes,
      barber_name: bookingContext.barberName,
      consumer_name: bookingContext.consumerName,
      barber_profile_picture: bookingContext.barberProfilePicture,
      consumer_profile_picture: bookingContext.consumerProfilePicture,
    };
    return await api.post<Conversation>('/messages/conversations', data);
  }

  async getMessages(conversationId: string, page = 1, limit = 50): Promise<{ messages: Message[], pagination?: any }> {
    const response = await api.get<{ messages: Message[], pagination?: any }>(`/messages/conversations/${conversationId}/messages`, { 
      page, 
      limit 
    });
    // Backend returns { messages: [...], pagination: {...} }
    return response;
  }

  async sendMessage(conversationId: string, content: string, messageType: 'text' | 'image' = 'text', mediaUrl?: string): Promise<Message> {
    const response = await api.post<{ message: Message }>(`/messages/conversations/${conversationId}/messages`, {
      content,
      message_type: messageType,
      media_url: mediaUrl,
    });
    // Backend returns { message: {...} }, extract the message
    return response.message || response as unknown as Message;
  }

  async markConversationAsRead(conversationId: string): Promise<void> {
    await api.put(`/messages/conversations/${conversationId}/read`, {});
  }

  async deleteConversation(conversationId: string): Promise<void> {
    await api.delete(`/messages/conversations/${conversationId}`);
  }

  async getUnreadCount(): Promise<number> {
    const response = await api.get<{ count: number } | number>('/messages/unread-count');
    // Handle both wrapped { count: N } and direct number responses
    if (typeof response === 'number') return response;
    return (response as { count: number }).count || 0;
  }

  async uploadChatImage(file: File): Promise<string> {
    const formData = new FormData();
    formData.append('image', file);
    const response = await api.upload<{ url: string }>('/upload/chat-image', formData);
    return response.url;
  }

  // ============================================================================
  // CAMPUS MANAGER - BARBER DIRECT MESSAGING
  // ============================================================================

  /**
   * Start or get a direct conversation with campus manager (for barbers)
   * or with a specific barber (for campus managers)
   */
  async startCMBarberConversation(barberUserId?: string): Promise<{ conversationId: number; otherUserId: string; isNew: boolean }> {
    const response = await api.post<{ conversation: { id: number; otherUserId: string; isNew: boolean } }>('/messages/cm-barber', {
      barberUserId
    });
    return {
      conversationId: response.conversation.id,
      otherUserId: response.conversation.otherUserId,
      isNew: response.conversation.isNew
    };
  }

  /**
   * Get all CM-barber conversations (for campus managers)
   * @param campusId - Optional campus ID for admins to view specific campus
   */
  async getCMBarberConversations(campusId?: string): Promise<{
    barbers: Array<{
      userId: string;
      barberId: string;
      name: string;
      firstName: string;
      lastName: string;
      avatarUrl: string | null;
      email: string;
      conversationId: number | null;
      lastMessage: string | null;
      lastMessageAt: string | null;
      unreadCount: number;
    }>;
  }> {
    const params: Record<string, string> = {};
    if (campusId) {
      params.campusId = campusId;
    }
    return await api.get<{ barbers: any[] }>('/messages/cm-barber/conversations', params);
  }

  // ============================================================================
  // BARBER-TO-BARBER DIRECT MESSAGING
  // ============================================================================

  /**
   * Get all barbers on the same campus for barber-to-barber chat
   * @param campusId - Optional campus ID for admins to view a specific campus
   */
  async getBarberChatBarbers(campusId?: string): Promise<{
    barbers: Array<{
      userId: string;
      barberId: string;
      name: string;
      firstName: string;
      lastName: string;
      avatarUrl: string | null;
      email: string;
      isCampusManager: boolean;
      conversationId: number | null;
      lastMessage: string | null;
      lastMessageAt: string | null;
      unreadCount: number;
    }>;
  }> {
    const params = campusId ? `?campusId=${campusId}` : '';
    return await api.get<{ barbers: any[] }>(`/messages/barber-chats/barbers${params}`);
  }

  /**
   * Start or get a direct conversation with another barber
   */
  async startBarberConversation(otherBarberUserId: string): Promise<{ conversationId: number; otherUserId: string; isNew: boolean }> {
    const response = await api.post<{ conversation: { id: number; otherUserId: string; isNew: boolean } }>('/messages/barber-chats', {
      otherBarberUserId
    });
    return {
      conversationId: response.conversation.id,
      otherUserId: response.conversation.otherUserId,
      isNew: response.conversation.isNew
    };
  }
}

export default new MessageService();

