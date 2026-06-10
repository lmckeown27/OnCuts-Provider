/**
 * Barber Dashboard Page - Version 4.0 (Cache Buster)
 * Last updated: 2025-12-18 00:15:00
 */
import { useState, useEffect, useRef, useMemo, useCallback } from 'react';
import { useNavigate, useLocation, Link } from 'react-router-dom';
import { Calendar, DollarSign, TrendingUp, Settings, LogOut, ChevronDown, ChevronLeft, ChevronRight, Scissors, Inbox, Shield, MapPin, MessageCircle, MessageSquare, Search, Filter, X, Clock, Zap, ArrowLeft, Bell, AlertCircle, Check, Send, AlertTriangle, Trash2, Pencil, Save, User, Mail, FileText, CreditCard, Landmark, Star, RefreshCw, RotateCcw } from 'lucide-react';
import { API_BASE_URL } from '../config/constants';
import notificationService, { Notification } from '../services/notification.service';
import api from '../services/api.service';
import socketService from '../services/socket.service';
import Avatar from '../components/Avatar';
import Button from '../components/Button';
import Card from '../components/Card';
import TimeInput from '../components/TimeInput';
import BarberProfileEditor from '../components/BarberProfileEditor';
import BarberServiceSpecialties from '../components/BarberServiceSpecialties';
import BarberBookingRequestsDropdown from '../components/booking/BarberBookingRequestsDropdown';
import { CampusManagerBadge } from '../components/CampusManagerBadge';
import { CampusManagerDashboard } from '../components/CampusManagerDashboard';
import { AdminDashboard } from '../components/AdminDashboard';
import BarberChatsModal from '../components/BarberChatsModal';
import BarberLocationsModal from '../components/BarberLocationsModal';
import ServiceDetailsModal from '../components/ServiceDetailsModal';
import PaymentManagementModal from '../components/PaymentManagementModal';
import BlockTimeModal from '../components/BlockTimeModal';
// import WalkInPaymentModal from '../components/WalkInPaymentModal'; // Walk-in feature disabled
import BookingDetailsModal from '../components/BookingDetailsModal';
import PullToRefresh from '../components/PullToRefresh';
import DatePicker from '../components/DatePicker';
import AvailableTimePickerDropdown from '../components/AvailableTimePickerDropdown';
import { CampusCutLogo } from '@assets';
import { useAuthStore } from '../store/useAuthStore';
import campusService from '../services/campus.service';
import barberService, { TimeBlock } from '../services/barber.service';
import type { Campus } from '../types';
import { useMessageStore } from '../store/useMessageStore';
import { useViewport, useBodyScrollLock, useGeolocation, useDynamicViewportHeight } from '../hooks';
import toast from 'react-hot-toast';

const COMPONENT_VERSION = 'v4.0-modal-fix';

export default function BarberPage() {
  console.log('🚀 BarberPage loaded -', COMPONENT_VERSION);
  const navigate = useNavigate();
  const location = useLocation();
  const platformPrefix = location.pathname.startsWith('/app') ? '/app' : '/web';
  
  // Viewport detection for responsive behavior
  const { isMobile, isTablet, viewport } = useViewport();
  
  // Handle dynamic viewport height for mobile browser bar changes
  useDynamicViewportHeight();
  
  // Auto-update barber's location when they access the dashboard
  // This ensures their location stays current for consumer discovery
  useGeolocation();
  
  // Message store for unread count
  const { unreadCount: unreadMessages, loadUnreadCount } = useMessageStore();
  
  const [showProfileDropdown, setShowProfileDropdown] = useState(false);
  
  // Modal states with visibility for animations
  const [showProfileEditor, setShowProfileEditor] = useState(false);
  const [isProfileEditorVisible, setIsProfileEditorVisible] = useState(false);
  
  const [showServiceSpecialties, setShowServiceSpecialties] = useState(false);
  const [isServiceSpecialtiesVisible, setIsServiceSpecialtiesVisible] = useState(false);
  
  const [showCampusManagerDashboard, setShowCampusManagerDashboard] = useState(false);
  const [isCampusManagerVisible, setIsCampusManagerVisible] = useState(false);
  
  const [showAdminDashboard, setShowAdminDashboard] = useState(false);
  const [isAdminDashboardVisible, setIsAdminDashboardVisible] = useState(false);
  
  const [showBarberChats, setShowBarberChats] = useState(false);
  const [isBarberChatsVisible, setIsBarberChatsVisible] = useState(false);
  
  const [showPayoutSettings, setShowPayoutSettings] = useState(false);
  const [showBlockTimeModal, setShowBlockTimeModal] = useState(false);
  
  // Google Calendar integration state
  const [googleCalendarConnected, setGoogleCalendarConnected] = useState<boolean | null>(null);
  const [googleCalendarLoading, setGoogleCalendarLoading] = useState(false);
  const [blockTimeInitialValues, setBlockTimeInitialValues] = useState<{
    date?: string;
    startTime?: string;
    endTime?: string;
  }>({});
  
  const [showBookings, setShowBookings] = useState(false);
  const [isBookingsVisible, setIsBookingsVisible] = useState(false);
  
  const [showLocations, setShowLocations] = useState(false);
  const [isLocationsVisible, setIsLocationsVisible] = useState(false);
  
  const [showAvailability, setShowAvailability] = useState(false);
  
  // const [showWalkInPayment, setShowWalkInPayment] = useState(false); // Walk-in feature disabled
  const [isAvailabilityVisible, setIsAvailabilityVisible] = useState(false);
  
  const [showServiceDetails, setShowServiceDetails] = useState(false);
  const [selectedAppointment, setSelectedAppointment] = useState<any>(null);
  
  // Notifications state
  const [notifications, setNotifications] = useState<Notification[]>([]);
  const [unreadNotifications, setUnreadNotifications] = useState(0);
  const [showNotifications, setShowNotifications] = useState(false);
  const [isNotificationsVisible, setIsNotificationsVisible] = useState(false);
  const [showBookingDetailsModal, setShowBookingDetailsModal] = useState(false);
  const [notificationFilter, setNotificationFilter] = useState<'all' | 'bookings' | 'payments' | 'reviews' | 'cancellations' | 'messages'>('all');
  
  // Lock body scroll when any modal is open
  const isAnyModalOpen =
    showProfileEditor ||
    showServiceSpecialties ||
    showCampusManagerDashboard ||
    showAdminDashboard ||
    showBarberChats ||
    showBookings ||
    showLocations ||
    showAvailability ||
    showServiceDetails ||
    showNotifications ||
    showBookingDetailsModal ||
    showPayoutSettings;
  useBodyScrollLock(isAnyModalOpen);
  
  // Fetch notifications
  const fetchNotifications = async () => {
    try {
      const data = await notificationService.getNotifications();
      setNotifications(data.notifications);
      setUnreadNotifications(data.unreadCount);
    } catch (error) {
      console.error('Failed to fetch notifications:', error);
    }
  };
  
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

  // Notifications popup handlers
  const openNotifications = () => {
    window.scrollTo({ top: 0, behavior: 'instant' });
    setShowNotifications(true);
    requestAnimationFrame(() => {
      requestAnimationFrame(() => {
        setIsNotificationsVisible(true);
      });
    });
  };

  const closeNotifications = () => {
    setIsNotificationsVisible(false);
    setTimeout(() => {
      setShowNotifications(false);
    }, 150);
  };
  
  // Format time helper
  const formatNotificationTime = (dateString: string) => {
    if (!dateString) return '';
    const date = new Date(dateString);
    if (isNaN(date.getTime())) return '';
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
  
  // Fetch notifications and unread messages on mount
  useEffect(() => {
    fetchNotifications();
    loadUnreadCount();
  }, [loadUnreadCount]);

  // Optional: open payout modal (e.g. return from /web/barber/connect bookmark)
  useEffect(() => {
    const searchParams = new URLSearchParams(location.search);
    if (searchParams.get('showPayoutSettings') === 'true') {
      setShowPayoutSettings(true);
      // Clear the query param from URL without triggering navigation
      const newUrl = location.pathname;
      window.history.replaceState({}, '', newUrl);
    }
    
    // Handle Google Calendar OAuth callback
    const googleCalendarStatus = searchParams.get('googleCalendar');
    if (googleCalendarStatus === 'success') {
      toast.success('Google Calendar connected successfully!');
      setGoogleCalendarConnected(true);
      window.history.replaceState({}, '', location.pathname);
    } else if (googleCalendarStatus === 'error') {
      const message = searchParams.get('message') || 'Failed to connect';
      toast.error(`Google Calendar: ${message}`);
      window.history.replaceState({}, '', location.pathname);
    }
  }, [location]);
  
  // Check Google Calendar connection status
  const checkGoogleCalendarStatus = async () => {
    try {
      // api.get() unwraps the response, so result IS the data directly
      const data = await api.get<{ connected: boolean }>('/auth/google-calendar/status');
      setGoogleCalendarConnected(data?.connected ?? false);
    } catch (error) {
      setGoogleCalendarConnected(false);
    }
  };
  
  // Connect Google Calendar
  const connectGoogleCalendar = async () => {
    try {
      setGoogleCalendarLoading(true);
      // Add timestamp to prevent caching
      // api.get() unwraps the response, so result IS the data directly
      const data = await api.get<{ authUrl: string }>(`/auth/google-calendar/connect?_t=${Date.now()}`);
      
      if (data?.authUrl) {
        // Redirect to Google OAuth
        window.location.href = data.authUrl;
      } else {
        toast.error('Failed to get Google Calendar URL');
        setGoogleCalendarLoading(false);
      }
    } catch (error: any) {
      toast.error('Failed to connect Google Calendar');
      setGoogleCalendarLoading(false);
    }
  };
  
  // Disconnect Google Calendar
  const disconnectGoogleCalendar = async () => {
    try {
      await api.delete('/auth/google-calendar/disconnect');
      setGoogleCalendarConnected(false);
      toast.success('Google Calendar disconnected');
    } catch (error) {
      console.error('Failed to disconnect Google Calendar:', error);
      toast.error('Failed to disconnect Google Calendar');
    }
  };
  
  // Load Google Calendar status on mount
  useEffect(() => {
    checkGoogleCalendarStatus();
  }, []);
  
  const dropdownRef = useRef<HTMLDivElement>(null);
  
  // Generic modal animation helpers
  const openModal = (setShow: (v: boolean) => void, setVisible: (v: boolean) => void) => {
    // Scroll to top first to prevent white space issues on mobile
    window.scrollTo({ top: 0, behavior: 'instant' });
    setShow(true);
    requestAnimationFrame(() => {
      requestAnimationFrame(() => {
        setVisible(true);
      });
    });
  };

  const closeModal = (setShow: (v: boolean) => void, setVisible: (v: boolean) => void) => {
    setVisible(false);
    setTimeout(() => {
      setShow(false);
    }, 150);
  };

  // Modal open/close handlers
  const openProfileEditor = () => openModal(setShowProfileEditor, setIsProfileEditorVisible);
  const closeProfileEditor = () => closeModal(setShowProfileEditor, setIsProfileEditorVisible);
  
  const openServiceSpecialties = () => openModal(setShowServiceSpecialties, setIsServiceSpecialtiesVisible);
  const closeServiceSpecialties = () => closeModal(setShowServiceSpecialties, setIsServiceSpecialtiesVisible);
  
  const openCampusManager = () => openModal(setShowCampusManagerDashboard, setIsCampusManagerVisible);
  const closeCampusManager = () => closeModal(setShowCampusManagerDashboard, setIsCampusManagerVisible);
  
  const openAdminDashboard = () => openModal(setShowAdminDashboard, setIsAdminDashboardVisible);
  const closeAdminDashboard = () => closeModal(setShowAdminDashboard, setIsAdminDashboardVisible);
  
  const openBarberChats = () => openModal(setShowBarberChats, setIsBarberChatsVisible);
  const closeBarberChats = () => closeModal(setShowBarberChats, setIsBarberChatsVisible);
  
  const openBookings = () => openModal(setShowBookings, setIsBookingsVisible);
  const closeBookings = () => closeModal(setShowBookings, setIsBookingsVisible);
  
  const openLocations = () => openModal(setShowLocations, setIsLocationsVisible);
  const closeLocations = () => closeModal(setShowLocations, setIsLocationsVisible);
  
  const openAvailability = () => openModal(setShowAvailability, setIsAvailabilityVisible);
  const closeAvailability = () => closeModal(setShowAvailability, setIsAvailabilityVisible);
  
  // Get barber data from auth - in production this would come from API
  const { user, isLoading: isAuthLoading } = useAuthStore();
  const barberId = user?.id || '';
  const isCampusManager = user?.is_campus_manager || user?.user_type === 'campus_manager';
  
  // Role-based access control: Only barbers, campus managers, and admins can access this page
  // Consumers/students should be redirected to the consumer page
  const isAuthorizedForBarberPage = 
    user?.user_type === 'barber' || 
    user?.user_type === 'campus_manager' || 
    user?.user_type === 'admin' ||
    user?.has_barber_profile;
  
  useEffect(() => {
    // Don't redirect while auth is still loading - wait for fresh user data from /me endpoint
    if (isAuthLoading) return;
    
    if (user && !isAuthorizedForBarberPage) {
      console.warn('Unauthorized access to BarberPage. Redirecting to consumer page.', {
        userId: user.id,
        userType: user.user_type,
        hasBarberProfile: user.has_barber_profile
      });
      toast.error('You need a barber profile to access this page');
      navigate(`${platformPrefix}/consumer`);
    }
  }, [user, isAuthorizedForBarberPage, isAuthLoading, navigate, platformPrefix]);

  // State for booking details modal
  const [selectedBookingForDetails, setSelectedBookingForDetails] = useState<any | null>(null);
  const [bookingsRefreshKey, setBookingsRefreshKey] = useState(0);
  
  // State for barber profile data (for walk-in services, campus manager, and time blocking)
  const [barberProfile, setBarberProfile] = useState<{ id: string; name: string; specialties: string[]; campusId?: string; campusTimezone?: string } | null>(null);

  // Admin campus management - admins can manage any campus
  const isAdmin = user?.is_admin || user?.user_type === 'admin';
  const [allCampuses, setAllCampuses] = useState<Campus[]>([]);
  const [selectedAdminCampusId, setSelectedAdminCampusId] = useState<string>('');
  const [showCampusSelector, setShowCampusSelector] = useState(false);
  const [campusSearchQuery, setCampusSearchQuery] = useState('');
  const campusSelectorRef = useRef<HTMLDivElement>(null);
  const [totalPlatformUsers, setTotalPlatformUsers] = useState<number | null>(null);
  const [isLoadingPlatformStats, setIsLoadingPlatformStats] = useState(false);
  
  // Admin Dashboard specific state
  const [adminDashboardCampusId, setAdminDashboardCampusId] = useState<string | null>(null);
  const [adminCampusSearchQuery, setAdminCampusSearchQuery] = useState('');
  const [showAdminCampusDropdown, setShowAdminCampusDropdown] = useState(false);
  const adminCampusDropdownRef = useRef<HTMLDivElement>(null);
  
  // Campus Manager assignment state
  const [campusBarbersForManager, setCampusBarbersForManager] = useState<Array<{id: string; firstName: string; lastName: string; isCampusManager: boolean}>>([]);
  const [selectedCampusManagerId, setSelectedCampusManagerId] = useState<string>('');
  const [isAssigningCampusManager, setIsAssigningCampusManager] = useState(false);
  

  // Use barber profile campusId (from barbers table) for campus manager, fallback to user's campus_id
  // For admins, use the selected campus (or first available campus)
  const defaultCampusId = barberProfile?.campusId || user?.campus_id || '';
  const campusId = isAdmin && selectedAdminCampusId ? selectedAdminCampusId : defaultCampusId;
  
  // Find the current campus name from the list
  const currentCampus = allCampuses.find(c => c.id?.toString() === campusId);
  const campusName = currentCampus?.name || '';
  
  // Format campus name for display - remove trailing "University" except for "University of X" names
  const formatCampusName = (name: string) => {
    if (name.startsWith('University of ')) return name;
    if (name.endsWith(' University')) return name.slice(0, -11);
    return name;
  };

  // Fetch all campuses for admin users
  useEffect(() => {
    const fetchCampuses = async () => {
      if (!isAdmin) return;
      try {
        const campuses = await campusService.getCampuses();
        setAllCampuses(campuses);
        // Set initial selected campus if not already set
        if (!selectedAdminCampusId && campuses.length > 0) {
          // Default to user's campus if available, otherwise first campus
          const userCampus = campuses.find(c => c.id?.toString() === (user?.campus_id || ''));
          setSelectedAdminCampusId(userCampus?.id?.toString() || campuses[0]?.id?.toString() || '');
        }
      } catch (error) {
        console.error('Failed to fetch campuses for admin:', error);
      }
    };
    fetchCampuses();
  }, [isAdmin, user?.campus_id]);
  
  // Fetch barbers for selected admin dashboard campus (for manager assignment)
  useEffect(() => {
    const fetchCampusBarbersForManager = async () => {
      if (!isAdmin || !adminDashboardCampusId || !showAdminDashboard) {
        setCampusBarbersForManager([]);
        setSelectedCampusManagerId('');
        return;
      }
      try {
        const token = localStorage.getItem('accessToken');
        const adminApiUrl = API_BASE_URL.replace('/api/v1', '/api/admin');
        const response = await fetch(`${adminApiUrl}/campuses/${adminDashboardCampusId}/barbers`, {
          headers: { Authorization: `Bearer ${token}` },
        });
        const data = await response.json();
        if (data.success && data.barbers) {
          setCampusBarbersForManager(data.barbers);
          // Set current manager if any
          const currentManager = data.barbers.find((b: any) => b.isCampusManager);
          setSelectedCampusManagerId(currentManager?.id || '');
        }
      } catch (error) {
        console.error('Failed to fetch campus barbers:', error);
      }
    };
    fetchCampusBarbersForManager();
  }, [isAdmin, adminDashboardCampusId, showAdminDashboard]);

  // Fetch total platform users for admin view
  const fetchPlatformStats = useCallback(async () => {
    if (!isAdmin) return;
    setIsLoadingPlatformStats(true);
    const startTime = Date.now();
    try {
      // Admin routes are at /api/admin, not /api/v1/admin
      const token = localStorage.getItem('accessToken');
      const adminApiUrl = API_BASE_URL.replace('/api/v1', '/api/admin');
      const response = await fetch(`${adminApiUrl}/stats`, {
        headers: { Authorization: `Bearer ${token}` },
      });
      const data = await response.json();
      if (data.success && data.data?.total_users) {
        setTotalPlatformUsers(data.data.total_users);
      }
    } catch (error) {
      console.error('Failed to fetch platform stats:', error);
    } finally {
      // Ensure minimum 500ms animation for visual feedback
      const elapsed = Date.now() - startTime;
      const minDuration = 500;
      if (elapsed < minDuration) {
        await new Promise(resolve => setTimeout(resolve, minDuration - elapsed));
      }
      setIsLoadingPlatformStats(false);
    }
  }, [isAdmin]);

  useEffect(() => {
    fetchPlatformStats();
  }, [fetchPlatformStats]);
  
  // Handle campus manager assignment
  const handleCampusManagerChange = async (barberUserId: string) => {
    if (!adminDashboardCampusId) return;
    
    setIsAssigningCampusManager(true);
    try {
      const token = localStorage.getItem('accessToken');
      const adminApiUrl = API_BASE_URL.replace('/api/v1', '/api/admin');
      
      const response = await fetch(`${adminApiUrl}/campuses/${adminDashboardCampusId}/manager`, {
        method: 'POST',
        headers: { 
          Authorization: `Bearer ${token}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          barberUserId: barberUserId || null,
          action: barberUserId ? 'assign' : 'remove',
        }),
      });
      
      const data = await response.json();
      if (data.success) {
        setSelectedCampusManagerId(barberUserId);
        // Update the local barbers list to reflect the change
        setCampusBarbersForManager(prev => prev.map(b => ({
          ...b,
          isCampusManager: b.id === barberUserId,
        })));
        toast.success(barberUserId ? 'Campus manager assigned' : 'Campus manager removed');
      } else {
        toast.error(data.error || 'Failed to update campus manager');
      }
    } catch (error) {
      console.error('Failed to assign campus manager:', error);
      toast.error('Failed to update campus manager');
    } finally {
      setIsAssigningCampusManager(false);
    }
  };

  // Close campus selector when clicking outside
  useEffect(() => {
    const handleClickOutside = (event: MouseEvent) => {
      if (campusSelectorRef.current && !campusSelectorRef.current.contains(event.target as Node)) {
        setShowCampusSelector(false);
        setCampusSearchQuery('');
      }
    };
    
    if (showCampusSelector) {
      document.addEventListener('mousedown', handleClickOutside);
    }
    
    return () => {
      document.removeEventListener('mousedown', handleClickOutside);
    };
  }, [showCampusSelector]);

  // Close admin dashboard campus selector when clicking outside
  useEffect(() => {
    const handleClickOutside = (event: MouseEvent) => {
      if (adminCampusDropdownRef.current && !adminCampusDropdownRef.current.contains(event.target as Node)) {
        setShowAdminCampusDropdown(false);
        setAdminCampusSearchQuery('');
      }
    };
    
    if (showAdminCampusDropdown) {
      document.addEventListener('mousedown', handleClickOutside);
    }
    
    return () => {
      document.removeEventListener('mousedown', handleClickOutside);
    };
  }, [showAdminCampusDropdown]);

  // Fetch barber profile data for walk-in modal and campus manager
  useEffect(() => {
    const fetchBarberProfile = async () => {
      if (!barberId) return;
      try {
        const response = await api.get(`/barbers/user/${barberId}`);
        if (response) {
          const fullName = user ? `${user.first_name} ${user.last_name}`.trim() : 'Barber';
          setBarberProfile({
            id: response.id || '',
            name: response.name || fullName || 'Barber',
            specialties: response.specialties || [],
            campusId: response.campus_id || '',
            campusTimezone: response.campus_timezone || 'America/Los_Angeles'
          });
        }
      } catch (error) {
        console.error('Failed to fetch barber profile:', error);
      }
    };
    fetchBarberProfile();
  }, [barberId, user]);

  // Pull-to-refresh handler for mobile - reload the page
  const handlePullToRefresh = async () => {
    window.location.reload();
  };

  // Function to open booking details modal - receives full booking object
  const openBookingDetails = (booking: any) => {
    console.log('🔍 Opening booking details for:', booking.id);
    setSelectedBookingForDetails(booking);
    window.scrollTo({ top: 0, behavior: 'instant' });
    setShowBookingDetailsModal(true);
  };

  // Refresh bookings when a booking is updated
  const handleBookingUpdated = () => {
    setBookingsRefreshKey(prev => prev + 1);
  };

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

  return (
    <PullToRefresh onRefresh={handlePullToRefresh} className="min-h-screen bg-gray-50" disabled={isAnyModalOpen}>
      {/* Header */}
      <div className="bg-white shadow-sm border-b border-gray-200">
        <div className="max-w-7xl mx-auto px-3 sm:px-4 py-3 sm:py-4">
          <div className="flex items-center justify-between relative">
            {/* Left section - Messages + Campus Manager Badge */}
            <div className="flex items-center gap-2 sm:gap-4">
              {/* Consumer Chat Button */}
              <button
                onClick={() => navigate(`${platformPrefix}/barber/messages`)}
                className="flex items-center gap-2 px-3 sm:px-4 py-2 rounded-full bg-primary-50 hover:bg-primary-100 border border-primary-200 transition-colors relative"
                title="Consumer Chat"
              >
                <Send className="w-5 h-5 text-primary-600" />
                <span className="text-xs sm:text-sm font-semibold text-primary-700">Chats</span>
                {unreadMessages > 0 && (
                  <span className="absolute -top-1 -right-1 bg-red-500 text-white text-xs font-bold rounded-full min-w-[18px] h-[18px] flex items-center justify-center px-1">
                    {unreadMessages > 99 ? '99+' : unreadMessages}
                  </span>
                )}
              </button>
              
              {/* Role Badge */}
                {(isAdmin || isCampusManager) && (
                <div className="hidden sm:flex items-center px-3 py-1.5 rounded-full bg-gray-100 border border-gray-200">
                  <span className="text-xs font-semibold text-gray-600">{isAdmin ? 'Admin' : 'Campus Manager'}</span>
                </div>
                )}
              </div>
            
            {/* Center section - Logo always centered */}
            <div className="absolute left-1/2 transform -translate-x-1/2">
              <img src={CampusCutLogo} alt="CampusCut" className="h-10 sm:h-12 w-auto" />
            </div>
            
            {/* Right section - Booking Requests + Profile */}
            <div className="flex items-center gap-1.5 sm:gap-4">
              {/* Booking Requests Inbox */}
              <BarberBookingRequestsDropdown barberId={barberId} />

              {/* Profile Dropdown */}
              <div className="relative" ref={dropdownRef}>
              <button
                onClick={() => setShowProfileDropdown(!showProfileDropdown)}
                className="flex items-center gap-1 sm:gap-2 px-2 sm:px-3 py-2 rounded-lg hover:bg-gray-100 transition-colors"
              >
                <Avatar src={user?.profile_picture_url} alt={user?.first_name || 'Barber'} size="md" />
                <ChevronDown className={`w-4 h-4 text-gray-600 transition-transform ${showProfileDropdown ? 'rotate-180' : ''}`} />
              </button>

              {showProfileDropdown && (
                <div className="absolute right-0 mt-2 w-56 bg-white rounded-lg shadow-lg border border-gray-200 py-1 z-50 max-w-[calc(100vw-2rem)]">
                  <button
                    onClick={() => {
                      navigate(`${platformPrefix}/consumer`);
                      setShowProfileDropdown(false);
                    }}
                    className="w-full px-4 py-2 text-left text-sm text-primary-600 hover:bg-primary-50"
                  >
                    Switch to Consumer
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
                  <button
                    onClick={() => {
                      openServiceSpecialties();
                      setShowProfileDropdown(false);
                    }}
                    className="w-full px-4 py-2 text-left text-sm text-gray-700 hover:bg-gray-100 flex items-center gap-3"
                  >
                    <Scissors className="w-4 h-4 text-gray-500" />
                    Services
                  </button>
                  <button
                    onClick={() => {
                      openLocations();
                      setShowProfileDropdown(false);
                    }}
                    className="w-full px-4 py-2 text-left text-sm text-gray-700 hover:bg-gray-100 flex items-center gap-3"
                  >
                    <MapPin className="w-4 h-4 text-gray-500" />
                    Locations
                  </button>
                  <button
                    onClick={() => {
                      openBookings();
                      setShowProfileDropdown(false);
                    }}
                    className="w-full px-4 py-2 text-left text-sm text-gray-700 hover:bg-gray-100 flex items-center gap-3"
                  >
                    <Calendar className="w-4 h-4 text-gray-500" />
                    Bookings
                  </button>
                  <button
                    onClick={() => {
                      openAvailability();
                      setShowProfileDropdown(false);
                    }}
                    className="w-full px-4 py-2 text-left text-sm text-gray-700 hover:bg-gray-100 flex items-center gap-3"
                  >
                    <Clock className="w-4 h-4 text-gray-500" />
                    Availability
                  </button>
                  <button
                    onClick={() => {
                      setShowBlockTimeModal(true);
                      setShowProfileDropdown(false);
                    }}
                    className="w-full px-4 py-2 text-left text-sm text-gray-700 hover:bg-gray-100 flex items-center gap-3"
                  >
                    <AlertTriangle className="w-4 h-4 text-gray-500" />
                    Block Time
                  </button>
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
                  <button
                    onClick={() => {
                      setShowPayoutSettings(true);
                      setShowProfileDropdown(false);
                    }}
                    className="w-full px-4 py-2 text-left text-sm text-gray-700 hover:bg-gray-100 flex items-center gap-3"
                  >
                    <Landmark className="w-4 h-4 text-gray-500" />
                    Payout Settings
                  </button>
                  {/* Barber Chats (for non-CM barbers) */}
                  {!isCampusManager && (
                    <>
                      <div className="border-t border-gray-200 my-1"></div>
                      <button
                        onClick={() => {
                          setShowProfileDropdown(false);
                          openBarberChats();
                        }}
                        className="w-full px-4 py-2 text-left text-sm text-gray-700 hover:bg-gray-100"
                      >
                        Barber Chats
                      </button>
                    </>
                  )}
                  {/* Admin Dashboard (ADMIN only) */}
                  {isAdmin && (
                    <>
                      <div className="border-t border-gray-200 my-1"></div>
                      <button
                        onClick={() => {
                          openAdminDashboard();
                          setShowProfileDropdown(false);
                        }}
                        className="w-full px-4 py-2 text-left text-sm text-gray-700 hover:bg-gray-100"
                      >
                        Admin Dashboard
                      </button>
                    </>
                  )}
                  {/* Campus Manager Options (conditional) */}
                  {isCampusManager && (
                    <>
                      <div className="border-t border-gray-200 my-1"></div>
                      <button
                        onClick={() => {
                          openCampusManager();
                          setShowProfileDropdown(false);
                        }}
                        className="w-full px-4 py-2 text-left text-sm text-gray-700 hover:bg-gray-100"
                      >
                        Campus Manager
                      </button>
                      <button
                        onClick={() => {
                          setShowProfileDropdown(false);
                          openBarberChats();
                        }}
                        className="w-full px-4 py-2 text-left text-sm text-gray-700 hover:bg-gray-100"
                      >
                        Barber Chats
                      </button>
                    </>
                  )}
                  
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
                      navigate('/web');
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

      {/* Content - Combined Dashboard & Requests */}
      <div className="max-w-7xl mx-auto px-3 sm:px-4 py-4 sm:py-8">
        <DashboardView 
          navigate={navigate} 
          barberId={barberId} 
          barberProfileId={barberProfile?.id} 
          onViewDetails={openBookingDetails} 
          onRefreshBookings={handleBookingUpdated} 
          refreshKey={bookingsRefreshKey} 
          campusTimezone={barberProfile?.campusTimezone || 'America/Los_Angeles'}
          onBlockTime={(date, startTime, endTime) => {
            setBlockTimeInitialValues({ date, startTime, endTime });
            setShowBlockTimeModal(true);
          }}
          onEditAvailability={openAvailability}
          onUnblockTime={async (blockId) => {
            if (!barberProfile?.id) return;
            try {
              await barberService.deleteTimeBlock(barberProfile.id, blockId);
              // WebSocket will handle the UI update via time-block-update event
            } catch (error) {
              console.error('Failed to unblock time:', error);
              toast.error('Failed to unblock time');
            }
          }}
          googleCalendarConnected={googleCalendarConnected}
          googleCalendarLoading={googleCalendarLoading}
          onConnectGoogleCalendar={connectGoogleCalendar}
          onDisconnectGoogleCalendar={disconnectGoogleCalendar}
        />
      </div>

      {/* Profile Editor Modal */}
      {showProfileEditor && (
        <div 
          className={`fixed inset-0 min-h-[100dvh] flex items-center justify-center z-50 p-2 sm:p-4 transition-all duration-150 ease-out ${isProfileEditorVisible ? 'bg-black/50' : 'bg-black/0'}`}
          onClick={closeProfileEditor}
        >
          <div 
            className={`bg-white rounded-xl shadow-2xl max-w-lg w-full max-h-[85dvh] sm:max-h-[80vh] overflow-y-auto transition-all duration-150 ease-out
              ${isProfileEditorVisible ? 'opacity-100 scale-100 translate-y-0' : 'opacity-0 scale-95 -translate-y-2'}`}
            onClick={(e) => e.stopPropagation()}
          >
            <div className="sticky top-0 bg-gradient-to-r from-primary-500 to-primary-400 text-white px-6 py-4 flex items-center justify-between z-10">
              <div>
                <h2 className="text-2xl font-bold">Edit Profile</h2>
                <p className="text-white/80 text-sm">Update your barber profile</p>
              </div>
              <button
                onClick={closeProfileEditor}
                className="text-white hover:bg-white/20 rounded-full p-2 transition-colors"
              >
                <X className="w-6 h-6" />
              </button>
            </div>
            <div className="p-6">
              <BarberProfileEditor userId={barberId} onClose={closeProfileEditor} />
            </div>
          </div>
        </div>
      )}

      {/* Service Specialties Modal */}
      {showServiceSpecialties && (
        <div 
          className={`fixed inset-0 min-h-[100dvh] flex items-center justify-center z-50 p-2 sm:p-4 transition-all duration-150 ease-out ${isServiceSpecialtiesVisible ? 'bg-black/50' : 'bg-black/0'}`}
          onClick={closeServiceSpecialties}
        >
          <div 
            className={`bg-white rounded-xl shadow-2xl max-w-5xl w-full max-h-[95dvh] sm:max-h-[90vh] overflow-y-auto transition-all duration-150 ease-out
              ${isServiceSpecialtiesVisible ? 'opacity-100 scale-100 translate-y-0' : 'opacity-0 scale-95 -translate-y-2'}`}
            onClick={(e) => e.stopPropagation()}
          >
            <div className="sticky top-0 bg-gradient-to-r from-primary-500 to-primary-400 text-white px-6 py-4 flex items-center justify-between z-10">
              <div>
                <h2 className="text-2xl font-bold">Services & Pricing</h2>
                <p className="text-white/80 text-sm">Manage your service offerings</p>
              </div>
              <button
                onClick={closeServiceSpecialties}
                className="text-white hover:bg-white/20 rounded-full p-2 transition-colors"
              >
                <X className="w-6 h-6" />
              </button>
            </div>
            <div className="p-6">
              <BarberServiceSpecialties barberId={barberId} />
            </div>
          </div>
        </div>
      )}

      {/* Campus Manager Dashboard Modal (conditional) */}
      {isCampusManager && showCampusManagerDashboard && (
        <div 
          className={`fixed inset-0 min-h-[100dvh] flex items-center justify-center z-50 p-2 sm:p-4 transition-all duration-150 ease-out ${isCampusManagerVisible ? 'bg-black/50' : 'bg-black/0'}`}
          onClick={closeCampusManager}
        >
          <div 
            className={`bg-white rounded-xl shadow-2xl max-w-3xl w-full max-h-[85vh] sm:max-h-[88vh] overflow-y-auto overscroll-contain transition-all duration-150 ease-out
              ${isCampusManagerVisible ? 'opacity-100 scale-100 translate-y-0' : 'opacity-0 scale-95 -translate-y-2'}`}
            onClick={(e) => e.stopPropagation()}
          >
            <div className="sticky top-0 bg-white border-b border-gray-200 px-4 sm:px-6 py-3 sm:py-4 flex items-center justify-between rounded-t-xl z-10">
              <div className="flex-1">
                <h2 className="text-lg sm:text-xl font-bold text-gray-900">Campus Manager Dashboard</h2>
                {/* Campus Selector for Admins */}
                {isAdmin && allCampuses.length > 0 && (
                  <div className="mt-2 relative" ref={campusSelectorRef}>
                    <div className="flex flex-col sm:flex-row sm:items-center gap-2 sm:gap-4">
                      <div className="relative max-w-xs">
                        <input
                          type="text"
                          value={showCampusSelector ? campusSearchQuery : (campusName ? formatCampusName(campusName) : '')}
                          onChange={(e) => {
                            setCampusSearchQuery(e.target.value);
                            if (!showCampusSelector) setShowCampusSelector(true);
                          }}
                          onFocus={() => {
                            setShowCampusSelector(true);
                            setCampusSearchQuery('');
                          }}
                          onBlur={(e) => {
                            // Delay to allow click on dropdown items to register first
                            setTimeout(() => {
                              // Only close if focus moved outside the selector container
                              if (campusSelectorRef.current && !campusSelectorRef.current.contains(document.activeElement)) {
                                setShowCampusSelector(false);
                                setCampusSearchQuery('');
                              }
                            }, 150);
                          }}
                          placeholder="Search campuses..."
                          className="w-full text-base text-gray-700 bg-gray-100 hover:bg-gray-200 focus:bg-white focus:ring-2 focus:ring-primary-500 px-3 py-1.5 pr-8 rounded-lg transition-colors border border-transparent focus:border-primary-300 outline-none"
                        />
                        <ChevronDown 
                          onClick={() => setShowCampusSelector(!showCampusSelector)}
                          className={`absolute right-2 top-1/2 -translate-y-1/2 w-4 h-4 text-gray-400 hover:text-gray-600 transition-transform cursor-pointer ${showCampusSelector ? 'rotate-180' : ''}`} 
                        />
                      </div>
                      {/* Total Platform Users - Admin Only */}
                      {totalPlatformUsers !== null && (
                        <div className="relative flex items-center gap-2 text-sm text-gray-700 bg-gray-100 pl-3 pr-8 py-1.5 rounded-lg">
                          <span>Total Users:</span>
                          <span className="font-semibold text-primary-600">{totalPlatformUsers.toLocaleString()}</span>
                          <button
                            onClick={fetchPlatformStats}
                            disabled={isLoadingPlatformStats}
                            className="absolute right-2 top-1/2 -translate-y-1/2 p-0.5 hover:bg-gray-200 rounded-full transition-colors disabled:opacity-50"
                            title="Refresh user count"
                          >
                            <RefreshCw className={`w-3.5 h-3.5 text-gray-400 hover:text-gray-600 ${isLoadingPlatformStats ? 'animate-spin' : ''}`} />
                          </button>
                        </div>
                      )}
                    </div>
                    
                    {/* Campus Dropdown */}
                    {showCampusSelector && (
                      <div className="absolute top-full left-0 mt-1 bg-white border border-gray-200 rounded-lg shadow-lg z-20 min-w-[300px] max-h-[300px] overflow-y-auto overscroll-contain">
                        <div className="p-2">
                          {allCampuses
                            .filter(campus => {
                              if (!campusSearchQuery) return true;
                              const query = campusSearchQuery.toLowerCase();
                              return (
                                campus.name?.toLowerCase().includes(query) ||
                                campus.city?.toLowerCase().includes(query) ||
                                campus.state?.toLowerCase().includes(query)
                              );
                            })
                            .map((campus) => (
                              <button
                                key={campus.id}
                                onClick={() => {
                                  setSelectedAdminCampusId(campus.id?.toString() || '');
                                  setShowCampusSelector(false);
                                  setCampusSearchQuery('');
                                }}
                                className={`w-full text-left px-3 py-2 rounded-md text-sm transition-colors ${
                                  campus.id?.toString() === campusId
                                    ? 'bg-primary-100 text-primary-700 font-medium'
                                    : 'hover:bg-gray-100 text-gray-700'
                                }`}
                              >
                                <div className="font-medium">{campus.name ? formatCampusName(campus.name) : ''}</div>
                                {campus.city && campus.state && (
                                  <div className="text-xs text-gray-500">{campus.city}, {campus.state}</div>
                                )}
                              </button>
                            ))}
                          {allCampuses.filter(campus => {
                            if (!campusSearchQuery) return true;
                            const query = campusSearchQuery.toLowerCase();
                            return (
                              campus.name?.toLowerCase().includes(query) ||
                              campus.city?.toLowerCase().includes(query) ||
                              campus.state?.toLowerCase().includes(query)
                            );
                          }).length === 0 && (
                            <p className="text-sm text-gray-500 px-3 py-2">No campuses found</p>
                          )}
                        </div>
                      </div>
                    )}
                  </div>
                )}
                {/* Show campus name for non-admin campus managers */}
                {!isAdmin && campusName && (
                  <p className="text-sm text-gray-500 mt-1">
                    {formatCampusName(campusName)}
                  </p>
                )}
              </div>
              <button
                onClick={closeCampusManager}
                className="text-gray-400 hover:text-gray-600 hover:bg-gray-100 rounded-full p-1 transition-colors"
              >
                <X className="w-6 h-6" />
              </button>
            </div>
            <div className="p-4 sm:p-6">
              <CampusManagerDashboard campusId={campusId} campusName={campusName ? formatCampusName(campusName) : ''} />
            </div>
          </div>
        </div>
      )}

      {/* Admin Dashboard Modal (ADMIN only) */}
      {isAdmin && showAdminDashboard && (
        <div 
          className={`fixed inset-0 min-h-[100dvh] flex items-center justify-center z-50 p-2 sm:p-4 transition-all duration-150 ease-out ${isAdminDashboardVisible ? 'bg-black/50' : 'bg-black/0'}`}
          onClick={closeAdminDashboard}
        >
          <div 
            className={`bg-white rounded-xl shadow-2xl max-w-3xl w-full max-h-[85vh] sm:max-h-[88vh] overflow-y-auto overscroll-contain transition-all duration-150 ease-out
              ${isAdminDashboardVisible ? 'opacity-100 scale-100 translate-y-0' : 'opacity-0 scale-95 -translate-y-2'}`}
            onClick={(e) => e.stopPropagation()}
          >
            <div className="sticky top-0 bg-white border-b border-gray-200 px-4 sm:px-6 py-3 sm:py-4 flex items-start justify-between rounded-t-xl z-10">
              <div className="flex-1">
                {/* Campus Selector Row */}
                <div className="relative" ref={adminCampusDropdownRef}>
                  <div className="flex flex-col sm:flex-row sm:items-center gap-2 sm:gap-4">
                    {/* Campus Search Input */}
                    <div className="relative max-w-xs">
                      <input
                        type="text"
                        value={showAdminCampusDropdown ? adminCampusSearchQuery : (adminDashboardCampusId ? formatCampusName(allCampuses.find(c => c.id?.toString() === adminDashboardCampusId)?.name || '') : '')}
                        onChange={(e) => {
                          setAdminCampusSearchQuery(e.target.value);
                          if (!showAdminCampusDropdown) setShowAdminCampusDropdown(true);
                        }}
                        onFocus={() => {
                          setShowAdminCampusDropdown(true);
                          setAdminCampusSearchQuery('');
                        }}
                        placeholder="All Universities"
                        className="w-full text-base text-gray-700 bg-gray-100 hover:bg-gray-200 focus:bg-white focus:ring-2 focus:ring-primary-500 px-3 py-1.5 pr-8 rounded-lg transition-colors border border-transparent focus:border-primary-300 outline-none"
                      />
                      <ChevronDown
                        onClick={() => setShowAdminCampusDropdown(!showAdminCampusDropdown)}
                        className={`absolute right-2 top-1/2 -translate-y-1/2 w-4 h-4 text-gray-400 hover:text-gray-600 transition-transform cursor-pointer ${showAdminCampusDropdown ? 'rotate-180' : ''}`}
                      />
                    </div>
                    {/* Campus Manager Selector (only when campus selected) */}
                    {adminDashboardCampusId && (
                      <div className="flex items-center gap-2 px-3 py-1.5 bg-gray-100 rounded-lg w-full sm:w-auto max-w-xs sm:max-w-none">
                        <p className="text-sm text-gray-700 whitespace-nowrap flex-shrink-0">Campus Manager:</p>
                        <select
                          value={selectedCampusManagerId}
                          onChange={(e) => handleCampusManagerChange(e.target.value)}
                          disabled={isAssigningCampusManager}
                          className="text-sm bg-transparent focus:outline-none disabled:opacity-50 cursor-pointer text-primary-600 font-semibold flex-1 min-w-0"
                        >
                          <option value="">No campus manager assigned</option>
                          {campusBarbersForManager.map(barber => (
                            <option key={barber.id} value={barber.id}>
                              {barber.firstName} {barber.lastName}
                            </option>
                          ))}
                        </select>
                      </div>
                    )}
                  </div>
                  {/* Campus Dropdown */}
                  {showAdminCampusDropdown && (
                    <div className="absolute top-full left-0 mt-1 bg-white border border-gray-200 rounded-lg shadow-lg z-20 min-w-[300px] max-h-[300px] overflow-y-auto overscroll-contain">
                      <div className="p-2">
                        {allCampuses
                          .filter(campus => {
                            if (!adminCampusSearchQuery) return true;
                            const query = adminCampusSearchQuery.toLowerCase();
                            return campus.name.toLowerCase().includes(query) ||
                                   campus.city?.toLowerCase().includes(query) ||
                                   campus.state?.toLowerCase().includes(query);
                          })
                          .map(campus => (
                            <button
                              key={campus.id}
                              onClick={() => {
                                setAdminDashboardCampusId(campus.id?.toString() || null);
                                setShowAdminCampusDropdown(false);
                                setAdminCampusSearchQuery('');
                              }}
                              className={`w-full text-left px-3 py-2 rounded-md text-sm transition-colors ${
                                campus.id?.toString() === adminDashboardCampusId
                                  ? 'bg-primary-100 text-primary-700 font-medium'
                                  : 'hover:bg-gray-100 text-gray-700'
                              }`}
                            >
                              <div className="font-medium">{formatCampusName(campus.name)}</div>
                              <div className="text-xs text-gray-500">{campus.city}, {campus.state}</div>
                            </button>
                          ))}
                      </div>
                    </div>
                  )}
                </div>
              </div>
              <button
                onClick={closeAdminDashboard}
                className="text-gray-400 hover:text-gray-600 hover:bg-gray-100 rounded-full p-1 transition-colors ml-2"
              >
                <X className="w-6 h-6" />
              </button>
            </div>
            <div className="p-4 sm:p-6">
              <AdminDashboard 
                campuses={allCampuses}
                selectedCampusId={adminDashboardCampusId || ''}
                onCampusIdChange={(id) => setAdminDashboardCampusId(id)}
                isLoadingCampuses={false}
                hideHeader={true}
              />
            </div>
          </div>
        </div>
      )}

      {/* Barber-to-Barber Chats Modal (for all barbers) */}
      {showBarberChats && (
        <BarberChatsModal
          isVisible={isBarberChatsVisible}
          onClose={closeBarberChats}
          onSelectBarber={(barberUserId: string, conversationId: number | null) => {
            closeBarberChats();
            if (conversationId) {
              navigate(`${platformPrefix}/barber/messages/${conversationId}`);
            } else {
              // Start new conversation and navigate
              import('../services/message.service').then(async (mod) => {
                const result = await mod.default.startBarberConversation(barberUserId);
                navigate(`${platformPrefix}/barber/messages/${result.conversationId}`);
              }).catch(console.error);
            }
          }}
        />
      )}

      <PaymentManagementModal
        isOpen={showPayoutSettings}
        onClose={() => setShowPayoutSettings(false)}
      />

      {/* Block Time Modal - One-time date-specific availability blocks */}
      {barberProfile?.id && (
        <BlockTimeModal
          isVisible={showBlockTimeModal}
          onClose={() => {
            setShowBlockTimeModal(false);
            setBlockTimeInitialValues({});
          }}
          barberId={barberProfile.id}
          initialDate={blockTimeInitialValues.date}
          initialStartTime={blockTimeInitialValues.startTime}
          initialEndTime={blockTimeInitialValues.endTime}
        />
      )}

      {/* Service Details Modal */}
      {selectedAppointment && (
        <ServiceDetailsModal
          isOpen={showServiceDetails}
          onClose={() => {
            setShowServiceDetails(false);
            setSelectedAppointment(null);
          }}
          appointment={selectedAppointment}
        />
      )}

      {/* Bookings Modal */}
      {showBookings && (
        <BookingsModal 
          isVisible={isBookingsVisible} 
          onClose={closeBookings}
          barberId={barberId}
        />
      )}

      {/* Locations Modal */}
      {showLocations && (
        <BarberLocationsModal 
          isVisible={isLocationsVisible} 
          onClose={closeLocations}
        />
      )}

      {/* Booking Details Modal - for schedule view bookings */}
      <BookingDetailsModal
        isOpen={showBookingDetailsModal}
        onClose={() => {
          setShowBookingDetailsModal(false);
          setSelectedBookingForDetails(null);
        }}
        booking={selectedBookingForDetails}
        onBookingUpdated={handleBookingUpdated}
      />

      {/* Availability Modal */}
      {showAvailability && (
        <AvailabilityModal 
          isVisible={isAvailabilityVisible} 
          onClose={closeAvailability}
          userId={user?.id}
        />
      )}

      {/* Walk-in Payment Modal - Feature disabled
      <WalkInPaymentModal
        isOpen={showWalkInPayment}
        onClose={() => setShowWalkInPayment(false)}
        barberName={barberProfile?.name || (user ? `${user.first_name} ${user.last_name}`.trim() : 'Barber')}
        barberSpecialties={barberProfile?.specialties || []}
      />
      */}

      {/* Notifications Modal */}
      {showNotifications && (
        <div 
          className={`fixed inset-0 min-h-[100dvh] bg-black/50 z-50 flex items-center justify-center p-4 transition-all duration-150 ease-out ${isNotificationsVisible ? 'opacity-100' : 'opacity-0'}`}
          onClick={closeNotifications}
        >
          <div 
            className={`bg-white rounded-2xl shadow-2xl max-w-md w-full max-h-[80dvh] sm:max-h-[80vh] overflow-hidden flex flex-col transition-all duration-150 ease-out ${
              isNotificationsVisible ? 'opacity-100 scale-100 translate-y-0' : 'opacity-0 scale-95 translate-y-4'
            }`}
            onClick={(e) => e.stopPropagation()}
          >
            {/* Header */}
            <div className="flex-shrink-0 bg-gradient-to-r from-primary-500 to-primary-400 px-6 py-4 flex items-center justify-between">
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

            {/* Filter Tabs */}
            <div className="flex-shrink-0 px-4 py-2 border-b border-gray-200 bg-gray-50 overflow-x-auto">
              <div className="flex gap-1 min-w-max">
                {[
                  { key: 'all', label: 'All' },
                  { key: 'bookings', label: 'Bookings' },
                  { key: 'payments', label: 'Payments' },
                  { key: 'reviews', label: 'Reviews' },
                  { key: 'cancellations', label: 'Cancelled' },
                  { key: 'messages', label: 'Messages' },
                ].map((tab) => (
                  <button
                    key={tab.key}
                    onClick={() => setNotificationFilter(tab.key as any)}
                    className={`px-3 py-1.5 text-xs font-medium rounded-full transition-colors whitespace-nowrap ${
                      notificationFilter === tab.key
                        ? 'bg-primary-500 text-white'
                        : 'bg-white text-gray-600 hover:bg-gray-100 border border-gray-200'
                    }`}
                  >
                    {tab.label}
                  </button>
                ))}
              </div>
            </div>

            {/* Content */}
            <div className="flex-1 min-h-0 overflow-y-auto">
              {notifications.length === 0 ? (
                <div className="p-8 text-center">
                  <Bell className="w-12 h-12 text-gray-300 mx-auto mb-3" />
                  <p className="text-gray-500">No notifications yet</p>
          </div>
              ) : (
                <div className="divide-y divide-gray-100">
                  {notifications
                    .filter((notification) => {
                      if (notificationFilter === 'all') return true;
                      const notifType = (notification.type || '').toLowerCase().trim();
                      const title = (notification.title || '').toLowerCase();
                      
                      switch (notificationFilter) {
                        case 'bookings':
                          return notifType === 'new_booking_request' || notifType === 'booking_accepted' || 
                                 title.includes('booking request') || title.includes('booking confirmed');
                        case 'payments':
                          return notifType === 'payment_received' || title.includes('payment');
                        case 'reviews':
                          return notifType === 'review' || notifType === 'new_review' || title.includes('review') || title.includes('star');
                        case 'cancellations':
                          return notifType === 'booking_rejected' || notifType === 'booking_cancelled' || title.includes('cancelled') || title.includes('rejected');
                        case 'messages':
                          return notifType === 'new_message' || title.includes('message');
                        default:
                          return true;
                      }
                    })
                    .map((notification) => {
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
                        navigate(`${platformPrefix}/barber/messages/${data.conversationId}`);
                        closeNotifications();
                      } else if (notifType === 'new_booking_request') {
                        // Stay on barber page, close modal - dashboard shows requests
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
                  {/* Empty state for filtered results */}
                  {notifications.filter((notification) => {
                    if (notificationFilter === 'all') return true;
                    const notifType = (notification.type || '').toLowerCase().trim();
                    const title = (notification.title || '').toLowerCase();
                    
                    switch (notificationFilter) {
                      case 'bookings':
                        return notifType === 'new_booking_request' || notifType === 'booking_accepted' || 
                               title.includes('booking request') || title.includes('booking confirmed');
                      case 'payments':
                        return notifType === 'payment_received' || title.includes('payment');
                      case 'reviews':
                        return notifType === 'review' || notifType === 'new_review' || title.includes('review') || title.includes('star');
                      case 'cancellations':
                        return notifType === 'booking_rejected' || notifType === 'booking_cancelled' || title.includes('cancelled') || title.includes('rejected');
                      case 'messages':
                        return notifType === 'new_message' || title.includes('message');
                      default:
                        return true;
                    }
                  }).length === 0 && (
                    <div className="p-8 text-center">
                      <Bell className="w-10 h-10 text-gray-300 mx-auto mb-2" />
                      <p className="text-gray-500 text-sm">No {notificationFilter} notifications</p>
                    </div>
                  )}
                </div>
      )}
    </div>

            {/* Footer */}
            <div className="px-6 py-4 border-t border-gray-200 bg-gray-50 flex-shrink-0">
              <Button
                onClick={closeNotifications}
                variant="secondary"
                className="w-full text-lg py-3"
              >
                Close
              </Button>
            </div>
          </div>
        </div>
      )}
    </PullToRefresh>
  );
}

interface DashboardViewProps {
  navigate: any;
  barberId: string;
  barberProfileId?: string; // ID from barbers table (for API calls that need it)
  onViewDetails: (booking: any) => void;
  onRefreshBookings?: () => void; // Callback to trigger refresh without opening modal
  refreshKey?: number;
  campusTimezone?: string;
  onBlockTime?: (date: string, startTime: string, endTime: string) => void; // Open block time modal with pre-filled values
  onEditAvailability?: () => void; // Open weekly availability modal
  onUnblockTime?: (blockId: string) => void; // Unblock a specific time block
  // Google Calendar integration
  googleCalendarConnected?: boolean | null;
  googleCalendarLoading?: boolean;
  onConnectGoogleCalendar?: () => void;
  onDisconnectGoogleCalendar?: () => void;
}

// Type for confirmed bookings
interface ConfirmedBooking {
  id: string;
  consumerId: string;
  barberId: string;
  serviceType: string;
  priceUsdCents: number;
  scheduledTime: string;
  status: string;
  createdAt: string;
  paidAt?: string;
  // Consumer-provided input data
  location?: string;
  notes?: string;
  serviceName?: string;
  // Review data (from consumer after service completion)
  review?: {
    rating: number;
    comment?: string;
    reviewedAt?: string;
  };
  consumer: {
    firstName: string;
    lastName: string;
    avatar?: string;
    email?: string;
    profilePictureUrl?: string;
  };
}

function DashboardView({ navigate, barberId, barberProfileId, onViewDetails, onRefreshBookings, refreshKey = 0, campusTimezone = 'America/Los_Angeles', onBlockTime, onEditAvailability, onUnblockTime, googleCalendarConnected, googleCalendarLoading, onConnectGoogleCalendar, onDisconnectGoogleCalendar }: DashboardViewProps) {
  // Get user from auth store for barber ID lookup
  const { user } = useAuthStore();
  const isAdmin = user?.is_admin || user?.user_type === 'admin';
  
  // Helper to get the current date in campus timezone
  const getTodayInCampusTimezone = () => {
    const now = new Date();
    // Get the date string in the campus timezone
    const dateStr = now.toLocaleDateString('en-CA', { timeZone: campusTimezone }); // 'en-CA' gives YYYY-MM-DD format
    const [year, month, day] = dateStr.split('-').map(Number);
    const campusToday = new Date(year, month - 1, day);
    campusToday.setHours(0, 0, 0, 0);
    return campusToday;
  };

  const [scheduleView, setScheduleView] = useState<'daily' | 'weekly' | 'monthly'>('daily');
  const [selectedDate, setSelectedDate] = useState<Date | null>(null); // Full date for modal
  const [showDayModal, setShowDayModal] = useState(false);
  const [isDayModalVisible, setIsDayModalVisible] = useState(false);
  const [monthOffset, setMonthOffset] = useState(0); // 0 = current month, 1 = next month, etc.
  const [weekOffset, setWeekOffset] = useState(0); // 0 = current week, 1 = next week, etc.
  const [dayOffset, setDayOffset] = useState(0); // 0 = today, 1 = tomorrow, etc.
  const [monthlyTimeBlocks, setMonthlyTimeBlocks] = useState<TimeBlock[]>([]); // Time blocks for calendar display
  const [weeklySchedule, setWeeklySchedule] = useState<any>(null); // Barber's weekly availability
  const [isLoadingWeeklySchedule, setIsLoadingWeeklySchedule] = useState(true); // Loading state for availability
  const [googleCalendarBusyTimes, setGoogleCalendarBusyTimes] = useState<Array<{ start: Date; end: Date }>>([]); // Google Calendar busy times
  const [availabilityRefreshKey, setAvailabilityRefreshKey] = useState(0); // Trigger refresh when availability changes
  const modalRef = useRef<HTMLDivElement>(null);
  const scheduleContainerRef = useRef<HTMLDivElement>(null);
  
  // Inline booking details state (shown within DayModal instead of separate popup)
  const [selectedBookingInline, setSelectedBookingInline] = useState<ConfirmedBooking | null>(null);
  const [isEditingBooking, setIsEditingBooking] = useState(false);
  const [isDeletingBooking, setIsDeletingBooking] = useState(false);
  const [isRemovingBooking, setIsRemovingBooking] = useState(false);
  const [isUndoingComplete, setIsUndoingComplete] = useState(false);
  const [isSavingBooking, setIsSavingBooking] = useState(false);
  const [cancelReason, setCancelReason] = useState('');
  const [editedDate, setEditedDate] = useState('');
  const [editedTime, setEditedTime] = useState('');
  const [editedLocation, setEditedLocation] = useState('');
  const [barberLocations, setBarberLocations] = useState<{id: string; name: string; description: string | null}[]>([]);
  const [barberIdForEdit, setBarberIdForEdit] = useState('');
  
  // Confirmed bookings state
  const [confirmedBookings, setConfirmedBookings] = useState<ConfirmedBooking[]>([]);
  const [isLoadingBookings, setIsLoadingBookings] = useState(true);
  
  // Viewport detection for responsive layout
  const { isMobile, isMobilePortrait, isTablet } = useViewport();

  // Fetch time blocks for calendar display
  useEffect(() => {
    const fetchMonthlyTimeBlocks = async () => {
      if (!barberProfileId) return;
      try {
        // Calculate start and end dates for current displayed month
        const today = new Date();
        const displayDate = new Date(today.getFullYear(), today.getMonth() + monthOffset, 1);
        const firstDayOfMonth = new Date(displayDate.getFullYear(), displayDate.getMonth(), 1);
        const lastDayOfMonth = new Date(displayDate.getFullYear(), displayDate.getMonth() + 1, 0);
        
        const startDate = `${firstDayOfMonth.getFullYear()}-${String(firstDayOfMonth.getMonth() + 1).padStart(2, '0')}-01`;
        const endDate = `${lastDayOfMonth.getFullYear()}-${String(lastDayOfMonth.getMonth() + 1).padStart(2, '0')}-${String(lastDayOfMonth.getDate()).padStart(2, '0')}`;
        
        const blocks = await barberService.getTimeBlocks(barberProfileId, startDate, endDate);
        setMonthlyTimeBlocks(blocks);
      } catch (error) {
        console.error('Failed to fetch monthly time blocks:', error);
        setMonthlyTimeBlocks([]);
      }
    };
    fetchMonthlyTimeBlocks();
  }, [barberProfileId, monthOffset]);

  // Fetch Google Calendar busy times when connected
  useEffect(() => {
    const fetchGoogleCalendarBusyTimes = async () => {
      // Only fetch if Google Calendar is connected
      if (!googleCalendarConnected) {
        setGoogleCalendarBusyTimes([]);
        return;
      }
      
      try {
        // Get busy times for current week + next 2 weeks
        const now = new Date();
        const startDate = new Date(now.getFullYear(), now.getMonth(), now.getDate());
        const endDate = new Date(startDate);
        endDate.setDate(endDate.getDate() + 21); // 3 weeks ahead
        
        const data = await api.get<{ busyTimes: Array<{ start: string; end: string }> }>(
          `/auth/google-calendar/busy-times?startDate=${startDate.toISOString()}&endDate=${endDate.toISOString()}`
        );
        
        if (data?.busyTimes) {
          setGoogleCalendarBusyTimes(data.busyTimes.map(bt => ({
            start: new Date(bt.start),
            end: new Date(bt.end)
          })));
        }
      } catch (error) {
        // Silently fail - Google Calendar is optional
        setGoogleCalendarBusyTimes([]);
      }
    };
    
    fetchGoogleCalendarBusyTimes();
  }, [googleCalendarConnected, dayOffset, weekOffset, monthOffset]);

  // Fetch barber's weekly availability schedule
  useEffect(() => {
    // Skip fetch if we don't have the barber profile ID yet
    if (!barberProfileId) {
      console.log('[DashboardView] Waiting for barberProfileId...');
      return;
    }
    
    let isMounted = true;
    
    const fetchWeeklySchedule = async () => {
      console.log('[DashboardView] Fetching weekly schedule for barber:', barberProfileId);
      setIsLoadingWeeklySchedule(true);
      try {
        // Add cache-busting timestamp to prevent stale 304 responses on initial load
        const response = await api.get(`/barbers/${barberProfileId}/availability`, {
          _t: Date.now() // Cache buster
        });
        
        if (!isMounted) return;
        
        console.log('[DashboardView] Received weekly schedule:', response?.weeklySchedule ? 'has data' : 'empty');
        
        // Set the schedule even if empty (to distinguish from loading state)
        if (response?.weeklySchedule !== undefined) {
          setWeeklySchedule(response.weeklySchedule);
        } else {
          // If no weeklySchedule in response, set empty object
          setWeeklySchedule({});
        }
      } catch (error) {
        console.error('[DashboardView] Failed to fetch weekly schedule:', error);
        if (isMounted) {
          // Set empty object on error so UI doesn't stay in loading state
          setWeeklySchedule({});
        }
      } finally {
        if (isMounted) {
          setIsLoadingWeeklySchedule(false);
        }
      }
    };
    
    fetchWeeklySchedule();
    
    return () => {
      isMounted = false;
    };
  }, [barberProfileId, availabilityRefreshKey]);
  
  // Fetch confirmed bookings using the API service (handles auth automatically)
  useEffect(() => {
    const fetchConfirmedBookings = async () => {
      try {
        setIsLoadingBookings(true);
        // Fetch ACCEPTED, COMPLETED, and PAID bookings for the barber's schedule
        const response = await api.get<{ bookings: ConfirmedBooking[] }>('/bookings-simple', {
          role: 'barber',
          status: 'ACCEPTED,COMPLETED,PAID',
        });
        
        setConfirmedBookings(response.bookings || []);
      } catch (error) {
        console.error('Error fetching confirmed bookings:', error);
      } finally {
        setIsLoadingBookings(false);
      }
    };
    
    fetchConfirmedBookings();
  }, [refreshKey]);

  // Listen for live booking updates via WebSocket
  useEffect(() => {
    // Ensure socket is connected
    socketService.connect();
    
    const handleBookingUpdate = (updatedBooking: any) => {
      console.log('📬 Received booking-update event:', updatedBooking);
      
      setConfirmedBookings(prevBookings => {
        // If booking was cancelled, remove it from the list
        if (updatedBooking.cancelled || updatedBooking.status?.toUpperCase() === 'CANCELLED') {
          console.log('🗑️ Removing cancelled booking from list:', updatedBooking.id);
          return prevBookings.filter(b => b.id !== updatedBooking.id);
        }
        
        // Check if this booking already exists in our list
        const existingIndex = prevBookings.findIndex(b => b.id === updatedBooking.id);
        
        if (existingIndex !== -1) {
          // Update existing booking in place
          const updated = [...prevBookings];
          updated[existingIndex] = {
            ...updated[existingIndex],
            scheduledTime: updatedBooking.scheduledTime || updated[existingIndex].scheduledTime,
            location: updatedBooking.location !== undefined ? updatedBooking.location : updated[existingIndex].location,
            notes: updatedBooking.notes !== undefined ? updatedBooking.notes : updated[existingIndex].notes,
            status: updatedBooking.status || updated[existingIndex].status,
          };
          console.log('📝 Updated booking in list:', updatedBooking.id);
          return updated;
        }
        
        // Booking not in our list - this could be a new booking that was just accepted
        // Don't add it inline since we don't have all the required data
        // The parent component will handle new bookings via notification refresh
        console.log('ℹ️ Booking not in current list, may need refresh:', updatedBooking.id);
        return prevBookings;
      });
    };
    
    socketService.onBookingUpdate(handleBookingUpdate);
    
    // Listen for newly confirmed bookings (when barber accepts a request)
    const handleBookingConfirmed = (newBooking: any) => {
      console.log('📬 Received booking-confirmed event:', newBooking);
      
      setConfirmedBookings(prevBookings => {
        // Check if this booking already exists
        const existingIndex = prevBookings.findIndex(b => b.id === newBooking.id);
        if (existingIndex !== -1) {
          console.log('ℹ️ Booking already in list, skipping:', newBooking.id);
          return prevBookings;
        }
        
        // Add the new booking to the list
        const formattedBooking: ConfirmedBooking = {
          id: newBooking.id,
          consumerId: newBooking.consumerId || '',
          barberId: newBooking.barberId || '',
          scheduledTime: newBooking.scheduledTime,
          location: newBooking.location || '',
          notes: newBooking.notes || '',
          status: newBooking.status || 'ACCEPTED',
          serviceType: newBooking.serviceType,
          priceUsdCents: newBooking.priceUsdCents || 0,
          createdAt: new Date().toISOString(),
          consumer: {
            firstName: newBooking.consumer?.firstName || '',
            lastName: newBooking.consumer?.lastName || '',
            avatar: newBooking.consumer?.profilePictureUrl,
            email: newBooking.consumer?.email,
            profilePictureUrl: newBooking.consumer?.profilePictureUrl,
          },
        };
        
        console.log('✅ Adding newly confirmed booking to dashboard:', newBooking.id);
        return [...prevBookings, formattedBooking];
      });
    };
    
    socketService.onBookingConfirmed(handleBookingConfirmed);
    
    // Listen for payment received events (when consumer pays)
    const handlePaymentReceived = (data: {
      bookingId: string;
      consumerName: string;
      totalFormatted: string;
      tipFormatted?: string;
    }) => {
      console.log('💰 Received payment-received event:', data);
      toast.success(
        `Payment received from ${data.consumerName}: ${data.totalFormatted}${data.tipFormatted ? ` (includes ${data.tipFormatted} tip)` : ''}`,
        { duration: 5000 }
      );
      
      // Remove the booking from the dashboard since it's now completed
      setConfirmedBookings(prevBookings => 
        prevBookings.filter(b => b.id !== data.bookingId)
      );
    };
    
    socketService.onPaymentReceived(handlePaymentReceived);
    
    // Listen for time block updates (when blocks are created/deleted)
    const handleTimeBlockUpdate = (data: {
      barberId: string;
      action: 'created' | 'deleted';
      timeBlock?: { id: string; blockDate: string; startTime: string; endTime: string };
      blockId?: string;
    }) => {
      console.log('🚫 Received time-block-update event:', data);
      
      if (data.action === 'created' && data.timeBlock) {
        setMonthlyTimeBlocks(prev => [...prev, {
          id: data.timeBlock!.id,
          blockDate: data.timeBlock!.blockDate,
          startTime: data.timeBlock!.startTime,
          endTime: data.timeBlock!.endTime,
          createdAt: new Date().toISOString()
        }]);
        toast.success('Time blocked successfully');
      } else if (data.action === 'deleted' && data.blockId) {
        setMonthlyTimeBlocks(prev => prev.filter(block => block.id !== data.blockId));
        toast.success('Time block removed');
      }
    };
    
    socketService.onTimeBlockUpdate(handleTimeBlockUpdate);
    
    // Listen for availability updates (when weekly schedule changes)
    const handleAvailabilityUpdate = (data: { barberId: string }) => {
      console.log('📅 Received availability-update event:', data);
      // Trigger a refresh of the weekly schedule
      setAvailabilityRefreshKey(prev => prev + 1);
      toast.success('Availability updated');
    };
    
    socketService.onAvailabilityUpdate(handleAvailabilityUpdate);
    
    return () => {
      socketService.offBookingUpdate(handleBookingUpdate);
      socketService.offBookingConfirmed(handleBookingConfirmed);
      socketService.offPaymentReceived(handlePaymentReceived);
      socketService.offTimeBlockUpdate(handleTimeBlockUpdate);
      socketService.offAvailabilityUpdate(handleAvailabilityUpdate);
    };
  }, []);

  // Touch/swipe state for switching views
  const touchStartX = useRef<number | null>(null);
  const touchStartY = useRef<number | null>(null);
  const lastWheelTime = useRef<number>(0);

  const views: ('daily' | 'weekly' | 'monthly')[] = ['daily', 'weekly', 'monthly'];
  
  const switchToNextView = () => {
    const currentIndex = views.indexOf(scheduleView);
    if (currentIndex < views.length - 1) {
      setScheduleView(views[currentIndex + 1]);
    }
  };

  const switchToPrevView = () => {
    const currentIndex = views.indexOf(scheduleView);
    if (currentIndex > 0) {
      setScheduleView(views[currentIndex - 1]);
    }
  };

  // Touch handlers for mobile swipe
  const handleTouchStart = (e: React.TouchEvent) => {
    touchStartX.current = e.touches[0].clientX;
    touchStartY.current = e.touches[0].clientY;
  };

  const handleTouchEnd = (e: React.TouchEvent) => {
    if (touchStartX.current === null || touchStartY.current === null) return;
    
    const touchEndX = e.changedTouches[0].clientX;
    const touchEndY = e.changedTouches[0].clientY;
    const deltaX = touchEndX - touchStartX.current;
    const deltaY = touchEndY - touchStartY.current;
    
    // Only trigger if horizontal swipe is dominant and significant (>50px)
    if (Math.abs(deltaX) > 50 && Math.abs(deltaX) > Math.abs(deltaY) * 1.5) {
      if (deltaX < 0) {
        // Swipe left -> next view
        switchToNextView();
      } else {
        // Swipe right -> previous view
        switchToPrevView();
      }
    }
    
    touchStartX.current = null;
    touchStartY.current = null;
  };

  // Use native wheel event listener to properly prevent browser back/forward navigation
  useEffect(() => {
    const container = scheduleContainerRef.current;
    if (!container) return;

    const handleWheel = (e: WheelEvent) => {
      // Only respond to horizontal scroll (deltaX) which is 2-finger swipe on trackpad
      if (Math.abs(e.deltaX) > 30 && Math.abs(e.deltaX) > Math.abs(e.deltaY)) {
        // Prevent browser back/forward navigation
        e.preventDefault();
        
        // Debounce to prevent rapid switching
        const now = Date.now();
        if (now - lastWheelTime.current < 300) return;
        
        lastWheelTime.current = now;
        if (e.deltaX > 0) {
          // Scroll right -> next view
          setScheduleView(prev => {
            const idx = views.indexOf(prev);
            return idx < views.length - 1 ? views[idx + 1] : prev;
          });
        } else {
          // Scroll left -> previous view
          setScheduleView(prev => {
            const idx = views.indexOf(prev);
            return idx > 0 ? views[idx - 1] : prev;
          });
        }
      }
    };

    // Add with passive: false to allow preventDefault
    container.addEventListener('wheel', handleWheel, { passive: false });
    return () => container.removeEventListener('wheel', handleWheel);
  }, []);

  // Day modal open/close handlers with animation
  const openDayModal = (date: Date) => {
    setSelectedDate(date);
    // Scroll to bottom to prevent pull-to-refresh from activating while popup is open
    window.scrollTo({ top: document.body.scrollHeight, behavior: 'instant' });
    setShowDayModal(true);
    requestAnimationFrame(() => {
      requestAnimationFrame(() => {
        setIsDayModalVisible(true);
      });
    });
  };

  const closeDayModal = () => {
    setIsDayModalVisible(false);
    setTimeout(() => {
      setShowDayModal(false);
      setSelectedDate(null);
      // Reset inline booking state
      setSelectedBookingInline(null);
      setIsEditingBooking(false);
      setIsDeletingBooking(false);
      setIsRemovingBooking(false);
      setCancelReason('');
      // Scroll back to top when modal closes
      window.scrollTo({ top: 0, behavior: 'instant' });
    }, 150);
  };

  // Initialize editable fields when a booking is selected for inline view
  const selectBookingForInlineView = (booking: ConfirmedBooking) => {
    setSelectedBookingInline(booking);
    const scheduledTime = new Date(booking.scheduledTime);
    // Format date as YYYY-MM-DD for DatePicker
    setEditedDate(scheduledTime.toISOString().split('T')[0]);
    const hours = String(scheduledTime.getHours()).padStart(2, '0');
    const minutes = String(scheduledTime.getMinutes()).padStart(2, '0');
    setEditedTime(`${hours}:${minutes}`);
    setEditedLocation(booking.location || '');
    setIsEditingBooking(false);
    setIsDeletingBooking(false);
    setIsRemovingBooking(false);
    setCancelReason('');
  };

  // Back to appointments list
  const backToAppointmentsList = () => {
    setSelectedBookingInline(null);
    setIsEditingBooking(false);
    setIsDeletingBooking(false);
    setIsRemovingBooking(false);
    setCancelReason('');
  };

  // Start editing booking - fetch barber ID and locations
  const startEditingBooking = async () => {
    // Fetch the barber's own ID and locations
    if (user?.id) {
      try {
        // Get barber ID
        const barberResponse = await api.get<{ id: string }>(`/barbers/user/${user.id}`);
        const barberId = barberResponse?.id || '';
        setBarberIdForEdit(barberId);
        console.log('[BarberPage] Barber ID for edit:', barberId);
        
        // Fetch locations for this barber
        if (barberId) {
          const locationsResponse = await fetch(`${import.meta.env.VITE_API_URL}/locations/for-booking/${barberId}`, {
            headers: {
              'Authorization': `Bearer ${localStorage.getItem('accessToken')}`,
            },
          });
          if (locationsResponse.ok) {
            const locData = await locationsResponse.json();
            setBarberLocations(locData.data || []);
            console.log('[BarberPage] Loaded locations:', locData.data);
          }
        }
      } catch (error) {
        console.error('Failed to fetch barber data for edit:', error);
      }
    }
    
    setIsEditingBooking(true);
  };

  // Handle saving booking changes
  const handleSaveBookingChanges = async () => {
    if (!selectedBookingInline) return;
    
    // Validate date (YYYY-MM-DD format from DatePicker)
    if (!editedDate) {
      toast.error('Please select a date');
      return;
    }
    
    // Validate time (HH:MM format from time picker)
    if (!editedTime) {
      toast.error('Please select a time');
      return;
    }

    setIsSavingBooking(true);
    try {
      // Combine date (YYYY-MM-DD) and time (HH:MM) into ISO string
      const newScheduledTime = new Date(`${editedDate}T${editedTime}`);
      
      if (isNaN(newScheduledTime.getTime())) {
        toast.error('Invalid date or time selected');
        setIsSavingBooking(false);
        return;
      }
      
      // Track what changed for the success message
      const originalDate = selectedBookingInline.scheduledTime 
        ? new Date(selectedBookingInline.scheduledTime) 
        : null;
      const originalLocation = selectedBookingInline.location || '';
      
      const changes: string[] = [];
      
      // Check if date changed
      if (originalDate && originalDate.toDateString() !== newScheduledTime.toDateString()) {
        changes.push('date');
      }
      
      // Check if time changed
      if (originalDate && (originalDate.getHours() !== newScheduledTime.getHours() || originalDate.getMinutes() !== newScheduledTime.getMinutes())) {
        changes.push('time');
      }
      
      // Check if location changed
      if ((editedLocation || '') !== originalLocation) {
        changes.push('location');
      }
      
      await api.put(`/bookings-simple/${selectedBookingInline.id}`, {
        scheduledTime: newScheduledTime.toISOString(),
        location: editedLocation || null,
      });
      
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
      closeDayModal(); // Close the modal entirely
      if (onRefreshBookings) onRefreshBookings(); // Trigger refresh without reopening modal
    } catch (error: any) {
      console.error('Failed to update booking:', error);
      toast.error(error.message || 'Failed to update booking');
    } finally {
      setIsSavingBooking(false);
    }
  };

  // Handle canceling booking
  const handleCancelBooking = async () => {
    if (!selectedBookingInline) return;
    
    setIsSavingBooking(true);
    try {
      await api.delete(`/bookings-simple/${selectedBookingInline.id}`, {
        reason: cancelReason || undefined,
      });
      toast.success('Booking cancelled successfully');
      closeDayModal();
      if (onRefreshBookings) onRefreshBookings(); // Trigger refresh without reopening modal
    } catch (error: any) {
      console.error('Failed to cancel booking:', error);
      toast.error(error.message || 'Failed to cancel booking');
    } finally {
      setIsSavingBooking(false);
    }
  };

  // Handle removing completed booking from schedule
  const handleRemoveBooking = async () => {
    if (!selectedBookingInline) return;
    
    setIsSavingBooking(true);
    try {
      await api.delete(`/bookings-simple/${selectedBookingInline.id}`);
      toast.success('Booking removed from schedule');
      closeDayModal();
      if (onRefreshBookings) onRefreshBookings();
    } catch (error: any) {
      console.error('Failed to remove booking:', error);
      toast.error(error.message || 'Failed to remove booking');
    } finally {
      setIsSavingBooking(false);
    }
  };

  // Handle completing booking (request payment)
  const handleCompleteBooking = async () => {
    if (!selectedBookingInline) return;
    
    try {
      await api.post(`/bookings-simple/${selectedBookingInline.id}/request-payment`, {});
      toast.success('Payment request sent to customer');
      closeDayModal();
      navigate(`/web/payment/${selectedBookingInline.id}`);
    } catch (error: any) {
      console.error('Failed to request payment:', error);
      toast.error(error.message || 'Failed to request payment');
    }
  };

  // Handle undoing a completed booking (revert to ACCEPTED)
  const handleUndoComplete = async () => {
    if (!selectedBookingInline) return;
    
    setIsSavingBooking(true);
    try {
      await api.put(`/bookings-simple/${selectedBookingInline.id}/undo-complete`, {});
      toast.success('Booking reverted to accepted');
      setIsUndoingComplete(false);
      closeDayModal();
      if (onRefreshBookings) onRefreshBookings();
    } catch (error: any) {
      console.error('Failed to undo complete:', error);
      toast.error(error.message || 'Failed to undo completion');
    } finally {
      setIsSavingBooking(false);
    }
  };

  // Close modal when clicking outside
  useEffect(() => {
    const handleClickOutside = (event: MouseEvent) => {
      if (modalRef.current && !modalRef.current.contains(event.target as Node)) {
        closeDayModal();
      }
    };

    if (showDayModal) {
      document.addEventListener('mousedown', handleClickOutside);
      return () => document.removeEventListener('mousedown', handleClickOutside);
    }
  }, [showDayModal]);

  // Get appointments for a specific date from confirmed bookings
  const getAppointmentsForDate = (date: Date): ConfirmedBooking[] => {
    const targetDate = new Date(date);
    targetDate.setHours(0, 0, 0, 0);
    const nextDay = new Date(targetDate);
    nextDay.setDate(nextDay.getDate() + 1);
    
    return confirmedBookings
      .filter(booking => {
        const bookingDate = new Date(booking.scheduledTime);
        return bookingDate >= targetDate && bookingDate < nextDay;
      })
      .sort((a, b) => new Date(a.scheduledTime).getTime() - new Date(b.scheduledTime).getTime());
  };

  const handleDayClick = (date: Date) => {
    openDayModal(date);
  };

  return (
    <>
      {/* Schedule Section - Top Priority */}
      <Card>
        <div
          ref={scheduleContainerRef}
          onTouchStart={handleTouchStart}
          onTouchEnd={handleTouchEnd}
          className="touch-pan-y p-4 pb-0"
        >
        <div className="flex flex-col items-center gap-3 mb-4">
          {/* Jump to Today/This Week/This Month button - shown when offset is non-zero */}
          {((scheduleView === 'daily' && dayOffset !== 0) || 
            (scheduleView === 'weekly' && weekOffset !== 0) || 
            (scheduleView === 'monthly' && monthOffset !== 0)) && (
            <button 
              onClick={() => {
                if (scheduleView === 'daily') setDayOffset(0);
                else if (scheduleView === 'weekly') setWeekOffset(0);
                else setMonthOffset(0);
              }}
              className="px-3 py-1.5 text-sm bg-primary-100 text-primary-700 rounded-lg hover:bg-primary-200 transition-colors font-medium"
            >
              {scheduleView === 'daily' ? 'Today' : scheduleView === 'weekly' ? 'This Week' : 'This Month'}
            </button>
          )}
          
          {/* Appointments Count - centered above toggle buttons */}
          <p className="text-sm sm:text-base text-gray-600 font-medium">
            {(() => {
              const today = getTodayInCampusTimezone();
              
              if (scheduleView === 'daily') {
                const displayDate = new Date(today);
                displayDate.setDate(displayDate.getDate() + dayOffset);
                const nextDay = new Date(displayDate);
                nextDay.setDate(nextDay.getDate() + 1);
                const count = confirmedBookings.filter(b => {
                  const bookingDate = new Date(b.scheduledTime);
                  return bookingDate >= displayDate && bookingDate < nextDay;
                }).length;
                return `${count} appointment${count !== 1 ? 's' : ''}`;
              } else if (scheduleView === 'weekly') {
                const todayDay = today.getDay();
                const startOfWeek = new Date(today);
                const daysFromMonday = todayDay === 0 ? 6 : todayDay - 1;
                startOfWeek.setDate(today.getDate() - daysFromMonday + (weekOffset * 7));
                startOfWeek.setHours(0, 0, 0, 0);
                const endOfWeek = new Date(startOfWeek);
                endOfWeek.setDate(startOfWeek.getDate() + 7);
                const count = confirmedBookings.filter(b => {
                  const bookingDate = new Date(b.scheduledTime);
                  return bookingDate >= startOfWeek && bookingDate < endOfWeek;
                }).length;
                const weekWord = weekOffset === 0 ? 'this' : 'that';
                return `${count} appointment${count !== 1 ? 's' : ''} ${weekWord} week`;
              } else {
                const displayDate = new Date(today.getFullYear(), today.getMonth() + monthOffset, 1);
                const displayMonth = displayDate.getMonth();
                const displayYear = displayDate.getFullYear();
                const count = confirmedBookings.filter(b => {
                  const bookingDate = new Date(b.scheduledTime);
                  return bookingDate.getMonth() === displayMonth && bookingDate.getFullYear() === displayYear;
                }).length;
                const monthWord = monthOffset === 0 ? 'this' : 'that';
                return `${count} appointment${count !== 1 ? 's' : ''} ${monthWord} month`;
              }
            })()}
          </p>

          {/* View Toggle Buttons */}
          <div className="grid grid-cols-3 gap-2 sm:gap-3 justify-items-center">
            {/* Walk-in feature disabled
            <div></div>
            <button
              onClick={onWalkInClick}
              className="px-4 sm:px-6 py-2.5 sm:py-3 bg-green-600 hover:bg-green-700 text-white rounded-xl transition-colors text-sm sm:text-base font-semibold min-w-[5rem] sm:min-w-[6rem] text-center"
              title="Quick payment for walk-in customers"
            >
              Walk-in
            </button>
            <div></div>
            */}
            
            {/* Daily Button */}
            <button
              onClick={() => setScheduleView('daily')}
              className={`px-4 sm:px-6 py-2.5 sm:py-3 rounded-xl text-sm sm:text-base font-semibold transition-colors min-w-[5rem] sm:min-w-[6rem] ${
                scheduleView === 'daily'
                  ? 'bg-primary-400 text-white'
                  : 'bg-gray-100 text-gray-700 hover:bg-gray-200'
              }`}
            >
              Daily
            </button>
            {/* Weekly Button */}
            <button
              onClick={() => setScheduleView('weekly')}
              className={`px-4 sm:px-6 py-2.5 sm:py-3 rounded-xl text-sm sm:text-base font-semibold transition-colors min-w-[5rem] sm:min-w-[6rem] ${
                scheduleView === 'weekly'
                  ? 'bg-primary-400 text-white'
                  : 'bg-gray-100 text-gray-700 hover:bg-gray-200'
              }`}
            >
              Weekly
            </button>
            {/* Monthly Button */}
            <button
              onClick={() => setScheduleView('monthly')}
              className={`px-4 sm:px-6 py-2.5 sm:py-3 rounded-xl text-sm sm:text-base font-semibold transition-colors min-w-[5rem] sm:min-w-[6rem] ${
                scheduleView === 'monthly'
                  ? 'bg-primary-400 text-white'
                  : 'bg-gray-100 text-gray-700 hover:bg-gray-200'
              }`}
            >
              Monthly
            </button>
          </div>

          {/* Date Navigation - below toggle buttons */}
          {scheduleView === 'daily' && (
            <div className="flex items-center gap-2">
              <button 
                onClick={() => setDayOffset(prev => prev - 1)}
                className="p-1.5 hover:bg-gray-100 rounded-lg transition-colors"
              >
                <ChevronLeft className="w-5 h-5 text-gray-600" />
              </button>
              <h3 className="text-lg sm:text-xl font-bold text-gray-900 min-w-[200px] sm:min-w-[280px] text-center">
                {dayOffset === 0 ? 'Today - ' : dayOffset === 1 ? 'Tomorrow - ' : dayOffset === -1 ? 'Yesterday - ' : ''}
                {(() => {
                  const today = getTodayInCampusTimezone();
                  const displayDate = new Date(today);
                  displayDate.setDate(displayDate.getDate() + dayOffset);
                  return displayDate.toLocaleDateString('en-US', { weekday: 'long', month: 'long', day: 'numeric', year: 'numeric' });
                })()}
              </h3>
              <button 
                onClick={() => setDayOffset(prev => prev + 1)}
                className="p-1.5 hover:bg-gray-100 rounded-lg transition-colors"
              >
                <ChevronRight className="w-5 h-5 text-gray-600" />
              </button>
            </div>
          )}

          {/* Weekly Date Navigation */}
          {scheduleView === 'weekly' && (
            <div className="flex items-center gap-2">
              <button 
                onClick={() => setWeekOffset(prev => prev - 1)}
                className="p-1.5 hover:bg-gray-100 rounded-lg transition-colors"
              >
                <ChevronLeft className="w-5 h-5 text-gray-600" />
              </button>
              <h3 className="text-lg sm:text-xl font-bold text-gray-900 min-w-[200px] sm:min-w-[280px] text-center">
                {(() => {
                  const today = getTodayInCampusTimezone();
                  const todayDay = today.getDay();
                  const startOfWeek = new Date(today);
                  const daysFromMonday = todayDay === 0 ? 6 : todayDay - 1;
                  startOfWeek.setDate(today.getDate() - daysFromMonday + (weekOffset * 7));
                  const endOfWeek = new Date(startOfWeek);
                  endOfWeek.setDate(startOfWeek.getDate() + 6);
                  const startMonth = startOfWeek.toLocaleDateString('en-US', { month: 'long' });
                  const endMonth = endOfWeek.toLocaleDateString('en-US', { month: 'long' });
                  const year = endOfWeek.getFullYear();
                  return startMonth === endMonth 
                    ? `${startMonth} ${startOfWeek.getDate()} - ${endOfWeek.getDate()}, ${year}`
                    : `${startMonth} ${startOfWeek.getDate()} - ${endMonth} ${endOfWeek.getDate()}, ${year}`;
                })()}
              </h3>
              <button 
                onClick={() => setWeekOffset(prev => prev + 1)}
                className="p-1.5 hover:bg-gray-100 rounded-lg transition-colors"
              >
                <ChevronRight className="w-5 h-5 text-gray-600" />
              </button>
            </div>
          )}

          {/* Monthly Date Navigation */}
          {scheduleView === 'monthly' && (
            <div className="flex items-center gap-2">
              <button 
                onClick={() => setMonthOffset(prev => prev - 1)}
                className="p-1.5 hover:bg-gray-100 rounded-lg transition-colors"
              >
                <ChevronLeft className="w-5 h-5 text-gray-600" />
              </button>
              <h3 className="text-lg sm:text-xl font-bold text-gray-900 min-w-[160px] text-center">
                {(() => {
                  const today = getTodayInCampusTimezone();
                  const displayDate = new Date(today.getFullYear(), today.getMonth() + monthOffset, 1);
                  return displayDate.toLocaleDateString('en-US', { month: 'long', year: 'numeric' });
                })()}
              </h3>
              <button 
                onClick={() => setMonthOffset(prev => prev + 1)}
                className="p-1.5 hover:bg-gray-100 rounded-lg transition-colors"
              >
                <ChevronRight className="w-5 h-5 text-gray-600" />
              </button>
            </div>
          )}
        </div>

        {/* Daily View */}
        {scheduleView === 'daily' && (() => {
          // Filter bookings for the selected day (using dayOffset) - using campus timezone
          const today = getTodayInCampusTimezone();
          const displayDate = new Date(today);
          displayDate.setDate(displayDate.getDate() + dayOffset);
          const nextDay = new Date(displayDate);
          nextDay.setDate(nextDay.getDate() + 1);
          
          const dailyAppointments = confirmedBookings
            .filter(booking => {
              const bookingDate = new Date(booking.scheduledTime);
              return bookingDate >= displayDate && bookingDate < nextDay;
            })
            .sort((a, b) => new Date(a.scheduledTime).getTime() - new Date(b.scheduledTime).getTime());

          const formatPrice = (cents: number) => `$${(cents / 100).toFixed(0)}`;
          const formatTime = (dateStr: string) => new Date(dateStr).toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit', timeZone: campusTimezone });
          const dayLabel = dayOffset === 0 ? 'Today' : dayOffset === 1 ? 'Tomorrow' : dayOffset === -1 ? 'Yesterday' : '';
          const dateFormatted = displayDate.toLocaleDateString('en-US', { weekday: 'long', month: 'long', day: 'numeric', year: 'numeric' });

          // Get availability for this day
          const dayNames = ['sunday', 'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday'] as const;
          const dayOfWeek = displayDate.getDay();
          const dayKey = dayNames[dayOfWeek];
          const daySchedule = weeklySchedule?.[dayKey];
          
          // Get time blocks for this day
          const dateStr = `${displayDate.getFullYear()}-${String(displayDate.getMonth() + 1).padStart(2, '0')}-${String(displayDate.getDate()).padStart(2, '0')}`;
          const dayBlocks = monthlyTimeBlocks.filter(block => block.blockDate === dateStr);
          
          // Get intervals (support both new and legacy format)
          let intervals: { start: string; end: string }[] = [];
          if (daySchedule?.enabled) {
            if (daySchedule.intervals && Array.isArray(daySchedule.intervals)) {
              intervals = daySchedule.intervals.map((i: any) => ({ start: i.start, end: i.end }));
            } else if (daySchedule.start && daySchedule.end) {
              intervals = [{ start: daySchedule.start, end: daySchedule.end }];
            }
          }
          
          // Format time for display (12-hour)
          const formatTime12 = (time: string) => {
            const [hours, minutes] = time.split(':').map(Number);
            const period = hours >= 12 ? 'PM' : 'AM';
            const displayHours = hours === 0 ? 12 : hours > 12 ? hours - 12 : hours;
            return `${displayHours}:${String(minutes).padStart(2, '0')} ${period}`;
          };
          
          // Generate hourly slots from intervals
          const generateHourlySlots = (intervals: { start: string; end: string }[]) => {
            const slots: { start: string; end: string }[] = [];
            intervals.forEach(interval => {
              const [startHour] = interval.start.split(':').map(Number);
              const [endHour] = interval.end.split(':').map(Number);
              for (let hour = startHour; hour < endHour; hour++) {
                slots.push({
                  start: `${String(hour).padStart(2, '0')}:00`,
                  end: `${String(hour + 1).padStart(2, '0')}:00`
                });
              }
            });
            return slots;
          };
          
          const hourlySlots = generateHourlySlots(intervals);
          
          // Helper to convert time to minutes
          const timeToMinutes = (time: string) => {
            const [h, m] = time.split(':').map(Number);
            return h * 60 + m;
          };
          
          // Helper to check if slot is blocked (manual block)
          const getBlockForSlot = (slot: { start: string; end: string }) => {
            const slotStart = timeToMinutes(slot.start);
            const slotEnd = timeToMinutes(slot.end);
            return dayBlocks.find(block => {
              const blockStart = timeToMinutes(block.startTime);
              const blockEnd = timeToMinutes(block.endTime);
              return slotStart < blockEnd && slotEnd > blockStart;
            });
          };
          
          // Helper to check if slot is blocked by Google Calendar
          const getGoogleCalendarBlockForSlot = (slot: { start: string; end: string }) => {
            const slotStart = timeToMinutes(slot.start);
            const slotEnd = timeToMinutes(slot.end);
            
            // Convert slot times to full Date for the displayed day
            const slotStartDate = new Date(displayDate);
            slotStartDate.setHours(Math.floor(slotStart / 60), slotStart % 60, 0, 0);
            const slotEndDate = new Date(displayDate);
            slotEndDate.setHours(Math.floor(slotEnd / 60), slotEnd % 60, 0, 0);
            
            return googleCalendarBusyTimes.find(busy => {
              // Check if this busy time overlaps with the slot on this day
              const busyStart = busy.start;
              const busyEnd = busy.end;
              
              // Check if busy time is on the same day and overlaps
              return (
                busyStart < slotEndDate && busyEnd > slotStartDate
              );
            });
          };
          
          // Helper to get appointment for slot
          const getAppointmentForSlot = (slot: { start: string; end: string }) => {
            const slotStart = timeToMinutes(slot.start);
            const slotEnd = timeToMinutes(slot.end);
            return dailyAppointments.find(apt => {
              const aptTime = new Date(apt.scheduledTime);
              const aptMinutes = aptTime.getHours() * 60 + aptTime.getMinutes();
              return aptMinutes >= slotStart && aptMinutes < slotEnd;
            });
          };
          
          const availableCount = hourlySlots.filter(slot => !getBlockForSlot(slot) && !getGoogleCalendarBlockForSlot(slot) && !getAppointmentForSlot(slot)).length;
          const bookedCount = hourlySlots.filter(slot => getAppointmentForSlot(slot)).length;
          const blockedCount = hourlySlots.filter(slot => (getBlockForSlot(slot) || getGoogleCalendarBlockForSlot(slot)) && !getAppointmentForSlot(slot)).length;

          return (
            <div className="max-w-2xl mx-auto">
              {isLoadingBookings || isLoadingWeeklySchedule ? (
                <div className="text-center py-8 sm:py-12">
                  <div className="animate-spin w-10 h-10 border-4 border-primary-200 border-t-primary-500 rounded-full mx-auto mb-4"></div>
                  <p className="text-gray-500">{isLoadingWeeklySchedule ? 'Loading availability...' : 'Loading appointments...'}</p>
                </div>
              ) : !daySchedule?.enabled || intervals.length === 0 ? (
                <div className="p-4 bg-gray-50 rounded-lg border border-gray-200 text-center">
                  <p className="text-sm text-gray-500 mb-3">Not available on {dayKey.charAt(0).toUpperCase() + dayKey.slice(1)}s</p>
                  <button
                    onClick={() => onEditAvailability?.()}
                    className="text-sm px-3 py-1.5 bg-primary-100 hover:bg-primary-200 text-primary-700 rounded-lg transition-colors inline-flex items-center gap-1.5"
                  >
                    <Settings className="w-4 h-4" />
                    Add Availability
                  </button>
                </div>
              ) : (
                <div>
                  {/* Google Calendar Integration Button - Hidden for now, functionality preserved */}
                  <div className="hidden flex justify-center mb-3">
                    {googleCalendarConnected === null ? (
                      <div className="px-4 py-2 bg-gray-100 text-gray-500 text-sm font-medium rounded-lg">
                        Checking Google Calendar...
                      </div>
                    ) : googleCalendarConnected ? (
                      <button
                        onClick={() => onDisconnectGoogleCalendar?.()}
                        className="px-4 py-2 bg-primary-100 hover:bg-primary-200 text-primary-700 text-sm font-medium rounded-lg transition-colors border border-primary-300 flex flex-col items-center"
                      >
                        <span>Google Calendar Connected</span>
                        <span className="text-xs text-primary-500 sm:hidden">(Tap to Disconnect)</span>
                        <span className="text-xs text-primary-500 hidden sm:inline">(Click to Disconnect)</span>
                      </button>
                    ) : (
                      <button
                        onClick={() => onConnectGoogleCalendar?.()}
                        disabled={googleCalendarLoading}
                        className="px-4 py-2 bg-white hover:bg-gray-50 text-gray-700 text-sm font-medium rounded-lg transition-colors border border-gray-300 flex items-center gap-2 shadow-sm disabled:opacity-50"
                      >
                        <svg className="w-4 h-4" viewBox="0 0 24 24">
                          <path fill="#4285F4" d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z"/>
                          <path fill="#34A853" d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z"/>
                          <path fill="#FBBC05" d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z"/>
                          <path fill="#EA4335" d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z"/>
                        </svg>
                        {googleCalendarLoading ? 'Connecting...' : 'Connect Google Calendar'}
                      </button>
                    )}
                  </div>
                  
                  {/* Edit Availability Button */}
                  <div className="flex justify-center mb-3">
                    <button
                      onClick={() => onEditAvailability?.()}
                      className="px-4 py-2 bg-primary-500 hover:bg-primary-600 text-white text-sm font-medium rounded-lg transition-colors shadow-sm"
                    >
                      <span className="sm:hidden">Tap here to Edit Availability</span>
                      <span className="hidden sm:inline">Click here to Edit Availability</span>
                    </button>
                  </div>
                  <div className="space-y-2">
                    {hourlySlots.map((slot, idx) => {
                      const block = getBlockForSlot(slot);
                      const appointment = getAppointmentForSlot(slot);
                      
                      // Appointment takes priority
                      if (appointment) {
                        const isCompleted = appointment.status === 'COMPLETED' || appointment.status === 'PAID';
                        return (
                          <div 
                            key={idx}
                            onClick={() => onViewDetails(appointment)}
                            className={`p-3 rounded-lg border transition-colors cursor-pointer ${
                              isCompleted 
                                ? 'bg-green-50 border-green-200 hover:border-green-400' 
                                : 'bg-blue-50 border-blue-200 hover:border-blue-400'
                            }`}
                          >
                            <div className="flex items-center justify-between">
                              <div>
                                <p className="text-sm font-semibold text-gray-900">
                                  {formatTime12(slot.start)} - {formatTime12(slot.end)}
                                </p>
                                <p className="text-sm text-gray-700">
                                  {appointment.consumer.firstName} {appointment.consumer.lastName}
                                </p>
                              </div>
                              <div className="text-right">
                                  <p className="text-xs text-gray-500 font-semibold">
                                    {appointment.serviceName || appointment.serviceType.toLowerCase().replace(/_/g, ' ').replace(/\b\w/g, (c: string) => c.toUpperCase())}
                                  </p>
                                <p className="font-bold text-green-600">${(appointment.priceUsdCents / 100).toFixed(0)}</p>
                              </div>
                            </div>
                          </div>
                        );
                      }
                      
                      // Blocked slot - with unblock option (manual block)
                      if (block) {
                        return (
                          <div 
                            key={idx}
                            className="px-3 py-2 bg-red-50 text-red-700 rounded-lg text-sm border border-red-200 flex items-center justify-between"
                          >
                            <div className="flex items-center gap-2">
                              <Clock className="w-4 h-4 text-red-500" />
                              <span className="font-medium">{formatTime12(slot.start)} - {formatTime12(slot.end)}</span>
                            </div>
                            <button
                              onClick={() => onUnblockTime?.(block.id)}
                              className="text-xs px-2 py-1 bg-red-100 hover:bg-red-200 text-red-700 font-medium rounded transition-colors border border-red-300"
                            >
                              Unblock
                            </button>
                          </div>
                        );
                      }
                      
                      // Google Calendar blocked slot - not unblockable from CampusCuts
                      const googleBlock = getGoogleCalendarBlockForSlot(slot);
                      if (googleBlock) {
                        return (
                          <div 
                            key={idx}
                            className="px-3 py-2 bg-blue-50 text-blue-700 rounded-lg text-sm border border-blue-200 flex items-center justify-between"
                          >
                            <div className="flex items-center gap-2">
                              <svg className="w-4 h-4" viewBox="0 0 24 24">
                                <path fill="#4285F4" d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z"/>
                                <path fill="#34A853" d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z"/>
                                <path fill="#FBBC05" d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z"/>
                                <path fill="#EA4335" d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z"/>
                              </svg>
                              <span className="font-medium">{formatTime12(slot.start)} - {formatTime12(slot.end)}</span>
                            </div>
                            <span className="text-xs text-blue-500">Google Calendar</span>
                          </div>
                        );
                      }
                      
                      // Available slot - clickable to block
                      return (
                        <div 
                          key={idx}
                          onClick={() => onBlockTime?.(dateStr, slot.start, slot.end)}
                          className="px-3 py-2 bg-primary-50 text-primary-700 rounded-lg text-sm font-medium border border-primary-200 flex items-center gap-2 cursor-pointer hover:bg-primary-100 hover:border-primary-300 transition-colors"
                        >
                          <div className="w-2 h-2 rounded-full bg-primary-400"></div>
                          {formatTime12(slot.start)} - {formatTime12(slot.end)}
                          <span className="text-xs text-primary-500 ml-auto sm:hidden">Tap to block</span>
                          <span className="text-xs text-primary-500 ml-auto hidden sm:inline">Click to block</span>
                        </div>
                      );
                    })}
                  </div>
                </div>
              )}
            </div>
          );
        })()}

        {/* Weekly View */}
        {scheduleView === 'weekly' && (() => {
          // Get the week based on weekOffset - using campus timezone
          const today = getTodayInCampusTimezone();
          const todayDay = today.getDay(); // 0 = Sunday, 1 = Monday, etc.
          
          // Calculate start of current week (Monday)
          const startOfWeek = new Date(today);
          const daysFromMonday = todayDay === 0 ? 6 : todayDay - 1;
          startOfWeek.setDate(today.getDate() - daysFromMonday);
          // Apply week offset
          startOfWeek.setDate(startOfWeek.getDate() + (weekOffset * 7));
          startOfWeek.setHours(0, 0, 0, 0);
          
          // Build week days array dynamically (handles month boundaries automatically)
          const weekDays = [];
          for (let i = 0; i < 7; i++) {
            const date = new Date(startOfWeek);
            date.setDate(startOfWeek.getDate() + i);
            weekDays.push({
              name: date.toLocaleDateString('en-US', { weekday: 'long' }),
              shortName: date.toLocaleDateString('en-US', { weekday: 'short' }),
              date: date.getDate(),
              month: date.toLocaleDateString('en-US', { month: 'short' }),
              fullDate: date,
            });
          }
          
          const endOfWeek = new Date(startOfWeek);
          endOfWeek.setDate(startOfWeek.getDate() + 7);
          
          // Group bookings by date
          const weekAppointmentsByDate: { [dateKey: string]: ConfirmedBooking[] } = {};
          confirmedBookings.forEach(booking => {
            const bookingDate = new Date(booking.scheduledTime);
            if (bookingDate >= startOfWeek && bookingDate < endOfWeek) {
              const dateKey = bookingDate.toDateString();
              if (!weekAppointmentsByDate[dateKey]) {
                weekAppointmentsByDate[dateKey] = [];
              }
              weekAppointmentsByDate[dateKey].push(booking);
            }
          });

          const totalWeekAppointments = Object.values(weekAppointmentsByDate).reduce((sum, arr) => sum + arr.length, 0);
          
          // Format week range - show month on both ends if they differ
          const startMonth = startOfWeek.toLocaleDateString('en-US', { month: 'long' });
          const endDate = new Date(endOfWeek.getTime() - 1);
          const endMonth = endDate.toLocaleDateString('en-US', { month: 'long' });
          const weekRangeText = startMonth === endMonth 
            ? `${startOfWeek.toLocaleDateString('en-US', { month: 'long', day: 'numeric' })} - ${endDate.toLocaleDateString('en-US', { day: 'numeric', year: 'numeric' })}`
            : `${startOfWeek.toLocaleDateString('en-US', { month: 'short', day: 'numeric' })} - ${endDate.toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' })}`;

          return (
            <div>
              {/* Mobile: List view */}
              <div className="sm:hidden space-y-2">
                {weekDays.map(day => {
                  const dayBookings = weekAppointmentsByDate[day.fullDate.toDateString()] || [];
                  const isToday = day.fullDate.toDateString() === today.toDateString();
                  // Get time blocks for this day
                  const dateStr = `${day.fullDate.getFullYear()}-${String(day.fullDate.getMonth() + 1).padStart(2, '0')}-${String(day.fullDate.getDate()).padStart(2, '0')}`;
                  const dayTimeBlocks = monthlyTimeBlocks.filter(block => block.blockDate === dateStr);
                  const hasTimeBlocks = dayTimeBlocks.length > 0;
                  // Count Google Calendar busy times for this day
                  const dayStart = new Date(day.fullDate);
                  dayStart.setHours(0, 0, 0, 0);
                  const dayEnd = new Date(day.fullDate);
                  dayEnd.setHours(23, 59, 59, 999);
                  const dayGoogleBlocks = googleCalendarBusyTimes.filter(bt => 
                    bt.start < dayEnd && bt.end > dayStart
                  );
                  const hasGoogleBlocks = dayGoogleBlocks.length > 0;

                  return (
                    <div
                      key={day.fullDate.toISOString()}
                      onClick={() => handleDayClick(day.fullDate)}
                      className={`flex items-center justify-between p-4 rounded-xl border active:scale-98 transition-all ${
                        isToday
                          ? 'bg-primary-400 text-white border-primary-500'
                          : 'bg-gray-50 border-gray-200'
                      } cursor-pointer`}
                    >
                      <div className="flex items-center gap-4">
                        <div className="text-center">
                          <div className={`text-3xl font-bold ${isToday ? 'text-white' : 'text-gray-900'}`}>{day.date}</div>
                          {/* Show month if different from first day of week */}
                          {day.month !== weekDays[0].month && (
                            <div className={`text-xs ${isToday ? 'text-white/70' : 'text-gray-500'}`}>{day.month}</div>
                          )}
                        </div>
                        <div>
                          <div className={`font-semibold text-base ${isToday ? 'text-white' : 'text-gray-900'}`}>{day.name}</div>
                          {(() => {
                            const completedCount = dayBookings.filter(b => b.status === 'COMPLETED' || b.status === 'PAID' || b.paidAt).length;
                            const pendingCount = dayBookings.filter(b => b.status === 'ACCEPTED').length;
                            
                            if (dayBookings.length === 0 && !hasTimeBlocks && !hasGoogleBlocks) {
                              return (
                                <div className={`text-sm ${isToday ? 'text-white/70' : 'text-gray-500'}`}>
                                  No appointments
                                </div>
                              );
                            }
                            
                            return (
                              <div className="flex flex-col gap-0.5">
                                {completedCount > 0 && (
                                  <div className={`text-sm ${isToday ? 'text-white/70' : 'text-green-700 font-bold'}`}>
                                    {completedCount} completed
                                  </div>
                                )}
                                {pendingCount > 0 && (
                                  <div className={`text-sm ${isToday ? 'text-white/70' : 'text-amber-600 font-bold'}`}>
                                    {pendingCount} booked
                                  </div>
                                )}
                                {hasTimeBlocks && (
                                  <div className={`text-sm ${isToday ? 'text-white/70' : 'text-red-500 font-bold'}`}>
                                    {dayTimeBlocks.length} blocked
                                  </div>
                                )}
                                {hasGoogleBlocks && (
                                  <div className={`text-sm ${isToday ? 'text-white/70' : 'text-blue-600 font-bold'}`}>
                                    {dayGoogleBlocks.length} calendar
                                  </div>
                                )}
                              </div>
                            );
                          })()}
                        </div>
                      </div>
                      <ChevronDown className={`w-6 h-6 -rotate-90 ${isToday ? 'text-white/70' : 'text-gray-400'}`} />
                    </div>
                  );
                })}
              </div>

              {/* Desktop: Grid view */}
              <div className="hidden sm:grid grid-cols-7 gap-4">
                {/* Week day headers */}
                {weekDays.map(day => (
                  <div key={day.fullDate.toISOString() + '-header'} className="text-center font-bold text-gray-600 text-base py-2">
                    {day.shortName}
                  </div>
                ))}
                {/* Week day cards */}
                {weekDays.map(day => {
                  const dayBookings = weekAppointmentsByDate[day.fullDate.toDateString()] || [];
                  const isToday = day.fullDate.toDateString() === today.toDateString();
                  // Get time blocks for this day
                  const dateStr = `${day.fullDate.getFullYear()}-${String(day.fullDate.getMonth() + 1).padStart(2, '0')}-${String(day.fullDate.getDate()).padStart(2, '0')}`;
                  const dayTimeBlocks = monthlyTimeBlocks.filter(block => block.blockDate === dateStr);
                  const hasTimeBlocks = dayTimeBlocks.length > 0;
                  // Count Google Calendar busy times for this day
                  const dayStartDesktop = new Date(day.fullDate);
                  dayStartDesktop.setHours(0, 0, 0, 0);
                  const dayEndDesktop = new Date(day.fullDate);
                  dayEndDesktop.setHours(23, 59, 59, 999);
                  const dayGoogleBlocksDesktop = googleCalendarBusyTimes.filter(bt => 
                    bt.start < dayEndDesktop && bt.end > dayStartDesktop
                  );
                  const hasGoogleBlocksDesktop = dayGoogleBlocksDesktop.length > 0;

                  return (
                    <div
                      key={day.fullDate.toISOString()}
                      onClick={() => handleDayClick(day.fullDate)}
                      className={`p-5 rounded-xl border overflow-hidden min-h-[160px] flex flex-col ${
                        isToday
                          ? 'bg-primary-400 text-white border-primary-500'
                          : 'bg-gray-50 border-gray-200 hover:border-primary-300'
                      } cursor-pointer transition-colors`}
                    >
                      <div className="text-center mb-4">
                        <div className="text-3xl font-bold mb-1">{day.date}</div>
                        <div className={`text-sm ${isToday ? 'text-white/80' : 'text-gray-500'}`}>
                          {/* Show month if different from first day of week */}
                          {day.month !== weekDays[0].month ? `${day.month} - ${day.name}` : day.name}
                        </div>
                      </div>
                      <div className="text-sm space-y-1.5 flex-1 overflow-hidden">
                        {(() => {
                          const completedCount = dayBookings.filter(b => b.status === 'COMPLETED' || b.status === 'PAID' || b.paidAt).length;
                          const pendingCount = dayBookings.filter(b => b.status === 'ACCEPTED').length;
                          
                          if (dayBookings.length === 0 && !hasTimeBlocks && !hasGoogleBlocksDesktop) {
                            return (
                              <div className={isToday ? 'text-white/60' : 'text-gray-400'}>No apts</div>
                            );
                          }
                          
                          return (
                            <div className="flex flex-col gap-0.5">
                              {completedCount > 0 && (
                                <div className={`${isToday ? 'text-white/80' : 'text-green-700 font-bold'}`}>
                                  {completedCount} completed
                                </div>
                              )}
                              {pendingCount > 0 && (
                                <div className={`${isToday ? 'text-white/80' : 'text-amber-600 font-bold'}`}>
                                  {pendingCount} booked
                                </div>
                              )}
                              {hasTimeBlocks && (
                                <div className={`${isToday ? 'text-white/70' : 'text-red-500 font-bold'}`}>
                                  {dayTimeBlocks.length} blocked
                                </div>
                              )}
                              {hasGoogleBlocksDesktop && (
                                <div className={`${isToday ? 'text-white/70' : 'text-blue-600 font-bold'}`}>
                                  {dayGoogleBlocksDesktop.length} calendar
                                </div>
                              )}
                            </div>
                          );
                        })()}
                      </div>
                    </div>
                  );
                })}
              </div>
            </div>
          );
        })()}

        {/* Monthly View */}
        {scheduleView === 'monthly' && (() => {
          // Use campus timezone to determine current month
          const today = getTodayInCampusTimezone();
          // Calculate the displayed month based on offset
          const displayDate = new Date(today.getFullYear(), today.getMonth() + monthOffset, 1);
          const displayMonth = displayDate.getMonth();
          const displayYear = displayDate.getFullYear();
          
          // Get first day of month and number of days
          const firstDayOfMonth = new Date(displayYear, displayMonth, 1);
          const lastDayOfMonth = new Date(displayYear, displayMonth + 1, 0);
          const daysInMonth = lastDayOfMonth.getDate();
          const startDayOfWeek = firstDayOfMonth.getDay(); // 0 = Sunday
          
          const monthName = displayDate.toLocaleDateString('en-US', { month: 'long', year: 'numeric' });
          
          // Group bookings by day of month
          const monthAppointmentsByDay: { [day: number]: ConfirmedBooking[] } = {};
          confirmedBookings.forEach(booking => {
            const bookingDate = new Date(booking.scheduledTime);
            if (bookingDate.getMonth() === displayMonth && bookingDate.getFullYear() === displayYear) {
              const day = bookingDate.getDate();
              if (!monthAppointmentsByDay[day]) {
                monthAppointmentsByDay[day] = [];
              }
              monthAppointmentsByDay[day].push(booking);
            }
          });
          
          const totalMonthAppointments = Object.values(monthAppointmentsByDay).reduce((sum, arr) => sum + arr.length, 0);
          
          // Group time blocks by day of month
          const monthTimeBlocksByDay: { [day: number]: TimeBlock[] } = {};
          monthlyTimeBlocks.forEach(block => {
            // block.blockDate is in YYYY-MM-DD format
            const [blockYear, blockMonth, blockDay] = block.blockDate.split('-').map(Number);
            if (blockMonth - 1 === displayMonth && blockYear === displayYear) {
              if (!monthTimeBlocksByDay[blockDay]) {
                monthTimeBlocksByDay[blockDay] = [];
              }
              monthTimeBlocksByDay[blockDay].push(block);
            }
          });
          
          // Create array with empty slots for padding
          const calendarDays: (number | null)[] = [];
          for (let i = 0; i < startDayOfWeek; i++) {
            calendarDays.push(null); // Padding for days before first of month
          }
          for (let i = 1; i <= daysInMonth; i++) {
            calendarDays.push(i);
          }
          
          return (
          <div>
              <div className="grid grid-cols-7 gap-1.5 sm:gap-3">
              {/* Calendar header */}
                {['S', 'M', 'T', 'W', 'T', 'F', 'S'].map((dayLabel, i) => (
                  <div key={i} className="text-center font-bold text-gray-600 text-sm sm:text-base py-2 sm:py-3">
                    <span className="sm:hidden">{dayLabel}</span>
                    <span className="hidden sm:inline">{['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'][i]}</span>
                </div>
              ))}
              {/* Calendar days */}
                {calendarDays.map((day, index) => {
                  if (day === null) {
                    return <div key={`empty-${index}`} className="aspect-square" />;
                  }
                  
                  const dayBookings = monthAppointmentsByDay[day] || [];
                  const dayTimeBlocks = monthTimeBlocksByDay[day] || [];
                  const hasAppointments = dayBookings.length > 0;
                  const hasTimeBlocks = dayTimeBlocks.length > 0;
                  // Check if this day is "today" in campus timezone (must match day, month, and year)
                  const isToday = day === today.getDate() && displayMonth === today.getMonth() && displayYear === today.getFullYear();
                  
                  return (
                    <div
                      key={day}
                      onClick={() => handleDayClick(new Date(displayYear, displayMonth, day))}
                      className={`aspect-square p-1.5 sm:p-3 rounded-lg sm:rounded-xl border overflow-hidden ${
                        isToday 
                          ? 'bg-primary-400 text-white border-primary-500' 
                          : 'bg-gray-50 border-gray-200 hover:border-primary-300'
                      } cursor-pointer active:scale-95 transition-all`}
                    >
                      <div className="text-sm sm:text-base font-bold mb-0.5 sm:mb-1">{day}</div>
                      {/* Mobile: Show +X bookings count with color coding */}
                      <div className="sm:hidden flex flex-col items-center gap-0">
                        {(() => {
                          const completedCount = dayBookings.filter(b => b.status === 'COMPLETED' || b.status === 'PAID').length;
                          const pendingCount = dayBookings.filter(b => b.status === 'ACCEPTED').length;
                          return (
                            <>
                              {completedCount > 0 && (
                                <div className={`text-xs font-bold ${isToday ? 'text-white' : 'text-green-600'}`}>
                                  +{completedCount}
                                </div>
                              )}
                              {pendingCount > 0 && (
                                <div className={`text-xs font-bold ${isToday ? 'text-white/80' : 'text-amber-500'}`}>
                                  +{pendingCount}
                                </div>
                              )}
                              {hasTimeBlocks && (
                                <div className={`text-xs font-bold ${isToday ? 'text-white/70' : 'text-red-500'}`}>
                                  {dayTimeBlocks.length}🚫
                                </div>
                              )}
                            </>
                          );
                        })()}
                      </div>
                      {/* Desktop: Show names with color-coded counts */}
                      <div className="hidden sm:block text-sm space-y-0.5 overflow-hidden">
                        {dayBookings.length === 0 && !hasTimeBlocks ? (
                          <div className={isToday ? 'text-white/60' : 'text-gray-400'}>No apts</div>
                        ) : (
                          (() => {
                            const completedCount = dayBookings.filter(b => b.status === 'COMPLETED' || b.status === 'PAID').length;
                            const pendingCount = dayBookings.filter(b => b.status === 'ACCEPTED').length;
                            return (
                              <div className="flex flex-col gap-0.5">
                                {completedCount > 0 && (
                                  <div className={`text-xs font-bold ${isToday ? 'text-white' : 'text-green-600'}`}>
                                    {completedCount} done
                                  </div>
                                )}
                                {pendingCount > 0 && (
                                  <div className={`text-xs font-bold ${isToday ? 'text-white/80' : 'text-amber-500'}`}>
                                    {pendingCount} booked
                                  </div>
                                )}
                                {hasTimeBlocks && (
                                  <div className={`text-xs font-bold ${isToday ? 'text-white/70' : 'text-red-500'}`}>
                                    {dayTimeBlocks.length} blocked
                                  </div>
                                )}
                              </div>
                            );
                          })()
                        )}
                      </div>
                    </div>
                  );
                })}
              </div>
            </div>
          );
              })()}

        {/* View indicator dots at bottom for swipe hint - mobile only */}
        <div className="flex justify-center gap-2 mt-4 sm:hidden">
          {views.map((view) => (
            <div
              key={view}
              className={`w-2 h-2 rounded-full transition-colors ${
                scheduleView === view ? 'bg-primary-400' : 'bg-gray-300'
              }`}
            />
          ))}
            </div>
          </div>
      </Card>

      {/* Day Detail Modal */}
      {showDayModal && selectedDate !== null && (
        <div 
          className={`fixed inset-0 min-h-[100dvh] flex items-center justify-center z-50 p-4 transition-all duration-150 ease-out ${
            isDayModalVisible ? 'bg-black/50' : 'bg-black/0'
          }`}
          onClick={closeDayModal}
        >
          <div 
            ref={modalRef} 
            className={`bg-white rounded-lg shadow-2xl max-w-2xl w-full max-h-[80dvh] sm:max-h-[80vh] overflow-hidden transition-all duration-150 ease-out ${
              isDayModalVisible 
                ? 'opacity-100 scale-100 translate-y-0' 
                : 'opacity-0 scale-95 translate-y-4'
            }`}
            onClick={(e) => e.stopPropagation()}
          >
            {/* Header - changes based on whether viewing booking details */}
            <div className="bg-primary-400 text-white p-6">
              <div className="flex items-center justify-between">
                <div>
                  <h2 className="text-2xl font-bold">
                    {selectedBookingInline ? 'Booking Details' : selectedDate.toLocaleDateString('en-US', { month: 'long', day: 'numeric', year: 'numeric' })}
                  </h2>
                  <p className="text-white/80">
                    {selectedBookingInline 
                      ? `${selectedBookingInline.status}` 
                      : `${getAppointmentsForDate(selectedDate).length} appointment${getAppointmentsForDate(selectedDate).length !== 1 ? 's' : ''}`
                    }
                  </p>
                </div>
                <button
                  onClick={closeDayModal}
                  className="text-white hover:bg-white/20 rounded-full p-2 transition-colors"
                >
                  <svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                    <path d="M18 6 6 18"></path>
                    <path d="m6 6 12 12"></path>
                  </svg>
                </button>
              </div>
            </div>
            
            <div className="p-6 overflow-y-auto max-h-[calc(80dvh-120px)] sm:max-h-[calc(80vh-120px)]">
              {/* Show booking details inline when a booking is selected */}
              {selectedBookingInline ? (
                <div className="space-y-4">
                  {/* Back button */}
                  <button
                    onClick={backToAppointmentsList}
                    className="flex items-center gap-2 text-gray-600 hover:text-gray-900 transition-colors"
                  >
                    <ChevronLeft className="w-5 h-5" />
                    <span className="text-sm font-medium">Back to Appointments</span>
                  </button>

                  {/* Cancel confirmation view */}
                  {isDeletingBooking ? (
                    <div className="space-y-4">
                      <div className="flex items-center gap-3 p-4 bg-red-50 rounded-xl border border-red-200">
                        <AlertTriangle className="w-8 h-8 text-red-500 flex-shrink-0" />
                        <div>
                          <h3 className="font-bold text-red-800">Cancel this booking?</h3>
                          <p className="text-sm text-red-600">
                            The customer will be notified. This action cannot be undone.
                          </p>
                        </div>
                      </div>
                      <div>
                        <label className="block text-sm font-medium text-gray-700 mb-2">
                          Reason for cancellation (optional)
                        </label>
                        <textarea
                          value={cancelReason}
                          onChange={(e) => setCancelReason(e.target.value)}
                          placeholder="e.g., Schedule conflict, emergency..."
                          className="w-full px-4 py-3 border border-gray-300 rounded-lg focus:ring-2 focus:ring-red-400 focus:border-transparent resize-none"
                          rows={3}
                        />
                      </div>
                      <div className="flex gap-3">
                        <button
                          onClick={() => setIsDeletingBooking(false)}
                          className="flex-1 py-3 text-gray-700 bg-gray-100 hover:bg-gray-200 rounded-xl font-semibold transition-colors"
                          disabled={isSavingBooking}
                        >
                          Keep Booking
                        </button>
                        <button
                          onClick={handleCancelBooking}
                          disabled={isSavingBooking}
                          className="flex-1 py-3 bg-red-500 hover:bg-red-600 text-white rounded-xl font-semibold transition-colors flex items-center justify-center gap-2"
                        >
                          {isSavingBooking ? (
                            <>
                              <div className="w-4 h-4 border-2 border-white/30 border-t-white rounded-full animate-spin" />
                              Cancelling...
                            </>
                          ) : (
                            <>
                              <Trash2 className="w-4 h-4" />
                              Cancel Booking
                            </>
                          )}
                        </button>
                      </div>
                    </div>
                  ) : isEditingBooking ? (
                    /* Edit view */
                    <div className="space-y-4">
                      <h3 className="font-bold text-gray-900 flex items-center gap-2">
                        <Pencil className="w-5 h-5 text-primary-500" />
                        Edit Booking
                      </h3>
                      
                      {/* Date Picker */}
                      <div className="bg-gray-50 rounded-xl p-3">
                        <DatePicker
                          label="Date"
                          value={editedDate}
                          onChange={(newDate) => {
                            setEditedDate(newDate);
                            setEditedTime(''); // Reset time when date changes
                          }}
                          minDate={new Date().toISOString().split('T')[0]}
                          required
                        />
                      </div>
                      
                      {/* Time Picker */}
                      <div className="bg-gray-50 rounded-xl p-3">
                        <label className="block text-sm font-medium text-gray-700 mb-2">
                          <div className="flex items-center gap-2">
                            <Clock className="w-4 h-4" />
                            Time
                          </div>
                        </label>
                        <AvailableTimePickerDropdown
                          barberId={barberIdForEdit}
                          date={editedDate}
                          value={editedTime}
                          onChange={(value) => setEditedTime(value)}
                          disabled={!editedDate}
                        />
                      </div>
                      
                      {/* Location */}
                      <div className="bg-gray-50 rounded-xl p-3">
                        <label className="block text-sm font-medium text-gray-700 mb-1">
                          <div className="flex items-center gap-2">
                            <MapPin className="w-4 h-4" />
                            Location
                          </div>
                        </label>
                        {barberLocations.length > 0 ? (
                          <select
                            value={editedLocation}
                            onChange={(e) => setEditedLocation(e.target.value)}
                            className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-primary-400 focus:border-transparent bg-white text-base"
                          >
                            <option value="">Select a location</option>
                            {barberLocations.map((loc) => (
                              <option key={loc.id} value={loc.name}>
                                {loc.name}
                              </option>
                            ))}
                          </select>
                        ) : (
                          <input
                            type="text"
                            value={editedLocation}
                            onChange={(e) => setEditedLocation(e.target.value)}
                            placeholder="Enter location..."
                            className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-primary-400 focus:border-transparent text-base"
                          />
                        )}
                      </div>
                      {selectedBookingInline.notes && (
                        <div>
                          <label className="block text-sm font-medium text-gray-700 mb-1">Customer Notes</label>
                          <div className="w-full px-3 py-2 bg-gray-100 border border-gray-200 rounded-lg text-gray-700 italic">
                            "{selectedBookingInline.notes}"
                          </div>
                        </div>
                      )}
                      <div className="flex gap-3 pt-2">
                        <button
                          onClick={() => setIsEditingBooking(false)}
                          className="flex-1 py-3 text-gray-700 bg-gray-100 hover:bg-gray-200 rounded-xl font-semibold transition-colors"
                          disabled={isSavingBooking}
                        >
                          Cancel
                        </button>
                        <button
                          onClick={handleSaveBookingChanges}
                          disabled={isSavingBooking}
                          className="flex-1 py-3 bg-primary-500 hover:bg-primary-600 text-white rounded-xl font-semibold transition-colors flex items-center justify-center gap-2"
                        >
                          {isSavingBooking ? (
                            <>
                              <div className="w-4 h-4 border-2 border-white/30 border-t-white rounded-full animate-spin" />
                              Saving...
                            </>
                          ) : (
                            <>
                              <Save className="w-4 h-4" />
                              Save Changes
                            </>
                          )}
                        </button>
                      </div>
                    </div>
                  ) : (
                    /* View mode - booking details */
                    <div className="space-y-5">
                      {/* Customer Info */}
                      <div className="flex items-center gap-4 p-4 bg-gray-50 rounded-xl">
                        <div className="w-14 h-14 rounded-full bg-primary-100 flex items-center justify-center overflow-hidden">
                          {(selectedBookingInline.consumer.profilePictureUrl || selectedBookingInline.consumer.avatar) ? (
                            <img 
                              src={selectedBookingInline.consumer.profilePictureUrl || selectedBookingInline.consumer.avatar} 
                              alt="Customer" 
                              className="w-14 h-14 rounded-full object-cover"
                            />
                          ) : (
                            <User className="w-7 h-7 text-primary-600" />
                          )}
                        </div>
                        <div className="flex-1">
                          <h3 className="font-bold text-gray-900 text-lg">
                            {selectedBookingInline.consumer.firstName} {selectedBookingInline.consumer.lastName}
                          </h3>
                          {selectedBookingInline.consumer.email && (
                            <p className="text-sm text-gray-500 flex items-center gap-1">
                              <Mail className="w-3 h-3" />
                              {selectedBookingInline.consumer.email}
                            </p>
                          )}
                        </div>
                      </div>

                      {/* Service Details */}
                      <div className="space-y-3">
                        <h4 className="font-semibold text-gray-700 text-sm uppercase tracking-wide">Service</h4>
                        <div className="flex items-center justify-between p-3 bg-primary-50 rounded-lg border border-primary-100">
                          <span className="font-semibold text-gray-900">
                            {selectedBookingInline.serviceName || selectedBookingInline.serviceType}
                          </span>
                          <span className="font-bold text-primary-600 text-lg">
                            ${(selectedBookingInline.priceUsdCents / 100).toFixed(2)}
                          </span>
                        </div>
                      </div>

                      {/* Date & Time */}
                      <div className="space-y-3">
                        <h4 className="font-semibold text-gray-700 text-sm uppercase tracking-wide">When</h4>
                        <div className="grid grid-cols-2 gap-3">
                          <div className="flex items-center gap-3 p-3 bg-gray-50 rounded-lg">
                            <Calendar className="w-5 h-5 text-primary-500" />
                            <div>
                              <p className="text-xs text-gray-500">Date</p>
                              <p className="font-semibold text-gray-900">
                                {new Date(selectedBookingInline.scheduledTime).toLocaleDateString('en-US', { weekday: 'short', month: 'short', day: 'numeric' })}
                              </p>
                            </div>
                          </div>
                          <div className="flex items-center gap-3 p-3 bg-gray-50 rounded-lg">
                            <Clock className="w-5 h-5 text-primary-500" />
                            <div>
                              <p className="text-xs text-gray-500">Time</p>
                              <p className="font-semibold text-gray-900">
                                {new Date(selectedBookingInline.scheduledTime).toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit' })}
                              </p>
                            </div>
                          </div>
                        </div>
                      </div>

                      {/* Location */}
                      {selectedBookingInline.location && (
                        <div className="space-y-3">
                          <h4 className="font-semibold text-gray-700 text-sm uppercase tracking-wide">Where</h4>
                          <div className="flex items-center gap-3 p-3 bg-gray-50 rounded-lg">
                            <MapPin className="w-5 h-5 text-primary-500 flex-shrink-0" />
                            <p className="font-medium text-gray-900">{selectedBookingInline.location}</p>
                          </div>
                        </div>
                      )}

                      {/* Notes */}
                      {selectedBookingInline.notes && (
                        <div className="space-y-3">
                          <h4 className="font-semibold text-gray-700 text-sm uppercase tracking-wide">Notes</h4>
                          <div className="flex items-start gap-3 p-3 bg-gray-50 rounded-lg">
                            <FileText className="w-5 h-5 text-primary-500 flex-shrink-0 mt-0.5" />
                            <p className="text-gray-700 italic">"{selectedBookingInline.notes}"</p>
                          </div>
                        </div>
                      )}

                      {/* Customer Feedback (for completed/paid bookings) */}
                      {(selectedBookingInline.status === 'COMPLETED' || selectedBookingInline.status === 'PAID') && selectedBookingInline.review && (
                        <div className="space-y-3">
                          <h4 className="font-semibold text-gray-700 text-sm uppercase tracking-wide">Customer Feedback</h4>
                          <div className="p-4 bg-yellow-50 rounded-xl border border-yellow-100">
                            <div className="flex items-center gap-1 mb-2">
                              {[1, 2, 3, 4, 5].map(star => (
                                <Star
                                  key={star}
                                  className={`w-5 h-5 ${star <= selectedBookingInline.review.rating ? 'text-yellow-400 fill-yellow-400' : 'text-gray-300'}`}
                                />
                              ))}
                              <span className="ml-2 font-semibold text-gray-700">
                                {selectedBookingInline.review.rating?.toFixed(1)}
                              </span>
                            </div>
                            {selectedBookingInline.review.comment && (
                              <p className="text-gray-700 italic">"{selectedBookingInline.review.comment}"</p>
                            )}
                          </div>
                        </div>
                      )}

                      {/* Booking Reference */}
                      <div className="text-center pt-2">
                        <p className="text-xs text-gray-400">Booking Reference</p>
                        <p className="font-mono text-sm text-gray-600 font-medium">
                          {selectedBookingInline.id.slice(0, 8).toUpperCase()}
                        </p>
                      </div>

                      {/* Action Buttons */}
                      {(() => {
                        const canEdit = selectedBookingInline.status === 'ACCEPTED';
                        const canCancel = selectedBookingInline.status === 'ACCEPTED' || selectedBookingInline.status === 'PENDING';
                        const canComplete = selectedBookingInline.status === 'ACCEPTED';
                        const canRemove = isAdmin && (selectedBookingInline.status === 'COMPLETED' || selectedBookingInline.status === 'PAID');
                        const canUndoComplete = selectedBookingInline.status === 'COMPLETED';
                        
                        if (!canComplete && !canEdit && !canCancel && !canRemove && !canUndoComplete) return null;
                        
                        return (
                          <div className="space-y-3 pt-4 border-t border-gray-100">
                            {canComplete && (
                              <button
                                onClick={handleCompleteBooking}
                                className="w-full py-3 bg-green-500 hover:bg-green-600 text-white rounded-xl font-semibold transition-colors flex items-center justify-center gap-2"
                              >
                                <CreditCard className="w-4 h-4" />
                                Request Payment
                              </button>
                            )}
                            {(canEdit || canCancel) && (
                              <div className="flex gap-3">
                                {canEdit && (
                                  <button
                                    onClick={startEditingBooking}
                                    className="flex-1 py-3 bg-primary-500 hover:bg-primary-600 text-white rounded-xl font-semibold transition-colors flex items-center justify-center gap-2"
                                  >
                                    <Pencil className="w-4 h-4" />
                                    Edit
                                  </button>
                                )}
                                {canCancel && (
                                  <button
                                    onClick={() => setIsDeletingBooking(true)}
                                    className="flex-1 py-3 bg-red-50 hover:bg-red-100 text-red-600 rounded-xl font-semibold transition-colors flex items-center justify-center gap-2 border border-red-200"
                                  >
                                    <Trash2 className="w-4 h-4" />
                                    Cancel
                                  </button>
                                )}
                              </div>
                            )}
                            
                            {/* Undo Complete Button (for COMPLETED bookings awaiting payment) */}
                            {canUndoComplete && !isUndoingComplete && !isRemovingBooking && (
                              <div className="space-y-2">
                                <p className="text-sm text-gray-500 text-center">
                                  Marked as complete by mistake?
                                </p>
                                <button
                                  onClick={() => setIsUndoingComplete(true)}
                                  className="w-full py-3 bg-primary-500 hover:bg-primary-600 text-white rounded-xl font-semibold transition-colors shadow-sm"
                                >
                                  Undo Complete
                                </button>
                              </div>
                            )}

                            {/* Undo Complete Confirmation */}
                            {isUndoingComplete && (
                              <div className="space-y-3">
                                <div className="p-3 bg-primary-50 rounded-lg border border-primary-200">
                                  <p className="font-semibold text-gray-800 text-sm">Undo completion?</p>
                                  <p className="text-xs text-gray-600">This will revert the booking to accepted status.</p>
                                </div>
                                <div className="flex gap-3">
                                  <button
                                    onClick={() => setIsUndoingComplete(false)}
                                    className="flex-1 py-2.5 text-gray-700 bg-gray-100 hover:bg-gray-200 rounded-xl font-semibold transition-colors text-sm"
                                    disabled={isSavingBooking}
                                  >
                                    Cancel
                                  </button>
                                  <button
                                    onClick={handleUndoComplete}
                                    disabled={isSavingBooking}
                                    className="flex-1 py-2.5 bg-primary-500 hover:bg-primary-600 text-white rounded-xl font-semibold transition-colors flex items-center justify-center gap-2 text-sm"
                                  >
                                    {isSavingBooking ? (
                                      <>
                                        <div className="w-3 h-3 border-2 border-white/30 border-t-white rounded-full animate-spin" />
                                        Reverting...
                                      </>
                                    ) : (
                                      'Undo'
                                    )}
                                  </button>
                                </div>
                              </div>
                            )}

                            {/* Remove from Schedule Button (for completed bookings) */}
                            {canRemove && !isRemovingBooking && !isUndoingComplete && (
                              <button
                                onClick={() => setIsRemovingBooking(true)}
                                className="w-full py-3 bg-gray-100 hover:bg-gray-200 text-gray-600 rounded-xl font-semibold transition-colors"
                              >
                                Remove from Schedule
                              </button>
                            )}

                            {/* Remove Confirmation */}
                            {isRemovingBooking && !isUndoingComplete && (
                              <div className="space-y-3">
                                <div className="flex items-center gap-3 p-3 bg-gray-50 rounded-lg border border-gray-200">
                                  <AlertTriangle className="w-5 h-5 text-gray-500 flex-shrink-0" />
                                  <div>
                                    <p className="font-semibold text-gray-800 text-sm">Remove this booking?</p>
                                    <p className="text-xs text-gray-600">This will permanently remove it from your schedule.</p>
                                  </div>
                                </div>
                                <div className="flex gap-3">
                                  <button
                                    onClick={() => setIsRemovingBooking(false)}
                                    className="flex-1 py-2.5 text-gray-700 bg-gray-100 hover:bg-gray-200 rounded-xl font-semibold transition-colors text-sm"
                                    disabled={isSavingBooking}
                                  >
                                    Keep
                                  </button>
                                  <button
                                    onClick={handleRemoveBooking}
                                    disabled={isSavingBooking}
                                    className="flex-1 py-2.5 bg-red-500 hover:bg-red-600 text-white rounded-xl font-semibold transition-colors flex items-center justify-center gap-2 text-sm"
                                  >
                                    {isSavingBooking ? (
                                      <>
                                        <div className="w-3 h-3 border-2 border-white/30 border-t-white rounded-full animate-spin" />
                                        Removing...
                                      </>
                                    ) : (
                                      <>
                                        <Trash2 className="w-3 h-3" />
                                        Remove
                                      </>
                                    )}
                                  </button>
                                </div>
                              </div>
                            )}
                          </div>
                        );
                      })()}
                    </div>
                  )}
                </div>
              ) : (
                /* Appointments list view */
                <>
                  {/* Unified Timeline View */}
                  {(() => {
                    // Show loading spinner while fetching availability
                    if (isLoadingWeeklySchedule || !weeklySchedule) {
                      return (
                        <div className="text-center py-8">
                          <div className="animate-spin w-8 h-8 border-4 border-primary-200 border-t-primary-500 rounded-full mx-auto mb-3"></div>
                          <p className="text-gray-500 text-sm">Loading availability...</p>
                        </div>
                      );
                    }
                    
                    const dayNames = ['sunday', 'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday'] as const;
                    const dayOfWeek = selectedDate.getDay();
                    const dayKey = dayNames[dayOfWeek];
                    const daySchedule = weeklySchedule[dayKey];
                    
                    if (!daySchedule?.enabled) {
                      return (
                        <div className="p-4 bg-gray-50 rounded-lg border border-gray-200 text-center">
                          <p className="text-sm text-gray-500 mb-3">Not available on {dayKey.charAt(0).toUpperCase() + dayKey.slice(1)}s</p>
                          <button
                            onClick={() => {
                              setSelectedDate(null);
                              onEditAvailability?.();
                            }}
                            className="text-sm px-3 py-1.5 bg-primary-100 hover:bg-primary-200 text-primary-700 rounded-lg transition-colors inline-flex items-center gap-1.5"
                          >
                            <Settings className="w-4 h-4" />
                            Add Availability
                          </button>
                        </div>
                      );
                    }
                    
                    // Get intervals (support both new and legacy format)
                    let intervals: { start: string; end: string }[] = [];
                    if (daySchedule.intervals && Array.isArray(daySchedule.intervals)) {
                      intervals = daySchedule.intervals.map((i: any) => ({ start: i.start, end: i.end }));
                    } else if (daySchedule.start && daySchedule.end) {
                      intervals = [{ start: daySchedule.start, end: daySchedule.end }];
                    }
                    
                    if (intervals.length === 0) {
                      return (
                        <div className="p-4 bg-gray-50 rounded-lg border border-gray-200 text-center">
                          <p className="text-sm text-gray-500 mb-3">No availability set for {dayKey.charAt(0).toUpperCase() + dayKey.slice(1)}s</p>
                          <button
                            onClick={() => {
                              setSelectedDate(null);
                              onEditAvailability?.();
                            }}
                            className="text-sm px-3 py-1.5 bg-primary-100 hover:bg-primary-200 text-primary-700 rounded-lg transition-colors inline-flex items-center gap-1.5"
                          >
                            <Settings className="w-4 h-4" />
                            Add Availability
                          </button>
                        </div>
                      );
                    }
                    
                    // Format time for display
                    const formatTime = (time: string) => {
                      const [hours, minutes] = time.split(':').map(Number);
                      const period = hours >= 12 ? 'PM' : 'AM';
                      const displayHours = hours === 0 ? 12 : hours > 12 ? hours - 12 : hours;
                      return `${displayHours}:${String(minutes).padStart(2, '0')} ${period}`;
                    };
                    
                    // Generate hourly slots from intervals
                    const generateHourlySlots = (intervals: { start: string; end: string }[]) => {
                      const slots: { start: string; end: string }[] = [];
                      intervals.forEach(interval => {
                        const [startHour] = interval.start.split(':').map(Number);
                        const [endHour] = interval.end.split(':').map(Number);
                        for (let hour = startHour; hour < endHour; hour++) {
                          slots.push({
                            start: `${String(hour).padStart(2, '0')}:00`,
                            end: `${String(hour + 1).padStart(2, '0')}:00`
                          });
                        }
                      });
                      return slots;
                    };
                    
                    const hourlySlots = generateHourlySlots(intervals);
                    const dateStr = `${selectedDate.getFullYear()}-${String(selectedDate.getMonth() + 1).padStart(2, '0')}-${String(selectedDate.getDate()).padStart(2, '0')}`;
                    const dayBlocks = monthlyTimeBlocks.filter(block => block.blockDate === dateStr);
                    const dayAppointments = getAppointmentsForDate(selectedDate);
                    
                    // Helper to convert time to minutes
                    const timeToMinutes = (time: string) => {
                      const [h, m] = time.split(':').map(Number);
                      return h * 60 + m;
                    };
                    
                    // Helper to check if slot is blocked
                    const getBlockForSlot = (slot: { start: string; end: string }) => {
                      const slotStart = timeToMinutes(slot.start);
                      const slotEnd = timeToMinutes(slot.end);
                      return dayBlocks.find(block => {
                        const blockStart = timeToMinutes(block.startTime);
                        const blockEnd = timeToMinutes(block.endTime);
                        return slotStart < blockEnd && slotEnd > blockStart;
                      });
                    };
                    
                    // Helper to get appointment for slot
                    const getAppointmentForSlot = (slot: { start: string; end: string }) => {
                      const slotStart = timeToMinutes(slot.start);
                      const slotEnd = timeToMinutes(slot.end);
                      return dayAppointments.find(apt => {
                        const aptTime = new Date(apt.scheduledTime);
                        const aptMinutes = aptTime.getHours() * 60 + aptTime.getMinutes();
                        return aptMinutes >= slotStart && aptMinutes < slotEnd;
                      });
                    };
                    
                    // Helper to check if slot is blocked by Google Calendar
                    const getGoogleCalendarBlockForSlotModal = (slot: { start: string; end: string }) => {
                      const slotStart = timeToMinutes(slot.start);
                      const slotEnd = timeToMinutes(slot.end);
                      
                      // Convert slot times to full Date for the selected day
                      const slotStartDate = new Date(selectedDate);
                      slotStartDate.setHours(Math.floor(slotStart / 60), slotStart % 60, 0, 0);
                      const slotEndDate = new Date(selectedDate);
                      slotEndDate.setHours(Math.floor(slotEnd / 60), slotEnd % 60, 0, 0);
                      
                      return googleCalendarBusyTimes.find(busy => {
                        return (busy.start < slotEndDate && busy.end > slotStartDate);
                      });
                    };
                    
                    const availableCount = hourlySlots.filter(slot => !getBlockForSlot(slot) && !getGoogleCalendarBlockForSlotModal(slot) && !getAppointmentForSlot(slot)).length;
                    const bookedCount = hourlySlots.filter(slot => getAppointmentForSlot(slot)).length;
                    const blockedCount = hourlySlots.filter(slot => (getBlockForSlot(slot) || getGoogleCalendarBlockForSlotModal(slot)) && !getAppointmentForSlot(slot)).length;
                    
                    return (
                      <div>
                        {/* Google Calendar Integration Button - Hidden for now, functionality preserved */}
                        <div className="hidden flex justify-center mb-3">
                          {googleCalendarConnected === null ? (
                            <div className="px-4 py-2 bg-gray-100 text-gray-500 text-sm font-medium rounded-lg">
                              Checking Google Calendar...
                            </div>
                          ) : googleCalendarConnected ? (
                            <button
                              onClick={() => onDisconnectGoogleCalendar?.()}
                              className="px-4 py-2 bg-primary-100 hover:bg-primary-200 text-primary-700 text-sm font-medium rounded-lg transition-colors border border-primary-300 flex flex-col items-center"
                            >
                              <span>Google Calendar Connected</span>
                              <span className="text-xs text-primary-500 sm:hidden">(Tap to Disconnect)</span>
                              <span className="text-xs text-primary-500 hidden sm:inline">(Click to Disconnect)</span>
                            </button>
                          ) : (
                            <button
                              onClick={() => onConnectGoogleCalendar?.()}
                              disabled={googleCalendarLoading}
                              className="px-4 py-2 bg-white hover:bg-gray-50 text-gray-700 text-sm font-medium rounded-lg transition-colors border border-gray-300 flex items-center gap-2 shadow-sm disabled:opacity-50"
                            >
                              <svg className="w-4 h-4" viewBox="0 0 24 24">
                                <path fill="#4285F4" d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z"/>
                                <path fill="#34A853" d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z"/>
                                <path fill="#FBBC05" d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z"/>
                                <path fill="#EA4335" d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z"/>
                              </svg>
                              {googleCalendarLoading ? 'Connecting...' : 'Connect Google Calendar'}
                            </button>
                          )}
                        </div>
                        <div className="flex justify-center mb-3">
                          <button
                            onClick={() => {
                              setSelectedDate(null);
                              onEditAvailability?.();
                            }}
                            className="px-4 py-2 bg-primary-500 hover:bg-primary-600 text-white text-sm font-medium rounded-lg transition-colors shadow-sm"
                          >
                            <span className="sm:hidden">Tap here to Edit Availability</span>
                            <span className="hidden sm:inline">Click here to Edit Availability</span>
                          </button>
                        </div>
                        <div className="space-y-2">
                          {hourlySlots.map((slot, idx) => {
                            const block = getBlockForSlot(slot);
                            const appointment = getAppointmentForSlot(slot);
                            
                            // Appointment takes priority
                            if (appointment) {
                              const isCompleted = appointment.status === 'COMPLETED' || appointment.status === 'PAID';
                              return (
                                <div 
                                  key={idx}
                                  onClick={() => selectBookingForInlineView(appointment)}
                                  className={`p-3 rounded-lg border transition-colors cursor-pointer ${
                                    isCompleted 
                                      ? 'bg-green-50 border-green-200 hover:border-green-400' 
                                      : 'bg-blue-50 border-blue-200 hover:border-blue-400'
                                  }`}
                                >
                                  <div className="flex items-center justify-between">
                                    <div>
                                      <p className="text-sm font-semibold text-gray-900">
                                        {formatTime(slot.start)} - {formatTime(slot.end)}
                                      </p>
                                      <p className="text-sm text-gray-700">
                                        {appointment.consumer.firstName} {appointment.consumer.lastName}
                                      </p>
                                    </div>
                                    <div className="text-right">
                                      <p className="text-xs text-gray-500">
                                        {appointment.serviceName || appointment.serviceType.toLowerCase().replace(/_/g, ' ').replace(/\b\w/g, (c: string) => c.toUpperCase())}
                                      </p>
                                      <p className="font-bold text-green-600">${(appointment.priceUsdCents / 100).toFixed(0)}</p>
                                    </div>
                                  </div>
                                </div>
                              );
                            }
                            
                            // Blocked slot - with unblock option (manual block)
                            if (block) {
                              return (
                                <div 
                                  key={idx}
                                  className="px-3 py-2 bg-red-50 text-red-700 rounded-lg text-sm border border-red-200 flex items-center justify-between"
                                >
                                  <div className="flex items-center gap-2">
                                    <Clock className="w-4 h-4 text-red-500" />
                                    <span className="font-medium">{formatTime(slot.start)} - {formatTime(slot.end)}</span>
                                  </div>
                                  <button
                                    onClick={() => onUnblockTime?.(block.id)}
                                    className="text-xs px-2 py-1 bg-red-100 hover:bg-red-200 text-red-700 font-medium rounded transition-colors border border-red-300"
                                  >
                                    Unblock
                                  </button>
                                </div>
                              );
                            }
                            
                            // Google Calendar blocked slot - not unblockable from CampusCuts
                            const googleBlockModal = getGoogleCalendarBlockForSlotModal(slot);
                            if (googleBlockModal) {
                              return (
                                <div 
                                  key={idx}
                                  className="px-3 py-2 bg-blue-50 text-blue-700 rounded-lg text-sm border border-blue-200 flex items-center justify-between"
                                >
                                  <div className="flex items-center gap-2">
                                    <svg className="w-4 h-4" viewBox="0 0 24 24">
                                      <path fill="#4285F4" d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z"/>
                                      <path fill="#34A853" d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z"/>
                                      <path fill="#FBBC05" d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z"/>
                                      <path fill="#EA4335" d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z"/>
                                    </svg>
                                    <span className="font-medium">{formatTime(slot.start)} - {formatTime(slot.end)}</span>
                                  </div>
                                  <span className="text-xs text-blue-500">Google Calendar</span>
                                </div>
                              );
                            }
                            
                            // Available slot - clickable to block
                            return (
                              <div 
                                key={idx}
                                onClick={() => {
                                  onBlockTime?.(dateStr, slot.start, slot.end);
                                  setSelectedDate(null); // Close the day detail modal
                                }}
                                className="px-3 py-2 bg-primary-50 text-primary-700 rounded-lg text-sm font-medium border border-primary-200 flex items-center gap-2 cursor-pointer hover:bg-primary-100 hover:border-primary-300 transition-colors"
                              >
                                <div className="w-2 h-2 rounded-full bg-primary-400"></div>
                                {formatTime(slot.start)} - {formatTime(slot.end)}
                                <span className="text-xs text-primary-500 ml-auto sm:hidden">Tap to block</span>
                                <span className="text-xs text-primary-500 ml-auto hidden sm:inline">Click to block</span>
                              </div>
                            );
                          })}
                        </div>
                      </div>
                    );
                  })()}
                </>
              )}
            </div>
          </div>
        </div>
      )}
    </>
  );
}

// Bookings Modal Component - View and manage all bookings
function BookingsModal({ isVisible, onClose, barberId }: { isVisible: boolean; onClose: () => void; barberId: string }) {
  const [activeTab, setActiveTab] = useState<'upcoming' | 'today' | 'past'>('today');
  const [bookings, setBookings] = useState<any[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [markingComplete, setMarkingComplete] = useState<string | null>(null);
  const [selectedBooking, setSelectedBooking] = useState<any | null>(null);
  const [showBookingDetails, setShowBookingDetails] = useState(false);

  // Fetch bookings when modal opens
  useEffect(() => {
    if (isVisible && barberId) {
      fetchBookings();
    }
  }, [isVisible, barberId]);

  const fetchBookings = async () => {
    setIsLoading(true);
    try {
      // Fetch all bookings for this barber (ACCEPTED and COMPLETED)
      // Use role=barber to get bookings where user is the barber
      const response = await api.get(`/bookings-simple?role=barber`);
      // api.get already extracts data, so response is { bookings: [...] }
      const bookingsArray = response.bookings || response.data?.bookings || [];
      // Filter to only show ACCEPTED, COMPLETED, and PAID bookings
      const relevantBookings = bookingsArray.filter(
        (b: any) => b.status === 'ACCEPTED' || b.status === 'COMPLETED' || b.status === 'PAID'
      );
      setBookings(relevantBookings);
    } catch (error) {
      console.error('Failed to fetch bookings:', error);
      toast.error('Failed to load bookings');
    } finally {
      setIsLoading(false);
    }
  };

  // Helper functions
  const formatServiceType = (service: string) => {
    if (!service) return 'Service';
    return service.toLowerCase().replace(/_/g, ' ').replace(/\b\w/g, char => char.toUpperCase());
  };

  const formatPrice = (cents: number) => `$${(cents / 100).toFixed(2)}`;

  const formatDateTime = (dateStr: string) => {
    const date = new Date(dateStr);
    return {
      date: date.toLocaleDateString('en-US', { weekday: 'short', month: 'short', day: 'numeric' }),
      time: date.toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit' }),
    };
  };

  const isToday = (dateStr: string) => {
    const date = new Date(dateStr);
    const today = new Date();
    return date.toDateString() === today.toDateString();
  };

  const isPast = (dateStr: string) => {
    const date = new Date(dateStr);
    const now = new Date();
    return date < now;
  };

  const isPaymentDue = (booking: any) => {
    // Payment is due if:
    // 1. Booking is ACCEPTED (not yet completed)
    // 2. Scheduled time was 15+ minutes ago
    if (booking.status !== 'ACCEPTED') return false;
    const scheduledTime = new Date(booking.scheduledTime);
    const fifteenMinsAgo = new Date(Date.now() - 15 * 60 * 1000);
    return scheduledTime <= fifteenMinsAgo;
  };

  // Filter bookings by tab
  const filteredBookings = bookings.filter(booking => {
    const now = new Date();
    const bookingDate = new Date(booking.scheduledTime);
    
    if (activeTab === 'today') {
      return isToday(booking.scheduledTime) && booking.status === 'ACCEPTED';
    } else if (activeTab === 'upcoming') {
      return bookingDate > now && !isToday(booking.scheduledTime) && booking.status === 'ACCEPTED';
    } else {
      // Past: paid bookings, completed bookings (awaiting payment), OR past accepted bookings
      return booking.status === 'PAID' || booking.status === 'COMPLETED' || (booking.status === 'ACCEPTED' && isPast(booking.scheduledTime) && !isToday(booking.scheduledTime));
    }
  }).sort((a, b) => {
    // Sort by date (ascending for upcoming/today, descending for past)
    const dateA = new Date(a.scheduledTime).getTime();
    const dateB = new Date(b.scheduledTime).getTime();
    return activeTab === 'past' ? dateB - dateA : dateA - dateB;
  });

  // Mark booking as complete - triggers payment request
  const handleMarkComplete = async (bookingId: string) => {
    setMarkingComplete(bookingId);
    try {
      const response = await api.put(`/bookings-simple/${bookingId}/complete`);
      if (response.success) {
        toast.success('Service marked complete! Payment request sent to customer.');
        fetchBookings(); // Refresh list
      } else {
        toast.error(response.error || 'Failed to mark as complete');
      }
    } catch (error: any) {
      console.error('Failed to mark booking complete:', error);
      toast.error(error.message || 'Failed to mark as complete');
    } finally {
      setMarkingComplete(null);
    }
  };

  const getStatusBadge = (booking: any) => {
    // Check for payment by status OR paidAt field
    if (booking.status === 'PAID' || booking.paidAt) {
      return <span className="px-2 py-1 bg-gray-100 text-gray-700 rounded-full text-xs font-semibold">Paid</span>;
    }
    if (booking.status === 'COMPLETED') {
      // COMPLETED means awaiting payment
      return <span className="px-2 py-1 bg-amber-100 text-amber-700 rounded-full text-xs font-semibold animate-pulse">Awaiting Payment</span>;
    }
    if (isPaymentDue(booking)) {
      return <span className="px-2 py-1 bg-amber-100 text-amber-700 rounded-full text-xs font-semibold animate-pulse">Payment Due</span>;
    }
    return <span className="px-2 py-1 bg-blue-100 text-blue-700 rounded-full text-xs font-semibold">Confirmed</span>;
  };

  return (
    <div 
      className={`fixed inset-0 min-h-[100dvh] flex items-center justify-center z-50 p-4 transition-all duration-150 ease-out ${
        isVisible ? 'bg-black/50' : 'bg-black/0'
      }`}
      onClick={onClose}
    >
      <div 
        className={`bg-white rounded-2xl shadow-2xl max-w-2xl w-full max-h-[90dvh] sm:max-h-[90vh] overflow-hidden transition-all duration-150 ease-out ${
          isVisible 
            ? 'opacity-100 scale-100 translate-y-0' 
            : 'opacity-0 scale-95 translate-y-4'
        }`}
        onClick={(e) => e.stopPropagation()}
      >
        {/* Header */}
        <div className="sticky top-0 bg-gradient-to-r from-primary-500 to-primary-400 text-white px-6 py-4 flex items-center justify-between z-10">
                        <div>
            <h2 className="text-2xl font-bold">Bookings</h2>
            <p className="text-white/80 text-sm">{bookings.filter(b => b.status === 'ACCEPTED').length} active, {bookings.filter(b => b.status === 'COMPLETED' || b.status === 'PAID').length} completed</p>
                        </div>
          <button
            onClick={onClose}
            className="text-white hover:bg-white/20 rounded-full p-2 transition-colors"
          >
            <X className="w-6 h-6" />
          </button>
                      </div>

        {/* Tabs */}
        <div className="flex border-b border-gray-200">
          {[
            { key: 'today', label: 'Today' },
            { key: 'upcoming', label: 'Upcoming' },
            { key: 'past', label: 'Past' },
          ].map(tab => (
            <button
              key={tab.key}
              onClick={() => setActiveTab(tab.key as any)}
              className={`flex-1 py-3 text-sm font-semibold transition-colors ${
                activeTab === tab.key
                  ? 'text-primary-600 border-b-2 border-primary-500 bg-primary-50'
                  : 'text-gray-500 hover:text-gray-700 hover:bg-gray-50'
              }`}
            >
              {tab.label}
            </button>
          ))}
        </div>

        {/* Bookings List */}
        <div className="overflow-y-auto max-h-[calc(90vh-200px)] p-4">
          {isLoading ? (
            <div className="flex items-center justify-center py-12">
              <div className="w-8 h-8 border-4 border-primary-200 border-t-primary-500 rounded-full animate-spin" />
            </div>
          ) : filteredBookings.length === 0 ? (
            <div className="text-center py-12">
              <Calendar className="w-12 h-12 text-gray-300 mx-auto mb-4" />
              <p className="text-gray-600 font-medium">No {activeTab} bookings</p>
              <p className="text-gray-400 text-sm mt-1">
                {activeTab === 'today' && 'No appointments scheduled for today'}
                {activeTab === 'upcoming' && 'No future appointments yet'}
                {activeTab === 'past' && 'No completed services yet'}
              </p>
            </div>
          ) : (
            <div className="space-y-3">
              {filteredBookings.map((booking) => {
                const { date, time } = formatDateTime(booking.scheduledTime);
                // Show "Mark Complete" for all ACCEPTED bookings - barber can trigger payment at any time
                const showMarkComplete = booking.status === 'ACCEPTED';
                
                return (
                  <div 
                    key={booking.id} 
                    className={`p-4 rounded-xl border transition-all cursor-pointer ${
                      booking.status === 'PAID' || booking.paidAt
                        ? 'bg-gray-50 border-gray-200 hover:border-gray-400'
                        : isPaymentDue(booking) || booking.status === 'COMPLETED'
                          ? 'bg-amber-50 border-amber-200 hover:border-amber-400'
                          : 'bg-gray-50 border-gray-200 hover:border-primary-400 hover:shadow-md'
                    }`}
                          onClick={() => {
                      setSelectedBooking(booking);
                      window.scrollTo({ top: 0, behavior: 'instant' });
                      setShowBookingDetails(true);
                    }}
                  >
                    {/* Top Row: Customer + Status */}
                    <div className="flex items-start justify-between mb-2">
                      <div className="flex items-center gap-3">
                        <div className="w-10 h-10 rounded-full bg-gray-200 flex items-center justify-center overflow-hidden">
                          {(booking.consumer?.avatar || booking.consumer?.profileImageUrl) ? (
                            <img 
                              src={booking.consumer.avatar || booking.consumer.profileImageUrl} 
                              alt="" 
                              className="w-full h-full object-cover"
                            />
                          ) : (
                            <span className="text-gray-600 font-semibold text-sm">
                              {booking.consumer?.firstName?.[0]}{booking.consumer?.lastName?.[0]}
                            </span>
                          )}
                      </div>
                        <div>
                          <p className="font-bold text-gray-900">
                            {booking.consumer?.firstName} {booking.consumer?.lastName}
                          </p>
                          <p className="text-sm text-gray-600">
                            {booking.serviceName || formatServiceType(booking.serviceType)}
                          </p>
                    </div>
                      </div>
                      <div className="text-right">
                        {getStatusBadge(booking)}
                        <p className="font-bold text-green-600 mt-1">{formatPrice(booking.priceUsdCents)}</p>
                      </div>
                    </div>

                    {/* Date/Time Row */}
                    <div className="flex flex-wrap items-center gap-x-4 gap-y-1 text-sm text-gray-600 mb-3">
                      <span className="flex items-center gap-1">
                        <Calendar className="w-4 h-4 flex-shrink-0" />
                        {date}
                      </span>
                      <span className="flex items-center gap-1">
                        <Clock className="w-4 h-4 flex-shrink-0" />
                        {time}
                      </span>
                      {booking.location && (
                        <span className="flex items-center gap-1">
                          <MapPin className="w-4 h-4 flex-shrink-0" />
                          <span className="truncate max-w-[120px]">{booking.location}</span>
                        </span>
                      )}
                    </div>

                    {/* Notes */}
                    {booking.notes && (
                      <div className="text-sm text-gray-500 italic mb-3 px-3 py-2 bg-white/50 rounded-lg">
                        "{booking.notes}"
                      </div>
                    )}

                    {/* Action Button */}
                    {showMarkComplete && (
                      <button
                        onClick={(e) => {
                          e.stopPropagation(); // Prevent opening details modal
                          handleMarkComplete(booking.id);
                        }}
                        disabled={markingComplete === booking.id}
                        className={`w-full py-2.5 rounded-lg font-semibold transition-all flex items-center justify-center gap-2 ${
                          markingComplete === booking.id
                            ? 'bg-gray-300 text-gray-500 cursor-not-allowed'
                            : 'bg-green-500 hover:bg-green-600 text-white active:scale-98'
                        }`}
                      >
                        {markingComplete === booking.id ? (
                          <>
                            <div className="w-4 h-4 border-2 border-white/30 border-t-white rounded-full animate-spin" />
                            Processing...
                          </>
                        ) : (
                          <>
                            <Check className="w-4 h-4" />
                            Mark Service Complete
                          </>
                        )}
                      </button>
                    )}

                    {/* Review display for completed/paid bookings */}
                    {(booking.status === 'COMPLETED' || booking.status === 'PAID') && booking.review && (
                      <div className="mt-3 p-3 bg-white rounded-lg border border-green-100" onClick={(e) => e.stopPropagation()}>
                        <div className="flex items-center gap-1 mb-1">
                          {[1, 2, 3, 4, 5].map(star => (
                            <span key={star} className={star <= booking.review.rating ? 'text-yellow-400' : 'text-gray-300'}>★</span>
                  ))}
                </div>
                        {booking.review.comment && (
                          <p className="text-sm text-gray-600 italic">"{booking.review.comment}"</p>
              )}
            </div>
                    )}
                    
                    {/* Tap to view details hint */}
                    <p className="text-xs text-gray-400 text-center mt-2">Tap to view details</p>
          </div>
                );
              })}
        </div>
      )}
        </div>
      </div>

      {/* Booking Details Modal */}
      <BookingDetailsModal
        isOpen={showBookingDetails}
        onClose={() => {
          setShowBookingDetails(false);
          setSelectedBooking(null);
        }}
        booking={selectedBooking}
        onBookingUpdated={fetchBookings}
      />
    </div>
  );
}

// Types for Calendly-style availability with multiple intervals per day
interface TimeInterval {
  id: string;
  start: string;
  end: string;
}

interface DayAvailability {
  enabled: boolean;
  intervals: TimeInterval[];
}

interface WeeklyAvailability {
  monday: DayAvailability;
  tuesday: DayAvailability;
  wednesday: DayAvailability;
  thursday: DayAvailability;
  friday: DayAvailability;
  saturday: DayAvailability;
  sunday: DayAvailability;
}

type DayKey = keyof WeeklyAvailability;

// Generate unique ID for intervals
const generateId = () => Math.random().toString(36).substring(2, 9);

// Default availability with intervals structure
const createDefaultAvailability = (): WeeklyAvailability => ({
  monday: { enabled: true, intervals: [{ id: generateId(), start: '09:00', end: '17:00' }] },
  tuesday: { enabled: true, intervals: [{ id: generateId(), start: '09:00', end: '17:00' }] },
  wednesday: { enabled: true, intervals: [{ id: generateId(), start: '09:00', end: '17:00' }] },
  thursday: { enabled: true, intervals: [{ id: generateId(), start: '09:00', end: '17:00' }] },
  friday: { enabled: true, intervals: [{ id: generateId(), start: '09:00', end: '17:00' }] },
  saturday: { enabled: false, intervals: [] },
  sunday: { enabled: false, intervals: [] },
});

// Migrate old format (single start/end) to new format (intervals array)
const migrateSchedule = (schedule: Record<string, unknown>): WeeklyAvailability => {
  const days: DayKey[] = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'];
  const migrated = createDefaultAvailability();
  
  for (const day of days) {
    const dayData = schedule[day] as { enabled?: boolean; start?: string; end?: string; intervals?: TimeInterval[] } | undefined;
    if (!dayData) continue;
    
    // If already has intervals array, use it
    if (dayData.intervals && Array.isArray(dayData.intervals) && dayData.intervals.length > 0) {
      // Filter out invalid intervals and provide defaults for missing fields
      const validIntervals = dayData.intervals
        .filter(i => i && (i.start || i.end)) // Keep intervals that have at least one time
        .map(i => ({
          id: i.id || generateId(),
          start: i.start || '09:00',
          end: i.end || '17:00'
        }));
      
      migrated[day] = {
        enabled: dayData.enabled ?? (validIntervals.length > 0),
        intervals: validIntervals
      };
    } 
    // Migrate from old single start/end format
    else if (dayData.start && dayData.end && dayData.enabled) {
      migrated[day] = {
        enabled: true,
        intervals: [{ id: generateId(), start: dayData.start, end: dayData.end }]
      };
    } 
    // Disabled day
    else {
      migrated[day] = {
        enabled: dayData.enabled ?? false,
        intervals: []
      };
    }
  }
  
  return migrated;
};

// Validation types
type IntervalError = {
  type: 'reverse' | 'overlap';
  message: string;
};

type ValidationErrors = {
  [day in DayKey]?: {
    [intervalId: string]: IntervalError;
  };
};

// Helper to convert time string to minutes
const timeToMinutes = (time: string | undefined | null): number => {
  if (!time || typeof time !== 'string' || !time.includes(':')) {
    return 0;
  }
  const [hours, minutes] = time.split(':').map(Number);
  if (isNaN(hours) || isNaN(minutes)) return 0;
  return hours * 60 + minutes;
};

// Validate all intervals and return errors
const validateAvailability = (availability: WeeklyAvailability): ValidationErrors => {
  const errors: ValidationErrors = {};
  
  const dayKeys: DayKey[] = ['sunday', 'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday'];
  
  for (const day of dayKeys) {
    const intervals = availability[day].intervals;
    
    for (let i = 0; i < intervals.length; i++) {
      const current = intervals[i];
      const startMins = timeToMinutes(current.start);
      const endMins = timeToMinutes(current.end);
      
      // Check for reverse time (start >= end)
      if (startMins >= endMins) {
        if (!errors[day]) errors[day] = {};
        errors[day]![current.id] = {
          type: 'reverse',
          message: 'End time must be after start time'
        };
        continue; // Skip overlap check if times are reversed
      }
      
      // Check for overlaps with other intervals
      for (let j = 0; j < intervals.length; j++) {
        if (i === j) continue;
        
        const other = intervals[j];
        const otherStartMins = timeToMinutes(other.start);
        const otherEndMins = timeToMinutes(other.end);
        
        // Skip if other interval has reverse times
        if (otherStartMins >= otherEndMins) continue;
        
        // Check for overlap
        if (startMins < otherEndMins && endMins > otherStartMins) {
          if (!errors[day]) errors[day] = {};
          errors[day]![current.id] = {
            type: 'overlap',
            message: 'Time slots cannot overlap'
          };
          break;
        }
      }
    }
  }
  
  return errors;
};

// Availability Modal Component - Calendly-style with multiple intervals per day
function AvailabilityModal({ isVisible, onClose, userId }: { isVisible: boolean; onClose: () => void; userId?: string }) {
  const [availability, setAvailability] = useState<WeeklyAvailability>(createDefaultAvailability);
  const [isLoading, setIsLoading] = useState(true);
  const [isSaving, setIsSaving] = useState(false);
  const [barberId, setBarberId] = useState<string | null>(null);

  // Compute validation errors whenever availability changes
  const validationErrors = useMemo(() => validateAvailability(availability), [availability]);
  const hasValidationErrors = Object.keys(validationErrors).length > 0;

  // Load barber's current weekly schedule when modal opens
  useEffect(() => {
    if (isVisible && userId) {
      loadSchedule();
    }
  }, [isVisible, userId]);

  const loadSchedule = async () => {
    if (!userId) return;
    
    setIsLoading(true);
    try {
      const response = await fetch(`/api/v1/barbers/user/${userId}`, {
        headers: {
          'Authorization': `Bearer ${localStorage.getItem('accessToken')}`,
        },
      });
      
      if (response.ok) {
        const data = await response.json();
        if (data.data) {
          setBarberId(data.data.id);
          if (data.data.weekly_schedule) {
            // Migrate old format to new format if needed
            const migratedSchedule = migrateSchedule(data.data.weekly_schedule);
            setAvailability(migratedSchedule);
          }
        }
      }
    } catch (error) {
      console.error('Failed to load schedule:', error);
    } finally {
      setIsLoading(false);
    }
  };

  const days: { key: DayKey; label: string; shortLabel: string }[] = [
    { key: 'sunday', label: 'Sunday', shortLabel: 'Sun' },
    { key: 'monday', label: 'Monday', shortLabel: 'Mon' },
    { key: 'tuesday', label: 'Tuesday', shortLabel: 'Tue' },
    { key: 'wednesday', label: 'Wednesday', shortLabel: 'Wed' },
    { key: 'thursday', label: 'Thursday', shortLabel: 'Thu' },
    { key: 'friday', label: 'Friday', shortLabel: 'Fri' },
    { key: 'saturday', label: 'Saturday', shortLabel: 'Sat' },
  ];

  const addInterval = (day: DayKey) => {
    setAvailability(prev => {
      const dayData = prev[day];
      const lastInterval = dayData.intervals[dayData.intervals.length - 1];
      
      // Calculate next interval start (end of last interval + 1 hour)
      let newStart = '09:00';
      if (lastInterval && lastInterval.end && lastInterval.end.includes(':')) {
        const [hours] = lastInterval.end.split(':').map(Number);
        if (!isNaN(hours)) {
          const nextHour = Math.min(hours + 1, 23);
          newStart = `${nextHour.toString().padStart(2, '0')}:00`;
        }
      }
      
      // End time is 2 hours after start
      const [startHours] = newStart.split(':').map(Number);
      const endHour = Math.min(startHours + 2, 23);
      const newEnd = `${endHour.toString().padStart(2, '0')}:00`;
      
      return {
        ...prev,
        [day]: {
          enabled: true,
          intervals: [
            ...dayData.intervals,
            { id: generateId(), start: newStart, end: newEnd }
          ]
        }
      };
    });
  };

  const removeInterval = (day: DayKey, intervalId: string) => {
    setAvailability(prev => {
      const newIntervals = prev[day].intervals.filter(i => i.id !== intervalId);
      return {
        ...prev,
        [day]: {
          enabled: newIntervals.length > 0,
          intervals: newIntervals
        }
      };
    });
  };

  const updateInterval = (day: DayKey, intervalId: string, field: 'start' | 'end', value: string) => {
    setAvailability(prev => ({
      ...prev,
      [day]: {
        ...prev[day],
        intervals: prev[day].intervals.map(i => 
          i.id === intervalId ? { ...i, [field]: value } : i
        )
      }
    }));
  };

  const handleSave = async () => {
    if (!barberId) {
      console.error('No barber ID found');
      return;
    }
    
    // Safety check - should be disabled in UI but double-check
    if (hasValidationErrors) {
      toast.error('Please fix validation errors before saving');
      return;
    }
    
    setIsSaving(true);
    try {
      const response = await fetch(`/api/v1/barbers/${barberId}`, {
        method: 'PUT',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${localStorage.getItem('accessToken')}`,
        },
        body: JSON.stringify({ weekly_schedule: availability }),
      });
      
      if (response.ok) {
        toast.success('Availability saved!');
        onClose();
      } else {
        const errorData = await response.json();
        toast.error(errorData.error?.message || 'Failed to save availability');
      }
    } catch (error) {
      console.error('Failed to save availability:', error);
      toast.error('Failed to save availability');
    } finally {
      setIsSaving(false);
    }
  };

  // Format time for display (12-hour format)
  const formatTime = (time24: string | undefined | null): string => {
    if (!time24 || typeof time24 !== 'string' || !time24.includes(':')) {
      return 'N/A';
    }
    const [hourStr, minuteStr] = time24.split(':');
    const hour = parseInt(hourStr, 10);
    if (isNaN(hour)) return 'N/A';
    const displayHour = hour === 0 ? 12 : hour > 12 ? hour - 12 : hour;
    const period = hour < 12 ? 'am' : 'pm';
    return `${displayHour}:${minuteStr}${period}`;
  };

  return (
    <div 
      className={`fixed inset-0 min-h-[100dvh] flex items-center justify-center z-50 p-4 transition-all duration-150 ease-out ${isVisible ? 'bg-black/50' : 'bg-black/0'}`}
      onClick={onClose}
    >
      <div 
        className={`bg-white rounded-2xl shadow-2xl max-w-md w-full max-h-[85dvh] sm:max-h-[90vh] flex flex-col overflow-hidden transition-all duration-150 ease-out ${
          isVisible ? 'opacity-100 scale-100 translate-y-0' : 'opacity-0 scale-95 translate-y-4'
        }`}
        onClick={(e) => e.stopPropagation()}
      >
        {/* Header */}
        <div className="flex-shrink-0 bg-gradient-to-r from-primary-500 to-primary-400 px-6 py-4 flex items-center justify-between">
          <div>
            <h2 className="text-xl font-bold text-white">Set Your Availability</h2>
            <p className="text-white/80 text-sm">Add multiple time slots per day</p>
          </div>
          <button 
            onClick={onClose}
            className="text-white hover:bg-white/20 rounded-full p-2 transition-colors"
          >
            <X className="w-6 h-6" />
          </button>
        </div>

        {/* Content */}
        <div className="p-4 sm:p-6 overflow-y-auto overscroll-contain flex-1 min-h-0">
          {isLoading ? (
            <div className="flex items-center justify-center py-12">
              <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-primary-500" />
            </div>
          ) : (
            <div className="space-y-4">
              {days.map(({ key, label, shortLabel }) => (
                <div 
                  key={key}
                  className={`rounded-xl border-2 transition-all overflow-hidden ${
                    availability[key].enabled && availability[key].intervals.length > 0
                      ? 'border-primary-200 bg-primary-50/50' 
                      : 'border-gray-200 bg-gray-50'
                  }`}
                >
                  {/* Day header */}
                  <div className="flex items-center gap-3 p-3 sm:p-4">
                    {/* Day abbreviation badge */}
                    <div className={`w-10 h-10 rounded-full flex items-center justify-center font-bold text-xs sm:text-sm ${
                      availability[key].enabled && availability[key].intervals.length > 0
                        ? 'bg-primary-500 text-white'
                        : 'bg-gray-200 text-gray-500'
                    }`}>
                      {shortLabel}
                    </div>
                    
                    {/* Day name and intervals or unavailable */}
                    <div className="flex-1 min-w-0">
                      <div className="font-semibold text-gray-900 hidden sm:block">{label}</div>
                      
                      {availability[key].intervals.length === 0 ? (
                        <span className="text-gray-400 text-sm">Unavailable</span>
                      ) : (
                        <div className="space-y-2 mt-2">
                          {availability[key].intervals.map((interval, idx) => {
                            const intervalError = validationErrors[key]?.[interval.id];
                            return (
                              <div key={interval.id}>
                                <div className="flex items-center gap-1 sm:gap-2">
                                  <TimeInput
                                    value={interval.start}
                                    onChange={(value) => updateInterval(key, interval.id, 'start', value)}
                                    aria-label={`${label} start time`}
                                    className="w-[5.5rem] sm:w-28"
                                    error={!!intervalError}
                                  />
                                  <span className="text-gray-400 text-sm">-</span>
                                  <TimeInput
                                    value={interval.end}
                                    onChange={(value) => updateInterval(key, interval.id, 'end', value)}
                                    aria-label={`${label} end time`}
                                    className="w-[5.5rem] sm:w-28"
                                    error={!!intervalError}
                                  />
                                  <button
                                    onClick={() => removeInterval(key, interval.id)}
                                    className="p-1.5 text-gray-400 hover:text-red-500 hover:bg-red-50 rounded-md transition-colors"
                                    title={`Remove ${label} interval ${idx + 1}`}
                                  >
                                    <X className="w-4 h-4" />
                                  </button>
                                </div>
                                {intervalError && (
                                  <p className="text-red-500 text-xs mt-1 flex items-center gap-1">
                                    <svg className="w-3 h-3" fill="currentColor" viewBox="0 0 20 20">
                                      <path fillRule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7 4a1 1 0 11-2 0 1 1 0 012 0zm-1-9a1 1 0 00-1 1v4a1 1 0 102 0V6a1 1 0 00-1-1z" clipRule="evenodd" />
                                    </svg>
                                    {intervalError.message}
                                  </p>
                                )}
                              </div>
                            );
                          })}
                        </div>
                      )}
                    </div>
                    
                    {/* Action buttons */}
                    <div className="flex items-center gap-1">
                      {/* Add interval button */}
                      <button
                        onClick={() => addInterval(key)}
                        className="p-2 text-primary-600 hover:bg-primary-100 rounded-lg transition-colors"
                        title={`Add time slot for ${label}`}
                      >
                        <svg viewBox="0 0 10 10" className="w-5 h-5" fill="none" stroke="currentColor" strokeLinecap="round" strokeLinejoin="round">
                          <circle cx="5" cy="5" r="4.5" />
                          <path d="M5 3v4M3 5h4" />
                        </svg>
                      </button>
                      
                    </div>
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>

        {/* Footer */}
        <div className="flex-shrink-0 bg-white border-t border-gray-200 px-6 py-4 flex justify-between">
          <Button variant="secondary" onClick={onClose} disabled={isSaving}>
            Cancel
          </Button>
          <Button onClick={handleSave} disabled={isSaving || isLoading || hasValidationErrors}>
            {isSaving ? 'Saving...' : hasValidationErrors ? 'Fix Errors to Save' : 'Save Availability'}
          </Button>
        </div>
      </div>
    </div>
  );
}
