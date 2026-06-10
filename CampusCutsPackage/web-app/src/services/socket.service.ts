import { io, Socket } from 'socket.io-client';
import { WS_URL, STORAGE_KEYS } from '../config/constants';
import type { Message, Booking } from '../types';

type SocketEventHandler = (...args: any[]) => void;

class SocketService {
  private socket: Socket | null = null;
  private isConnected = false;

  connect(): void {
    // If socket exists and is connected, just ensure we're in the right room
    if (this.socket?.connected) {
      this.joinPersonalRoom();
      return;
    }

    const token = localStorage.getItem(STORAGE_KEYS.ACCESS_TOKEN);
    if (!token) {
      console.warn('Cannot connect to socket without authentication token');
      return;
    }

    // If socket exists but is disconnected, try to reconnect
    if (this.socket) {
      console.log('Socket exists but disconnected, attempting reconnect...');
      this.socket.connect();
      return;
    }

    this.socket = io(WS_URL, {
      auth: {
        token,
      },
      transports: ['websocket', 'polling'],
      reconnection: true,
      reconnectionAttempts: Infinity, // Keep trying to reconnect
      reconnectionDelay: 1000,
      reconnectionDelayMax: 5000,
    });

    this.socket.on('connect', () => {
      console.log('✅ Socket.IO connected, socket id:', this.socket?.id);
      this.isConnected = true;
      this.joinPersonalRoom();
    });

    this.socket.on('disconnect', (reason) => {
      console.log('❌ Socket.IO disconnected, reason:', reason);
      this.isConnected = false;
    });

    this.socket.on('connect_error', (error) => {
      console.error('❌ Socket.IO connection error:', error.message);
    });

    // Log when we successfully rejoin after reconnection
    this.socket.on('joined-personal', (data) => {
      console.log('📬 Joined personal room:', data);
    });
  }

  private joinPersonalRoom(): void {
    const user = localStorage.getItem(STORAGE_KEYS.USER);
    if (user && this.socket) {
      const userId = JSON.parse(user).id;
      console.log('🔄 Joining personal room: user-' + userId);
      this.socket.emit('join-personal', userId);
    }
  }

  disconnect(): void {
    if (this.socket) {
      this.socket.disconnect();
      this.socket = null;
      this.isConnected = false;
    }
  }

  on(event: string, handler: SocketEventHandler): void {
    this.socket?.on(event, handler);
  }

  off(event: string, handler?: SocketEventHandler): void {
    if (handler) {
      this.socket?.off(event, handler);
    } else {
      this.socket?.off(event);
    }
  }

  emit(event: string, ...args: any[]): void {
    if (!this.socket?.connected) {
      console.warn('Socket not connected, attempting to reconnect...');
      this.connect();
    }
    this.socket?.emit(event, ...args);
  }

  // Message-specific methods
  joinConversation(conversationId: string): void {
    this.emit('join-conversation', conversationId);
  }

  leaveConversation(conversationId: string): void {
    this.emit('leave-conversation', conversationId);
  }

  sendMessage(conversationId: string, content: string): void {
    this.emit('send-message', { conversationId, content });
  }

  onNewMessage(handler: (message: Message) => void): void {
    this.on('new-message', handler);
  }

  offNewMessage(handler?: (message: Message) => void): void {
    this.off('new-message', handler);
  }

  // Booking-specific methods
  onBookingUpdate(handler: (booking: Booking) => void): void {
    this.on('booking-update', handler);
  }

  offBookingUpdate(handler?: (booking: Booking) => void): void {
    this.off('booking-update', handler);
  }

  // New booking request methods (for barbers)
  onNewBookingRequest(handler: (booking: any) => void): void {
    this.on('new-booking-request', handler);
  }

  offNewBookingRequest(handler?: (booking: any) => void): void {
    this.off('new-booking-request', handler);
  }

  // Booking completed methods (for consumers - payment request)
  onBookingCompleted(handler: (data: {
    bookingId: string;
    status: string;
    barberName: string;
    serviceName: string;
    price: number;
    priceFormatted: string;
    paymentUrl: string;
    scheduledDate: string;
    scheduledTime: string;
    location: string;
  }) => void): void {
    this.on('booking-completed', handler);
  }

  offBookingCompleted(handler?: (data: any) => void): void {
    this.off('booking-completed', handler);
  }

  // Booking confirmed methods (for barbers - when they accept a booking)
  onBookingConfirmed(handler: (booking: {
    id: string;
    consumerId: string;
    barberId: string;
    serviceType: string;
    priceUsdCents: number;
    scheduledTime: string;
    status: string;
    location?: string;
    notes?: string;
    consumer: {
      firstName: string;
      lastName: string;
      email?: string;
      profilePictureUrl?: string;
    };
  }) => void): void {
    this.on('booking-confirmed', handler);
  }

  offBookingConfirmed(handler?: (booking: any) => void): void {
    this.off('booking-confirmed', handler);
  }

  // Payment received methods (for barbers - when consumer pays)
  onPaymentReceived(handler: (data: {
    bookingId: string;
    consumerId: string;
    consumerName: string;
    amountPaid: number;
    tipAmount: number;
    totalFormatted: string;
    tipFormatted?: string;
  }) => void): void {
    this.on('payment-received', handler);
  }

  offPaymentReceived(handler?: (data: any) => void): void {
    this.off('payment-received', handler);
  }

  // Booking status change methods (for consumers - when barber undoes completion)
  onBookingStatusChanged(handler: (data: {
    bookingId: string;
    status: string;
    message?: string;
  }) => void): void {
    this.on('booking-status-changed', handler);
  }

  offBookingStatusChanged(handler?: (data: any) => void): void {
    this.off('booking-status-changed', handler);
  }

  // Notification methods
  onNotification(handler: (notification: any) => void): void {
    this.on('notification', handler);
  }

  offNotification(handler?: (notification: any) => void): void {
    this.off('notification', handler);
  }

  // Time block methods (for barbers - real-time availability updates)
  onTimeBlockUpdate(handler: (data: {
    barberId: string;
    action: 'created' | 'deleted';
    timeBlock?: {
      id: string;
      blockDate: string;
      startTime: string;
      endTime: string;
    };
    blockId?: string;
  }) => void): void {
    this.on('time-block-update', handler);
  }

  offTimeBlockUpdate(handler?: (data: any) => void): void {
    this.off('time-block-update', handler);
  }

  // Availability update methods (for barbers - when weekly schedule changes)
  onAvailabilityUpdate(handler: (data: {
    barberId: string;
  }) => void): void {
    this.on('availability-update', handler);
  }

  offAvailabilityUpdate(handler?: (data: any) => void): void {
    this.off('availability-update', handler);
  }

  getConnectionStatus(): boolean {
    return this.isConnected;
  }
}

export default new SocketService();

