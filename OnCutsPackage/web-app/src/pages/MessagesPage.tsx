/**
 * Messages Page - Booking-Centric Chat System
 * Similar to Airbnb's messaging interface
 */

import { useState, useEffect, useLayoutEffect, useRef, useCallback } from 'react';
import { useNavigate, useParams, useLocation, Link } from 'react-router-dom';
import { 
  ArrowLeft, 
  Send, 
  MessageCircle, 
  Calendar, 
  MapPin, 
  Clock,
  User,
  ChevronLeft,
  ChevronDown,
  MoreVertical,
  Check,
  CheckCheck,
  Scissors,
  LogOut,
  LayoutDashboard,
  Info,
  X,
  DollarSign,
  FileText,
  AlertCircle,
  Trash2,
  Bell,
  Lock,
  Pencil,
  XCircle,
  Loader2
} from 'lucide-react';
import { useAuthStore } from '../store/useAuthStore';
import messageService from '../services/message.service';
import notificationService, { Notification } from '../services/notification.service';
import socketService from '../services/socket.service';
import { usePlatform } from '../utils/platform';
import { useDynamicViewportHeight } from '../hooks';
import Avatar from '../components/Avatar';
import Card from '../components/Card';
import Button from '../components/Button';
import BarberBookingRequestsDropdown from '../components/booking/BarberBookingRequestsDropdown';
import DatePicker from '../components/DatePicker';
import AvailableTimePickerDropdown from '../components/AvailableTimePickerDropdown';
import { CampusCutLogo } from '@assets';
import type { Conversation, Message } from '../types';
import toast from 'react-hot-toast';

interface BarberLocation {
  id: string;
  name: string;
  description: string | null;
  address: string | null;
  is_primary?: boolean;
}

interface ConversationWithDetails extends Conversation {
  booking?: {
    id?: string;
    barberId?: string;
    serviceName: string;
    servicePrice?: number;
    scheduledTime: string;
    location: string;
    locationDetails?: string;
    status: 'pending' | 'accepted' | 'confirmed' | 'completed' | 'cancelled' | 'rejected';
    notes?: string;
    barberName?: string;
    consumerName?: string;
  };
  otherUser: {
    id: string;
    username?: string;
    firstName: string;
    lastName: string;
    profilePicture?: string;
    userType: 'student' | 'barber';
    barberInfo?: {
      id?: string;
      displayName?: string;
      specialties?: string[];
      rating?: number;
    };
  };
  lastMessage?: {
    content: string;
    senderId: string;
    time: string;
  };
  unreadCount: number;
  // Whether the barber has accepted this conversation/booking
  isAccepted?: boolean;
}

interface MessageWithSender {
  id: string;
  conversation_id?: string;
  conversationId?: string;
  sender_id?: string;
  senderId?: string;
  content: string;
  message_type?: 'text' | 'image' | 'system';
  messageType?: 'text' | 'image' | 'system';
  media_url?: string;
  mediaUrl?: string;
  is_read?: boolean;
  isRead?: boolean;
  created_at?: string;
  createdAt?: string;
  sender?: {
    id: string;
    username?: string;
    firstName: string;
    lastName: string;
    profilePicture?: string;
  };
  isOwn?: boolean;
}

export default function MessagesPage() {
  const navigate = useNavigate();
  const { conversationId } = useParams<{ conversationId: string }>();
  const location = useLocation();
  const { user, isLoading: isAuthLoading } = useAuthStore();
  const platform = usePlatform();
  const platformPrefix = `/${platform}`;
  
  // Handle dynamic viewport height for mobile browser bar changes
  useDynamicViewportHeight();
  
  // ALL useState hooks must be declared before any early returns (React Rules of Hooks)
  const [conversations, setConversations] = useState<ConversationWithDetails[]>([]);
  const [selectedConversation, setSelectedConversation] = useState<ConversationWithDetails | null>(null);
  const [messages, setMessages] = useState<MessageWithSender[]>([]);
  const [newMessage, setNewMessage] = useState('');
  const [isLoading, setIsLoading] = useState(true);
  const [isSending, setIsSending] = useState(false);
  const [showMobileChat, setShowMobileChat] = useState(false);
  const [isCreatingConversation, setIsCreatingConversation] = useState(false);
  const [showProfileDropdown, setShowProfileDropdown] = useState(false);
  const [showServiceDetails, setShowServiceDetails] = useState(false);
  const [deletingConversation, setDeletingConversation] = useState<ConversationWithDetails | null>(null);
  const [showDeleteConfirm, setShowDeleteConfirm] = useState(false);
  const [isDeleting, setIsDeleting] = useState(false);
  
  // Edit booking state
  const [isEditingBooking, setIsEditingBooking] = useState(false);
  const [editDate, setEditDate] = useState('');
  const [editTime, setEditTime] = useState('');
  const [editLocation, setEditLocation] = useState('');
  const [isSavingEdit, setIsSavingEdit] = useState(false);
  const [barberLocations, setBarberLocations] = useState<BarberLocation[]>([]);
  const [locationsLoading, setLocationsLoading] = useState(false);
  const [editBarberId, setEditBarberId] = useState<string>('');
  const [editBarberWeeklySchedule, setEditBarberWeeklySchedule] = useState<any>(null);
  const [notifications, setNotifications] = useState<Notification[]>([]);
  const [unreadNotifications, setUnreadNotifications] = useState(0);
  const [showNotifications, setShowNotifications] = useState(false);
  
  const messagesEndRef = useRef<HTMLDivElement>(null);
  const messagesContainerRef = useRef<HTMLDivElement>(null);
  const inputRef = useRef<HTMLInputElement>(null);
  const hasScrolledRef = useRef(false);
  const dropdownRef = useRef<HTMLDivElement>(null);

  // Determine the view based on the URL path
  // /barber/messages = barber view, /consumer/messages = consumer view
  const isBarberView = location.pathname.includes('/barber/messages');
  
  const barberId = user?.id || '';

  // Close dropdown when clicking outside
  useEffect(() => {
    const handleClickOutside = (event: MouseEvent) => {
      if (dropdownRef.current && !dropdownRef.current.contains(event.target as Node)) {
        setShowProfileDropdown(false);
      }
    };

    document.addEventListener('mousedown', handleClickOutside);
    return () => document.removeEventListener('mousedown', handleClickOutside);
  }, []);

  // Handle navigation state for starting a BOOKING-CENTRIC conversation
  const startConversationData = location.state as { 
    startConversation?: boolean; 
    otherUserId?: string; 
    bookingId?: string;
    // Booking context for CampusCuts
    serviceName?: string;
    servicePrice?: number;
    scheduledAt?: string;
    location?: string;
    locationDetails?: string;
    notes?: string;
    barberName?: string;
    consumerName?: string;
    barberProfilePicture?: string;
    consumerProfilePicture?: string;
  } | null;

  // Scroll to bottom of messages
  const scrollToBottom = useCallback(() => {
    const container = messagesContainerRef.current;
    if (container) {
      container.scrollTop = container.scrollHeight;
    }
  }, []);

  // Fetch conversations
  const fetchConversations = useCallback(async () => {
    try {
      const response = await messageService.getConversations();
      // Handle both response formats: { conversations: [...] } and { data: [...] }
      const conversationsData = (response as any).conversations || (response as any).data || [];
      if (Array.isArray(conversationsData)) {
        setConversations(conversationsData as ConversationWithDetails[]);
      } else {
        console.warn('Unexpected conversations response format:', response);
        setConversations([]);
      }
    } catch (error) {
      console.error('Failed to fetch conversations:', error);
    }
  }, []);

  // Fetch messages for a conversation
  const fetchMessages = useCallback(async (convId: string) => {
    try {
      const response = await messageService.getMessages(convId);
      // Handle various response formats: { messages: [...] }, { data: { messages: [...] } }, or direct array
      let messagesData: any[] = [];
      
      if (Array.isArray(response)) {
        messagesData = response;
      } else if ((response as any).messages && Array.isArray((response as any).messages)) {
        messagesData = (response as any).messages;
      } else if ((response as any).data?.messages && Array.isArray((response as any).data.messages)) {
        messagesData = (response as any).data.messages;
      } else if ((response as any).data && Array.isArray((response as any).data)) {
        messagesData = (response as any).data;
      }
      
      console.log('📨 Fetched messages:', messagesData.length, 'messages');
      setMessages(messagesData as MessageWithSender[]);
      
      // Mark as read
      await messageService.markConversationAsRead(convId);
      // Update unread count in conversations list
      setConversations(prev => prev.map(c => 
        c.id === convId ? { ...c, unreadCount: 0 } : c
      ));
    } catch (error) {
      console.error('Failed to fetch messages:', error);
      setMessages([]);
    }
  }, []);

  // Cancel booking handler (also deletes conversation)
  const handleCancelBooking = async () => {
    if (!deletingConversation) return;
    
    setIsDeleting(true);
    try {
      // Cancel the booking if it exists
      if (deletingConversation.booking?.id) {
        await fetch(`${import.meta.env.VITE_API_URL}/bookings-simple/${deletingConversation.booking.id}`, {
          method: 'DELETE',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${localStorage.getItem('accessToken')}`,
          },
          body: JSON.stringify({ reason: 'Cancelled by user' }),
        });
      }
      
      // Delete the conversation
      await messageService.deleteConversation(String(deletingConversation.id));
      toast.success('Booking cancelled successfully');
      
      // Remove from list
      setConversations(prev => prev.filter(c => c.id !== deletingConversation.id));
      
      // If the deleted conversation was selected, clear it
      if (selectedConversation?.id === deletingConversation.id) {
        setSelectedConversation(null);
        setMessages([]);
        setShowMobileChat(false);
      }
      
      // Close modal
      setShowDeleteConfirm(false);
      setDeletingConversation(null);
    } catch (error) {
      console.error('Failed to cancel booking:', error);
      toast.error('Failed to cancel booking');
    } finally {
      setIsDeleting(false);
    }
  };

  const openDeleteConfirm = (conv: ConversationWithDetails, e: React.MouseEvent) => {
    e.stopPropagation(); // Prevent selecting the conversation
    setDeletingConversation(conv);
    window.scrollTo({ top: 0, behavior: 'instant' });
    setShowDeleteConfirm(true);
  };

  // Start editing booking
  const startEditingBooking = async () => {
    if (!selectedConversation?.booking) return;
    const booking = selectedConversation.booking;
    const scheduledDate = new Date(booking.scheduledTime);
    setEditDate(scheduledDate.toISOString().split('T')[0]);
    setEditTime(scheduledDate.toTimeString().slice(0, 5));
    setEditLocation(booking.location || '');
    
    console.log('[MessagesPage] startEditingBooking called');
    console.log('[MessagesPage] Current user type:', user?.user_type, 'user ID:', user?.id);
    console.log('[MessagesPage] Other user type:', selectedConversation.otherUser?.userType, 'other user ID:', selectedConversation.otherUser?.id);
    console.log('[MessagesPage] Booking barberId:', booking.barberId);
    
    // Get barber ID - need to get the barber table ID, not user ID
    // Priority: booking.barberId > otherUser.barberInfo.id > API lookup
    let barberId = booking.barberId || selectedConversation.otherUser?.barberInfo?.id || '';
    console.log('[MessagesPage] Initial barberId:', barberId, 'from booking:', booking.barberId, 'from barberInfo:', selectedConversation.otherUser?.barberInfo?.id);
    
    // Determine who the barber is based on who is viewing the conversation
    // If current user is a barber, they are the barber for this booking
    // If current user is a consumer, the other user is the barber
    if (!barberId) {
      if (user?.user_type === 'barber') {
        // Current user is the barber - look up their barber ID
        console.log('[MessagesPage] Looking up barber ID for current user (barber):', user.id);
        try {
          const url = `${import.meta.env.VITE_API_URL}/barbers/user/${user.id}`;
          console.log('[MessagesPage] Fetching from:', url);
          const response = await fetch(url, {
            headers: {
              'Authorization': `Bearer ${localStorage.getItem('accessToken')}`,
            },
          });
          console.log('[MessagesPage] Response status:', response.status);
          if (response.ok) {
            const data = await response.json();
            console.log('[MessagesPage] Barber lookup response:', data);
            barberId = data.data?.id || data.id || '';
            console.log('[MessagesPage] Current user is barber, found barber ID:', barberId);
          } else {
            const errorText = await response.text();
            console.error('[MessagesPage] Barber lookup failed:', errorText);
          }
        } catch (error) {
          console.error('Failed to look up barber ID for current user:', error);
        }
      } else if (selectedConversation.otherUser?.userType?.toLowerCase() === 'barber') {
        // Other user is the barber - look up their barber ID
        console.log('[MessagesPage] Looking up barber ID for other user (barber):', selectedConversation.otherUser.id);
        try {
          const url = `${import.meta.env.VITE_API_URL}/barbers/user/${selectedConversation.otherUser.id}`;
          console.log('[MessagesPage] Fetching from:', url);
          const response = await fetch(url, {
            headers: {
              'Authorization': `Bearer ${localStorage.getItem('accessToken')}`,
            },
          });
          console.log('[MessagesPage] Response status:', response.status);
          if (response.ok) {
            const data = await response.json();
            console.log('[MessagesPage] Barber lookup response:', data);
            barberId = data.data?.id || data.id || '';
            console.log('[MessagesPage] Other user is barber, found barber ID:', barberId);
          } else {
            const errorText = await response.text();
            console.error('[MessagesPage] Barber lookup failed:', errorText);
          }
        } catch (error) {
          console.error('Failed to look up barber ID for other user:', error);
        }
      } else {
        console.log('[MessagesPage] Neither current user nor other user is a barber!');
      }
    }
    
    setEditBarberId(barberId);
    console.log('[MessagesPage] Edit barber ID set to:', barberId);
    
    // Fetch barber's available locations and weekly schedule
    if (barberId) {
      try {
        setLocationsLoading(true);
        
        // Fetch locations
        const locationsResponse = await fetch(`${import.meta.env.VITE_API_URL}/locations/for-booking/${barberId}`, {
          headers: {
            'Authorization': `Bearer ${localStorage.getItem('accessToken')}`,
          },
        });
        if (locationsResponse.ok) {
          const data = await locationsResponse.json();
          setBarberLocations(data.data || []);
        }
        
        // Fetch weekly schedule for DatePicker availability indicators
        const availabilityResponse = await fetch(`${import.meta.env.VITE_API_URL}/barbers/${barberId}/availability`, {
          headers: {
            'Authorization': `Bearer ${localStorage.getItem('accessToken')}`,
          },
        });
        if (availabilityResponse.ok) {
          const data = await availabilityResponse.json();
          setEditBarberWeeklySchedule(data.weeklySchedule || null);
        }
      } catch (error) {
        console.error('Failed to fetch barber data:', error);
      } finally {
        setLocationsLoading(false);
      }
    }
    
    setIsEditingBooking(true);
  };

  // Cancel editing
  const cancelEditingBooking = () => {
    setIsEditingBooking(false);
    setEditDate('');
    setEditTime('');
    setEditLocation('');
    setEditBarberWeeklySchedule(null);
  };

  // Save booking edits
  const saveBookingEdits = async () => {
    if (!selectedConversation?.booking?.id) return;
    
    setIsSavingEdit(true);
    try {
      const scheduledTime = new Date(`${editDate}T${editTime}`).toISOString();
      
      // Track what changed for the success message
      const originalDate = selectedConversation.booking.scheduledTime 
        ? new Date(selectedConversation.booking.scheduledTime) 
        : null;
      const newDate = new Date(scheduledTime);
      const originalLocation = selectedConversation.booking.location || '';
      
      const changes: string[] = [];
      
      // Check if date changed
      if (originalDate && originalDate.toDateString() !== newDate.toDateString()) {
        changes.push('date');
      }
      
      // Check if time changed
      if (originalDate && (originalDate.getHours() !== newDate.getHours() || originalDate.getMinutes() !== newDate.getMinutes())) {
        changes.push('time');
      }
      
      // Check if location changed
      if (editLocation !== originalLocation) {
        changes.push('location');
      }
      
      const response = await fetch(`${import.meta.env.VITE_API_URL}/bookings/${selectedConversation.booking.id}`, {
        method: 'PATCH',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${localStorage.getItem('accessToken')}`,
        },
        body: JSON.stringify({
          scheduledTime,
          location: editLocation,
        }),
      });

      if (!response.ok) throw new Error('Failed to update booking');

      // Update local state
      setSelectedConversation(prev => prev ? {
        ...prev,
        booking: prev.booking ? {
          ...prev.booking,
          scheduledTime,
          location: editLocation,
        } : undefined,
      } : null);

      // Update in conversations list
      setConversations(prev => prev.map(conv => 
        conv.id === selectedConversation.id && conv.booking
          ? { ...conv, booking: { ...conv.booking, scheduledTime, location: editLocation } }
          : conv
      ));

      // Build success message
      let successMessage = 'Booking ';
      if (changes.length === 0) {
        successMessage = 'No changes were made';
      } else if (changes.length === 1) {
        successMessage += `${changes[0]} has been successfully changed`;
      } else if (changes.length === 2) {
        successMessage += `${changes[0]} and ${changes[1]} have been successfully changed`;
      } else {
        successMessage += `${changes.slice(0, -1).join(', ')}, and ${changes[changes.length - 1]} have been successfully changed`;
      }
      
      toast.success(successMessage);
      setIsEditingBooking(false);
      setShowServiceDetails(false); // Close the mobile modal
    } catch (error) {
      console.error('Failed to update booking:', error);
      toast.error('Failed to update booking');
    } finally {
      setIsSavingEdit(false);
    }
  };

  // Fetch notifications
  const fetchNotifications = useCallback(async () => {
    try {
      const data = await notificationService.getNotifications();
      setNotifications(data.notifications);
      setUnreadNotifications(data.unreadCount);
    } catch (error) {
      console.error('Failed to fetch notifications:', error);
    }
  }, []);

  const handleMarkNotificationRead = async (notificationId: string) => {
    try {
      await notificationService.markAsRead(notificationId);
      setNotifications(prev => prev.map(n => 
        n.id === notificationId ? { ...n, is_read: true } : n
      ));
      setUnreadNotifications(prev => Math.max(0, prev - 1));
    } catch (error) {
      console.error('Failed to mark notification as read:', error);
    }
  };

  const handleMarkAllNotificationsRead = async () => {
    try {
      await notificationService.markAllAsRead();
      setNotifications(prev => prev.map(n => ({ ...n, is_read: true })));
      setUnreadNotifications(0);
    } catch (error) {
      console.error('Failed to mark all notifications as read:', error);
    }
  };

  const handleDeleteAllNotifications = async () => {
    try {
      await notificationService.deleteAllNotifications();
      setNotifications([]);
      setUnreadNotifications(0);
    } catch (error) {
      console.error('Failed to delete all notifications:', error);
    }
  };

  // Initial load
  useEffect(() => {
    const loadData = async () => {
      setIsLoading(true);
      await Promise.all([fetchConversations(), fetchNotifications()]);
      setIsLoading(false);
    };
    loadData();
  }, [fetchConversations, fetchNotifications]);

  // Track if we've already attempted to start a conversation to prevent retry loops
  const hasAttemptedConversation = useRef(false);

  // Handle starting a new BOOKING-CENTRIC conversation from navigation state
  useEffect(() => {
    const startNewConversation = async () => {
      // Only attempt once per page load to prevent retry loops
      if (
        startConversationData?.startConversation && 
        startConversationData.otherUserId && 
        !isCreatingConversation &&
        !hasAttemptedConversation.current
      ) {
        hasAttemptedConversation.current = true;
        setIsCreatingConversation(true);
        try {
          // Create BOOKING-CENTRIC conversation with full service context
          const response = await messageService.createConversation({
            other_user_id: startConversationData.otherUserId,
            booking_id: startConversationData.bookingId,
            // Pass booking context for CampusCuts service-centric messaging
            service_name: startConversationData.serviceName,
            service_price: startConversationData.servicePrice,
            scheduled_time: startConversationData.scheduledAt,
            location: startConversationData.location,
            location_details: startConversationData.locationDetails,
            notes: startConversationData.notes,
            barber_name: startConversationData.barberName,
            consumer_name: startConversationData.consumerName,
            barber_profile_picture: startConversationData.barberProfilePicture,
            consumer_profile_picture: startConversationData.consumerProfilePicture,
          });
          
          // Refresh conversations list
          await fetchConversations();
          
          // Navigate to the conversation
          const convId = (response as any).id || (response as any).conversation?.id || (response as any).data?.conversation?.id;
          if (convId) {
            const messagesPath = isBarberView ? 'barber/messages' : 'consumer/messages';
            navigate(`${platformPrefix}/${messagesPath}/${convId}`, { replace: true, state: null });
          }
        } catch (error) {
          console.error('Failed to create conversation:', error);
          toast.error('Failed to start conversation. Please try again later.');
          // Clear the state to prevent showing a loading state forever
          const messagesPath = isBarberView ? 'barber/messages' : 'consumer/messages';
          navigate(`${platformPrefix}/${messagesPath}`, { replace: true, state: null });
        } finally {
          setIsCreatingConversation(false);
        }
      }
    };
    
    startNewConversation();
  }, [startConversationData, isCreatingConversation, fetchConversations, navigate, platformPrefix, isBarberView]);

  // Handle conversation selection from URL
  useEffect(() => {
    if (conversationId && conversations.length > 0) {
      const conv = conversations.find(c => c.id === conversationId);
      if (conv) {
        setSelectedConversation(conv);
        fetchMessages(conversationId);
        window.scrollTo({ top: 0, behavior: 'instant' });
        setShowMobileChat(true);
      }
    }
  }, [conversationId, conversations, fetchMessages]);

  // Socket.io real-time messages
  useEffect(() => {
    const handleNewMessage = (message: Message) => {
      console.log('📩 Socket received new-message:', message);
      console.log('📩 Current conversation:', selectedConversation?.id, 'Message conversation:', message.conversation_id);
      
      // Add to messages if in current conversation (compare as numbers to handle type differences)
      if (selectedConversation && Number(message.conversation_id) === Number(selectedConversation.id)) {
        console.log('📩 Adding message to current conversation');
        setMessages(prev => [...prev, message as unknown as MessageWithSender]);
        scrollToBottom();
        // Mark as read since we're viewing
        messageService.markConversationAsRead(message.conversation_id);
      }
      
      // Update conversation list
      fetchConversations();
    };

    socketService.onNewMessage(handleNewMessage);
    
    return () => {
      socketService.offNewMessage(handleNewMessage);
    };
  }, [selectedConversation, fetchConversations, scrollToBottom]);

  // Socket.io real-time booking updates (cancellations, edits)
  useEffect(() => {
    const handleBookingUpdate = (updatedBooking: any) => {
      console.log('📬 MessagesPage received booking-update:', updatedBooking);
      
      // If booking was cancelled, remove the conversation and close any open modals
      if (updatedBooking.cancelled || updatedBooking.status?.toUpperCase() === 'CANCELLED') {
        console.log('🗑️ Booking cancelled, removing conversation');
        
        // Find and remove the conversation with this booking
        setConversations(prev => {
          const filtered = prev.filter(c => c.booking?.id !== updatedBooking.id);
          return filtered;
        });
        
        // If the cancelled booking's conversation was selected, close it
        if (selectedConversation?.booking?.id === updatedBooking.id) {
          setSelectedConversation(null);
          setMessages([]);
          setShowMobileChat(false);
          setShowServiceDetails(false);
          toast('This booking has been cancelled', { icon: 'ℹ️' });
        }
        
        // Close confirmation modal if it was showing for this booking
        if (deletingConversation?.booking?.id === updatedBooking.id) {
          setShowDeleteConfirm(false);
          setDeletingConversation(null);
        }
      } else {
        // Booking was edited, update the conversation's booking data
        setConversations(prev => prev.map(conv => {
          if (conv.booking?.id === updatedBooking.id) {
            return {
              ...conv,
              booking: {
                ...conv.booking,
                scheduledTime: updatedBooking.scheduledTime || conv.booking.scheduledTime,
                location: updatedBooking.location !== undefined ? updatedBooking.location : conv.booking.location,
                status: updatedBooking.status || conv.booking.status,
              },
            };
          }
          return conv;
        }));
        
        // Update selected conversation if it matches
        if (selectedConversation?.booking?.id === updatedBooking.id) {
          setSelectedConversation(prev => prev ? {
            ...prev,
            booking: prev.booking ? {
              ...prev.booking,
              scheduledTime: updatedBooking.scheduledTime || prev.booking.scheduledTime,
              location: updatedBooking.location !== undefined ? updatedBooking.location : prev.booking.location,
              status: updatedBooking.status || prev.booking.status,
            } : undefined,
          } : null);
        }
      }
    };
    
    socketService.onBookingUpdate(handleBookingUpdate);
    
    return () => {
      socketService.offBookingUpdate(handleBookingUpdate);
    };
  }, [selectedConversation, deletingConversation]);

  // Scroll to bottom when messages change
  useLayoutEffect(() => {
    if (messages.length > 0) {
      scrollToBottom();
      // Additional attempts with delays in case content is still loading
      setTimeout(scrollToBottom, 50);
      setTimeout(scrollToBottom, 150);
    }
  }, [messages, scrollToBottom]);
  
  // Additional scroll after conversation selection
  useEffect(() => {
    if (selectedConversation && messages.length > 0) {
      const container = messagesContainerRef.current;
      if (container) {
        // Immediate scroll
        container.scrollTop = container.scrollHeight;
        // Delayed scrolls for content that loads async
        setTimeout(() => {
          if (container) container.scrollTop = container.scrollHeight;
        }, 100);
        setTimeout(() => {
          if (container) container.scrollTop = container.scrollHeight;
        }, 500);
      }
    }
  }, [selectedConversation, messages.length]);

  // Handle selecting a conversation
  const handleSelectConversation = (conv: ConversationWithDetails) => {
    setSelectedConversation(conv);
    setIsEditingBooking(false); // Reset edit mode when changing conversations
    fetchMessages(conv.id);
    window.scrollTo({ top: 0, behavior: 'instant' });
    setShowMobileChat(true);
    const messagesPath = isBarberView ? 'barber/messages' : 'consumer/messages';
    navigate(`${platformPrefix}/${messagesPath}/${conv.id}`, { replace: true });
  };

  // Handle sending a message
  const handleSendMessage = async () => {
    if (!newMessage.trim() || !selectedConversation || isSending) return;

    const messageContent = newMessage.trim();
    setNewMessage('');
    setIsSending(true);

    // Optimistic update
    const optimisticMessage: MessageWithSender = {
      id: `temp-${Date.now()}`,
      conversation_id: selectedConversation.id,
      sender_id: user?.id || '',
      content: messageContent,
      message_type: 'text',
      is_read: true,
      created_at: new Date().toISOString(),
      isOwn: true,
      sender: {
        id: user?.id || '',
        firstName: user?.first_name || '',
        lastName: user?.last_name || '',
      }
    };

    setMessages(prev => [...prev, optimisticMessage]);
    scrollToBottom();

    try {
      const response = await messageService.sendMessage(selectedConversation.id, messageContent);
      
      console.log('✅ Message sent, response:', response);
      
      // Replace optimistic message with real one
      // The response should be the Message object with id, content, created_at, etc.
      const resp = response as any;
      const realMessage: MessageWithSender = {
        id: resp.id || optimisticMessage.id,
        conversation_id: selectedConversation.id,
        sender_id: user?.id || '',
        content: resp.content || messageContent,
        message_type: resp.message_type || 'text',
        is_read: resp.is_read || false,
        created_at: resp.created_at || new Date().toISOString(),
        createdAt: resp.created_at || new Date().toISOString(),
        isOwn: true,
        sender: resp.sender || {
          id: user?.id || '',
          firstName: user?.first_name || '',
          lastName: user?.last_name || '',
        }
      };
      
      setMessages(prev => prev.map(m => 
        m.id === optimisticMessage.id ? realMessage : m
      ));
      
      // Update conversations list
      fetchConversations();
    } catch (error) {
      console.error('Failed to send message:', error);
      toast.error('Failed to send message');
      // Remove optimistic message on error
      setMessages(prev => prev.filter(m => m.id !== optimisticMessage.id));
      setNewMessage(messageContent);
    } finally {
      setIsSending(false);
      // Use setTimeout to ensure focus is restored after React state updates
      // This helps on both desktop and mobile browsers
      setTimeout(() => {
        inputRef.current?.focus();
      }, 0);
    }
  };

  // Handle back button on mobile
  const handleBackToList = () => {
    setShowMobileChat(false);
    setSelectedConversation(null);
    const messagesPath = isBarberView ? 'barber/messages' : 'consumer/messages';
    navigate(`${platformPrefix}/${messagesPath}`, { replace: true });
  };

  // Format time - with null/undefined safety
  const formatTime = (dateString: string | undefined | null) => {
    if (!dateString) return '';
    
    const date = new Date(dateString);
    
    // Check for Invalid Date
    if (isNaN(date.getTime())) return '';
    
    const now = new Date();
    const diff = now.getTime() - date.getTime();
    const days = Math.floor(diff / (1000 * 60 * 60 * 24));

    if (days === 0) {
      return date.toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit' });
    } else if (days === 1) {
      return 'Yesterday';
    } else if (days < 7) {
      return date.toLocaleDateString('en-US', { weekday: 'short' });
    } else {
      return date.toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
    }
  };

  // Render conversation list
  const renderConversationList = () => (
    <div className="flex flex-col h-full">
      {/* Header - Title only */}
      <div className="p-4 border-b border-gray-200 bg-white">
        <h1 className="text-xl font-bold text-gray-900">Messages</h1>
      </div>

      {/* Conversation List */}
      <div className="flex-1 overflow-y-auto">
        {isLoading ? (
          <div className="flex items-center justify-center h-40">
            <div className="animate-spin rounded-full h-8 w-8 border-2 border-primary-500 border-t-transparent"></div>
          </div>
        ) : conversations.length === 0 ? (
          <div className="flex flex-col items-center justify-center h-full p-8 text-center">
            <MessageCircle className="w-16 h-16 text-gray-300 mb-4" />
            <h3 className="text-lg font-semibold text-gray-700 mb-2">No messages yet</h3>
            <p className="text-gray-500 mb-4">
              {isBarberView 
                ? "When customers book with you, you can message them here."
                : "When you book a service, you can message your barber here."}
            </p>
            <Button 
              onClick={() => navigate(isBarberView ? `${platformPrefix}/barber` : `${platformPrefix}/consumer`)} 
              variant="primary"
            >
              {isBarberView ? "Go to Dashboard" : "Find a Barber"}
            </Button>
          </div>
        ) : (
          conversations.map((conv) => (
            <div
              key={conv.id}
              onClick={() => handleSelectConversation(conv)}
              className={`group relative p-4 border-b border-gray-100 cursor-pointer hover:bg-gray-50 transition-colors ${
                selectedConversation?.id === conv.id ? 'bg-primary-50' : ''
              }`}
            >
              {/* Delete button - visible on hover (desktop only, mobile has it in chat header) */}
              <button
                onClick={(e) => openDeleteConfirm(conv, e)}
                className="hidden md:block absolute top-2 right-2 p-1.5 rounded-full bg-white shadow-sm border border-gray-200 opacity-0 group-hover:opacity-100 hover:bg-red-50 hover:border-red-200 transition-all z-10"
                title="Delete conversation"
              >
                <Trash2 className="w-4 h-4 text-gray-400 hover:text-red-500" />
              </button>

              <div className="flex items-start gap-3">
                {/* Avatar */}
                <div className="w-12 h-12 rounded-full bg-gray-200 flex items-center justify-center flex-shrink-0">
                  {conv.otherUser?.profilePicture ? (
                    <img 
                      src={conv.otherUser.profilePicture} 
                      alt=""
                      className="w-full h-full rounded-full object-cover"
                    />
                  ) : (
                    <User className="w-6 h-6 text-gray-400" />
                  )}
                </div>

                {/* Content */}
                <div className="flex-1 min-w-0">
                  <div className="flex items-center justify-between mb-1">
                    <h3 className="font-semibold text-gray-900 truncate">
                      {conv.otherUser?.firstName} {conv.otherUser?.lastName}
                    </h3>
                    <span className="text-xs text-gray-500 flex-shrink-0">
                      {conv.lastMessage?.time ? formatTime(conv.lastMessage.time) : ''}
                    </span>
                  </div>
                  
                  {/* Booking context */}
                  {conv.booking && (
                    <div className="flex items-center gap-1 text-xs text-primary-600 mb-1">
                      <Calendar className="w-3 h-3" />
                      <span className="truncate">{conv.booking.serviceName}</span>
                    </div>
                  )}

                  {/* Last message */}
                  <div className="flex items-center justify-between">
                    <p className="text-sm text-gray-600 truncate">
                      {conv.lastMessage?.content || 'No messages yet'}
                    </p>
                    {conv.unreadCount > 0 && (
                      <span className="ml-2 px-2 py-0.5 bg-primary-500 text-white text-xs font-bold rounded-full flex-shrink-0">
                        {conv.unreadCount}
                      </span>
                    )}
                  </div>
                </div>
              </div>
            </div>
          ))
        )}
      </div>
    </div>
  );

  // Render chat view
  const renderChatView = () => {
    if (!selectedConversation) {
      return (
        <div className="flex flex-col items-center justify-center h-full text-center p-8 bg-gray-50">
          <h3 className="text-xl font-semibold text-gray-700 mb-2">Select a conversation</h3>
          <p className="text-gray-500">Choose a conversation from the list to start messaging</p>
        </div>
      );
    }

    return (
      <div className="flex flex-col h-full min-h-0">
        {/* Chat Header */}
        <div className="p-4 border-b border-gray-200 bg-white">
          <div className="flex items-center gap-3">
            <button
              onClick={handleBackToList}
              className="md:hidden p-2 hover:bg-gray-100 rounded-lg transition-colors"
            >
              <ChevronLeft className="w-5 h-5 text-gray-600" />
            </button>
            
            <div className="w-10 h-10 rounded-full bg-gray-200 flex items-center justify-center flex-shrink-0">
              {selectedConversation.otherUser?.profilePicture ? (
                <img 
                  src={selectedConversation.otherUser.profilePicture} 
                  alt=""
                  className="w-full h-full rounded-full object-cover"
                />
              ) : (
                <User className="w-5 h-5 text-gray-400" />
              )}
            </div>
            
            <div className="flex-1 min-w-0">
              <h2 className="font-semibold text-gray-900 truncate">
                {selectedConversation.otherUser?.firstName} {selectedConversation.otherUser?.lastName}
              </h2>
              {selectedConversation.booking && (
                <p className="text-xs text-gray-500 truncate md:hidden">
                  {selectedConversation.booking.serviceName} • {new Date(selectedConversation.booking.scheduledTime).toLocaleDateString()}
                </p>
              )}
            </div>

            {/* Desktop - Compact inline booking context */}
            {selectedConversation.booking && (
              <div className="hidden md:flex items-center gap-3 px-3 py-1.5 bg-primary-50 border border-primary-200 rounded-lg text-xs">
                <div className="flex items-center gap-1 text-primary-700">
                  <Scissors className="w-3.5 h-3.5" />
                  <span className="font-medium">{selectedConversation.booking.serviceName}</span>
                </div>
                <div className="flex items-center gap-1 text-primary-700">
                  <Calendar className="w-3.5 h-3.5" />
                  <span>{new Date(selectedConversation.booking.scheduledTime).toLocaleDateString()}</span>
                </div>
                <div className="flex items-center gap-1 text-primary-700">
                  <Clock className="w-3.5 h-3.5" />
                  <span>{new Date(selectedConversation.booking.scheduledTime).toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit' })}</span>
                </div>
                <span className={`px-2 py-0.5 rounded-full text-xs font-medium ${
                  selectedConversation.booking.status === 'accepted' || selectedConversation.booking.status === 'confirmed' ? 'bg-green-100 text-green-700' :
                  selectedConversation.booking.status === 'pending' ? 'bg-yellow-100 text-yellow-700' :
                  selectedConversation.booking.status === 'completed' ? 'bg-blue-100 text-blue-700' :
                  selectedConversation.booking.status === 'cancelled' || selectedConversation.booking.status === 'rejected' ? 'bg-red-100 text-red-700' :
                  'bg-gray-100 text-gray-700'
                }`}>
                  {selectedConversation.booking.status}
                </span>
              </div>
            )}

            {/* Service Details Button - Mobile Only (panel is visible on desktop) */}
            <button 
              onClick={() => { window.scrollTo({ top: 0, behavior: 'instant' }); setShowServiceDetails(true); }}
              className="md:hidden p-2 hover:bg-primary-50 rounded-lg transition-colors"
              title="View Service Details"
            >
              <Info className="w-5 h-5 text-primary-600" />
            </button>

            {/* Delete Conversation Button - Mobile Only */}
            <button 
              onClick={(e) => openDeleteConfirm(selectedConversation, e)}
              className="md:hidden p-2 hover:bg-red-50 rounded-lg transition-colors"
              title="Delete conversation"
            >
              <Trash2 className="w-5 h-5 text-gray-400 hover:text-red-500" />
            </button>
          </div>

          {/* Pending Status Banner - Show when barber hasn't accepted yet */}
          {selectedConversation.booking?.status === 'pending' && !isBarberView && (
            <div className="mt-3 p-3 bg-yellow-50 border border-yellow-200 rounded-lg">
              <div className="flex items-center gap-2 text-yellow-700">
                <AlertCircle className="w-4 h-4 flex-shrink-0" />
                <p className="text-sm">
                  <span className="font-medium">Request Pending</span> - Your messages will be delivered once the barber accepts your booking request.
                </p>
              </div>
            </div>
          )}

          {/* Compact Booking Context Bar - Mobile: Interactive button | Desktop: Static display */}
          {selectedConversation.booking && (
            <>
              {/* Mobile - Interactive button to open service details modal */}
              <button 
                onClick={() => { window.scrollTo({ top: 0, behavior: 'instant' }); setShowServiceDetails(true); }}
                className="md:hidden mt-3 w-full p-3 bg-primary-50 border border-primary-200 rounded-lg hover:bg-primary-100 transition-colors"
              >
                <div className="flex items-center justify-between">
                  <div className="flex items-center gap-4">
                    {/* Service */}
                    <div className="flex flex-col items-center text-primary-700">
                      <Scissors className="w-4 h-4 mb-0.5" />
                      <span className="font-medium text-xs">{selectedConversation.booking.serviceName}</span>
                    </div>
                    {/* Date */}
                    <div className="flex flex-col items-center text-primary-700">
                      <Calendar className="w-4 h-4 mb-0.5" />
                      <span className="text-xs">{new Date(selectedConversation.booking.scheduledTime).toLocaleDateString()}</span>
                    </div>
                    {/* Time */}
                    <div className="flex flex-col items-center text-primary-700">
                      <Clock className="w-4 h-4 mb-0.5" />
                      <span className="text-xs">{new Date(selectedConversation.booking.scheduledTime).toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit' })}</span>
                    </div>
                  </div>
                  <div className="flex items-center gap-2">
                    <span className={`px-2 py-0.5 rounded-full text-xs font-medium ${
                      selectedConversation.booking.status === 'accepted' || selectedConversation.booking.status === 'confirmed' ? 'bg-green-100 text-green-700' :
                      selectedConversation.booking.status === 'pending' ? 'bg-yellow-100 text-yellow-700' :
                      selectedConversation.booking.status === 'completed' ? 'bg-blue-100 text-blue-700' :
                      selectedConversation.booking.status === 'cancelled' || selectedConversation.booking.status === 'rejected' ? 'bg-red-100 text-red-700' :
                      'bg-gray-100 text-gray-700'
                    }`}>
                      {selectedConversation.booking.status}
                    </span>
                    <ChevronDown className="w-4 h-4 text-primary-600" />
                  </div>
                </div>
              </button>

            </>
          )}
        </div>

        {/* Messages */}
        <div 
          ref={(el) => {
            messagesContainerRef.current = el;
            // Scroll to bottom immediately when container is mounted or messages change
            if (el && messages.length > 0) {
              el.scrollTop = el.scrollHeight;
            }
          }} 
          className="flex-1 min-h-0 overflow-y-auto p-4 bg-gray-50"
        >
          {messages.length === 0 ? (
            <div className="flex flex-col items-center justify-center h-full text-center">
              <p className="text-gray-500">No messages yet. Start the conversation!</p>
            </div>
          ) : (
            <div>
              {messages.map((message, idx) => {
                const senderId = message.senderId || message.sender_id;
                const isOwn = senderId === user?.id || (message as any).isOwn;
                const prevSenderId = messages[idx - 1]?.senderId || messages[idx - 1]?.sender_id;
                const nextSenderId = messages[idx + 1]?.senderId || messages[idx + 1]?.sender_id;
                const showAvatar = !isOwn && (idx === 0 || prevSenderId !== senderId);
                
                // iOS-style: Only show timestamp on last message in a group
                // A group is consecutive messages from same sender within 1 minute
                const currentTime = new Date(message.createdAt || message.created_at || 0).getTime();
                const nextTime = messages[idx + 1] 
                  ? new Date(messages[idx + 1].createdAt || messages[idx + 1].created_at || 0).getTime() 
                  : 0;
                const isNextSameSender = nextSenderId === senderId;
                const isWithinOneMinute = nextTime && Math.abs(nextTime - currentTime) < 60000; // 1 minute
                const showTimestamp = !isNextSameSender || !isWithinOneMinute;
                
                // Determine if this is the last message in a group (for spacing)
                const isLastInGroup = !isNextSameSender || !isWithinOneMinute;
                
                return (
                  <div
                    key={message.id}
                    className={`flex items-end gap-2 ${isOwn ? 'justify-end' : 'justify-start'} ${isLastInGroup ? 'mb-3' : 'mb-px'}`}
                  >
                    {!isOwn && showAvatar && (
                      <div className="w-8 h-8 rounded-full bg-gray-200 flex items-center justify-center flex-shrink-0">
                        {message.sender?.profilePicture ? (
                          <img 
                            src={message.sender.profilePicture} 
                            alt=""
                            className="w-full h-full rounded-full object-cover"
                          />
                        ) : (
                          <User className="w-4 h-4 text-gray-400" />
                        )}
                      </div>
                    )}
                    {!isOwn && !showAvatar && <div className="w-8 flex-shrink-0" />}
                    
                    <div className={`max-w-[70%] ${isOwn ? 'order-1' : ''}`}>
                      <div
                        className={`px-4 py-2 rounded-2xl ${
                          isOwn 
                            ? 'bg-primary-500 text-white rounded-br-sm' 
                            : 'bg-white border border-gray-200 text-gray-900 rounded-bl-sm'
                        }`}
                      >
                        <p className="text-sm whitespace-pre-wrap break-words">
                          {message.content || ''}
                        </p>
                      </div>
                      {showTimestamp && (message.createdAt || message.created_at) && (
                        <div className={`flex items-center gap-1 mt-1 ${isOwn ? 'justify-end' : 'justify-start'}`}>
                          <span className="text-xs text-gray-400">
                            {formatTime(message.createdAt || message.created_at)}
                          </span>
                          {isOwn && (
                            (message.isRead || message.is_read)
                              ? <CheckCheck className="w-3 h-3 text-primary-500" />
                              : <Check className="w-3 h-3 text-gray-400" />
                          )}
                        </div>
                      )}
                    </div>
                  </div>
                );
              })}
              <div ref={messagesEndRef} />
            </div>
          )}
        </div>

        {/* Message Input */}
        <div className="p-4 border-t border-gray-200 bg-white">
          {/* Messaging lock logic for pending bookings:
              - Barbers can always message (to initiate conversation)
              - Consumers can only respond after barber has sent at least one message */}
          {(() => {
            const isPending = selectedConversation?.booking?.status === 'pending';
            
            if (isPending) {
              // Check if barber has sent any messages in this conversation
              // The barber is the "other user" from consumer view, or "current user" from barber view
              const barberHasMessaged = isBarberView 
                ? messages.some(m => (m.sender_id || m.senderId) === user?.id)
                : messages.some(m => (m.sender_id || m.senderId) !== user?.id);
              
              // Barber can always message on pending
              if (isBarberView) {
                return (
                  <div className="space-y-2">
                    <div className="flex items-center justify-center gap-2 py-1.5 px-3 bg-blue-50 border border-blue-200 rounded-full text-blue-700 text-xs">
                      <Info className="w-3.5 h-3.5" />
                      <span>Booking pending – message to discuss details before accepting</span>
                    </div>
                    <div className="flex items-center gap-3">
                      <input
                        ref={inputRef}
                        type="text"
                        value={newMessage}
                        onChange={(e) => setNewMessage(e.target.value)}
                        onKeyPress={(e) => e.key === 'Enter' && handleSendMessage()}
                        placeholder="Type a message..."
                        className="flex-1 px-4 py-2 border border-gray-300 rounded-full focus:outline-none focus:ring-2 focus:ring-primary-500 focus:border-transparent"
                        disabled={isSending}
                      />
                      <button
                        type="button"
                        onMouseDown={(e) => e.preventDefault()}
                        onClick={handleSendMessage}
                        disabled={!newMessage.trim() || isSending}
                        className={`p-2 rounded-full transition-colors ${
                          newMessage.trim() && !isSending
                            ? 'bg-primary-500 text-white hover:bg-primary-600'
                            : 'bg-gray-100 text-gray-400 cursor-not-allowed'
                        }`}
                      >
                        <Send className="w-5 h-5" />
                      </button>
                    </div>
                  </div>
                );
              }
              
              // Consumer can message only if barber has sent at least one message
              if (barberHasMessaged) {
                return (
                  <div className="space-y-2">
                    <div className="flex items-center justify-center gap-2 py-1.5 px-3 bg-blue-50 border border-blue-200 rounded-full text-blue-700 text-xs">
                      <MessageCircle className="w-3.5 h-3.5" />
                      <span>Barber reached out – reply to discuss details</span>
                    </div>
                    <div className="flex items-center gap-3">
                      <input
                        ref={inputRef}
                        type="text"
                        value={newMessage}
                        onChange={(e) => setNewMessage(e.target.value)}
                        onKeyPress={(e) => e.key === 'Enter' && handleSendMessage()}
                        placeholder="Type a message..."
                        className="flex-1 px-4 py-2 border border-gray-300 rounded-full focus:outline-none focus:ring-2 focus:ring-primary-500 focus:border-transparent"
                        disabled={isSending}
                      />
                      <button
                        type="button"
                        onMouseDown={(e) => e.preventDefault()}
                        onClick={handleSendMessage}
                        disabled={!newMessage.trim() || isSending}
                        className={`p-2 rounded-full transition-colors ${
                          newMessage.trim() && !isSending
                            ? 'bg-primary-500 text-white hover:bg-primary-600'
                            : 'bg-gray-100 text-gray-400 cursor-not-allowed'
                        }`}
                      >
                        <Send className="w-5 h-5" />
                      </button>
                    </div>
                  </div>
                );
              }
              
              // Consumer cannot message yet - barber hasn't initiated
              return (
                <div className="flex items-center justify-center gap-2 py-2 px-4 bg-amber-50 border border-amber-200 rounded-full text-amber-700 text-sm">
                  <Lock className="w-4 h-4" />
                  <span>Waiting for barber to respond to your request</span>
                </div>
              );
            }
            
            // Booking is not pending - normal messaging
            return (
              <div className="flex items-center gap-3">
                <input
                  ref={inputRef}
                  type="text"
                  value={newMessage}
                  onChange={(e) => setNewMessage(e.target.value)}
                  onKeyPress={(e) => e.key === 'Enter' && handleSendMessage()}
                  placeholder="Type a message..."
                  className="flex-1 px-4 py-2 border border-gray-300 rounded-full focus:outline-none focus:ring-2 focus:ring-primary-500 focus:border-transparent"
                  disabled={isSending}
                />
                <button
                  type="button"
                  onMouseDown={(e) => e.preventDefault()}
                  onClick={handleSendMessage}
                  disabled={!newMessage.trim() || isSending}
                  className={`p-2 rounded-full transition-colors ${
                    newMessage.trim() && !isSending
                      ? 'bg-primary-500 text-white hover:bg-primary-600'
                      : 'bg-gray-100 text-gray-400 cursor-not-allowed'
                  }`}
                >
                  <Send className="w-5 h-5" />
                </button>
              </div>
            );
          })()}
        </div>
      </div>
    );
  };

  // Wait for auth to finish loading before rendering
  // This check is placed after all hooks to comply with React's Rules of Hooks
  if (isAuthLoading) {
    return (
      <div className="min-h-screen flex items-center justify-center">
        <Loader2 className="w-8 h-8 text-primary-500 animate-spin" />
      </div>
    );
  }

  return (
    <div className="h-screen bg-gray-50 flex flex-col overflow-hidden" style={{ height: '100dvh' }}>
      {/* Main Header - Same as BarberPage/ConsumerPage */}
      <div className="bg-white shadow-sm border-b border-gray-200 flex-shrink-0">
        <div className="max-w-7xl mx-auto px-3 sm:px-4 py-3 sm:py-4">
          <div className="flex items-center justify-between relative">
            {/* Left section - Dashboard button only */}
            <div className="flex items-center gap-2 sm:gap-4">
              {/* Dashboard Button */}
              <button
                onClick={() => {
                  const destination = isBarberView ? `${platformPrefix}/barber` : `${platformPrefix}/consumer`;
                  navigate(destination);
                }}
                className="flex items-center gap-2 p-2 sm:px-4 sm:py-2 rounded-lg bg-gray-100 hover:bg-gray-200 transition-colors border border-gray-300"
                title="Back to Dashboard"
              >
                <LayoutDashboard className="w-4 h-4 text-gray-600" />
                <span className="hidden lg:inline text-sm font-medium text-gray-700">Dashboard</span>
              </button>
            </div>
            
            {/* Center section - Logo always centered */}
            <div className="absolute left-1/2 transform -translate-x-1/2">
              <img src={CampusCutLogo} alt="CampusCut" className="h-10 sm:h-12 w-auto" />
            </div>
            
            {/* Right section - Messages, Booking Requests (if barber) + Profile */}
            <div className="flex items-center gap-1.5 sm:gap-4">
              
              {/* Booking Requests Inbox - only for barbers */}
              {isBarberView && <BarberBookingRequestsDropdown barberId={barberId} />}

              {/* Profile Dropdown */}
              <div className="relative" ref={dropdownRef}>
                <button
                  onClick={() => setShowProfileDropdown(!showProfileDropdown)}
                  className="flex items-center gap-1 sm:gap-2 px-2 sm:px-3 py-2 rounded-lg hover:bg-gray-100 transition-colors"
                >
                  <Avatar src={user?.profile_picture_url} alt={user?.first_name || 'User'} size="md" />
                  <ChevronDown className={`w-4 h-4 text-gray-600 transition-transform ${showProfileDropdown ? 'rotate-180' : ''}`} />
                </button>

                {showProfileDropdown && (
                  <div className="absolute right-0 mt-2 w-56 bg-white rounded-lg shadow-lg border border-gray-200 py-1 z-50 max-w-[calc(100vw-2rem)]">
                    {/* Switch View - matches BarberPage dropdown */}
                    {isBarberView ? (
                      <button
                        onClick={() => {
                          navigate(`${platformPrefix}/consumer`);
                          setShowProfileDropdown(false);
                        }}
                        className="w-full px-4 py-2 text-left text-sm text-primary-600 hover:bg-primary-50"
                      >
                        Switch to Consumer
                      </button>
                    ) : (
                      (user?.user_type === 'barber' || user?.user_type === 'campus_manager' || user?.has_barber_profile) && (
                        <button
                          onClick={() => {
                            navigate(`${platformPrefix}/barber`);
                            setShowProfileDropdown(false);
                          }}
                          className="w-full px-4 py-2 text-left text-sm text-primary-600 hover:bg-primary-50 flex items-center gap-3"
                        >
                          <Scissors className="w-4 h-4 text-primary-500" />
                          Switch to Barber
                        </button>
                      )
                    )}
                    <div className="border-t border-gray-200 my-1"></div>
                    
                    {/* Barber-specific options */}
                    {isBarberView && (
                      <>
                        <button
                          onClick={() => {
                            navigate(`${platformPrefix}/barber`);
                            setShowProfileDropdown(false);
                          }}
                          className="w-full px-4 py-2 text-left text-sm text-gray-700 hover:bg-gray-100 flex items-center gap-3"
                        >
                          <LayoutDashboard className="w-4 h-4 text-gray-500" />
                          Dashboard
                        </button>
                      </>
                    )}
                    
                    {/* Notifications */}
                    <button
                      onClick={() => {
                        window.scrollTo({ top: 0, behavior: 'instant' });
                        setShowNotifications(true);
                        setShowProfileDropdown(false);
                      }}
                      className="w-full px-4 py-2 text-left text-sm text-gray-700 hover:bg-gray-100 flex items-center gap-3"
                    >
                      <Bell className="w-4 h-4 text-gray-500" />
                      Notifications
                      {unreadNotifications > 0 && (
                        <span className="ml-auto px-2 py-0.5 bg-red-500 text-white text-xs font-bold rounded-full">
                          {unreadNotifications}
                        </span>
                      )}
                    </button>
                    
                    <div className="border-t border-gray-200 my-1"></div>
                    <Link
                      to="/privacy"
                      onClick={() => setShowProfileDropdown(false)}
                      className="w-full px-4 py-2 text-left text-sm text-gray-700 hover:bg-gray-100 flex items-center gap-3"
                    >
                      <FileText className="w-4 h-4 text-gray-500" />
                      Privacy Policy
                    </Link>
                    <Link
                      to="/terms"
                      onClick={() => setShowProfileDropdown(false)}
                      className="w-full px-4 py-2 text-left text-sm text-gray-700 hover:bg-gray-100 flex items-center gap-3"
                    >
                      <FileText className="w-4 h-4 text-gray-500" />
                      Terms of Service
                    </Link>
                    <div className="border-t border-gray-200 my-1"></div>
                    <button
                      onClick={() => {
                        useAuthStore.getState().logout();
                        navigate(`${platformPrefix}`);
                        setShowProfileDropdown(false);
                      }}
                      className="w-full px-4 py-2 text-left text-sm text-red-600 hover:bg-red-50 flex items-center gap-3"
                    >
                      <LogOut className="w-4 h-4 text-red-500" />
                      Sign Out
                    </button>
                  </div>
                )}
              </div>
            </div>
          </div>
        </div>
      </div>

      {/* Messages Content */}
      <div className="flex-1 min-h-0 overflow-hidden">
        {/* Desktop Layout - Three Column */}
        <div className="hidden md:flex h-full min-h-0">
          {/* Conversation List - Fixed Width */}
          <div className="w-80 lg:w-96 border-r border-gray-200 bg-white flex-shrink-0 overflow-hidden">
            {renderConversationList()}
          </div>
          
          {/* Chat View - Reduced Width, matches Service Details height */}
          <div className="flex-1 max-w-2xl border-r border-gray-200 h-full min-h-0 overflow-hidden">
            {renderChatView()}
          </div>

          {/* Service Details Panel - Right Side (Desktop Only) */}
          <div className="w-80 lg:w-96 bg-white flex-shrink-0 h-full overflow-hidden flex flex-col">
            {selectedConversation?.booking ? (
              <>
                {/* Panel Header - Fixed */}
                <div className="bg-gradient-to-r from-primary-500 to-primary-400 px-5 py-4 flex-shrink-0">
                  <h2 className="text-lg font-bold text-white">Service Details</h2>
                  <p className="text-white/80 text-sm">Booking Information</p>
                </div>

                {/* Panel Content - Scrollable */}
                <div className="flex-1 p-4 space-y-3 overflow-y-auto">
                  {/* Service Name & Price */}
                  <div className="flex items-center justify-between p-3 bg-gray-50 rounded-xl">
                    <div className="flex items-center gap-3">
                      <div className="w-9 h-9 bg-primary-100 rounded-full flex items-center justify-center">
                        <Scissors className="w-4 h-4 text-primary-600" />
                      </div>
                      <div>
                        <h3 className="font-semibold text-gray-900 text-sm">{selectedConversation.booking.serviceName}</h3>
                        <p className="text-xs text-gray-500">Service</p>
                      </div>
                    </div>
                    {selectedConversation.booking.servicePrice && (
                      <p className="text-base font-bold text-gray-900">${selectedConversation.booking.servicePrice}</p>
                    )}
                  </div>

                  {/* Date & Time */}
                  {isEditingBooking ? (
                    <div className="space-y-3">
                      {/* Date Picker */}
                      <div className="p-3 bg-gray-50 rounded-xl">
                        <DatePicker
                          label="Date"
                          value={editDate}
                          onChange={(newDate) => {
                            setEditDate(newDate);
                            setEditTime(''); // Reset time when date changes
                          }}
                          minDate={new Date().toISOString().split('T')[0]}
                          weeklySchedule={editBarberWeeklySchedule}
                          required
                        />
                      </div>
                      
                      {/* Time Picker */}
                      <div className="p-3 bg-gray-50 rounded-xl">
                        <div className="flex items-center gap-1.5 text-gray-500 mb-2">
                          <Clock className="w-3.5 h-3.5" />
                          <span className="text-xs font-medium">Time</span>
                        </div>
                        <AvailableTimePickerDropdown
                          barberId={editBarberId}
                          date={editDate}
                          value={editTime}
                          onChange={(value) => setEditTime(value)}
                          disabled={!editDate}
                        />
                      </div>
                    </div>
                  ) : (
                    <div className="grid grid-cols-2 gap-3">
                      <div className="p-3 bg-gray-50 rounded-xl">
                        <div className="flex items-center gap-1.5 text-gray-500 mb-1">
                          <Calendar className="w-3.5 h-3.5" />
                          <span className="text-xs">Date</span>
                        </div>
                        <p className="font-medium text-gray-900 text-sm">
                          {new Date(selectedConversation.booking.scheduledTime).toLocaleDateString('en-US', { 
                            weekday: 'short',
                            month: 'short', 
                            day: 'numeric'
                          })}
                        </p>
                      </div>
                      <div className="p-3 bg-gray-50 rounded-xl">
                        <div className="flex items-center gap-1.5 text-gray-500 mb-1">
                          <Clock className="w-3.5 h-3.5" />
                          <span className="text-xs">Time</span>
                        </div>
                        <p className="font-medium text-gray-900 text-sm">
                          {new Date(selectedConversation.booking.scheduledTime).toLocaleTimeString('en-US', { 
                            hour: 'numeric', 
                            minute: '2-digit'
                          })}
                        </p>
                      </div>
                    </div>
                  )}

                  {/* Location */}
                  <div className="p-3 bg-gray-50 rounded-xl">
                    <div className="flex items-center gap-1.5 text-gray-500 mb-1">
                      <MapPin className="w-3.5 h-3.5" />
                      <span className="text-xs">Location</span>
                    </div>
                    {isEditingBooking ? (
                      locationsLoading ? (
                        <div className="text-sm text-gray-500 py-1">Loading locations...</div>
                      ) : barberLocations.length > 0 ? (
                        <select
                          value={editLocation}
                          onChange={(e) => setEditLocation(e.target.value)}
                          className="w-full text-sm font-medium text-gray-900 bg-white border border-gray-300 rounded-lg px-2 py-1.5 focus:ring-2 focus:ring-primary-400 focus:border-transparent"
                        >
                          <option value="">Select a location</option>
                          {barberLocations.map((loc) => (
                            <option key={loc.id} value={loc.name}>
                              {loc.name}{loc.is_primary ? ' (Primary)' : ''}
                            </option>
                          ))}
                        </select>
                      ) : (
                        <input
                          type="text"
                          value={editLocation}
                          onChange={(e) => setEditLocation(e.target.value)}
                          placeholder="Enter location"
                          className="w-full text-base font-medium text-gray-900 bg-white border border-gray-300 rounded-lg px-2 py-1 focus:ring-2 focus:ring-primary-400 focus:border-transparent"
                        />
                      )
                    ) : (
                      <p className="font-medium text-gray-900 text-sm">{selectedConversation.booking.location || 'TBD'}</p>
                    )}
                  </div>

                  {/* Status */}
                  <div className="p-3 bg-gray-50 rounded-xl">
                    <p className="text-xs text-gray-500 mb-1">Status</p>
                    <span className={`inline-flex px-2.5 py-1 rounded-full text-xs font-medium ${
                      selectedConversation.booking.status === 'accepted' || selectedConversation.booking.status === 'confirmed' ? 'bg-green-100 text-green-700' :
                      selectedConversation.booking.status === 'pending' ? 'bg-yellow-100 text-yellow-700' :
                      selectedConversation.booking.status === 'completed' ? 'bg-blue-100 text-blue-700' :
                      selectedConversation.booking.status === 'cancelled' || selectedConversation.booking.status === 'rejected' ? 'bg-red-100 text-red-700' :
                      'bg-gray-100 text-gray-700'
                    }`}>
                      {selectedConversation.booking.status === 'pending' ? 'Awaiting Acceptance' :
                       selectedConversation.booking.status === 'accepted' ? 'Accepted' :
                       selectedConversation.booking.status === 'confirmed' ? 'Confirmed' :
                       selectedConversation.booking.status === 'completed' ? 'Completed' :
                       selectedConversation.booking.status === 'cancelled' ? 'Cancelled' :
                       selectedConversation.booking.status === 'rejected' ? 'Rejected' :
                       selectedConversation.booking.status}
                    </span>
                  </div>

                  {/* Notes */}
                  {selectedConversation.booking.notes && (
                    <div className="p-3 bg-gray-50 rounded-xl">
                      <div className="flex items-center gap-1.5 text-gray-500 mb-1">
                        <FileText className="w-3.5 h-3.5" />
                        <span className="text-xs">Notes</span>
                      </div>
                      <p className="text-gray-900 text-sm">{selectedConversation.booking.notes}</p>
                    </div>
                  )}

                  {/* Barber/Consumer Info */}
                  <div className="p-3 bg-gray-50 rounded-xl">
                    <div className="flex items-center gap-3">
                      <div className="w-9 h-9 rounded-full bg-gray-200 flex items-center justify-center flex-shrink-0">
                        {selectedConversation.otherUser?.profilePicture ? (
                          <img 
                            src={selectedConversation.otherUser.profilePicture} 
                            alt=""
                            className="w-full h-full rounded-full object-cover"
                          />
                        ) : (
                          <User className="w-4 h-4 text-gray-400" />
                        )}
                      </div>
                      <div>
                        <p className="font-medium text-gray-900 text-sm">
                          {selectedConversation.otherUser?.firstName} {selectedConversation.otherUser?.lastName}
                        </p>
                      </div>
                    </div>
                  </div>

                  {/* Action Buttons */}
                  {selectedConversation.booking.status !== 'completed' && 
                   selectedConversation.booking.status !== 'cancelled' && 
                   selectedConversation.booking.status !== 'rejected' && (
                    <div className="flex gap-2 pt-2">
                      {isEditingBooking ? (
                        <>
                          <button
                            onClick={cancelEditingBooking}
                            className="flex-1 flex items-center justify-center gap-2 px-3 py-2.5 bg-gray-100 text-gray-700 rounded-xl hover:bg-gray-200 transition-colors text-sm font-medium"
                            disabled={isSavingEdit}
                          >
                            <ArrowLeft className="w-4 h-4" />
                            Back
                          </button>
                          <button
                            onClick={saveBookingEdits}
                            disabled={isSavingEdit}
                            className="flex-1 flex items-center justify-center gap-2 px-3 py-2.5 bg-primary-600 text-white rounded-xl hover:bg-primary-700 transition-colors text-sm font-medium disabled:opacity-50"
                          >
                            <Check className="w-4 h-4" />
                            {isSavingEdit ? 'Saving...' : 'Save'}
                          </button>
                        </>
                      ) : (
                        <>
                          <button
                            onClick={startEditingBooking}
                            className="flex-1 flex items-center justify-center gap-2 px-3 py-2.5 bg-primary-50 text-primary-700 rounded-xl hover:bg-primary-100 transition-colors text-sm font-medium"
                          >
                            <Pencil className="w-4 h-4" />
                            Edit
                          </button>
                          <button
                            onClick={() => openDeleteConfirm(selectedConversation, new MouseEvent('click') as any)}
                            className="flex-1 flex items-center justify-center gap-2 px-3 py-2.5 bg-red-50 text-red-600 rounded-xl hover:bg-red-100 transition-colors text-sm font-medium"
                          >
                            <XCircle className="w-4 h-4" />
                            Cancel
                          </button>
                        </>
                      )}
                    </div>
                  )}
                </div>
              </>
            ) : (
              <div className="flex flex-col items-center justify-center h-full text-center p-6 bg-gray-50">
                <Info className="w-12 h-12 text-gray-300 mb-3" />
                <h3 className="text-base font-semibold text-gray-600 mb-1">Service Details</h3>
                <p className="text-sm text-gray-500">Select a conversation to view booking details</p>
              </div>
            )}
          </div>
        </div>

        {/* Mobile Layout - Toggle Between List and Chat */}
        <div className="md:hidden h-full">
          {showMobileChat && selectedConversation ? (
            renderChatView()
          ) : (
            renderConversationList()
          )}
        </div>
      </div>

      {/* Service Details Modal - Mobile Only */}
      {showServiceDetails && selectedConversation?.booking && (
        <div 
          className="fixed inset-0 min-h-[100dvh] bg-black/50 z-50 flex items-center justify-center p-4 md:hidden"
          onClick={() => setShowServiceDetails(false)}
        >
          <div 
            className="bg-white rounded-2xl shadow-xl max-w-md w-full max-h-[80dvh] sm:max-h-[80vh] overflow-hidden"
            onClick={(e) => e.stopPropagation()}
          >
            {/* Modal Header */}
            <div className="sticky top-0 bg-gradient-to-r from-primary-500 to-primary-400 px-6 py-4 flex items-center justify-between">
              <div>
                <h2 className="text-xl font-bold text-white">Service Details</h2>
                <p className="text-white/80 text-sm">Booking Information</p>
              </div>
              <button 
                onClick={() => setShowServiceDetails(false)}
                className="text-white hover:bg-white/20 rounded-full p-2 transition-colors"
              >
                <X className="w-6 h-6" />
              </button>
            </div>

            {/* Modal Content */}
            <div className="p-6 space-y-4 overflow-y-auto max-h-[60dvh] sm:max-h-[60vh]">
              {/* Service Name & Price */}
              <div className="flex items-center justify-between p-4 bg-gray-50 rounded-xl">
                <div className="flex items-center gap-3">
                  <div className="w-10 h-10 bg-primary-100 rounded-full flex items-center justify-center">
                    <Scissors className="w-5 h-5 text-primary-600" />
                  </div>
                  <div>
                    <h3 className="font-semibold text-gray-900">{selectedConversation.booking.serviceName}</h3>
                    <p className="text-sm text-gray-500">Service</p>
                  </div>
                </div>
                {selectedConversation.booking.servicePrice && (
                  <div className="text-right">
                    <p className="text-lg font-bold text-gray-900">${selectedConversation.booking.servicePrice}</p>
                  </div>
                )}
              </div>

              {/* Date & Time */}
              {isEditingBooking ? (
                <div className="space-y-4">
                  {/* Date Picker */}
                  <div className="p-4 bg-gray-50 rounded-xl">
                    <DatePicker
                      label="Date"
                      value={editDate}
                      onChange={(newDate) => {
                        setEditDate(newDate);
                        setEditTime(''); // Reset time when date changes
                      }}
                      minDate={new Date().toISOString().split('T')[0]}
                      weeklySchedule={editBarberWeeklySchedule}
                      required
                    />
                  </div>
                  
                  {/* Time Picker */}
                  <div className="p-4 bg-gray-50 rounded-xl">
                    <div className="flex items-center gap-2 text-gray-500 mb-2">
                      <Clock className="w-4 h-4" />
                      <span className="text-xs font-medium">Time</span>
                    </div>
                    <AvailableTimePickerDropdown
                      barberId={editBarberId}
                      date={editDate}
                      value={editTime}
                      onChange={(value) => setEditTime(value)}
                      disabled={!editDate}
                    />
                  </div>
                </div>
              ) : (
                <div className="grid grid-cols-2 gap-4">
                  <div className="p-4 bg-gray-50 rounded-xl">
                    <div className="flex items-center gap-2 text-gray-500 mb-1">
                      <Calendar className="w-4 h-4" />
                      <span className="text-xs">Date</span>
                    </div>
                    <p className="font-medium text-gray-900">
                      {new Date(selectedConversation.booking.scheduledTime).toLocaleDateString('en-US', { 
                        weekday: 'short',
                        month: 'short', 
                        day: 'numeric',
                        year: 'numeric'
                      })}
                    </p>
                  </div>
                  <div className="p-4 bg-gray-50 rounded-xl">
                    <div className="flex items-center gap-2 text-gray-500 mb-1">
                      <Clock className="w-4 h-4" />
                      <span className="text-xs">Time</span>
                    </div>
                    <p className="font-medium text-gray-900">
                      {new Date(selectedConversation.booking.scheduledTime).toLocaleTimeString('en-US', { 
                        hour: 'numeric', 
                        minute: '2-digit'
                      })}
                    </p>
                  </div>
                </div>
              )}

              {/* Location */}
              <div className="p-4 bg-gray-50 rounded-xl">
                <div className="flex items-center gap-2 text-gray-500 mb-1">
                  <MapPin className="w-4 h-4" />
                  <span className="text-xs">Location</span>
                </div>
                {isEditingBooking ? (
                  locationsLoading ? (
                    <div className="text-sm text-gray-500 py-1">Loading locations...</div>
                  ) : barberLocations.length > 0 ? (
                    <select
                      value={editLocation}
                      onChange={(e) => setEditLocation(e.target.value)}
                      className="w-full text-base font-medium text-gray-900 bg-white border border-gray-300 rounded-lg px-3 py-2 focus:ring-2 focus:ring-primary-400 focus:border-transparent"
                    >
                      <option value="">Select a location</option>
                      {barberLocations.map((loc) => (
                        <option key={loc.id} value={loc.name}>
                          {loc.name}{loc.is_primary ? ' (Primary)' : ''}
                        </option>
                      ))}
                    </select>
                  ) : (
                    <input
                      type="text"
                      value={editLocation}
                      onChange={(e) => setEditLocation(e.target.value)}
                      placeholder="Enter location"
                      className="w-full text-base font-medium text-gray-900 bg-white border border-gray-300 rounded-lg px-3 py-2 focus:ring-2 focus:ring-primary-400 focus:border-transparent"
                    />
                  )
                ) : (
                  <>
                    <p className="font-medium text-gray-900">{selectedConversation.booking.location || 'TBD'}</p>
                    {selectedConversation.booking.locationDetails && (
                      <p className="text-sm text-gray-600 mt-1">{selectedConversation.booking.locationDetails}</p>
                    )}
                  </>
                )}
              </div>

              {/* Status */}
              <div className="p-4 bg-gray-50 rounded-xl">
                <div className="flex items-center justify-between">
                  <div>
                    <p className="text-xs text-gray-500 mb-1">Status</p>
                    <span className={`inline-flex px-3 py-1 rounded-full text-sm font-medium ${
                      selectedConversation.booking.status === 'accepted' || selectedConversation.booking.status === 'confirmed' ? 'bg-green-100 text-green-700' :
                      selectedConversation.booking.status === 'pending' ? 'bg-yellow-100 text-yellow-700' :
                      selectedConversation.booking.status === 'completed' ? 'bg-blue-100 text-blue-700' :
                      selectedConversation.booking.status === 'cancelled' || selectedConversation.booking.status === 'rejected' ? 'bg-red-100 text-red-700' :
                      'bg-gray-100 text-gray-700'
                    }`}>
                      {selectedConversation.booking.status === 'pending' ? 'Awaiting Acceptance' :
                       selectedConversation.booking.status === 'accepted' ? 'Accepted' :
                       selectedConversation.booking.status === 'confirmed' ? 'Confirmed' :
                       selectedConversation.booking.status === 'completed' ? 'Completed' :
                       selectedConversation.booking.status === 'cancelled' ? 'Cancelled' :
                       selectedConversation.booking.status === 'rejected' ? 'Rejected' :
                       selectedConversation.booking.status}
                    </span>
                  </div>
                </div>
              </div>

              {/* Notes */}
              {selectedConversation.booking.notes && (
                <div className="p-4 bg-gray-50 rounded-xl">
                  <div className="flex items-center gap-2 text-gray-500 mb-1">
                    <FileText className="w-4 h-4" />
                    <span className="text-xs">Notes</span>
                  </div>
                  <p className="text-gray-900">{selectedConversation.booking.notes}</p>
                </div>
              )}

              {/* Barber/Consumer Info */}
              <div className="p-4 bg-gray-50 rounded-xl">
                <div className="flex items-center gap-3">
                  <div className="w-10 h-10 rounded-full bg-gray-200 flex items-center justify-center flex-shrink-0">
                    {selectedConversation.otherUser?.profilePicture ? (
                      <img 
                        src={selectedConversation.otherUser.profilePicture} 
                        alt=""
                        className="w-full h-full rounded-full object-cover"
                      />
                    ) : (
                      <User className="w-5 h-5 text-gray-400" />
                    )}
                  </div>
                  <div>
                    <p className="font-medium text-gray-900">
                      {selectedConversation.otherUser?.firstName} {selectedConversation.otherUser?.lastName}
                    </p>
                  </div>
                </div>
              </div>
            </div>

            {/* Modal Footer - pt-4 above buttons, pb-4 below last element */}
            <div className="px-6 pt-4 pb-4 border-t border-gray-200 bg-gray-50 space-y-3">
              {selectedConversation.booking.status !== 'completed' && 
               selectedConversation.booking.status !== 'cancelled' && 
               selectedConversation.booking.status !== 'rejected' && (
                <div className="flex gap-2">
                  {isEditingBooking ? (
                    <>
                      <button
                        onClick={cancelEditingBooking}
                        className="flex-1 flex items-center justify-center gap-2 px-4 py-3 bg-gray-100 text-gray-700 rounded-xl hover:bg-gray-200 transition-colors font-medium"
                        disabled={isSavingEdit}
                      >
                        <ArrowLeft className="w-4 h-4" />
                        Back
                      </button>
                      <button
                        onClick={saveBookingEdits}
                        disabled={isSavingEdit}
                        className="flex-1 flex items-center justify-center gap-2 px-4 py-3 bg-primary-600 text-white rounded-xl hover:bg-primary-700 transition-colors font-medium disabled:opacity-50"
                      >
                        <Check className="w-4 h-4" />
                        {isSavingEdit ? 'Saving...' : 'Save'}
                      </button>
                    </>
                  ) : (
                    <>
                      <button
                        onClick={startEditingBooking}
                        className="flex-1 flex items-center justify-center gap-2 px-4 py-3 bg-primary-50 text-primary-700 rounded-xl hover:bg-primary-100 transition-colors font-medium"
                      >
                        <Pencil className="w-4 h-4" />
                        Edit
                      </button>
                      <button
                        onClick={() => {
                          setShowServiceDetails(false);
                          openDeleteConfirm(selectedConversation, new MouseEvent('click') as any);
                        }}
                        className="flex-1 flex items-center justify-center gap-2 px-4 py-3 bg-red-50 text-red-600 rounded-xl hover:bg-red-100 transition-colors font-medium"
                      >
                        <XCircle className="w-4 h-4" />
                        Cancel
                      </button>
                    </>
                  )}
                </div>
              )}
              {!isEditingBooking && (
                <Button
                  onClick={() => setShowServiceDetails(false)}
                  variant="outline"
                  className="w-full"
                >
                  Close
                </Button>
              )}
            </div>
          </div>
        </div>
      )}

      {/* Delete/Cancel Confirmation Modal - Shows "Delete Conversation" for direct chats, "Cancel Booking" for booking chats */}
      {showDeleteConfirm && deletingConversation && (
        <div 
          className="fixed inset-0 min-h-[100dvh] bg-black/50 z-50 flex items-center justify-center p-4"
          onClick={() => {
            setShowDeleteConfirm(false);
            setDeletingConversation(null);
          }}
        >
          <div 
            className="bg-white rounded-2xl shadow-xl max-w-sm w-full overflow-hidden transform transition-all"
            onClick={(e) => e.stopPropagation()}
          >
            {/* Header */}
            <div className="p-6 text-center">
              <h3 className="text-lg font-bold text-gray-900 mb-2">
                {deletingConversation.booking ? 'Cancel Booking?' : 'Delete Conversation?'}
              </h3>
              <p className="text-sm text-gray-600">
                Are you sure you want to {deletingConversation.booking ? 'cancel your booking' : 'delete your conversation'} with{' '}
                <span className="font-semibold">
                  {deletingConversation.otherUser?.firstName} {deletingConversation.otherUser?.lastName}
                </span>
                ? This action cannot be undone.
              </p>
              {deletingConversation.booking && (
                <p className="text-xs text-gray-500 mt-2">
                  Service: {deletingConversation.booking.serviceName}
                </p>
              )}
            </div>

            {/* Actions */}
            <div className="px-6 py-4 bg-gray-50 border-t border-gray-200 flex gap-3">
              <Button
                onClick={() => {
                  setShowDeleteConfirm(false);
                  setDeletingConversation(null);
                }}
                variant="secondary"
                className="flex-1"
              >
                {deletingConversation.booking ? 'Keep Booking' : 'Keep Conversation'}
              </Button>
              <Button
                onClick={handleCancelBooking}
                disabled={isDeleting}
                className="flex-1 bg-red-600 hover:bg-red-700 text-white"
              >
                {isDeleting ? (
                  <div className="w-5 h-5 border-2 border-white border-t-transparent rounded-full animate-spin" />
                ) : (
                  deletingConversation.booking ? 'Cancel Booking' : 'Delete Conversation'
                )}
              </Button>
            </div>
          </div>
        </div>
      )}

      {/* Notifications Modal */}
      {showNotifications && (
        <div 
          className="fixed inset-0 min-h-[100dvh] bg-black/50 z-50 flex items-center justify-center p-4"
          onClick={() => setShowNotifications(false)}
        >
          <div 
            className="bg-white rounded-2xl shadow-xl max-w-md w-full max-h-[80dvh] sm:max-h-[80vh] overflow-hidden transform transition-all"
            onClick={(e) => e.stopPropagation()}
          >
            {/* Header */}
            <div className="bg-gradient-to-r from-primary-500 to-primary-400 px-6 py-4 flex items-center justify-between">
              <div>
                <h2 className="text-xl font-bold text-white">Notifications</h2>
                <p className="text-white/80 text-sm">
                  {unreadNotifications > 0 ? `${unreadNotifications} unread` : 'All caught up!'}
                </p>
              </div>
              <div className="flex items-center gap-2">
                {unreadNotifications > 0 && (
                  <button 
                    onClick={handleMarkAllNotificationsRead}
                    className="text-white/80 hover:text-white text-sm underline"
                  >
                    Mark all read
                  </button>
                )}
                {notifications.length > 0 && (
                  <button 
                    onClick={handleDeleteAllNotifications}
                    className="text-white/80 hover:text-white text-sm underline"
                  >
                    Delete all
                  </button>
                )}
                <button 
                  onClick={() => setShowNotifications(false)}
                  className="text-white hover:bg-white/20 rounded-full p-2 transition-colors"
                >
                  <X className="w-5 h-5" />
                </button>
              </div>
            </div>

            {/* Content */}
            <div className="max-h-[60dvh] sm:max-h-[60vh] overflow-y-auto">
              {notifications.length === 0 ? (
                <div className="p-8 text-center">
                  <Bell className="w-12 h-12 text-gray-300 mx-auto mb-3" />
                  <p className="text-gray-500">No notifications yet</p>
                </div>
              ) : (
                <div className="divide-y divide-gray-100">
                  {notifications.map((notification) => {
                    // Normalize type for matching (handle case/whitespace variations)
                    const notifType = (notification.type || '').toLowerCase().trim();
                    const isMessageNotification = notifType === 'new_message' || notification.title?.toLowerCase().includes('message');
                    
                    // Determine icon and colors based on notification type
                    const getNotificationStyle = () => {
                      if (isMessageNotification) {
                        return { bg: 'bg-primary-100', icon: <MessageCircle className="w-5 h-5 text-primary-600" /> };
                      }
                      switch (notifType) {
                        case 'booking_accepted':
                          return { bg: 'bg-green-100', icon: <Check className="w-5 h-5 text-green-600" /> };
                        case 'booking_rejected':
                        case 'booking_cancelled':
                          return { bg: 'bg-red-100', icon: <AlertCircle className="w-5 h-5 text-red-600" /> };
                        case 'new_booking_request':
                          return { bg: 'bg-primary-100', icon: <Calendar className="w-5 h-5 text-primary-600" /> };
                        default:
                          return { bg: 'bg-primary-100', icon: <Bell className="w-5 h-5 text-primary-600" /> };
                      }
                    };
                    
                    const style = getNotificationStyle();
                    
                    // Parse notification data
                    const data = notification.data ? (typeof notification.data === 'string' ? JSON.parse(notification.data) : notification.data) : {};
                    
                    // Handle click to navigate
                    const handleNotificationClick = () => {
                      if (!notification.is_read) {
                        handleMarkNotificationRead(notification.id);
                      }
                      
                      // Message notifications navigate to the conversation
                      if (isMessageNotification && data.conversationId) {
                        // Navigate to the conversation
                        const conv = conversations.find(c => c.id.toString() === data.conversationId.toString());
                        if (conv) {
                          handleSelectConversation(conv);
                        }
                        setShowNotifications(false);
                      } else {
                        // For other notifications, close modal and stay on current page
                        setShowNotifications(false);
                      }
                    };
                    
                    return (
                      <div 
                        key={notification.id}
                        className={`p-4 hover:bg-gray-50 cursor-pointer transition-colors ${
                          !notification.is_read ? 'bg-primary-50/50' : ''
                        }`}
                        onClick={handleNotificationClick}
                      >
                        <div className="flex items-start gap-3">
                          <div className={`w-10 h-10 rounded-full flex items-center justify-center flex-shrink-0 ${style.bg}`}>
                            {style.icon}
                          </div>
                          <div className="flex-1 min-w-0">
                            <div className="flex items-center justify-between mb-1">
                              <h4 className="font-semibold text-gray-900 text-sm">
                                {notification.title}
                              </h4>
                              {!notification.is_read && (
                                <span className="w-2 h-2 bg-primary-500 rounded-full flex-shrink-0"></span>
                              )}
                            </div>
                            <p className="text-sm text-gray-600 line-clamp-2">
                              {notification.message}
                            </p>
                            <p className="text-xs text-gray-400 mt-1">
                              {formatTime(notification.created_at)}
                            </p>
                          </div>
                        </div>
                      </div>
                    );
                  })}
                </div>
              )}
            </div>

            {/* Footer */}
            <div className="px-6 py-4 border-t border-gray-200 bg-gray-50">
              <Button
                onClick={() => setShowNotifications(false)}
                variant="secondary"
                className="w-full"
              >
                Close
              </Button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

