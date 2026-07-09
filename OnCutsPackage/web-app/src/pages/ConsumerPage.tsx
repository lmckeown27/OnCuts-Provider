// @ts-nocheck
import { useState, useEffect, useRef } from 'react';
import { useNavigate, useLocation, Link } from 'react-router-dom';
import { Users as UsersIcon, User as UserIcon, Calendar, Settings, LogOut, ChevronDown, Instagram, Scissors, ArrowLeft, Menu, MessageCircle, Clock, MapPin, Bell, X, AlertCircle, Check, Trash2, Star, FileText } from 'lucide-react';
import Avatar from '../components/Avatar';
import Card from '../components/Card';
import Button from '../components/Button';
import Loading from '../components/Loading';
import ConsumerProfileEditor, { ConsumerProfileEditorRef } from '../components/ConsumerProfileEditor';
import BarberApplicationModal from '../components/BarberApplicationModal';
import type { FilterCriteria } from '../types/barber-filters';
import barberService from '../services/barber.service';
import notificationService, { Notification } from '../services/notification.service';
import api from '../services/api.service';
import { barberApplicationService } from '../services/barber-application.service';
import type { Barber } from '../types';
import type { University } from '../components/UniversitySelector';
import toast from 'react-hot-toast';
import { CampusCutLogo } from '@assets';
import { useAuthStore } from '../store/useAuthStore';
import { useMessageStore } from '../store/useMessageStore';
import { useViewport, useBodyScrollLock, calculateDistance, kmToMiles, useDynamicViewportHeight } from '../hooks';
import LoginPrompt from '../components/LoginPrompt';
import PaymentRequestModal from '../components/PaymentRequestModal';
import PullToRefresh from '../components/PullToRefresh';
import type { WeeklySchedule } from '../types';
import socketService from '../services/socket.service';

// Storage keys
const UNIVERSITY_STORAGE_KEY = 'campuscut_selected_university';

// Helper to format service names from SNAKE_CASE to Title Case
const formatServiceName = (name: string): string => {
  return name
    .toLowerCase()
    .split('_')
    .map(word => word.charAt(0).toUpperCase() + word.slice(1))
    .join(' ');
};
const FILTER_STORAGE_KEY = 'campuscut_filter_criteria';

// Format time from 24h to 12h format (e.g., "09:00" -> "9am", "17:00" -> "5pm")
function formatTime(time24: string | undefined | null): string {
  if (!time24 || typeof time24 !== 'string' || !time24.includes(':')) {
    return 'N/A';
  }
  const [hourStr, minuteStr] = time24.split(':');
  let hour = parseInt(hourStr, 10);
  const minute = parseInt(minuteStr, 10);
  if (isNaN(hour) || isNaN(minute)) return 'N/A';
  const ampm = hour >= 12 ? 'pm' : 'am';
  hour = hour % 12 || 12;
  return minute === 0 ? `${hour}${ampm}` : `${hour}:${minuteStr}${ampm}`;
}

// Format schedule for display - returns array of { day, times } objects
// Supports both new multi-interval format and legacy single interval format
function formatSchedule(schedule: WeeklySchedule | undefined): { day: string; times: string }[] {
  if (!schedule) return [];
  
  const dayOrder = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'] as const;
  const dayAbbrev: Record<string, string> = {
    monday: 'Mon', tuesday: 'Tue', wednesday: 'Wed', thursday: 'Thu',
    friday: 'Fri', saturday: 'Sat', sunday: 'Sun'
  };
  
  return dayOrder
    .filter(day => {
      const daySchedule = schedule[day];
      if (!daySchedule?.enabled) return false;
      
      // Check for new multi-interval format
      if (daySchedule.intervals !== undefined) {
        return Array.isArray(daySchedule.intervals) && daySchedule.intervals.length > 0;
      }
      
      // Legacy format
      return daySchedule.start && daySchedule.end;
    })
    .map(day => {
      const daySchedule = schedule[day];
      let times: string;
      
      // Check for new multi-interval format
      if (daySchedule.intervals && Array.isArray(daySchedule.intervals) && daySchedule.intervals.length > 0) {
        // Filter out invalid intervals and show all valid ones (e.g., "9am-12pm, 2pm-6pm")
        const validIntervals = daySchedule.intervals.filter(
          interval => interval && interval.start && interval.end
        );
        times = validIntervals.length > 0
          ? validIntervals.map(interval => `${formatTime(interval.start)}-${formatTime(interval.end)}`).join(', ')
          : 'Available';
      } else if (daySchedule.start && daySchedule.end) {
        // Legacy format
        times = `${formatTime(daySchedule.start)}-${formatTime(daySchedule.end)}`;
      } else {
        times = 'Available';
      }
      
      return {
        day: dayAbbrev[day],
        times
      };
    });
}

// Fisher-Yates shuffle for fair random ordering of barbers
// This gives every barber an equal chance of being seen first
function shuffleBarbers(barbers: Barber[]): Barber[] {
  const shuffled = [...barbers];
  for (let i = shuffled.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [shuffled[i], shuffled[j]] = [shuffled[j], shuffled[i]];
  }
  return shuffled;
}

export default function ConsumerPage() {
  const navigate = useNavigate();
  const location = useLocation();
  
  // Handle dynamic viewport height for mobile browser bar changes
  useDynamicViewportHeight();
  
  // Message store for unread count
  const { unreadCount: unreadMessages, loadUnreadCount } = useMessageStore();
  
  const [showProfileDropdown, setShowProfileDropdown] = useState(false);
  const [showProfileEditor, setShowProfileEditor] = useState(false);
  const [isProfileEditorVisible, setIsProfileEditorVisible] = useState(false);
  const profileEditorRef = useRef<ConsumerProfileEditorRef>(null);
  const [showBarberApplication, setShowBarberApplication] = useState(false);
  const [hasPendingApplication, setHasPendingApplication] = useState(false);
  const [hasRejectedApplication, setHasRejectedApplication] = useState(false);
  const [notifications, setNotifications] = useState<Notification[]>([]);
  const [unreadNotifications, setUnreadNotifications] = useState(0);
  const [showNotifications, setShowNotifications] = useState(false);
  const [isNotificationsVisible, setIsNotificationsVisible] = useState(false);
  const [showPendingPopup, setShowPendingPopup] = useState(false);
  const [isPendingPopupVisible, setIsPendingPopupVisible] = useState(false);
  const [showRejectedPopup, setShowRejectedPopup] = useState(false);
  const [isRejectedPopupVisible, setIsRejectedPopupVisible] = useState(false);
  const [showLoginPrompt, setShowLoginPrompt] = useState(false);
  const [showPaymentModal, setShowPaymentModal] = useState(false);
  const [paymentModalData, setPaymentModalData] = useState<{
    bookingId: string;
    barberName: string;
    serviceName: string;
    amount: number;
  } | null>(null);
  const [showDeclinedModal, setShowDeclinedModal] = useState(false);
  const [declinedModalData, setDeclinedModalData] = useState<{
    barberName: string;
    reason: string;
    message: string;
  } | null>(null);
  const [showAlternativeBarbersModal, setShowAlternativeBarbersModal] = useState(false);
  const [alternativeBarbersData, setAlternativeBarbersData] = useState<{
    scheduledTime: string;
    serviceType: string;
    campusId: string;
    cancelledBarberId: string;
    barberName: string;
    reason?: string;
  } | null>(null);
  const [alternativeBarbers, setAlternativeBarbers] = useState<Barber[]>([]);
  const [loadingAlternativeBarbers, setLoadingAlternativeBarbers] = useState(false);
  const dropdownRef = useRef<HTMLDivElement>(null);
  
  // Preserve form data from ScheduleServicePage when user clicks back
  const preservedFormData = location.state?.preservedFormData;
  
  // Viewport detection for responsive behavior
  const { isMobile, isTablet, viewport } = useViewport();
  
  // Track if any modal is open for disabling pull-to-refresh
  const isAnyModalOpen = showProfileEditor || showBarberApplication || showNotifications || showPendingPopup || showRejectedPopup || showLoginPrompt || showPaymentModal || showDeclinedModal || showAlternativeBarbersModal;
  
  // Lock body scroll when profile editor is open
  useBodyScrollLock(showProfileEditor);
  
  // Helper to scroll to top before opening modals (prevents white space on mobile)
  const scrollToTopAndOpen = (setShow: (v: boolean) => void, setVisible?: (v: boolean) => void) => {
    window.scrollTo({ top: 0, behavior: 'instant' });
    setShow(true);
    if (setVisible) {
      requestAnimationFrame(() => {
        requestAnimationFrame(() => {
          setVisible(true);
        });
      });
    }
  };
  
  // Profile editor open/close with animation
  const openProfileEditor = () => {
    scrollToTopAndOpen(setShowProfileEditor, setIsProfileEditorVisible);
  };
  
  const closeProfileEditor = () => {
    setIsProfileEditorVisible(false);
    setTimeout(() => {
      setShowProfileEditor(false);
    }, 150);
  };
  
  // Determine platform prefix based on current route
  const platformPrefix = location.pathname.startsWith('/app') ? '/app' : '/web';
  
  // Get consumer ID from auth
  const { user, setUser, isLoading: isAuthLoading } = useAuthStore();
  const consumerId = user?.id || '';
  
  // NOTE: isAuthLoading check is moved to the return statement below
  // to avoid violating React's Rules of Hooks (no early returns before hooks)
  
  // Check for active bookings and redirect to booking status page
  useEffect(() => {
    const checkActiveBookings = async () => {
      if (!user) return;
      
      try {
        const response = await api.get('/bookings-simple', { role: 'consumer' });
        const bookings = response.bookings || [];
        
        // Check if user has any PENDING or ACCEPTED bookings
        const activeBooking = bookings.find(
          (b: any) => b.status === 'PENDING' || b.status === 'ACCEPTED'
        );
        
        if (activeBooking) {
          // Redirect to booking status page
          navigate(`${platformPrefix}/consumer/booking-status`, { replace: true });
        }
      } catch (error) {
        console.error('Failed to check active bookings:', error);
      }
    };
    
    checkActiveBookings();
  }, [user?.id, platformPrefix, navigate]);

  // Check for barber profile if not already known
  useEffect(() => {
    const checkBarberProfile = async () => {
      if (user && user.has_barber_profile === undefined) {
        try {
          const barberProfile = await barberService.getBarberByUserId(user.id);
          // Only consider as having barber profile if it exists AND is active
          // Demoted barbers have is_active = false
          if (barberProfile && barberProfile.is_active !== false) {
            setUser({ ...user, has_barber_profile: true });
          } else {
            setUser({ ...user, has_barber_profile: false });
          }
        } catch {
          // No barber profile found
          setUser({ ...user, has_barber_profile: false });
        }
      }
    };
    checkBarberProfile();
  }, [user?.id]);

  // Check for pending or rejected barber application
  useEffect(() => {
    const checkApplicationStatus = async () => {
      if (user && !user.has_barber_profile) {
        try {
          const application = await barberApplicationService.getMyApplication();
          if (application) {
            if (application.status === 'pending' || application.status === 'under_review' || application.status === 'interview_scheduled') {
              setHasPendingApplication(true);
              setHasRejectedApplication(false);
            } else if (application.status === 'rejected') {
              setHasPendingApplication(false);
              setHasRejectedApplication(true);
            } else {
              setHasPendingApplication(false);
              setHasRejectedApplication(false);
            }
          } else {
            setHasPendingApplication(false);
            setHasRejectedApplication(false);
          }
        } catch {
          setHasPendingApplication(false);
          setHasRejectedApplication(false);
        }
      }
    };
    checkApplicationStatus();
  }, [user?.id, user?.has_barber_profile]);

  // Pending application popup handlers
  const openPendingPopup = () => {
    scrollToTopAndOpen(setShowPendingPopup, setIsPendingPopupVisible);
  };

  const closePendingPopup = () => {
    setIsPendingPopupVisible(false);
    setTimeout(() => {
      setShowPendingPopup(false);
    }, 150);
  };

  // Rejected application popup handlers
  const openRejectedPopup = () => {
    scrollToTopAndOpen(setShowRejectedPopup, setIsRejectedPopupVisible);
  };

  const closeRejectedPopup = () => {
    setIsRejectedPopupVisible(false);
    setTimeout(() => {
      setShowRejectedPopup(false);
    }, 150);
  };

  // Notifications popup handlers
  const openNotifications = () => {
    scrollToTopAndOpen(setShowNotifications, setIsNotificationsVisible);
  };

  const closeNotifications = () => {
    setIsNotificationsVisible(false);
    setTimeout(() => {
      setShowNotifications(false);
    }, 150);
  };

  // Handle "Become a Barber" button click
  const handleBecomeBarberClick = () => {
    // Check if user is authenticated first
    if (!user) {
      scrollToTopAndOpen(setShowLoginPrompt);
      return;
    }
    
    if (hasPendingApplication) {
      openPendingPopup();
    } else if (hasRejectedApplication) {
      openRejectedPopup();
    } else {
      scrollToTopAndOpen(setShowBarberApplication);
    }
  };
  
  // Debug viewport in development
  useEffect(() => {
    if (process.env.NODE_ENV === 'development') {
      console.log('📱 Viewport:', viewport, { isMobile, isTablet });
    }
  }, [viewport, isMobile, isTablet]);

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

  // Fetch notifications and unread messages
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
    if (user) {
      loadUnreadCount();
    }
  }, [user?.id, loadUnreadCount]);

  // Fetch alternative barbers when the modal opens
  useEffect(() => {
    const fetchAlternativeBarbers = async () => {
      if (!showAlternativeBarbersModal || !alternativeBarbersData) return;
      
      setLoadingAlternativeBarbers(true);
      try {
        // Parse the scheduled time to get date and time in Pacific timezone
        const scheduledDate = new Date(alternativeBarbersData.scheduledTime);
        const dateStr = scheduledDate.toLocaleDateString('en-CA', { timeZone: 'America/Los_Angeles' }); // YYYY-MM-DD
        const timeStr = scheduledDate.toLocaleTimeString('en-US', { 
          timeZone: 'America/Los_Angeles', 
          hour: '2-digit', 
          minute: '2-digit', 
          hour12: false 
        }); // HH:MM
        
        console.log('[Alternative Barbers] Fetching barbers available at:', { 
          date: dateStr, 
          time: timeStr, 
          campusId: alternativeBarbersData.campusId,
          serviceType: alternativeBarbersData.serviceType 
        });
        
        // Use the dedicated backend endpoint
        const response = await api.get('/barbers/available-at-time', {
          campusId: alternativeBarbersData.campusId,
          date: dateStr,
          time: timeStr,
          serviceType: alternativeBarbersData.serviceType,
          excludeBarberId: alternativeBarbersData.cancelledBarberId,
        });
        
        const availableBarbers = response.data?.barbers || response.barbers || [];
        console.log('[Alternative Barbers] Found:', availableBarbers.length, 'barbers');
        
        // Map to Barber type
        setAlternativeBarbers(availableBarbers.map((b: any) => ({
          id: b.id,
          name: b.name,
          profile_picture_url: b.avatar,
          average_rating: b.average_rating,
          total_reviews: b.total_reviews,
        })));
      } catch (error) {
        console.error('Failed to fetch alternative barbers:', error);
        setAlternativeBarbers([]);
      } finally {
        setLoadingAlternativeBarbers(false);
      }
    };
    
    fetchAlternativeBarbers();
  }, [showAlternativeBarbersModal, alternativeBarbersData]);

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
        `${data.barberName} completed your ${data.serviceName}. Ready to pay!`,
        { duration: 5000 }
      );

      // Open payment modal directly
      setPaymentModalData({
        bookingId: data.bookingId,
        barberName: data.barberName,
        serviceName: data.serviceName,
        amount: data.price,
      });
      window.scrollTo({ top: 0, behavior: 'instant' });
      setShowPaymentModal(true);

      // Also refresh notifications to add it to the list
      notificationService.getNotifications().then((notifData) => {
        setNotifications(notifData.notifications);
        setUnreadNotifications(notifData.unreadCount);
      }).catch(console.error);
    };

    socketService.onBookingCompleted(handleBookingCompleted);

    return () => {
      socketService.offBookingCompleted(handleBookingCompleted);
    };
  }, [user?.id]);

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

  // Format time for notifications
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

  // Pull-to-refresh handler for mobile - reload the page
  const handlePullToRefresh = async () => {
    window.location.reload();
  };

  // Wait for auth to finish loading before rendering
  // This check is placed after all hooks to comply with React's Rules of Hooks
  if (isAuthLoading) {
    return <Loading />;
  }

  return (
    <PullToRefresh onRefresh={handlePullToRefresh} className="min-h-screen bg-gray-50" disabled={isAnyModalOpen}>
      {/* Header */}
      <div className="bg-white shadow-sm border-b border-gray-200">
        <div className="max-w-7xl mx-auto px-3 sm:px-4 py-3 sm:py-4">
          <div className="flex items-center justify-between relative">
            {/* Left section - Switch button on mobile, Logo + Switch on desktop */}
            <div className="flex items-center gap-2 sm:gap-4">
              {/* Barber button - different behavior based on user role */}
              {user?.user_type === 'barber' || user?.user_type === 'admin' || user?.has_barber_profile ? (
                <button
                  onClick={() => navigate('/web/barber')}
                  className="px-3 py-2 sm:px-4 rounded-lg bg-primary-50 hover:bg-primary-100 transition-colors border border-primary-200"
                  title="Switch to barber view"
                >
                  <span className="text-xs sm:text-sm font-medium text-primary-700">Barber View</span>
                </button>
              ) : (
                <button
                  onClick={handleBecomeBarberClick}
                  className="px-4 py-2 sm:px-5 sm:py-2.5 rounded-lg bg-primary-500 hover:bg-primary-600 transition-colors shadow-md hover:shadow-lg active:scale-95"
                  title="Apply to become a barber"
                >
                  <span className="text-sm sm:text-base font-semibold text-white">Become a Barber</span>
                </button>
              )}
            </div>
            
            {/* Center section - Logo (centered on all screen sizes) - clickable to go home */}
            <button 
              onClick={() => navigate('/')}
              className="absolute left-1/2 transform -translate-x-1/2 cursor-pointer"
            >
              <img src={CampusCutLogo} alt="CampusCut" className="h-10 sm:h-12 w-auto" />
            </button>
            
            {/* Right section - Messages & Profile (authenticated) or Sign In (guest) */}
            <div className="flex items-center gap-2 sm:gap-4">
              {user ? (
                <>
                  {/* Messages Button - Only for authenticated users */}
                  <button
                    onClick={() => navigate(`${platformPrefix}/consumer/messages`)}
                    className="p-2 rounded-lg hover:bg-gray-100 transition-colors relative"
                    title="Messages"
                  >
                    <MessageCircle className="w-5 h-5 text-gray-600" />
                    {unreadMessages > 0 && (
                      <span className="absolute -top-1 -right-1 bg-red-500 text-white text-xs font-bold rounded-full min-w-[18px] h-[18px] flex items-center justify-center px-1">
                        {unreadMessages > 99 ? '99+' : unreadMessages}
                      </span>
                    )}
                  </button>
                  
                  {/* Profile Dropdown - Only for authenticated users */}
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
                        {/* Notifications */}
                        <button
                          onClick={() => {
                            openNotifications();
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
                        <button
                          onClick={() => {
                            openProfileEditor();
                            setShowProfileDropdown(false);
                          }}
                          className="w-full px-4 py-2 text-left text-sm text-gray-700 hover:bg-gray-100 flex items-center gap-3"
                        >
                          <Settings className="w-4 h-4 text-gray-500" />
                          Edit Profile
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
                </>
              ) : (
                /* Sign In button for unauthenticated users */
                <button
                  onClick={() => navigate('/web')}
                  className="flex items-center gap-2 px-4 py-2 bg-primary-600 text-white rounded-lg font-medium hover:bg-primary-700 transition-colors"
                >
                  <UserIcon className="w-4 h-4" />
                  <span className="hidden sm:inline">Sign In</span>
                </button>
              )}
            </div>
          </div>
        </div>
      </div>

      {/* Content */}
      <div className="max-w-7xl mx-auto px-3 sm:px-4 py-4 sm:py-8">
        <DiscoveryView navigate={navigate} onBecomeBarberClick={handleBecomeBarberClick} />
      </div>

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
                  className="bg-red-100 text-red-600 hover:bg-red-200 hover:text-red-700 rounded-lg px-3 py-1.5 transition-colors text-sm font-medium border border-red-200"
                  title="Delete Account"
                >
                  Delete Account
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
              <ConsumerProfileEditor ref={profileEditorRef} userId={consumerId} />
            </div>
          </div>
        </div>
      )}

      {/* Barber Application Modal */}
      <BarberApplicationModal
        isOpen={showBarberApplication}
        onClose={() => setShowBarberApplication(false)}
      />

      {/* Pending Application Popup */}
      {showPendingPopup && (
        <div 
          className={`fixed inset-0 min-h-[100dvh] bg-black/50 flex items-center justify-center z-50 p-4 transition-all duration-150 ease-out ${isPendingPopupVisible ? 'opacity-100' : 'opacity-0'}`}
          onClick={closePendingPopup}
        >
          <div 
            className={`bg-white rounded-2xl shadow-2xl max-w-md w-full p-8 text-center transition-all duration-150 ease-out
              ${isPendingPopupVisible ? 'opacity-100 scale-100 translate-y-0' : 'opacity-0 scale-95 translate-y-4'}`}
            onClick={(e) => e.stopPropagation()}
          >
            <h3 className="text-xl font-bold text-gray-900 mb-3">Application Under Review</h3>
            <p className="text-gray-600 mb-4">
              Please be patient as the campus manager goes over your application.
            </p>
            <p className="text-sm text-gray-500 mb-6">
              If you suspect your application was not sent, please contact{' '}
              <a 
                href="mailto:campuscuthelp@gmail.com?subject=Barber Application Issue"
                target="_blank"
                rel="noopener noreferrer"
                className="text-primary-600 hover:text-primary-700 font-medium"
              >
                campuscuthelp@gmail.com
              </a>
            </p>
            <button
              onClick={closePendingPopup}
              className="px-6 py-2.5 bg-primary-600 text-white rounded-lg font-semibold hover:bg-primary-700 transition-colors"
            >
              Got it
            </button>
          </div>
        </div>
      )}

      {/* Rejected Application Popup */}
      {showRejectedPopup && (
        <div 
          className={`fixed inset-0 min-h-[100dvh] bg-black/50 flex items-center justify-center z-50 p-4 transition-all duration-150 ease-out ${isRejectedPopupVisible ? 'opacity-100' : 'opacity-0'}`}
          onClick={closeRejectedPopup}
        >
          <div 
            className={`bg-white rounded-2xl shadow-2xl max-w-md w-full p-8 text-center transition-all duration-150 ease-out
              ${isRejectedPopupVisible ? 'opacity-100 scale-100 translate-y-0' : 'opacity-0 scale-95 translate-y-4'}`}
            onClick={(e) => e.stopPropagation()}
          >
            <div className="w-16 h-16 bg-red-100 rounded-full flex items-center justify-center mx-auto mb-5">
              <Scissors className="w-8 h-8 text-red-600" />
            </div>
            <h3 className="text-xl font-bold text-gray-900 mb-3">Previous Application Rejected</h3>
            <p className="text-gray-600 mb-4">
              Your previous application was not approved. You can submit a new application with updated information.
            </p>
            <p className="text-sm text-gray-500 mb-6">
              If you have questions about why your application was rejected, please contact <span className="text-primary-600 font-medium">campuscuthelp@gmail.com</span>
            </p>
            <div className="flex flex-col sm:flex-row gap-3 justify-center">
              <button
                onClick={closeRejectedPopup}
                className="px-6 py-2.5 border border-gray-300 text-gray-700 rounded-lg font-semibold hover:bg-gray-50 transition-colors"
              >
                Maybe Later
              </button>
              <button
                onClick={() => {
                  closeRejectedPopup();
                  // Clear the rejected status so they can apply again
                  setHasRejectedApplication(false);
                  scrollToTopAndOpen(setShowBarberApplication);
                }}
                className="px-6 py-2.5 bg-primary-600 text-white rounded-lg font-semibold hover:bg-primary-700 transition-colors"
              >
                Apply Again
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Login Prompt for unauthenticated users trying to become a barber */}
      <LoginPrompt
        isOpen={showLoginPrompt}
        onClose={() => setShowLoginPrompt(false)}
        action="become_barber"
      />

      {/* Notifications Modal */}
      {showNotifications && (
        <div 
          className={`fixed inset-0 min-h-[100dvh] bg-black/50 z-50 flex items-center justify-center p-4 transition-all duration-150 ease-out ${isNotificationsVisible ? 'opacity-100' : 'opacity-0'}`}
          onClick={closeNotifications}
        >
          <div 
            className={`bg-white rounded-2xl shadow-2xl max-w-md w-full max-h-[80dvh] sm:max-h-[80vh] overflow-hidden transition-all duration-150 ease-out ${
              isNotificationsVisible ? 'opacity-100 scale-100 translate-y-0' : 'opacity-0 scale-95 translate-y-4'
            }`}
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
                  onClick={closeNotifications}
                  className="text-white hover:bg-white/20 rounded-full p-2 transition-colors"
                >
                  <X className="w-5 h-5" />
                </button>
              </div>
            </div>

            {/* Content */}
            <div className="max-h-[60dvh] sm:max-h-[60vh] overflow-y-auto">
              {!notifications || notifications.length === 0 ? (
                <div className="p-8 text-center">
                  <Bell className="w-12 h-12 text-gray-300 mx-auto mb-3" />
                  <p className="text-gray-500">No notifications yet</p>
                </div>
              ) : (
                <div className="divide-y divide-gray-100">
                  {(notifications || []).map((notification) => {
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
                    
                    // Handle click - navigate to appropriate page
                    const handleNotificationClick = () => {
                      if (!notification.is_read) {
                        handleMarkNotificationRead(notification.id);
                      }
                      
                      // Message notifications navigate to the conversation
                      if (isMessageNotification && data.conversationId) {
                        navigate(`${platformPrefix}/consumer/messages/${data.conversationId}`);
                        closeNotifications();
                      } else if (notification.type === 'payment_request' && data.bookingId) {
                        // Payment request - open payment modal
                        setPaymentModalData({
                          bookingId: data.bookingId,
                          barberName: data.barberName || 'Your Barber',
                          serviceName: data.serviceName || 'Service',
                          amount: data.amount || 0,
                        });
                        window.scrollTo({ top: 0, behavior: 'instant' });
                        setShowPaymentModal(true);
                        closeNotifications();
                      } else if (notification.type === 'booking_rejected') {
                        // Booking declined - show decline details modal
                        // Extract barber name from the message (format: "Barber Name was unable to accept...")
                        const barberNameMatch = notification.message?.match(/^(.+?) was unable to accept/);
                        const barberName = barberNameMatch ? barberNameMatch[1] : 'The barber';
                        setDeclinedModalData({
                          barberName,
                          reason: data.reason || '',
                          message: notification.message || '',
                        });
                        setShowDeclinedModal(true);
                        closeNotifications();
                      } else if (notification.type === 'booking_cancelled' && data.cancelledBy === 'barber' && data.scheduledTime) {
                        // Barber cancelled - show alternative barbers modal
                        // Extract barber name from the message (format: "Barber Name has cancelled...")
                        const barberNameMatch = notification.message?.match(/^(.+?) has cancelled/);
                        const barberName = barberNameMatch ? barberNameMatch[1] : 'Your barber';
                        setAlternativeBarbersData({
                          scheduledTime: data.scheduledTime,
                          serviceType: data.serviceType,
                          campusId: data.campusId,
                          cancelledBarberId: data.cancelledBarberId,
                          barberName,
                          reason: data.reason,
                        });
                        setShowAlternativeBarbersModal(true);
                        closeNotifications();
                      } else {
                        // Default: close modal
                        closeNotifications();
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
                onClick={closeNotifications}
                variant="secondary"
                className="w-full"
              >
                Close
              </Button>
            </div>
          </div>
        </div>
      )}

      {/* Payment Request Modal */}
      {paymentModalData && (
        <PaymentRequestModal
          isOpen={showPaymentModal}
          onClose={() => {
            setShowPaymentModal(false);
            setPaymentModalData(null);
          }}
          bookingId={paymentModalData.bookingId}
          barberName={paymentModalData.barberName}
          serviceName={paymentModalData.serviceName}
          amount={paymentModalData.amount}
          onPaymentComplete={() => {
            handlePullToRefresh();
          }}
        />
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
                    <AlertCircle className="w-4 h-4" />
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
                }}
                className="w-full px-6 py-2.5 bg-primary-600 text-white rounded-lg font-semibold hover:bg-primary-700 transition-colors"
              >
                Find Another Barber
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Alternative Barbers Modal (shown when barber cancels) */}
      {showAlternativeBarbersModal && alternativeBarbersData && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4">
          <div 
            className="absolute inset-0 bg-black/50 backdrop-blur-sm"
            onClick={() => {
              setShowAlternativeBarbersModal(false);
              setAlternativeBarbersData(null);
              setAlternativeBarbers([]);
            }}
          />
          <div className="relative bg-white rounded-2xl shadow-2xl max-w-md w-full max-h-[80vh] overflow-hidden animate-slide-up flex flex-col">
            {/* Header */}
            <div className="bg-gradient-to-r from-primary-500 to-primary-600 px-6 py-4 flex items-center justify-center relative flex-shrink-0">
              <div className="flex flex-col items-center text-center">
                <h2 className="text-xl font-bold text-white">Booking Cancelled</h2>
                <p className="text-white/80 text-sm mt-1">Find an available barber for this time</p>
              </div>
              <button 
                className="absolute right-4 top-4 p-2 hover:bg-white/20 rounded-lg transition-colors"
                onClick={() => {
                  setShowAlternativeBarbersModal(false);
                  setAlternativeBarbersData(null);
                  setAlternativeBarbers([]);
                }}
              >
                <X className="w-5 h-5 text-white" />
              </button>
            </div>

            {/* Content */}
            <div className="p-6 overflow-y-auto flex-1">
              {/* Cancellation Info */}
              <div className="bg-red-50 border border-red-200 rounded-xl p-4 mb-6">
                <p className="text-red-800 text-sm">
                  <span className="font-semibold">{alternativeBarbersData.barberName}</span> has cancelled your appointment
                  {alternativeBarbersData.reason && (
                    <>: <span className="italic">"{alternativeBarbersData.reason}"</span></>
                  )}
                </p>
              </div>

              {/* Original Time Slot */}
              <div className="bg-primary-50 border border-primary-200 rounded-xl p-4 mb-6">
                <h4 className="font-semibold text-primary-800 mb-2">Original Time Slot</h4>
                <p className="text-primary-700 text-sm">
                  {new Date(alternativeBarbersData.scheduledTime).toLocaleDateString('en-US', {
                    weekday: 'long',
                    month: 'long',
                    day: 'numeric',
                  })} at {new Date(alternativeBarbersData.scheduledTime).toLocaleTimeString('en-US', {
                    hour: 'numeric',
                    minute: '2-digit',
                    hour12: true,
                  })}
                </p>
              </div>

              {/* Alternative Barbers */}
              <h4 className="font-semibold text-gray-800 mb-3">
                {loadingAlternativeBarbers 
                  ? 'Checking availability...' 
                  : alternativeBarbers.length > 0 
                    ? `${alternativeBarbers.length} barber${alternativeBarbers.length !== 1 ? 's' : ''} available at this time`
                    : 'No barbers available at this time'
                }
              </h4>

              {loadingAlternativeBarbers ? (
                <div className="flex items-center justify-center py-8">
                  <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-primary-500"></div>
                </div>
              ) : alternativeBarbers.length > 0 ? (
                <div className="space-y-3">
                  {alternativeBarbers.map((barber) => (
                    <button
                      key={barber.id}
                      onClick={() => {
                        setShowAlternativeBarbersModal(false);
                        setAlternativeBarbersData(null);
                        setAlternativeBarbers([]);
                        // Navigate to schedule with this barber
                        navigate(`${platformPrefix}/consumer/book/${barber.id}`, {
                          state: {
                            preselectedDate: alternativeBarbersData.scheduledTime.split('T')[0],
                            preselectedService: alternativeBarbersData.serviceType,
                          }
                        });
                      }}
                      className="w-full p-4 border border-gray-200 rounded-xl hover:border-primary-300 hover:bg-primary-50 transition-colors text-left flex items-center gap-4"
                    >
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
                              <Star className="w-3.5 h-3.5 fill-amber-400 text-amber-400" />
                              {barber.average_rating.toFixed(1)}
                            </span>
                          )}
                          {(barber.total_reviews ?? 0) > 0 && (
                            <span>({barber.total_reviews} reviews)</span>
                          )}
                        </div>
                      </div>
                      <ChevronDown className="w-5 h-5 text-gray-400 -rotate-90" />
                    </button>
                  ))}
                </div>
              ) : (
                <div className="text-center py-6">
                  <p className="text-gray-500 text-sm mb-4">
                    No other barbers are available at this specific time.
                  </p>
                  <button
                    onClick={() => {
                      setShowAlternativeBarbersModal(false);
                      setAlternativeBarbersData(null);
                      setAlternativeBarbers([]);
                    }}
                    className="text-primary-600 font-medium text-sm hover:text-primary-700"
                  >
                    Browse all barbers
                  </button>
                </div>
              )}
            </div>

            {/* Footer */}
            <div className="px-6 py-4 bg-gray-50 border-t flex-shrink-0">
              <button
                onClick={() => {
                  setShowAlternativeBarbersModal(false);
                  setAlternativeBarbersData(null);
                  setAlternativeBarbers([]);
                }}
                className="w-full px-6 py-2.5 bg-gray-200 text-gray-700 rounded-lg font-semibold hover:bg-gray-300 transition-colors"
              >
                Close
              </button>
            </div>
          </div>
        </div>
      )}
    </PullToRefresh>
  );
}

function DiscoveryView({ navigate, onBecomeBarberClick }: { navigate: any; onBecomeBarberClick: () => void }) {
  const location = useLocation();
  const [barbers, setBarbers] = useState<Barber[]>([]);
  const [filteredBarbers, setFilteredBarbers] = useState<Barber[]>([]);
  const [loading, setLoading] = useState(true);
  const [selectedBarber, setSelectedBarber] = useState<Barber | null>(null);
  const [selectedUniversity, setSelectedUniversity] = useState<University | null>(null);
  const [filterCriteria, setFilterCriteria] = useState<FilterCriteria>({
    serviceType: null,
    date: null,
    time: null,
    location: null,
    locationDetails: null,
  });
  const [showLoginPrompt, setShowLoginPrompt] = useState(false);
  const [loginPromptAction, setLoginPromptAction] = useState<'schedule' | 'become_barber' | 'general'>('general');
  const [loginRedirectBarber, setLoginRedirectBarber] = useState<Barber | null>(null);
  const [loadingBarberDetails, setLoadingBarberDetails] = useState(false);
  const [reviewsExpanded, setReviewsExpanded] = useState(false);
  const reviewsSectionRef = useRef<HTMLDivElement>(null);
  
  // Auth state
  const { isAuthenticated, user } = useAuthStore();
  
  // Viewport detection for responsive grid
  const { isMobile, isMobilePortrait, viewport } = useViewport();
  
  // University coordinates (used instead of geolocation)
  const latitude = selectedUniversity?.latitude ?? null;
  const longitude = selectedUniversity?.longitude ?? null;

  // Load saved university and filters on mount
  useEffect(() => {
    // Load university
    const savedUni = localStorage.getItem(UNIVERSITY_STORAGE_KEY);
    if (savedUni) {
      try {
        const parsed = JSON.parse(savedUni);
        setSelectedUniversity(parsed);
      } catch (e) {
        localStorage.removeItem(UNIVERSITY_STORAGE_KEY);
      }
    } else {
      // No university selected - redirect to landing page
      navigate('/');
      return;
    }
    
    // Load filters
    const savedFilters = localStorage.getItem(FILTER_STORAGE_KEY);
    if (savedFilters) {
      try {
        const parsed = JSON.parse(savedFilters);
        setFilterCriteria(parsed);
        // Clear filters from storage after loading (one-time use)
        localStorage.removeItem(FILTER_STORAGE_KEY);
      } catch (e) {
        localStorage.removeItem(FILTER_STORAGE_KEY);
      }
    }
  }, [navigate]);

  // Load barbers when university is selected
  useEffect(() => {
    if (selectedUniversity) {
      loadBarbers();
    }
  }, [selectedUniversity]);

  useEffect(() => {
    applyFilters();
  }, [barbers, filterCriteria, latitude, longitude, user?.id]);

  // Lock body scroll when barber modal is open (fixes mobile viewport issues)
  useEffect(() => {
    if (selectedBarber) {
      const scrollY = window.scrollY;
      document.body.style.overflow = 'hidden';
      document.body.style.position = 'fixed';
      document.body.style.width = '100%';
      document.body.style.top = `-${scrollY}px`;
      document.body.style.overscrollBehavior = 'none';
      document.documentElement.style.overscrollBehavior = 'none';
    } else {
      const scrollY = document.body.style.top;
      document.body.style.overflow = '';
      document.body.style.position = '';
      document.body.style.width = '';
      document.body.style.top = '';
      document.body.style.overscrollBehavior = '';
      document.documentElement.style.overscrollBehavior = '';
      if (scrollY) {
        window.scrollTo(0, parseInt(scrollY || '0') * -1);
      }
    }
    return () => {
      document.body.style.overflow = '';
      document.body.style.position = '';
      document.body.style.width = '';
      document.body.style.top = '';
      document.body.style.overscrollBehavior = '';
      document.documentElement.style.overscrollBehavior = '';
    };
  }, [selectedBarber]);

  // Helper to scroll to top before opening modals (prevents white space on mobile)
  const scrollToTopAndOpen = (setShow: (v: boolean) => void) => {
    window.scrollTo({ top: 0, behavior: 'instant' });
    setShow(true);
  };

  // Handle schedule click - check auth first
  const handleScheduleClick = (barber: Barber) => {
    if (!isAuthenticated) {
      setLoginPromptAction('schedule');
      setLoginRedirectBarber(barber); // Store barber for post-login redirect
      scrollToTopAndOpen(setShowLoginPrompt);
      return;
    }
    // Navigate to booking
    const formData = location.state?.preservedFormData;
    navigate(`/web/consumer/book/${barber.id}`, {
      state: {
        barber,
        filters: filterCriteria,
        preservedFormData: formData?.barberId === barber.id ? formData : undefined,
      },
    });
  };

  // Handle barber selection - fetch full details including reviews
  const handleBarberSelect = async (barber: Barber) => {
    // Show card immediately with list data
    setSelectedBarber(barber);
    setLoadingBarberDetails(true);
    setReviewsExpanded(false); // Reset reviews dropdown when selecting new barber
    
    try {
      // Fetch detailed barber info (includes reviews)
      const detailedBarber = await barberService.getBarberById(barber.id);
      // Merge detailed data with list data (preserving any fields that might only be in list)
      setSelectedBarber({ ...barber, ...detailedBarber });
    } catch (error) {
      console.error('Failed to fetch barber details:', error);
      // Keep showing list data if fetch fails
    } finally {
      setLoadingBarberDetails(false);
    }
  };

  const loadBarbers = async () => {
    try {
      setLoading(true);
      
      // Pass user location AND campusId to backend
      // When campusId is provided, ALL barbers for that campus are shown (regardless of distance)
      let response;
      if (latitude && longitude) {
        // Pass selectedUniversity.id to show all barbers assigned to that campus
        response = await barberService.getBarbersByLocation(
          latitude, 
          longitude, 
          {}, // filters
          8, // maxDistanceKm (only used when no campusId)
          selectedUniversity?.id // campusId - shows all barbers for this campus
        );
      } else {
        response = await barberService.getBarbers({ campus_id: selectedUniversity?.id });
      }
      
      const barbersData = response.data || [];
      
      // Randomly shuffle barbers to give every barber a fair chance at being seen
      const shuffledBarbers = shuffleBarbers(barbersData);
      setBarbers(shuffledBarbers);
      setFilteredBarbers(shuffledBarbers);
      
      setLoading(false);
    } catch (error) {
      console.error('Failed to load barbers:', error);
      setBarbers([]);
      setFilteredBarbers([]);
      setLoading(false);
    }
  };

  const applyFilters = () => {
    let filtered = [...barbers];

    // Filter out the user's own barber profile (prevent self-booking)
    if (user?.id) {
      filtered = filtered.filter(barber => barber.user_id !== user.id);
    }

    // Filter by service type
    if (filterCriteria.serviceType) {
      filtered = filtered.filter(barber =>
        barber.specialties?.some(specialty =>
          specialty.toLowerCase().includes(filterCriteria.serviceType!.toLowerCase()) ||
          filterCriteria.serviceType!.toLowerCase().includes(specialty.toLowerCase())
        )
      );
    }

    // Filter by availability (date/time)
    // For now, mock logic - in production, check actual availability
    if (filterCriteria.date && filterCriteria.time) {
      // All barbers available in demo
      filtered = filtered.filter(() => true);
    }

    // Filter by location
    if (filterCriteria.location) {
      // All barbers support all locations in demo
      filtered = filtered.filter(() => true);
    }

    // Keep random order from initial shuffle - no additional sorting
    // This ensures every barber has a fair chance at being seen

    setFilteredBarbers(filtered);
  };

  const handleFilterChange = (filters: FilterCriteria) => {
    setFilterCriteria(filters);
  };

  const clearFilters = () => {
    setFilterCriteria({
      serviceType: null,
      date: null,
      time: null,
      location: null,
      locationDetails: null,
    });
  };

  // Redirect handled in useEffect if no university

  if (loading || !selectedUniversity) {
    return <Loading />;
  }

  return (
    <>
      {/* Filter Header */}
      <div className="mb-4 sm:mb-6">
        {/* University and Filter Info */}
        <div className="text-center text-xs sm:text-sm text-gray-600 flex flex-wrap items-center justify-center gap-2">
          <span>Barbers at {selectedUniversity?.shortName || selectedUniversity?.name}</span>
          {filterCriteria.serviceType && (
            <>
              <span className="text-gray-400">•</span>
              <span className="text-primary-600 font-medium">{filterCriteria.serviceType}</span>
              <button 
                onClick={clearFilters}
                className="text-gray-400 hover:text-gray-600 underline"
              >
                Clear
              </button>
            </>
          )}
          <span className="text-gray-400">•</span>
          <button 
            onClick={() => navigate('/')}
            className="text-primary-600 hover:text-primary-700 underline"
          >
            Change
          </button>
        </div>
        
        {/* Results count */}
        {filteredBarbers && filteredBarbers.length > 0 && (
          <p className="text-center text-xs text-gray-500 mt-2">
            {filteredBarbers.length} barber{filteredBarbers.length !== 1 ? 's' : ''} found
          </p>
        )}
      </div>

      {/* Price disclaimer */}
      {filteredBarbers && filteredBarbers.length > 0 && (
        <p className="text-center text-xs text-gray-400 mt-4 italic">
          Prices are set by individual barbers
        </p>
      )}

      {/* No Results - University Based */}
      {(!filteredBarbers || filteredBarbers.length === 0) && selectedUniversity && !filterCriteria.serviceType && (
        <Card className="text-center py-8 sm:py-12">
          {/* No barbers message with try different university */}
          <div className="mb-10">
            <p className="text-gray-600 text-base sm:text-lg mb-2">No barbers at {selectedUniversity.shortName || selectedUniversity.name}</p>
            <p className="text-xs sm:text-sm text-gray-500 mb-4">
              There are no barbers registered at this campus yet.
              <br />
              Check back soon as more barbers join the platform!
            </p>
            <button 
              onClick={() => navigate('/')}
              className="text-primary-600 hover:text-primary-700 underline"
            >
              Try a different university
            </button>
          </div>
          
          {/* Become a barber CTA - separated with vertical space */}
          <div className="flex flex-col items-center gap-4 pt-8 border-t border-gray-200">
            <p className="text-base sm:text-lg text-gray-600 font-medium">
              Want to be a barber at {selectedUniversity.shortName || selectedUniversity.name}?
            </p>
            <button
              onClick={onBecomeBarberClick}
              className="px-6 py-4 rounded-lg bg-white border-2 border-primary-500 hover:bg-primary-50 transition-colors shadow-lg hover:shadow-xl active:scale-95"
            >
              <span className="text-lg font-semibold text-primary-600">Become a Barber</span>
            </button>
          </div>
        </Card>
      )}

      {/* No Results - Filter Based */}
      {(!filteredBarbers || filteredBarbers.length === 0) && filterCriteria.serviceType && (
        <Card className="text-center py-8 sm:py-12">
          <p className="text-gray-600 text-base sm:text-lg mb-2">No barbers match your criteria</p>
          <p className="text-xs sm:text-sm text-gray-500">Try adjusting your filters or check back later</p>
        </Card>
      )}


      {/* Barbers Grid - Responsive: 1 col portrait mobile, 2 col landscape/tablet, 3-5 col desktop */}
      <div className={`grid gap-3 sm:gap-4 mt-8 sm:mt-10 ${
        isMobilePortrait 
          ? 'grid-cols-1' 
          : 'grid-cols-2 md:grid-cols-3 lg:grid-cols-4 xl:grid-cols-5'
      }`}>
        {(filteredBarbers || []).map((barber) => {
          // Calculate price display - show range if multiple different prices
          const prices = barber.pricing?.map(p => p.price) || [];
          const minPrice = prices.length > 0 ? Math.min(...prices) : undefined;
          const maxPrice = prices.length > 0 ? Math.max(...prices) : undefined;
          const hasRange = minPrice !== undefined && maxPrice !== undefined && maxPrice !== minPrice;

          // Mobile portrait: Horizontal card layout
          if (isMobilePortrait) {
            return (
              <Card
                key={barber.id}
                className="cursor-pointer active:scale-98 transition-all duration-200 flex flex-row rounded-xl overflow-hidden"
                onClick={() => handleBarberSelect(barber)}
              >
                {/* Barber Profile Picture - Left Side */}
                <div className="relative w-28 h-28 flex-shrink-0 bg-gray-200">
                  {barber.profile_picture_url ? (
                    <img
                      src={barber.profile_picture_url}
                      alt={`${barber.user?.first_name || 'Barber'}`}
                      className="w-full h-full object-cover"
                      loading="lazy"
                    />
                  ) : (
                    <div className="w-full h-full flex items-center justify-center">
                      <UsersIcon className="w-8 h-8 text-gray-400" />
                    </div>
                  )}
                </div>
                {/* Info - Right Side */}
                <div className="flex-1 p-3 flex flex-col justify-center">
                  <div className="flex items-center justify-between gap-2">
                    <h3 className="font-bold text-gray-900 text-lg">
                      {barber.name || barber.display_name || `${barber.first_name || ''} ${barber.last_name || ''}`.trim() || 'Barber'}
                    </h3>
                    {minPrice !== undefined && (
                      <span className="text-primary-500 font-bold text-xl flex-shrink-0 mr-2">
                        {hasRange ? `$${minPrice} - $${maxPrice}` : `$${minPrice}`}
                      </span>
                    )}
                  </div>
                  {/* Distance display commented out
                {barber.distance_miles !== undefined && barber.distance_miles !== null && (
                    <div className="flex items-center gap-2 mt-1.5">
                      <span className="text-sm text-primary-600 font-medium">{barber.distance_miles} mi</span>
                    </div>
                  )}
                */}
                  {barber.instagram_handle && (
                    <div className="flex items-center gap-1 text-sm text-gray-500 mt-2">
                      <Instagram className="w-4 h-4 flex-shrink-0" />
                      <span>@{barber.instagram_handle}</span>
                    </div>
                  )}
                </div>
              </Card>
            );
          }

          // Default: Vertical card layout (tablet, desktop)
          return (
            <Card
              key={barber.id}
              className="cursor-pointer hover:shadow-2xl sm:hover:scale-105 active:scale-98 hover:-translate-y-1 transition-all duration-200 h-full flex flex-col rounded-lg overflow-hidden bg-transparent p-0 shadow-none hover:bg-transparent"
              onClick={() => handleBarberSelect(barber)}
            >
              {/* Barber Profile Picture with Name & Price Overlays */}
              <div className="relative mb-2 sm:mb-3 w-48 sm:w-56 aspect-square overflow-hidden rounded-lg bg-gray-200 mx-auto">
                {barber.profile_picture_url ? (
                  <img
                    src={barber.profile_picture_url}
                    alt={`${barber.user?.first_name || 'Barber'}`}
                    className="w-full h-full object-cover"
                    loading="lazy"
                  />
                ) : (
                  <div className="w-full h-full flex items-center justify-center">
                    <UsersIcon className="w-8 h-8 sm:w-12 sm:h-12 text-gray-400" />
                  </div>
                )}
                {/* Name Overlay - Top */}
                <div className="absolute top-0 left-0 right-0 bg-gradient-to-b from-black/70 to-transparent p-2 sm:p-3">
                  <h3 className="text-sm sm:text-lg font-bold text-white">
                    {barber.name || barber.display_name || `${barber.first_name || barber.user?.first_name || ''} ${barber.last_name || barber.user?.last_name || ''}`.trim() || 'Barber'}
                  </h3>
                </div>
                {/* Price Overlay - Bottom Left */}
                {minPrice !== undefined && (
                  <div className="absolute bottom-0 left-0 bg-primary-400/90 backdrop-blur-sm px-3 sm:px-4 py-1.5 sm:py-2.5 rounded-tr-lg rounded-bl-lg">
                    <div className="flex items-center text-white">
                      <span className="font-bold text-sm sm:text-base">
                        {hasRange ? `$${minPrice} - $${maxPrice}` : `$${minPrice}`}
                      </span>
                    </div>
                  </div>
                )}
                {/* Distance Overlay - Bottom Right - Commented out
                {barber.distance_miles !== undefined && barber.distance_miles !== null && (
                  <div className="absolute bottom-0 right-0 bg-gray-800/90 backdrop-blur-sm px-3 sm:px-4 py-1.5 sm:py-2.5 rounded-tl-lg rounded-br-lg">
                    <div className="flex items-center gap-1 text-white">
                      <MapPin className="w-3.5 h-3.5 sm:w-4 sm:h-4" />
                      <span className="font-bold text-sm sm:text-base">{barber.distance_miles} mi</span>
                    </div>
                  </div>
                )}
                */}
              </div>
            </Card>
          );
        })}
      </div>


      {/* Barber Profile Modal */}
      {selectedBarber && (() => {
        // Determine if barber has rich content that needs wider card
        const scheduleData = selectedBarber.weekly_schedule ? formatSchedule(selectedBarber.weekly_schedule) : [];
        const hasAvailability = scheduleData.length > 0;
        const hasManySpecialties = Array.isArray(selectedBarber.specialties) && selectedBarber.specialties.length > 3;
        const hasBio = !!selectedBarber.bio;
        
        // Check if availability has long time strings (with minutes like "11:30am")
        const hasLongTimeStrings = scheduleData.some(({ times }) => 
          times.includes(':') && times.length > 12
        );
        
        // Determine card width tier
        const needsExtraWideCard = hasAvailability && (hasLongTimeStrings || scheduleData.length >= 5);
        const hasRichContent = hasAvailability || hasManySpecialties || hasBio;
        
        return (
        <div 
          className="fixed inset-0 min-h-[100dvh] bg-black/60 flex items-center justify-center z-50 p-6 animate-fade-in"
          onClick={() => setSelectedBarber(null)}
        >
          <div 
            className={`bg-white rounded-2xl shadow-2xl w-full max-h-[85dvh] sm:max-h-[80vh] overflow-y-auto animate-slide-up ${
              needsExtraWideCard
                ? 'max-w-sm sm:max-w-3xl lg:max-w-4xl'
                : hasRichContent 
                  ? 'max-w-sm sm:max-w-2xl lg:max-w-3xl' 
                  : 'max-w-sm sm:max-w-md lg:max-w-lg'
            }`}
            onClick={(e) => e.stopPropagation()}
          >
            <div className="sticky top-0 bg-white border-b border-gray-200 px-6 py-4 sm:px-8 sm:py-5 flex items-center justify-between rounded-t-2xl z-10">
              <h2 className="text-xl sm:text-2xl lg:text-3xl font-bold text-gray-900">
                {selectedBarber.name || selectedBarber.display_name || `${selectedBarber.first_name || ''} ${selectedBarber.last_name || ''}`.trim() || 'Barber'}
              </h2>
              <div className="flex items-center gap-3">
                {selectedBarber.instagram_handle && (
                  <a
                    href={`https://instagram.com/${selectedBarber.instagram_handle}`}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="flex items-center gap-2 px-3 py-1.5 sm:px-4 sm:py-2 bg-gradient-to-r from-purple-500 to-pink-500 text-white rounded-lg hover:from-purple-600 hover:to-pink-600 transition-all shadow-sm hover:shadow-md"
                  >
                    <Instagram className="w-4 h-4 sm:w-5 sm:h-5" />
                    <span className="text-xs sm:text-sm font-medium">@{selectedBarber.instagram_handle}</span>
                  </a>
                )}
                <button
                  onClick={() => setSelectedBarber(null)}
                  className="p-2 hover:bg-gray-100 rounded-full transition-colors"
                >
                  <span className="text-gray-400 hover:text-gray-600 text-2xl leading-none">×</span>
                </button>
              </div>
            </div>
            <div className="p-6 sm:p-8">
              {/* Barber Profile Content */}
              <div className="space-y-6 sm:space-y-8">
                {/* Profile Header - Image left, info right */}
                <div className="flex flex-col sm:flex-row gap-6 sm:gap-8">
                  {/* Barber Profile Picture */}
                  <div className="relative w-48 sm:w-64 lg:w-72 aspect-square overflow-hidden rounded-lg bg-gray-200 flex-shrink-0 mx-auto sm:mx-0">
                    {selectedBarber.profile_picture_url ? (
                      <img
                        src={selectedBarber.profile_picture_url}
                        alt={`${selectedBarber.user?.first_name || 'Barber'}`}
                        className="w-full h-full object-cover"
                      />
                    ) : (
                      <div className="w-full h-full flex items-center justify-center">
                        <UsersIcon className="w-8 h-8 sm:w-12 sm:h-12 text-gray-400" />
                      </div>
                    )}
                  </div>
                  
                  {/* Specialties & Availability - Right side */}
                  <div className="flex-1 flex flex-col justify-center text-center sm:text-left">
                    {/* Services with Prices */}
                    {(Array.isArray(selectedBarber.pricing) && selectedBarber.pricing.length > 0) && (
                      <div className="mb-4 sm:mb-6">
                        <div className="flex items-center justify-center sm:justify-start text-gray-700 font-medium mb-3 sm:text-lg">
                          <span>Services</span>
                        </div>
                        <div className="flex flex-wrap justify-center sm:justify-start gap-2 sm:gap-3">
                          {selectedBarber.pricing.map((service, idx) => (
                            <span
                              key={idx}
                              className="px-3 py-1.5 bg-primary-100 text-primary-600 text-sm rounded-full font-medium flex items-center gap-1.5"
                            >
                              <span>{service.name}</span>
                              <span className="text-primary-500">•</span>
                              <span className="font-bold">${service.price}</span>
                            </span>
                          ))}
                        </div>
                      </div>
                    )}
                    
                    {/* Availability */}
                                    {selectedBarber.weekly_schedule && formatSchedule(selectedBarber.weekly_schedule).length > 0 && (
                                      <div>
                                        <div className="flex items-center justify-center sm:justify-start text-gray-700 font-medium mb-3 sm:text-lg">
                                          <span>Availability</span>
                                        </div>
                                        <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 gap-2">
                                          {formatSchedule(selectedBarber.weekly_schedule).map(({ day, times }) => (
                                            <div key={day} className="bg-gray-50 rounded-lg px-3 py-1.5 sm:px-4 sm:py-2 text-center">
                                              <div className="font-semibold text-gray-800 text-sm">{day}</div>
                                              <div className="flex flex-col gap-0.5">
                                                {times.split(', ').map((timeSlot, idx) => (
                                                  <div key={idx} className="text-xs text-gray-600 whitespace-nowrap">{timeSlot}</div>
                                                ))}
                                              </div>
                                            </div>
                                          ))}
                                        </div>
                                      </div>
                                    )}
                                    
                                    {/* Locations - Mobile Only */}
                                    {selectedBarber.service_locations && selectedBarber.service_locations.length > 0 && (
                                      <div className="sm:hidden mt-4">
                                        <div className="flex items-center justify-center text-gray-700 font-medium mb-3">
                                          <span>Locations</span>
                                        </div>
                                        <div className="flex flex-wrap justify-center gap-2">
                                          {selectedBarber.service_locations.map((location: { id: string; name: string; is_primary?: boolean }) => (
                                            <span
                                              key={location.id}
                                              className={`px-3 py-1.5 rounded-full text-sm font-medium ${
                                                location.is_primary
                                                  ? 'bg-primary-100 text-primary-700 border border-primary-200'
                                                  : 'bg-gray-100 text-gray-700'
                                              }`}
                                            >
                                              {location.name}
                                            </span>
                                          ))}
                                        </div>
                                      </div>
                                    )}
                                  </div>
                                </div>
                
                {/* Locations Section - Desktop Only (above About) */}
                                {selectedBarber.service_locations && selectedBarber.service_locations.length > 0 && (
                                  <div className="hidden sm:block pt-4 sm:pt-6 border-t border-gray-100">
                                    <div className="flex items-center justify-start text-gray-700 font-medium mb-3 sm:text-lg">
                                      <span>Locations</span>
                                    </div>
                                    <div className="flex flex-wrap gap-2 sm:gap-3">
                                      {selectedBarber.service_locations.map((location: { id: string; name: string; is_primary?: boolean }) => (
                                        <span
                                          key={location.id}
                                          className={`px-3 py-1.5 rounded-full text-sm font-medium ${
                                            location.is_primary
                                              ? 'bg-primary-100 text-primary-700 border border-primary-200'
                                              : 'bg-gray-100 text-gray-700'
                                          }`}
                                        >
                                          {location.name}
                                        </span>
                                      ))}
                                    </div>
                                  </div>
                                )}
                                
                                {/* Bio Section - Full width below */}
                                {selectedBarber.bio && (
                                  <div className="pt-4 sm:pt-6 border-t border-gray-100">
                                    <div className="flex items-center justify-center sm:justify-start text-gray-700 font-medium mb-3 sm:text-lg">
                                      <span>About</span>
                                    </div>
                                    <p className="text-gray-600 sm:text-lg leading-relaxed">{selectedBarber.bio}</p>
                                  </div>
                                )}

                                {/* Reviews Section - Collapsible */}
                                {(selectedBarber.reviews && selectedBarber.reviews.length > 0) || loadingBarberDetails ? (
                                  <div ref={reviewsSectionRef} className="pt-4 sm:pt-6 border-t border-gray-100">
                                    <button
                                      onClick={() => {
                                        const willExpand = !reviewsExpanded;
                                        setReviewsExpanded(willExpand);
                                        if (willExpand) {
                                          // Scroll to reviews section after a short delay for the animation
                                          setTimeout(() => {
                                            reviewsSectionRef.current?.scrollIntoView({ behavior: 'smooth', block: 'start' });
                                          }, 100);
                                        }
                                      }}
                                      className="w-full relative flex items-center justify-center sm:justify-between text-gray-700 font-medium sm:text-lg hover:text-gray-900 transition-colors"
                                    >
                                      <div className="flex flex-col items-center sm:items-start gap-1">
                                        <span>Reviews</span>
                                        {(selectedBarber.review_count ?? 0) > 0 && (
                                          <div className="flex items-center gap-1.5 px-2 py-0.5 bg-amber-50 border border-amber-200 rounded-full">
                                            <div className="flex items-center gap-0.5">
                                              {[1, 2, 3, 4, 5].map((star) => {
                                                const rating = selectedBarber.average_rating ?? 0;
                                                const filled = star <= Math.floor(rating);
                                                const partial = star === Math.ceil(rating) && rating % 1 !== 0;
                                                return (
                                                  <Star 
                                                    key={star} 
                                                    className={`w-3 h-3 ${
                                                      filled 
                                                        ? 'text-amber-500 fill-amber-500' 
                                                        : partial 
                                                          ? 'text-amber-500 fill-amber-200' 
                                                          : 'text-amber-200 fill-amber-200'
                                                    }`} 
                                                  />
                                                );
                                              })}
              </div>
                                            <span className="text-xs font-semibold text-amber-700">
                                              {(selectedBarber.average_rating ?? 0).toFixed(1)} ({selectedBarber.review_count})
                                            </span>
                                          </div>
                                        )}
                                        {loadingBarberDetails && (
                                          <div className="w-4 h-4 border-2 border-gray-300 border-t-primary-500 rounded-full animate-spin" />
                                        )}
                                      </div>
                                      <ChevronDown className={`absolute right-0 sm:relative w-5 h-5 text-gray-400 transition-transform duration-200 ${reviewsExpanded ? 'rotate-180' : ''}`} />
                                    </button>
                                    
                                    {/* Collapsible Reviews Content */}
                                    <div className={`overflow-hidden transition-all duration-300 ease-in-out ${reviewsExpanded ? 'max-h-[2000px] opacity-100 mt-4' : 'max-h-0 opacity-0'}`}>
                                      {loadingBarberDetails && !selectedBarber.reviews ? (
                                        <div className="space-y-4">
                                          {[1, 2].map((i) => (
                                            <div key={i} className="bg-gray-50 rounded-xl p-4 animate-pulse">
                                              <div className="flex items-start gap-3">
                                                <div className="w-10 h-10 rounded-full bg-gray-200" />
                                                <div className="flex-1">
                                                  <div className="h-4 bg-gray-200 rounded w-24 mb-2" />
                                                  <div className="h-3 bg-gray-200 rounded w-full mb-1" />
                                                  <div className="h-3 bg-gray-200 rounded w-3/4" />
                                                </div>
                                              </div>
                                            </div>
                                          ))}
                                        </div>
                                      ) : (
                                        <div className="space-y-3">
                                          {selectedBarber.reviews?.map((review) => (
                                            <div key={review.id} className="bg-gray-50 rounded-xl p-4">
                                              <div className="flex items-center justify-between gap-2 mb-1">
                                                <div className="flex items-center gap-2 min-w-0">
                                                  <span className="font-medium text-gray-900 truncate">
                                                    {review.first_name || 'Anonymous'} {review.last_name ? review.last_name.charAt(0) + '.' : ''}
                                                  </span>
                                                  {review.service_name && (
                                                    <span className="text-xs text-gray-500 bg-gray-200 px-2 py-0.5 rounded-full flex-shrink-0">
                                                      {formatServiceName(review.service_name)}
                                                    </span>
                                                  )}
                                                </div>
                                                <div className="flex items-center gap-0.5 flex-shrink-0">
                                                  {[...Array(5)].map((_, i) => (
                                                    <Star 
                                                      key={i} 
                                                      className={`w-3.5 h-3.5 ${i < review.rating ? 'text-amber-400 fill-amber-400' : 'text-gray-300'}`} 
                                                    />
                                                  ))}
                                                </div>
                                              </div>
                                              {review.review_text && (
                                                <p className="text-gray-600 text-sm leading-relaxed">{review.review_text}</p>
                                              )}
                                              <p className="text-gray-400 text-xs mt-2">
                                                {new Date(review.created_at).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' })}
                                              </p>
                                            </div>
                                          ))}
                                        </div>
                                      )}
                                    </div>
                                  </div>
                                ) : null}
              </div>
            </div>
            
            {/* Footer with Schedule Button */}
            <div className="sticky bottom-0 bg-white border-t border-gray-200 px-6 py-4 sm:px-8 sm:py-5 rounded-b-2xl">
              <Button
                onClick={() => handleScheduleClick(selectedBarber)}
                className="w-full py-3 sm:py-4 text-base sm:text-lg font-semibold"
              >
                Schedule Service
              </Button>
            </div>
          </div>
        </div>
        );
      })()}

      {/* Login Prompt for unauthenticated users */}
      <LoginPrompt
        isOpen={showLoginPrompt}
        onClose={() => {
          setShowLoginPrompt(false);
          setLoginRedirectBarber(null); // Clear redirect barber on close
        }}
        action={loginPromptAction}
        redirectBarber={loginRedirectBarber}
      />
    </>
  );
}
