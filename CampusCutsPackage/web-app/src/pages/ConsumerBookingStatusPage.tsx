/**
 * ConsumerBookingStatusPage - Shows consumer their active booking status
 * Displays pending → accepted flow and any changes made by barber
 */
import { useState, useEffect, useRef } from 'react';
import { useNavigate, useLocation, Link } from 'react-router-dom';
import { 
  Clock, Check, X, Calendar, MapPin, DollarSign, User, 
  MessageCircle, AlertTriangle, Bell, CheckCircle, Pencil,
  ChevronDown, Settings, LogOut, Trash2, FileText
} from 'lucide-react';
import api from '../services/api.service';
import notificationService, { Notification } from '../services/notification.service';
import { useAuthStore } from '../store/useAuthStore';
import { useMessageStore } from '../store/useMessageStore';
import Button from '../components/Button';
import Loading from '../components/Loading';
import { CampusCutLogo } from '@assets';
import Avatar from '../components/Avatar';
import AvailableTimePickerDropdown from '../components/AvailableTimePickerDropdown';
import DatePicker from '../components/DatePicker';
import PullToRefresh from '../components/PullToRefresh';
import barberService from '../services/barber.service';
import type { Barber } from '../types';
import ConsumerProfileEditor, { ConsumerProfileEditorRef } from '../components/ConsumerProfileEditor';
import { useBodyScrollLock } from '../hooks';
import toast from 'react-hot-toast';
import socketService from '../services/socket.service';

interface ActiveBooking {
  id: string;
  barberId: string;
  barberName: string;
  barberAvatar?: string;
  serviceName: string;
  serviceType: string;
  priceUsdCents: number;
  scheduledTime: string;
  location?: string;
  notes?: string;
  status: 'PENDING' | 'ACCEPTED' | 'COMPLETED' | 'CANCELLED';
  createdAt: string;
  // Original values (for detecting edits)
  originalScheduledTime?: string;
  originalLocation?: string;
  // Flags
  hasEdits?: boolean;
  editsAcknowledged?: boolean;
  // Payment tracking
  paymentRequestedAt?: string;
  paidAt?: string;
}

export default function ConsumerBookingStatusPage() {
  const navigate = useNavigate();
  const location = useLocation();
  const platformPrefix = location.pathname.startsWith('/app') ? '/app' : '/web';
  const { user, isLoading: isAuthLoading } = useAuthStore();
  const { unreadCount: unreadMessages, loadUnreadCount } = useMessageStore();
  
  // ALL useState hooks must be declared before any early returns (React Rules of Hooks)
  const [booking, setBooking] = useState<ActiveBooking | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [showProfileDropdown, setShowProfileDropdown] = useState(false);
  const [showProfileEditor, setShowProfileEditor] = useState(false);
  const [isProfileEditorVisible, setIsProfileEditorVisible] = useState(false);
  const profileEditorRef = useRef<ConsumerProfileEditorRef>(null);
  const [showEditModal, setShowEditModal] = useState(false);
  const [showCancelConfirm, setShowCancelConfirm] = useState(false);
  const [editDate, setEditDate] = useState(''); // YYYY-MM-DD format for DatePicker
  const [editTime, setEditTime] = useState('');
  const [editLocation, setEditLocation] = useState('');
  const [editNotes, setEditNotes] = useState('');
  const [editBarber, setEditBarber] = useState<Barber | null>(null);
  const [isLoadingBarber, setIsLoadingBarber] = useState(false);
  const [isSaving, setIsSaving] = useState(false);
  const [cancelReason, setCancelReason] = useState('');
  const [notifications, setNotifications] = useState<Notification[]>([]);
  const [unreadNotifications, setUnreadNotifications] = useState(0);
  const [showNotifications, setShowNotifications] = useState(false);
  const [showDeclinedModal, setShowDeclinedModal] = useState(false);
  const [declinedModalData, setDeclinedModalData] = useState<{
    barberName: string;
    reason: string;
    message: string;
  } | null>(null);
  // State for showing alternative barbers when booking is cancelled by barber
  const [cancelledBookingDetails, setCancelledBookingDetails] = useState<{
    scheduledTime: string;
    serviceType: string;
    campusId: string;
    cancelledBarberId: string;
    barberName: string;
    notificationId?: string; // For marking as read when dismissed
  } | null>(null);
  const [alternativeBarbers, setAlternativeBarbers] = useState<Barber[]>([]);
  const [loadingAlternativeBarbers, setLoadingAlternativeBarbers] = useState(false);
  const dropdownRef = useRef<HTMLDivElement>(null);

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

  useEffect(() => {
    fetchActiveBooking();
    loadUnreadCount(); // Load unread message count on mount
    // Poll for updates every 10 seconds (faster for payment request detection)
    const interval = setInterval(fetchActiveBooking, 10000);
    return () => clearInterval(interval);
  }, []);

  // Lock body scroll when modals are open (except cancel confirm which allows scrolling)
  useEffect(() => {
    if (showEditModal || showNotifications) {
      document.body.style.overflow = 'hidden';
    } else {
      document.body.style.overflow = '';
    }
    return () => {
      document.body.style.overflow = '';
    };
  }, [showEditModal, showNotifications]);

  // Fetch notifications
  useEffect(() => {
    const fetchNotifications = async () => {
      if (!user) return;
      try {
        const data = await notificationService.getNotifications();
        setNotifications(data.notifications);
        setUnreadNotifications(data.unreadCount);
      } catch (error) {
        console.error('Failed to fetch notifications:', error);
      }
    };
    fetchNotifications();
  }, [user?.id]);

  // WebSocket: Listen for booking completion (payment request) in real-time
  useEffect(() => {
    if (!user) return;

    // Ensure socket is connected
    socketService.connect();

    const handleBookingCompleted = (data: {
      bookingId: string;
      barberName: string;
      serviceName: string;
      price: number;
      priceFormatted: string;
      paymentUrl: string;
    }) => {
      console.log('Received booking-completed event:', data);
      
      // Show toast notification
      toast.success(
        `${data.barberName} completed your ${data.serviceName}. Time to pay!`,
        { duration: 5000 }
      );

      // Navigate directly to payment page
      navigate(`${platformPrefix}/payment/${data.bookingId}`);
    };

    socketService.onBookingCompleted(handleBookingCompleted);

    return () => {
      socketService.offBookingCompleted(handleBookingCompleted);
    };
  }, [user?.id, navigate, platformPrefix]);

  // WebSocket: Listen for booking status changes (e.g., barber undoes completion)
  useEffect(() => {
    if (!user || !booking) return;

    // Ensure socket is connected
    socketService.connect();

    const handleStatusChanged = (data: {
      bookingId: string;
      status: string;
      message?: string;
    }) => {
      console.log('Received booking-status-changed event:', data);
      
      // Check if this is for the current booking
      if (data.bookingId === booking.id) {
        // Refresh booking data to get the updated status
        toast.success(data.message || 'Booking status updated');
        fetchActiveBooking();
      }
    };

    socketService.onBookingStatusChanged(handleStatusChanged);

    return () => {
      socketService.offBookingStatusChanged(handleStatusChanged);
    };
  }, [user?.id, booking?.id]);

  // Listen for booking cancellation by barber
  useEffect(() => {
    if (!user?.id || !booking) return;

    socketService.connect();

    const handleBookingUpdate = (data: any) => {
      console.log('Received booking-update event:', data);
      
      // Check if this is for the current booking and it was cancelled by barber
      if (data.id === booking.id && (data.cancelled || data.status?.toUpperCase() === 'CANCELLED')) {
        // Only show alternative barbers if cancelled by barber
        if (data.cancelledBy === 'barber' || data.updatedBy === 'barber') {
          // Save the booking details for showing alternative barbers
          // Use data from WebSocket event (backend sends these now) with fallback to local booking state
          setCancelledBookingDetails({
            scheduledTime: data.scheduledTime || booking.scheduledTime,
            serviceType: data.serviceType || booking.serviceType,
            campusId: data.campusId || '',
            cancelledBarberId: data.barberId || booking.barberId,
            barberName: booking.barberName,
          });
          toast('Your booking has been cancelled by the barber', { icon: 'ℹ️' });
        }
        
        // Clear the current booking to show "No Active Booking" with alternatives
        setBooking(null);
      }
    };

    socketService.onBookingUpdate(handleBookingUpdate);

    return () => {
      socketService.offBookingUpdate(handleBookingUpdate);
    };
  }, [user?.id, booking?.id, booking?.scheduledTime, booking?.serviceType, booking?.barberId, booking?.barberName]);

  // Fetch alternative barbers when booking is cancelled by barber
  useEffect(() => {
    const fetchAlternativeBarbers = async () => {
      if (!cancelledBookingDetails) {
        return;
      }
      
      if (!cancelledBookingDetails.campusId) {
        return;
      }
      
      setLoadingAlternativeBarbers(true);
      try {
        // Parse the scheduled time to get date and time in Pacific timezone
        const scheduledDate = new Date(cancelledBookingDetails.scheduledTime);
        const dateStr = scheduledDate.toLocaleDateString('en-CA', { timeZone: 'America/Los_Angeles' }); // YYYY-MM-DD
        const timeStr = scheduledDate.toLocaleTimeString('en-US', { 
          timeZone: 'America/Los_Angeles', 
          hour: '2-digit', 
          minute: '2-digit', 
          hour12: false 
        }); // HH:MM
        
        // Use the dedicated backend endpoint
        const response = await api.get('/barbers/available-at-time', {
          campusId: cancelledBookingDetails.campusId,
          date: dateStr,
          time: timeStr,
          serviceType: cancelledBookingDetails.serviceType,
          excludeBarberId: cancelledBookingDetails.cancelledBarberId,
        });
        
        const availableBarbers = response.data?.barbers || response.barbers || [];
        
        // Map to Barber type
        setAlternativeBarbers(availableBarbers.map((b: any) => ({
          id: b.id,
          name: b.name,
          profile_picture_url: b.avatar,
          average_rating: b.average_rating,
          total_reviews: b.total_reviews,
        })));
      } catch (error) {
        console.error('[Alternative Barbers] Error fetching:', error);
        setAlternativeBarbers([]);
      } finally {
        setLoadingAlternativeBarbers(false);
      }
    };
    
    fetchAlternativeBarbers();
  }, [cancelledBookingDetails]);

  // Lock body scroll when profile editor is open (must be before any early returns)
  useBodyScrollLock(showProfileEditor);

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
      console.error('Failed to delete notifications:', error);
    }
  };

  const formatNotificationTime = (dateStr: string) => {
    const date = new Date(dateStr);
    const now = new Date();
    const diffMs = now.getTime() - date.getTime();
    const diffMins = Math.floor(diffMs / 60000);
    const diffHours = Math.floor(diffMs / 3600000);
    const diffDays = Math.floor(diffMs / 86400000);

    if (diffMins < 1) return 'Just now';
    if (diffMins < 60) return `${diffMins}m ago`;
    if (diffHours < 24) return `${diffHours}h ago`;
    if (diffDays < 7) return `${diffDays}d ago`;
    return date.toLocaleDateString();
  };

  const fetchActiveBooking = async () => {
    try {
      // Fetch consumer's active bookings (PENDING, ACCEPTED, or COMPLETED awaiting payment)
      // Add timestamp to bust cache after edits
      const response = await api.get('/bookings-simple', { 
        role: 'consumer',
        status: 'PENDING,ACCEPTED,COMPLETED',
        _t: Date.now() // Cache buster
      });
      
      const bookings = response.bookings || [];
      
      // Get the most recent active booking (prioritize COMPLETED awaiting payment, then ACCEPTED, then PENDING)
      const activeBooking = bookings
        .filter((b: any) => b.status === 'PENDING' || b.status === 'ACCEPTED' || b.status === 'COMPLETED')
        .sort((a: any, b: any) => {
          // Prioritize COMPLETED (awaiting payment) over ACCEPTED over PENDING
          const statusPriority: Record<string, number> = { 'COMPLETED': 0, 'ACCEPTED': 1, 'PENDING': 2 };
          const priorityDiff = (statusPriority[a.status] || 3) - (statusPriority[b.status] || 3);
          if (priorityDiff !== 0) return priorityDiff;
          return new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime();
        })[0];
      
      if (activeBooking) {
        // Fetch notifications to check for booking updates
        let hasEdits = false;
        let originalScheduledTime: string | undefined;
        
        let editsAlreadyAcknowledged = false;
        
        try {
          const notifResponse = await notificationService.getNotifications();
          
          // Find the most recent booking_updated notification for this booking
          const updateNotification = notifResponse.notifications
            .filter((n: any) => 
              n.type === 'booking_updated' && 
              n.data?.bookingId === activeBooking.id
            )
            .sort((a: any, b: any) => 
              new Date(b.created_at).getTime() - new Date(a.created_at).getTime()
            )[0];
          
          if (updateNotification && updateNotification.data?.originalScheduledTime) {
            originalScheduledTime = updateNotification.data.originalScheduledTime;
            // Only show edits if the notification is unread (not yet acknowledged)
            const timesAreDifferent = new Date(activeBooking.scheduledTime).getTime() !== 
                       new Date(originalScheduledTime).getTime();
            hasEdits = timesAreDifferent && !updateNotification.is_read;
            editsAlreadyAcknowledged = updateNotification.is_read;
          }
        } catch (notifError) {
          console.error('Failed to fetch notifications for edit detection:', notifError);
        }
        
        setBooking({
          ...activeBooking,
          originalScheduledTime,
          hasEdits,
          editsAcknowledged: editsAlreadyAcknowledged || !hasEdits, // Acknowledged if notification was read or no edits
        });
      } else {
        // No active booking - check for recent cancellation by barber to show alternative barbers
        setBooking(null);
        
        // Check if there's a recent barber-initiated cancellation notification
        try {
          const notifResponse = await notificationService.getNotifications();
          
          // Parse notification data properly - it might be a string or object
          const parseNotificationData = (n: any) => {
            if (!n.data) return {};
            if (typeof n.data === 'string') {
              try {
                return JSON.parse(n.data);
              } catch {
                return {};
              }
            }
            return n.data;
          };
          
          const recentCancellation = notifResponse.notifications
            .filter((n: any) => {
              const data = parseNotificationData(n);
              return n.type === 'booking_cancelled' && 
                data.cancelledBy === 'barber' &&
                data.scheduledTime;
            })
            .sort((a: any, b: any) => 
              new Date(b.created_at).getTime() - new Date(a.created_at).getTime()
            )[0];
          
          // Check for recent cancellation (within last 24 hours) - don't require unread
          // This allows the page to show alternative barbers even after refresh
          const oneDayAgo = new Date(Date.now() - 24 * 60 * 60 * 1000);
          const recentEnough = recentCancellation && 
            new Date(recentCancellation.created_at) > oneDayAgo;
          
          if (recentEnough) {
            const cancellationData = parseNotificationData(recentCancellation);
            
            // Extract barber name from the message (format: "Barber Name has cancelled...")
            const barberNameMatch = recentCancellation.message?.match(/^(.+?) has cancelled/);
            const barberName = barberNameMatch ? barberNameMatch[1] : 'Your barber';
            
            const details = {
              scheduledTime: cancellationData.scheduledTime,
              serviceType: cancellationData.serviceType,
              campusId: cancellationData.campusId || '',
              cancelledBarberId: cancellationData.cancelledBarberId || '',
              barberName,
              notificationId: recentCancellation.id, // Store for marking read later
            };
            setCancelledBookingDetails(details);
            
            // DON'T mark as read yet - wait until user dismisses the view
          }
        } catch (notifError) {
          console.error('Failed to check for cancellation notifications:', notifError);
        }
      }
    } catch (error) {
      console.error('Failed to fetch active booking:', error);
    } finally {
      setIsLoading(false);
    }
  };

  const handleBackToDiscover = () => {
    navigate(`${platformPrefix}/consumer`);
  };

  const handleMessageBarber = () => {
    if (booking) {
      navigate(`${platformPrefix}/consumer/messages`);
    }
  };

  const handleCancelBooking = async () => {
    if (!booking) return;
    setIsSaving(true);
    
    try {
      await api.delete(`/bookings-simple/${booking.id}`, { reason: cancelReason || undefined });
      toast.success('Booking cancelled');
      setShowCancelConfirm(false);
      navigate(`${platformPrefix}/consumer`);
    } catch (error: any) {
      toast.error(error.message || 'Failed to cancel booking');
    } finally {
      setIsSaving(false);
    }
  };

  const handleOpenEditModal = async () => {
    if (!booking) return;
    
    // Initialize edit fields with current booking values
    const scheduledDate = new Date(booking.scheduledTime);
    const year = scheduledDate.getFullYear();
    const month = String(scheduledDate.getMonth() + 1).padStart(2, '0');
    const day = String(scheduledDate.getDate()).padStart(2, '0');
    
    // Set date in YYYY-MM-DD format for DatePicker
    setEditDate(`${year}-${month}-${day}`);
    
    // Set time in 24-hour format (HH:MM) for TimePickerDropdown
    const hours = String(scheduledDate.getHours()).padStart(2, '0');
    const minutes = String(scheduledDate.getMinutes()).padStart(2, '0');
    setEditTime(`${hours}:${minutes}`);
    
    setEditLocation(booking.location || '');
    setEditNotes(booking.notes || '');
    
    setShowEditModal(true);
    
    // Fetch barber data to get weekly schedule for date picker
    setIsLoadingBarber(true);
    try {
      const barber = await barberService.getBarberById(booking.barberId);
      setEditBarber(barber);
      
      // If barber has service locations, auto-select appropriate location
      if (barber.service_locations && barber.service_locations.length > 0) {
        const currentLocation = booking.location || '';
        const locationExists = barber.service_locations.some(loc => loc.name === currentLocation);
        
        // If no location set or current location isn't valid, default to primary or first location
        if (!currentLocation || !locationExists) {
          const primaryLocation = barber.service_locations.find(loc => loc.is_primary);
          const defaultLocation = primaryLocation || barber.service_locations[0];
          setEditLocation(defaultLocation.name);
        }
      }
    } catch (error) {
      console.error('Failed to fetch barber data:', error);
    } finally {
      setIsLoadingBarber(false);
    }
  };

  const handleSaveEdit = async () => {
    if (!booking) return;
    setIsSaving(true);
    
    try {
      // Parse the YYYY-MM-DD date from DatePicker
      if (!editDate) {
        toast.error('Please select a date');
        setIsSaving(false);
        return;
      }
      
      const [year, month, day] = editDate.split('-').map(Number);
      if (isNaN(year) || isNaN(month) || isNaN(day)) {
        toast.error('Invalid date format');
        setIsSaving(false);
        return;
      }
      
      // Parse 24-hour format time from TimePickerDropdown (HH:MM)
      const [hours, minutes] = editTime.split(':').map(Number);
      
      if (isNaN(hours) || isNaN(minutes)) {
        toast.error('Please select a time');
        setIsSaving(false);
        return;
      }
      
      const newScheduledTime = new Date(year, month - 1, day, hours, minutes);
      
      await api.put(`/bookings-simple/${booking.id}`, {
        scheduledTime: newScheduledTime.toISOString(),
        location: editLocation,
        notes: editNotes,
      });
      
      toast.success('Booking updated!');
      setShowEditModal(false);
      fetchActiveBooking(); // Refresh booking data
    } catch (error: any) {
      toast.error(error.message || 'Failed to update booking');
    } finally {
      setIsSaving(false);
    }
  };

  const handleAcknowledgeEdits = async () => {
    if (!booking) return;
    
    try {
      // Find and mark the booking_updated notification as read
      const notifResponse = await notificationService.getNotifications();
      const updateNotification = notifResponse.notifications
        .filter((n: any) => 
          n.type === 'booking_updated' && 
          n.data?.bookingId === booking.id &&
          !n.is_read
        )
        .sort((a: any, b: any) => 
          new Date(b.created_at).getTime() - new Date(a.created_at).getTime()
        )[0];
      
      if (updateNotification) {
        await notificationService.markAsRead(updateNotification.id);
      }
      
      toast.success('Changes acknowledged!');
      setBooking(prev => prev ? { ...prev, editsAcknowledged: true, hasEdits: false } : null);
    } catch (error) {
      console.error('Failed to acknowledge edits:', error);
      // Still update local state even if notification marking fails
      toast.success('Changes acknowledged!');
      setBooking(prev => prev ? { ...prev, editsAcknowledged: true, hasEdits: false } : null);
    }
  };

  const formatDate = (dateStr: string) => {
    const date = new Date(dateStr);
    return date.toLocaleDateString('en-US', {
      weekday: 'long',
      month: 'long',
      day: 'numeric',
      year: 'numeric'
    });
  };

  const formatTime = (dateStr: string) => {
    const date = new Date(dateStr);
    return date.toLocaleTimeString('en-US', {
      hour: 'numeric',
      minute: '2-digit',
      hour12: true
    });
  };

  const formatPrice = (cents: number) => `$${(cents / 100).toFixed(2)}`;

  if (isLoading) {
    return (
      <div className="min-h-[100dvh] bg-gray-50 flex items-center justify-center">
        <div className="text-center">
          <div className="w-12 h-12 border-4 border-primary-200 border-t-primary-500 rounded-full animate-spin mx-auto mb-4" />
          <p className="text-gray-600">Loading your booking...</p>
        </div>
      </div>
    );
  }

  if (!booking) {
    return (
      <div className="min-h-[100dvh] bg-gray-50">
        {/* Header */}
        <div className="bg-white shadow-sm border-b border-gray-200">
          <div className="max-w-2xl mx-auto px-4 py-4 flex items-center justify-between">
            <img src={CampusCutLogo} alt="CampusCut" className="h-8" />
            <button
              onClick={handleBackToDiscover}
              className="text-primary-600 font-semibold hover:text-primary-700"
            >
              Find Barbers
            </button>
          </div>
        </div>
        
        <div className="max-w-2xl mx-auto px-4 py-8">
          {/* Cancelled by Barber - Show Alternative Barbers */}
          {cancelledBookingDetails ? (
            <div className="space-y-6">
              {/* Cancellation Notice */}
              <div className="bg-red-50 border border-red-200 rounded-xl p-4 text-center">
                <h2 className="text-xl font-bold text-red-800 mb-2">Booking Cancelled</h2>
                <p className="text-red-700">
                  <span className="font-semibold">{cancelledBookingDetails.barberName}</span> has cancelled your appointment.
                </p>
              </div>

              {/* Original Time Slot */}
              <div className="bg-primary-50 border border-primary-200 rounded-xl p-4 text-center">
                <h4 className="font-semibold text-primary-800 mb-1">Your Original Time Slot</h4>
                <p className="text-primary-700">
                  {new Date(cancelledBookingDetails.scheduledTime).toLocaleDateString('en-US', {
                    weekday: 'long',
                    month: 'long',
                    day: 'numeric',
                  })} at {new Date(cancelledBookingDetails.scheduledTime).toLocaleTimeString('en-US', {
                    hour: 'numeric',
                    minute: '2-digit',
                    hour12: true,
                  })}
                </p>
              </div>

              {/* Alternative Barbers */}
              <div>
                <h3 className="text-lg font-semibold text-gray-800 mb-3 text-center">
                  {loadingAlternativeBarbers 
                    ? 'Finding available barbers...' 
                    : alternativeBarbers.length > 0 
                      ? `${alternativeBarbers.length} barber${alternativeBarbers.length !== 1 ? 's' : ''} available at this time`
                      : 'No barbers available at this time'
                  }
                </h3>

                {loadingAlternativeBarbers ? (
                  <div className="flex items-center justify-center py-8">
                    <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-primary-500"></div>
                  </div>
                ) : alternativeBarbers.length > 0 ? (
                  <div className="space-y-3">
                    {alternativeBarbers.map((barber) => (
                      <div
                        key={barber.id}
                        className="w-full p-4 bg-white border border-gray-200 rounded-xl shadow-sm"
                      >
                        <div className="flex items-center gap-4">
                          <div className="w-12 h-12 rounded-full bg-gray-200 overflow-hidden flex-shrink-0">
                            {(barber.profile_picture_url || barber.profile_photo_url) ? (
                              <img src={barber.profile_picture_url || barber.profile_photo_url} alt={barber.name} className="w-full h-full object-cover" />
                            ) : (
                              <div className="w-full h-full flex items-center justify-center bg-primary-100">
                                <span className="text-primary-600 font-semibold text-lg">
                                  {barber.name?.charAt(0) || 'B'}
                                </span>
                              </div>
                            )}
                          </div>
                          <div className="flex-1 min-w-0">
                            <p className="font-semibold text-gray-900 truncate">{barber.name}</p>
                            <div className="flex items-center gap-2 text-sm text-gray-500">
                              {barber.average_rating && (
                                <span className="flex items-center gap-1">
                                  ⭐ {barber.average_rating.toFixed(1)}
                                </span>
                              )}
                              {(barber.total_reviews ?? 0) > 0 && (
                                <span>({barber.total_reviews} reviews)</span>
                              )}
                            </div>
                          </div>
                          <button
                            onClick={() => {
                              navigate(`${platformPrefix}/consumer/book/${barber.id}`, {
                                state: {
                                  preselectedDate: cancelledBookingDetails.scheduledTime.split('T')[0],
                                  preselectedService: cancelledBookingDetails.serviceType,
                                }
                              });
                            }}
                            className="flex-shrink-0 py-2 px-3 bg-primary-500 hover:bg-primary-600 text-white font-medium rounded-lg transition-colors text-xs"
                          >
                            Schedule
                          </button>
                        </div>
                      </div>
                    ))}
                  </div>
                ) : (
                  <div className="text-center py-4">
                    <p className="text-gray-500 text-sm">
                      No other barbers are available at this specific time.
                    </p>
                  </div>
                )}
              </div>

              {/* Browse All Barbers Button */}
              <div className="text-center pt-4">
                <button
                  onClick={async () => {
                    // Mark the cancellation notification as read when user dismisses
                    if (cancelledBookingDetails?.notificationId) {
                      try {
                        await notificationService.markAsRead(cancelledBookingDetails.notificationId);
                      } catch (e) {
                        console.error('Failed to mark notification as read:', e);
                      }
                    }
                    setCancelledBookingDetails(null);
                    setAlternativeBarbers([]);
                    handleBackToDiscover();
                  }}
                  className="px-6 py-3 bg-primary-500 hover:bg-primary-600 text-white font-semibold rounded-xl transition-colors"
                >
                  Browse All Barbers
                </button>
              </div>
            </div>
          ) : (
            /* Standard No Active Booking */
            <div className="text-center py-4">
          <Calendar className="w-16 h-16 text-gray-300 mx-auto mb-4" />
          <h2 className="text-2xl font-bold text-gray-900 mb-2">No Active Booking</h2>
          <p className="text-gray-600 mb-6">You don't have any pending or confirmed bookings.</p>
          <button
            onClick={handleBackToDiscover}
            className="px-6 py-3 bg-primary-500 hover:bg-primary-600 text-white font-semibold rounded-xl transition-colors"
          >
            Find a Barber
          </button>
            </div>
          )}
        </div>
      </div>
    );
  }

  const isPending = booking.status === 'PENDING';
  const isAccepted = booking.status === 'ACCEPTED';

  const handleGoToMessages = () => {
    navigate(`${platformPrefix}/consumer/messages`);
  };

  const handleLogout = () => {
    useAuthStore.getState().logout();
    navigate(`${platformPrefix}`);
    setShowProfileDropdown(false);
  };

  // Track if any modal is open for disabling pull-to-refresh
  const isAnyModalOpen = showEditModal || showNotifications || showCancelConfirm || showProfileEditor;
  
  // Close profile editor with animation
  const closeProfileEditor = () => {
    setIsProfileEditorVisible(false);
    setTimeout(() => {
      setShowProfileEditor(false);
    }, 150);
  };

  // Wait for auth to finish loading before rendering
  // This check is placed after all hooks to comply with React's Rules of Hooks
  if (isAuthLoading) {
    return <Loading />;
  }

  return (
    <PullToRefresh onRefresh={() => window.location.reload()} className="min-h-[100dvh] bg-gray-50" disabled={isAnyModalOpen}>
      {/* Header */}
      <div className="bg-white shadow-sm border-b border-gray-200">
        <div className="max-w-2xl mx-auto px-4 py-4 flex items-center justify-between">
          <button
            onClick={handleGoToMessages}
            className="p-2 hover:bg-gray-100 rounded-full transition-colors relative"
          >
            <MessageCircle className="w-6 h-6 text-gray-600" />
            {unreadMessages > 0 && (
              <span className="absolute -top-0.5 -right-0.5 bg-red-500 text-white text-xs font-bold rounded-full min-w-[18px] h-[18px] flex items-center justify-center px-1">
                {unreadMessages > 99 ? '99+' : unreadMessages}
              </span>
            )}
          </button>
          <img src={CampusCutLogo} alt="CampusCut" className="h-10" />
          
          {/* Profile Dropdown */}
          <div className="relative" ref={dropdownRef}>
            <button
              onClick={() => setShowProfileDropdown(!showProfileDropdown)}
              className="flex items-center gap-1 p-1 rounded-full hover:bg-gray-100 transition-colors"
            >
              <Avatar src={user?.profile_picture_url} alt={user?.first_name || 'User'} size="md" />
              <ChevronDown className={`w-5 h-5 text-gray-600 transition-transform ${showProfileDropdown ? 'rotate-180' : ''}`} />
            </button>

            {showProfileDropdown && (
              <div className="absolute right-0 mt-2 w-56 bg-white rounded-lg shadow-lg border border-gray-200 py-1 z-50">
                {/* User Info */}
                <div className="px-4 py-3 border-b border-gray-100">
                  <p className="font-semibold text-gray-900 truncate">{user?.first_name} {user?.last_name}</p>
                  <p className="text-sm text-gray-500 truncate">{user?.email}</p>
                </div>
                
                {/* Notifications */}
                <button
                  onClick={() => {
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
                
                {/* Edit Profile */}
                <button
                  onClick={() => {
                    setShowProfileEditor(true);
                    setTimeout(() => setIsProfileEditorVisible(true), 10);
                    setShowProfileDropdown(false);
                  }}
                  className="w-full px-4 py-2 text-left text-sm text-gray-700 hover:bg-gray-100 flex items-center gap-3"
                >
                  <Settings className="w-4 h-4 text-gray-500" />
                  Edit Profile
                </button>
                
                <div className="border-t border-gray-200 my-1"></div>
                
                {/* Legal Links */}
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
                
                {/* Sign Out */}
                <button
                  onClick={handleLogout}
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

      <div className="max-w-2xl mx-auto px-4 py-6">
        {/* Status Timeline */}
        <div className="bg-white rounded-2xl shadow-sm border border-gray-200 p-6 mb-6">
          <h2 className="text-lg font-bold text-gray-900 mb-6">Booking Status</h2>
          
          <div className="flex items-center justify-between relative">
            {/* Progress Line */}
            <div className="absolute top-5 left-10 right-10 h-1 bg-gray-200 rounded-full">
              <div 
                className={`h-full rounded-full transition-all duration-500 ${
                  isAccepted ? 'w-full bg-green-500' : 'w-0 bg-primary-500'
                }`}
              />
            </div>
            
            {/* Step 1: Pending */}
            <div className="flex flex-col items-center z-10">
              <div className={`w-10 h-10 rounded-full flex items-center justify-center ${
                isPending 
                  ? 'bg-amber-100 text-amber-600 ring-4 ring-amber-50' 
                  : 'bg-green-100 text-green-600'
              }`}>
                {isPending ? <Clock className="w-5 h-5" /> : <Check className="w-5 h-5" />}
              </div>
              <span className={`text-sm mt-2 font-medium ${isPending ? 'text-amber-600' : 'text-green-600'}`}>
                {isPending ? 'Pending' : 'Submitted'}
              </span>
            </div>
            
            {/* Step 2: Accepted */}
            <div className="flex flex-col items-center z-10">
              <div className={`w-10 h-10 rounded-full flex items-center justify-center ${
                isAccepted 
                  ? 'bg-green-100 text-green-600 ring-4 ring-green-50' 
                  : 'bg-gray-100 text-gray-400'
              }`}>
                {isAccepted ? <CheckCircle className="w-5 h-5" /> : <Check className="w-5 h-5" />}
              </div>
              <span className={`text-sm mt-2 font-medium ${isAccepted ? 'text-green-600' : 'text-gray-400'}`}>
                Confirmed
              </span>
            </div>
          </div>
          
          {isPending && (
            <div className="mt-6 p-4 bg-primary-50 rounded-xl border border-primary-100">
              <div className="flex items-start gap-3">
                <Clock className="w-5 h-5 text-primary-500 mt-0.5" />
                <div>
                  <p className="font-semibold text-primary-800">Waiting for barber confirmation</p>
                  <p className="text-sm text-primary-600 mt-1">
                    {booking.barberName} will review and confirm your booking request.
                  </p>
                </div>
              </div>
            </div>
          )}
          
          {isAccepted && (
            <div className="mt-6 p-4 bg-primary-50 rounded-xl border border-primary-100">
              <div className="flex items-start gap-3">
                <CheckCircle className="w-5 h-5 text-primary-500 mt-0.5" />
                <div>
                  <p className="font-semibold text-primary-800">Booking Confirmed!</p>
                  <p className="text-sm text-primary-600 mt-1">
                    Your appointment with {booking.barberName} is confirmed.
                  </p>
                </div>
              </div>
            </div>
          )}
        </div>

        {/* Payment Required Alert */}
        {(() => {
          // Check if payment is required:
          // - Status is COMPLETED (barber marked service complete) and not paid
          // - OR status is ACCEPTED and (payment requested OR 15 mins past scheduled time)
          const scheduledDate = new Date(booking.scheduledTime);
          const fifteenMinsAfter = new Date(scheduledDate.getTime() + 15 * 60 * 1000);
          const now = new Date();
          const isPaymentRequired = !booking.paidAt && (
            booking.status === 'COMPLETED' ||
            (booking.status === 'ACCEPTED' && (booking.paymentRequestedAt || now >= fifteenMinsAfter))
          );
          
          if (!isPaymentRequired) return null;
          
          return (
            <div className="bg-white rounded-2xl shadow-sm border-2 border-primary-400 p-6 mb-6">
              <div className="flex flex-col items-center text-center">
                <h3 className="font-bold text-gray-900 mb-2">Payment Required</h3>
                <p className="text-gray-600 text-sm mb-4">
                  {(booking.status === 'COMPLETED' || booking.paymentRequestedAt)
                    ? `${booking.barberName} has marked your service as complete. Please complete your payment.`
                    : `Your appointment time has passed. Please complete your payment to ${booking.barberName}.`
                  }
                </p>
                
                <button
                  onClick={() => navigate(`${platformPrefix}/payment/${booking.id}`)}
                  className="px-12 py-4 bg-primary-500 hover:bg-primary-600 text-white text-lg font-bold rounded-xl transition-colors"
                >
                  Pay ${(booking.priceUsdCents / 100).toFixed(2)}
                </button>
              </div>
            </div>
          );
        })()}

        {/* Edits Alert */}
        {booking.hasEdits && !booking.editsAcknowledged && (
          <div className="bg-white rounded-2xl shadow-sm border-2 border-amber-300 p-6 mb-6">
            <div className="flex flex-col items-center text-center">
              <div className="w-12 h-12 bg-amber-100 rounded-full flex items-center justify-center mb-4">
                <Pencil className="w-6 h-6 text-amber-600" />
              </div>
              <h3 className="font-bold text-gray-900 mb-2">Barber Made Changes</h3>
              <p className="text-gray-600 text-sm mb-4">
                {booking.barberName} has updated some details of your booking. Please review the changes below.
              </p>
              
              {/* Show what changed */}
              <div className="space-y-2 mb-4">
                {booking.originalScheduledTime && 
                 new Date(booking.scheduledTime).getTime() !== new Date(booking.originalScheduledTime).getTime() && (
                  <div className="flex items-center justify-center gap-2 text-sm flex-wrap">
                    <Calendar className="w-4 h-4 text-amber-500" />
                    <span className="text-gray-500 line-through">
                      {formatDate(booking.originalScheduledTime)} at {formatTime(booking.originalScheduledTime)}
                    </span>
                    <span className="text-gray-900 font-medium">
                      → {formatDate(booking.scheduledTime)} at {formatTime(booking.scheduledTime)}
                    </span>
                  </div>
                )}
              </div>
              
              <div className="flex gap-3 w-full max-w-md">
                <button
                  onClick={handleAcknowledgeEdits}
                  className="flex-1 py-2.5 bg-primary-500 hover:bg-primary-600 text-white font-semibold rounded-lg transition-colors flex items-center justify-center"
                >
                  OK with Changes
                </button>
                <button
                  onClick={handleMessageBarber}
                  className="flex-1 py-2.5 bg-gray-100 hover:bg-gray-200 text-gray-700 font-semibold rounded-lg transition-colors flex items-center justify-center gap-2"
                >
                  <MessageCircle className="w-4 h-4" />
                  Message Barber
                </button>
              </div>
            </div>
          </div>
        )}

        {/* Booking Details */}
        <div className="bg-white rounded-2xl shadow-sm border border-gray-200 p-6 mb-6">
          <h3 className="font-bold text-gray-900 mb-4">Booking Details</h3>
          
          {/* Barber Info */}
          <div className="flex items-center gap-4 p-4 bg-gray-50 rounded-xl mb-4">
            <div className="w-14 h-14 rounded-full bg-primary-100 flex items-center justify-center">
              {booking.barberAvatar ? (
                <img src={booking.barberAvatar} alt={booking.barberName} className="w-14 h-14 rounded-full object-cover" />
              ) : (
                <User className="w-7 h-7 text-primary-600" />
              )}
            </div>
            <div>
              <p className="text-sm text-gray-500">Barber</p>
              <p className="font-bold text-gray-900">{booking.barberName}</p>
            </div>
          </div>
          
          {/* Service & Price */}
          <div className="flex items-center justify-between p-4 bg-primary-50 rounded-xl mb-4">
            <div>
              <p className="text-sm text-gray-500">Service</p>
              <p className="font-semibold text-gray-900">{booking.serviceName || booking.serviceType}</p>
            </div>
            <p className="text-2xl font-bold text-primary-600">{formatPrice(booking.priceUsdCents)}</p>
          </div>
          
          {/* Date & Time */}
          <div className="grid grid-cols-2 gap-4 mb-4">
            <div className="p-4 bg-gray-50 rounded-xl">
              <div className="flex items-center gap-2 mb-1">
                <Calendar className="w-4 h-4 text-primary-500" />
                <span className="text-sm text-gray-500">Date</span>
              </div>
              <p className="font-semibold text-gray-900">{formatDate(booking.scheduledTime)}</p>
            </div>
            <div className="p-4 bg-gray-50 rounded-xl">
              <div className="flex items-center gap-2 mb-1">
                <Clock className="w-4 h-4 text-primary-500" />
                <span className="text-sm text-gray-500">Time</span>
              </div>
              <p className="font-semibold text-gray-900">{formatTime(booking.scheduledTime)}</p>
            </div>
          </div>
          
          {/* Location */}
          {booking.location && (
            <div className="p-4 bg-gray-50 rounded-xl mb-4">
              <div className="flex items-center gap-2 mb-1">
                <MapPin className="w-4 h-4 text-primary-500" />
                <span className="text-sm text-gray-500">Location</span>
              </div>
              <p className="font-semibold text-gray-900">{booking.location}</p>
            </div>
          )}
          
          {/* Notes */}
          {booking.notes && (
            <div className="p-4 bg-gray-50 rounded-xl">
              <p className="text-sm text-gray-500 mb-1">Your Notes</p>
              <p className="text-gray-700 italic">"{booking.notes}"</p>
            </div>
          )}
        </div>

        {/* Actions */}
        <div className="space-y-3">
          {/* Message button only shows after barber accepts (messaging locked during pending) */}
          {isAccepted && (
            <button
              onClick={handleMessageBarber}
              className="w-full py-3.5 bg-primary-500 hover:bg-primary-600 text-white font-semibold rounded-xl transition-colors flex items-center justify-center gap-2"
            >
              <MessageCircle className="w-5 h-5" />
              Message {booking.barberName}
            </button>
          )}
          
          {/* Edit and Cancel buttons for pending and accepted bookings (hidden if payment requested) */}
          {(isPending || isAccepted) && !booking.paymentRequestedAt && (
            <div className="grid grid-cols-2 gap-3">
              <button
                onClick={handleOpenEditModal}
                className="py-3 bg-amber-50 hover:bg-amber-100 text-amber-700 font-semibold rounded-xl transition-colors flex items-center justify-center gap-2 border border-amber-200"
              >
                <Pencil className="w-4 h-4" />
                Edit Booking
              </button>
              <button
                onClick={() => setShowCancelConfirm(true)}
                className="py-3 bg-red-50 hover:bg-red-100 text-red-600 font-semibold rounded-xl transition-colors flex items-center justify-center gap-2 border border-red-200"
              >
                <X className="w-4 h-4" />
                Cancel
              </button>
            </div>
          )}
        </div>
        
        {/* Booking Reference */}
        <div className="text-center mt-6">
          <p className="text-xs text-gray-400">Booking Reference</p>
          <p className="font-mono text-sm text-gray-600">{booking.id.slice(0, 8).toUpperCase()}</p>
        </div>
      </div>

      {/* Edit Modal */}
      {showEditModal && (
        <div className="fixed inset-0 min-h-[100dvh] bg-black/50 z-50 flex items-center justify-center p-4" onClick={() => setShowEditModal(false)}>
          <form 
            className="bg-white rounded-2xl shadow-xl max-w-md w-full max-h-[85dvh] sm:max-h-[90vh] overflow-y-auto p-6" 
            onClick={e => e.stopPropagation()}
            onSubmit={(e) => {
              e.preventDefault();
              handleSaveEdit();
            }}
          >
            <h3 className="text-xl font-bold text-gray-900 mb-4 flex items-center gap-2">
              <Pencil className="w-5 h-5 text-primary-500" />
              Edit Booking
            </h3>
            
            <div className="space-y-4">
              {/* Date Picker - shows calendar with barber's availability */}
              {isLoadingBarber ? (
                <div className="flex items-center justify-center py-8">
                  <div className="w-6 h-6 border-2 border-primary-200 border-t-primary-500 rounded-full animate-spin" />
                  <span className="ml-2 text-gray-500 text-sm">Loading availability...</span>
                </div>
              ) : (
                <DatePicker
                  label="Date"
                  value={editDate}
                  onChange={(newDate) => {
                    setEditDate(newDate);
                    // Reset time when date changes since availability may differ
                    setEditTime('');
                  }}
                  minDate={new Date().toISOString().split('T')[0]}
                  weeklySchedule={editBarber?.weekly_schedule}
                />
              )}
              
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">Time</label>
                <AvailableTimePickerDropdown
                  barberId={booking.barberId}
                  date={editDate}
                  value={editTime}
                  onChange={setEditTime}
                />
              </div>
              
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">Location</label>
                {editBarber?.service_locations && editBarber.service_locations.length > 0 ? (
                  <select
                    value={editLocation}
                    onChange={(e) => setEditLocation(e.target.value)}
                    className="w-full px-4 py-3 border border-gray-300 rounded-lg focus:ring-2 focus:ring-primary-400 focus:border-transparent bg-white"
                  >
                    <option value="">Select a location</option>
                    {editBarber.service_locations.map((location) => (
                      <option key={location.id} value={location.name}>
                        {location.name}{location.is_primary ? ' (Primary)' : ''}
                      </option>
                    ))}
                  </select>
                ) : (
                <input
                  type="text"
                  value={editLocation}
                  onChange={(e) => setEditLocation(e.target.value)}
                  placeholder="Where should the appointment take place?"
                  className="w-full px-4 py-3 border border-gray-300 rounded-lg focus:ring-2 focus:ring-primary-400 focus:border-transparent"
                />
                )}
              </div>
              
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">Notes</label>
                <textarea
                  value={editNotes}
                  onChange={(e) => setEditNotes(e.target.value)}
                  placeholder="Any special requests or notes for your barber..."
                  rows={3}
                  className="w-full px-4 py-3 border border-gray-300 rounded-lg focus:ring-2 focus:ring-primary-400 focus:border-transparent resize-none"
                />
              </div>
            </div>
            
            <div className="flex gap-3 mt-6">
              <button
                type="button"
                onClick={() => setShowEditModal(false)}
                className="flex-1 py-3 bg-gray-100 hover:bg-gray-200 text-gray-700 font-semibold rounded-xl transition-colors"
              >
                Cancel
              </button>
              <button
                type="submit"
                disabled={isSaving}
                className="flex-1 py-3 bg-primary-500 hover:bg-primary-600 text-white font-semibold rounded-xl transition-colors flex items-center justify-center gap-2 disabled:opacity-50"
              >
                {isSaving ? (
                  <>
                    <div className="w-4 h-4 border-2 border-white/30 border-t-white rounded-full animate-spin" />
                    Saving...
                  </>
                ) : (
                  'Save Changes'
                )}
              </button>
            </div>
          </form>
        </div>
      )}

      {/* Cancel Confirmation Modal */}
      {showCancelConfirm && (
        <div className="fixed inset-0 min-h-[100dvh] bg-black/50 z-50 flex items-center justify-center p-4" onClick={() => setShowCancelConfirm(false)}>
          <div className="bg-white rounded-2xl shadow-xl max-w-md w-full max-h-[85dvh] sm:max-h-[90vh] overflow-y-auto p-6" onClick={e => e.stopPropagation()}>
            <h3 className="text-xl font-bold text-gray-900 mb-2 flex items-center gap-2">
              <Trash2 className="w-5 h-5 text-red-500" />
              Cancel Booking
            </h3>
            <p className="text-gray-600 mb-4">Are you sure you want to cancel this booking? This action cannot be undone.</p>
            
            <div className="mb-4">
              <label className="block text-sm font-medium text-gray-700 mb-1">Reason (optional)</label>
              <textarea
                value={cancelReason}
                onChange={(e) => setCancelReason(e.target.value)}
                placeholder="Let the barber know why you're cancelling..."
                rows={3}
                className="w-full px-4 py-3 border border-gray-300 rounded-lg focus:ring-2 focus:ring-red-400 focus:border-transparent resize-none"
              />
            </div>
            
            <div className="flex gap-3">
              <button
                onClick={() => {
                  setShowCancelConfirm(false);
                  setCancelReason('');
                }}
                className="flex-1 py-3 bg-gray-100 hover:bg-gray-200 text-gray-700 font-semibold rounded-xl transition-colors"
              >
                Keep Booking
              </button>
              <button
                onClick={handleCancelBooking}
                disabled={isSaving}
                className="flex-1 py-3 bg-red-500 hover:bg-red-600 text-white font-semibold rounded-xl transition-colors flex items-center justify-center gap-2 disabled:opacity-50"
              >
                {isSaving ? (
                  <>
                    <div className="w-4 h-4 border-2 border-white/30 border-t-white rounded-full animate-spin" />
                    Cancelling...
                  </>
                ) : (
                  'Yes, Cancel'
                )}
              </button>
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
            className="bg-white rounded-2xl shadow-xl max-w-md w-full max-h-[85dvh] sm:max-h-[80vh] overflow-hidden transform transition-all"
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
            <div className="max-h-[60vh] overflow-y-auto">
              {notifications.length === 0 ? (
                <div className="p-8 text-center">
                  <Bell className="w-12 h-12 text-gray-300 mx-auto mb-3" />
                  <p className="text-gray-500">No notifications yet</p>
                </div>
              ) : (
                <div className="divide-y divide-gray-100">
                  {notifications.map((notification) => {
                    const notifType = (notification.type || '').toLowerCase().trim();
                    const isMessageNotification = notifType === 'new_message' || notification.title?.toLowerCase().includes('message');
                    
                    const getNotificationStyle = () => {
                      if (isMessageNotification) {
                        return { bg: 'bg-primary-100', icon: <MessageCircle className="w-5 h-5 text-primary-600" /> };
                      }
                      switch (notifType) {
                        case 'booking_accepted':
                          return { bg: 'bg-green-100', icon: <Check className="w-5 h-5 text-green-600" /> };
                        case 'booking_rejected':
                        case 'booking_cancelled':
                          return { bg: 'bg-red-100', icon: <AlertTriangle className="w-5 h-5 text-red-600" /> };
                        case 'new_booking_request':
                          return { bg: 'bg-primary-100', icon: <Calendar className="w-5 h-5 text-primary-600" /> };
                        default:
                          return { bg: 'bg-primary-100', icon: <Bell className="w-5 h-5 text-primary-600" /> };
                      }
                    };
                    
                    const style = getNotificationStyle();
                    const data = notification.data ? (typeof notification.data === 'string' ? JSON.parse(notification.data) : notification.data) : {};
                    
                    const handleNotificationClick = () => {
                      if (!notification.is_read) {
                        handleMarkNotificationRead(notification.id);
                      }
                      
                      if (isMessageNotification && data.conversationId) {
                        navigate(`${platformPrefix}/consumer/messages/${data.conversationId}`);
                        setShowNotifications(false);
                      } else if (notification.type === 'booking_rejected') {
                        // Booking declined - show decline details modal
                        const barberNameMatch = notification.message?.match(/^(.+?) was unable to accept/);
                        const barberName = barberNameMatch ? barberNameMatch[1] : 'The barber';
                        setDeclinedModalData({
                          barberName,
                          reason: data.reason || '',
                          message: notification.message || '',
                        });
                        setShowDeclinedModal(true);
                        setShowNotifications(false);
                      } else {
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
                              {formatNotificationTime(notification.created_at)}
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

      {/* Booking Declined Modal */}
      {showDeclinedModal && declinedModalData && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4">
          <div 
            className="absolute inset-0 bg-black/50 backdrop-blur-sm"
            onClick={() => {
              setShowDeclinedModal(false);
              setDeclinedModalData(null);
            }}
          />
          <div className="relative bg-white rounded-2xl shadow-2xl max-w-md w-full overflow-hidden animate-slide-up">
            {/* Header */}
            <div className="bg-gradient-to-r from-red-500 to-red-600 px-6 py-4 flex items-center justify-center relative">
              <div className="flex flex-col items-center text-center">
                <h2 className="text-xl font-bold text-white">Booking Declined</h2>
              </div>
              <button 
                className="absolute right-4 top-4 p-2 hover:bg-white/20 rounded-lg transition-colors"
                onClick={() => {
                  setShowDeclinedModal(false);
                  setDeclinedModalData(null);
                }}
              >
                <X className="w-5 h-5 text-white" />
              </button>
            </div>

            {/* Content */}
            <div className="p-6">
              <div className="text-center mb-6">
                <p className="text-gray-600">
                  <span className="font-semibold text-gray-900">{declinedModalData.barberName}</span> was unable to accept your booking request.
                </p>
              </div>

              {/* Reason Section */}
              {declinedModalData.reason && (
                <div className="bg-red-50 border border-red-200 rounded-xl p-4 mb-6">
                  <h4 className="font-semibold text-red-800 mb-2 flex items-center gap-2">
                    <AlertTriangle className="w-4 h-4" />
                    Reason for Declining
                  </h4>
                  <p className="text-red-700 text-sm">{declinedModalData.reason}</p>
                </div>
              )}

              {/* Support Contact */}
              <div className="bg-amber-50 border border-amber-200 rounded-lg p-3 text-center">
                <p className="text-sm text-amber-800">
                  Think a mistake was made? Contact us at{' '}
                  <a href="mailto:campuscuthelp@gmail.com" className="font-medium underline">
                    campuscuthelp@gmail.com
                  </a>
                </p>
              </div>
            </div>

            {/* Footer */}
            <div className="px-6 py-4 bg-gray-50 border-t">
              <button
                onClick={() => {
                  setShowDeclinedModal(false);
                  setDeclinedModalData(null);
                  navigate(`${platformPrefix}/consumer`);
                }}
                className="w-full px-6 py-2.5 bg-primary-600 text-white rounded-lg font-semibold hover:bg-primary-700 transition-colors"
              >
                Find Another Barber
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Profile Editor Modal */}
      {showProfileEditor && (
        <div 
          className={`fixed inset-0 min-h-[100dvh] flex items-center justify-center z-50 p-2 sm:p-4 transition-all duration-150 ease-out ${
            isProfileEditorVisible ? 'bg-black/50' : 'bg-black/0'
          }`}
          onClick={closeProfileEditor}
        >
          <div 
            className={`bg-white rounded-xl shadow-2xl max-w-lg w-full max-h-[85dvh] sm:max-h-[80vh] overflow-y-auto transition-all duration-150 ease-out ${
              isProfileEditorVisible ? 'opacity-100 scale-100 translate-y-0' : 'opacity-0 scale-95 -translate-y-2'
            }`}
            onClick={(e) => e.stopPropagation()}
          >
            <div className="sticky top-0 bg-white border-b border-gray-200 px-4 sm:px-6 py-3 sm:py-4 flex items-center justify-between rounded-t-xl z-10">
              <h2 className="text-lg sm:text-xl font-bold text-gray-900">Edit Profile</h2>
              <div className="flex items-center gap-2">
                <button
                  onClick={() => profileEditorRef.current?.showDeleteModal()}
                  className="bg-red-100 text-red-600 hover:bg-red-200 hover:text-red-700 rounded-lg px-3 py-1.5 transition-colors flex items-center gap-1.5 text-sm font-medium border border-red-200"
                  title="Delete Account"
                >
                  <Trash2 className="w-4 h-4" />
                  <span>Delete Account</span>
                </button>
                <button
                  onClick={closeProfileEditor}
                  className="text-gray-400 hover:text-gray-600 hover:bg-gray-100 rounded-full p-1 transition-colors"
                >
                  ×
                </button>
              </div>
            </div>
            <div className="p-6">
              <ConsumerProfileEditor ref={profileEditorRef} userId={user?.id || ''} />
            </div>
          </div>
        </div>
      )}
    </PullToRefresh>
  );
}

