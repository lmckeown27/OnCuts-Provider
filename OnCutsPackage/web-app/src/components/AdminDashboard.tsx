import { useState, useEffect, useMemo, useRef } from 'react';
import { 
  Users, Search, ChevronDown, Loader2, AlertCircle,
  Calendar, DollarSign, TrendingUp, Scissors, ChevronLeft, ChevronRight,
  MessageSquare, Star, Clock, UserPlus, Mail, X, CheckCircle, XCircle,
  Copy, Check
} from 'lucide-react';
import {
  Chart as ChartJS,
  CategoryScale,
  LinearScale,
  PointElement,
  LineElement,
  BarElement,
  Title,
  Tooltip,
  Legend,
  Filler,
} from 'chart.js';
import { Line } from 'react-chartjs-2';
import api from '../services/api.service';
import barberApplicationService, { BarberApplication } from '../services/barber-application.service';
import toast from 'react-hot-toast';
import Button from './Button';

// Register Chart.js components
ChartJS.register(
  CategoryScale,
  LinearScale,
  PointElement,
  LineElement,
  BarElement,
  Title,
  Tooltip,
  Legend,
  Filler
);

interface Campus {
  id: string;
  name: string;
  slug?: string;
  city?: string;
  state?: string;
  managerId?: string;
  managerName?: string;
}

interface CampusPerformance {
  totalBarbers: number;
  activeBarbers: number;
  totalBookings: number;
  completedBookings: number;
  cancelledBookings: number;
  totalRevenue: number; // Total money in circulation (what customers paid)
  totalPlatformFees: number; // Platform's gross cut (15%)
  totalBarberEarnings: number; // What barbers earned (85%)
  // Stripe fee breakdown
  stripeProcessingFees: number; // 2.9% + $0.30 per transaction
  stripeConnectFees: number; // Active accounts + volume + payouts
  activeConnectAccounts: number; // Number of barbers who received payouts
  estimatedPayouts: number; // Number of payouts made
  activeAccountBilling: number; // $2/account monthly fee
  volumeBilling: number; // 0.25% volume fee
  payoutFees: number; // $0.25 + 0.25% per payout
  estimatedStripeFees: number; // Total Stripe fees (processing + connect)
  netPlatformRevenue: number; // Platform's actual take after ALL Stripe fees
  completedTransactionCount: number; // Number of completed transactions
  // Card vs Cash breakdown
  cardRevenue: number;
  cardCount: number;
  cashRevenue: number;
  cashCount: number;
  averageRating: number;
  totalReviews: number;
  totalTips: number;
  // Average metrics
  averageBookingsPerDay: number;
  averageBookingsPerWeek: number;
  averageBookingsPerMonth: number;
  averageRevenuePerDay: number;
  averageRevenuePerWeek: number;
  averageRevenuePerMonth: number;
  averageCostPerAppointment: number;
  // AWS Cost Estimates
  awsEc2Cost: number; // EC2 instance
  awsVpcCost: number; // VPC networking
  awsRoute53Cost: number; // DNS
  awsFixedCosts: number; // Total fixed AWS costs
  awsDataTransferCost: number; // Variable data transfer
  awsS3StorageCost: number; // S3 storage
  awsS3RequestsCost: number; // S3 requests
  awsVariableCosts: number; // Total variable AWS costs
  awsTotalCost: number; // Total AWS costs
}

interface MetricsDataPoint {
  date: string;
  bookings: number;
  revenue: number;
  users: number;
}

interface MetricsResponse {
  period: string;
  data: MetricsDataPoint[];
  totalUsers?: number;
}

type MetricsPeriod = '1w' | '4w' | '1y' | 'mtd' | 'qtd' | 'ytd' | 'all';
type MetricsView = 'revenue' | 'bookings';
type AdminView = 'performance' | 'barbers' | 'users';

interface Barber {
  id: string;
  barberRecordId: string;
  firstName: string;
  lastName: string;
  email: string;
  profileImageUrl?: string;
  isActive: boolean;
  isCampusManager: boolean;
  campusId?: string;
  campusName?: string;
  hasStripeSetup?: boolean; // Stripe fully complete (visible to consumers)
  hasStripeAccountOnly?: boolean; // Stripe account created but payouts not enabled (NOT visible to consumers)
  createdAt?: string;
  completedBookings?: number;
  totalVolumeCents?: number;
}

interface BarberBooking {
  id: string;
  service_type: string;
  price_cents: number;
  tip_cents: number;
  total_paid_cents: number;
  status: string;
  payment_method: string | null;
  scheduled_time: string;
  created_at: string;
  paid_at: string | null;
  review_rating: number | null;
  review_text: string | null;
  consumer_id: string;
  consumer_first_name: string;
  consumer_last_name: string;
  consumer_email: string;
  consumer_avatar: string | null;
  message_count: number;
}

interface ConsumerBooking {
  id: string;
  service_type: string;
  price_cents: number;
  tip_cents: number;
  total_paid_cents: number;
  status: string;
  payment_method: string | null;
  scheduled_time: string;
  created_at: string;
  paid_at: string | null;
  review_rating: number | null;
  review_text: string | null;
  barber_record_id: string;
  barber_user_id: string;
  barber_first_name: string;
  barber_last_name: string;
  barber_email: string;
  barber_avatar: string | null;
}

interface BookingMessage {
  id: string;
  content: string;
  sender_id: string;
  created_at: string;
  is_read: boolean;
  sender_first_name: string;
  sender_last_name: string;
  sender_avatar: string | null;
  sender_role: string;
}

interface PlatformUser {
  id: string;
  first_name: string;
  last_name: string;
  email: string;
  role: string;
  avatar_url: string | null;
  campus_name: string | null;
  created_at: string;
  is_active: boolean;
  customer_number: number;
}

interface AdminDashboardProps {
  campuses?: Campus[];
  selectedCampusId?: string;
  onCampusIdChange?: (campusId: string | null) => void;
  isLoadingCampuses?: boolean;
  hideHeader?: boolean;
}

export function AdminDashboard({ 
  campuses: externalCampuses,
  selectedCampusId: externalCampusId,
  onCampusIdChange,
  isLoadingCampuses: externalIsLoading,
  hideHeader = false
}: AdminDashboardProps) {
  // Internal state for uncontrolled mode
  const [internalCampuses, setInternalCampuses] = useState<Campus[]>([]);
  const [internalSelectedCampusId, setInternalSelectedCampusId] = useState<string>('');
  const [internalIsLoadingCampuses, setInternalIsLoadingCampuses] = useState(true);
  
  // Use external or internal state
  const campuses = externalCampuses || internalCampuses;
  const selectedCampusId = externalCampusId !== undefined ? externalCampusId : internalSelectedCampusId;
  const isLoadingCampuses = externalIsLoading !== undefined ? externalIsLoading : internalIsLoadingCampuses;
  const isControlled = externalCampuses !== undefined;
  
  const setSelectedCampusId = (id: string | null) => {
    if (onCampusIdChange) {
      onCampusIdChange(id);
    } else {
      setInternalSelectedCampusId(id || '');
    }
  };
  
  const setCampuses = (campusList: Campus[]) => {
    if (!isControlled) {
      setInternalCampuses(campusList);
    }
  };
  
  const setIsLoadingCampuses = (loading: boolean) => {
    if (!isControlled) {
      setInternalIsLoadingCampuses(loading);
    }
  };
  const [performance, setPerformance] = useState<CampusPerformance | null>(null);
  const [barbers, setBarbers] = useState<Barber[]>([]);
  
  const [campusLoadError, setCampusLoadError] = useState<string | null>(null);
  const [isLoadingPerformance, setIsLoadingPerformance] = useState(false);
  const [isLoadingBarbers, setIsLoadingBarbers] = useState(false);
  const [isAssigning, setIsAssigning] = useState<string | null>(null);
  
  // Metrics chart state
  const [metrics, setMetrics] = useState<MetricsDataPoint[]>([]);
  const [metricsTotalUsers, setMetricsTotalUsers] = useState<number>(0);
  const [isLoadingMetrics, setIsLoadingMetrics] = useState(false);
  const [metricsPeriod, setMetricsPeriod] = useState<MetricsPeriod>('4w');
  const [metricsView, setMetricsView] = useState<MetricsView>('revenue');
  const [isChartHovered, setIsChartHovered] = useState(false);
  const [hoveredDataPoint, setHoveredDataPoint] = useState<{ label: string; revenue: number; bookings: number; users: number } | null>(null);
  
  const [campusSearchQuery, setCampusSearchQuery] = useState('');
  const [showCampusDropdown, setShowCampusDropdown] = useState(false);
  const [barberSearchQuery, setBarberSearchQuery] = useState('');
  const [adminView, setAdminView] = useState<AdminView>('performance');
  
  // Barber detail view state
  const [selectedBarber, setSelectedBarber] = useState<Barber | null>(null);
  const [barberBookings, setBarberBookings] = useState<BarberBooking[]>([]);
  const [isLoadingBarberBookings, setIsLoadingBarberBookings] = useState(false);
  const [selectedBookingMessages, setSelectedBookingMessages] = useState<BookingMessage[]>([]);
  const [selectedBookingId, setSelectedBookingId] = useState<string | null>(null);
  const [isLoadingMessages, setIsLoadingMessages] = useState(false);
  
  // Consumers view state
  const [users, setUsers] = useState<PlatformUser[]>([]);
  const [totalUsersCount, setTotalUsersCount] = useState(0);
  const [isLoadingUsers, setIsLoadingUsers] = useState(false);
  const [userSearchQuery, setUserSearchQuery] = useState('');
  
  // Consumer detail view state
  const [selectedConsumer, setSelectedConsumer] = useState<PlatformUser | null>(null);
  const [consumerBookings, setConsumerBookings] = useState<ConsumerBooking[]>([]);
  const [isLoadingConsumerBookings, setIsLoadingConsumerBookings] = useState(false);
  
  // Barber view state (shared between all-barbers and campus-specific views)
  const [barberViewTab, setBarberViewTab] = useState<'managers' | 'barbers' | 'applications'>('barbers');
  const [barberVisibilityFilter, setBarberVisibilityFilter] = useState<'visible' | 'hidden'>('visible');
  const [activeBarberStripeFilter, setActiveBarberStripeFilter] = useState<'all' | 'setup' | 'not-setup'>('all');
  const [allBarberSearchQuery, setAllBarberSearchQuery] = useState('');
  
  // Barber applications state
  const [applications, setApplications] = useState<BarberApplication[]>([]);
  const [isLoadingApplications, setIsLoadingApplications] = useState(false);
  const [applicationActionLoading, setApplicationActionLoading] = useState<string | null>(null);
  const [selectedApplication, setSelectedApplication] = useState<BarberApplication | null>(null);
  const [pendingApplicationAction, setPendingApplicationAction] = useState<{ app: BarberApplication; action: 'approve' | 'reject' } | null>(null);
  const [showContactModal, setShowContactModal] = useState<BarberApplication | null>(null);
  const [copiedField, setCopiedField] = useState<'email' | 'phone' | null>(null);
  
  const campusDropdownRef = useRef<HTMLDivElement>(null);
  const chartContainerRef = useRef<HTMLDivElement>(null);
  
  // Lock scroll when actively hovering chart
  useEffect(() => {
    if (!isChartHovered) return;
    
    const preventScroll = (e: TouchEvent) => {
      e.preventDefault();
    };

    // Lock body scroll on touch devices while chart is being interacted with
    document.body.style.overflow = 'hidden';
    document.addEventListener('touchmove', preventScroll, { passive: false });

    return () => {
      document.body.style.overflow = '';
      document.removeEventListener('touchmove', preventScroll);
    };
  }, [isChartHovered]);
  
  // Close campus dropdown when clicking outside
  useEffect(() => {
    const handleClickOutside = (event: MouseEvent) => {
      if (campusDropdownRef.current && !campusDropdownRef.current.contains(event.target as Node)) {
        setShowCampusDropdown(false);
      }
    };
    document.addEventListener('mousedown', handleClickOutside);
    return () => document.removeEventListener('mousedown', handleClickOutside);
  }, []);
  
  // Fetch all campuses
  const fetchCampuses = async () => {
    setIsLoadingCampuses(true);
    setCampusLoadError(null);
    try {
      const response = await api.get<{ campuses: Campus[] } | Campus[]>('/admin/campuses');
      const campusList = Array.isArray(response) ? response : response.campuses || [];
      setCampuses(campusList);
      // Don't auto-select first campus - admin should choose
    } catch (error: any) {
      console.error('Failed to fetch campuses:', error);
      setCampusLoadError(error.message || 'Failed to load campuses. The backend may need to be restarted.');
    } finally {
      setIsLoadingCampuses(false);
    }
  };
  
  useEffect(() => {
    fetchCampuses();
  }, []);
  
  // Fetch campus performance when campus changes (or aggregate when none selected)
  // Also poll every 30 seconds for real-time updates
  useEffect(() => {
    const fetchPerformance = async (showLoading = true) => {
      if (showLoading) setIsLoadingPerformance(true);
      try {
        // Use aggregate endpoint when no campus selected, otherwise campus-specific
        const url = selectedCampusId 
          ? `/admin/campuses/${selectedCampusId}/performance`
          : '/admin/campuses/aggregate/performance';
        const response = await api.get<CampusPerformance>(url);
        setPerformance(response);
      } catch (error) {
        console.error('Failed to fetch performance:', error);
        setPerformance(null);
      } finally {
        if (showLoading) setIsLoadingPerformance(false);
      }
    };
    
    // Initial fetch with loading indicator
    fetchPerformance(true);
    
    // Poll every 30 seconds without showing loading indicator
    const intervalId = setInterval(() => fetchPerformance(false), 30000);
    
    return () => clearInterval(intervalId);
  }, [selectedCampusId]);
  
  // Fetch barbers for campus when campus changes (or all barbers if no campus selected)
  useEffect(() => {
    const fetchBarbers = async () => {
      setIsLoadingBarbers(true);
      try {
        // If no campus selected, fetch all barbers; otherwise fetch campus-specific
        const url = selectedCampusId 
          ? `/admin/campuses/${selectedCampusId}/barbers`
          : '/admin/barbers';
        const response = await api.get<{ barbers: Barber[] } | Barber[]>(url);
        const barberList = Array.isArray(response) ? response : response.barbers || [];
        setBarbers(barberList);
      } catch (error) {
        console.error('Failed to fetch barbers:', error);
        setBarbers([]);
      } finally {
        setIsLoadingBarbers(false);
      }
    };
    
    fetchBarbers();
  }, [selectedCampusId]);
  
  // Fetch barber applications when campus changes (always fetch to show count)
  useEffect(() => {
    const fetchApplications = async () => {
      setIsLoadingApplications(true);
      try {
        // Pass campusId only if one is selected, otherwise fetch all applications
        const allApplications = await barberApplicationService.getAllApplications(selectedCampusId || undefined);
        // Filter to show actionable applications
        const actionableApplications = allApplications.filter(app => {
          if (app.status === 'pending') return true;
          if (app.status === 'approved' && app.application_type === 'guest' && !app.user_id) return true;
          return false;
        });
        setApplications(actionableApplications);
      } catch (error) {
        console.error('Failed to fetch applications:', error);
        setApplications([]);
      } finally {
        setIsLoadingApplications(false);
      }
    };
    
    fetchApplications();
  }, [selectedCampusId]);
  
  // Show confirmation for application action
  const requestApplicationAction = (app: BarberApplication, action: 'approve' | 'reject') => {
    setPendingApplicationAction({ app, action });
  };

  // Handle application action (approve/reject) - called after confirmation
  const confirmApplicationAction = async () => {
    if (!pendingApplicationAction) return;
    
    const { app, action } = pendingApplicationAction;
    setApplicationActionLoading(app.id);
    setPendingApplicationAction(null);
    
    try {
      if (action === 'approve') {
        await barberApplicationService.updateApplicationStatus(app.id, 'approved');
        toast.success('Application approved!');
      } else {
        await barberApplicationService.updateApplicationStatus(app.id, 'rejected');
        toast.success('Application rejected');
      }
      // Remove from list
      setApplications(prev => prev.filter(a => a.id !== app.id));
      // Clear selected application if it was the one being actioned
      if (selectedApplication?.id === app.id) {
        setSelectedApplication(null);
      }
      // Refresh barbers list in case new barber was added
      if (selectedCampusId) {
        const response = await api.get<{ barbers: Barber[] } | Barber[]>(`/admin/campuses/${selectedCampusId}/barbers`);
        const barberList = Array.isArray(response) ? response : response.barbers || [];
        setBarbers(barberList);
      }
    } catch (error) {
      console.error(`Failed to ${action} application:`, error);
      toast.error(`Failed to ${action} application`);
    } finally {
      setApplicationActionLoading(null);
    }
  };
  
  // Fetch metrics when campus or period changes (or aggregate when none selected)
  // Also poll every 30 seconds for real-time updates
  useEffect(() => {
    const fetchMetrics = async (showLoading = true) => {
      if (showLoading) setIsLoadingMetrics(true);
      try {
        // Use aggregate endpoint when no campus selected, otherwise campus-specific
        const url = selectedCampusId 
          ? `/admin/campuses/${selectedCampusId}/metrics?period=${metricsPeriod}`
          : `/admin/campuses/aggregate/metrics?period=${metricsPeriod}`;
        // api.get extracts the data, which could be the full response or just the data array
        const response = await api.get<MetricsResponse | MetricsDataPoint[]>(url);
        
        // Handle both response formats
        if (Array.isArray(response)) {
          setMetrics(response);
          setMetricsTotalUsers(response.reduce((sum, m) => sum + (m.users || 0), 0));
        } else if (response && typeof response === 'object') {
          setMetrics(response.data || []);
          setMetricsTotalUsers(response.totalUsers || response.data?.reduce((sum: number, m: MetricsDataPoint) => sum + (m.users || 0), 0) || 0);
        } else {
          setMetrics([]);
          setMetricsTotalUsers(0);
        }
      } catch (error) {
        console.error('Failed to fetch metrics:', error);
        setMetrics([]);
        setMetricsTotalUsers(0);
      } finally {
        if (showLoading) setIsLoadingMetrics(false);
      }
    };
    
    // Initial fetch with loading indicator
    fetchMetrics(true);
    
    // Poll every 30 seconds without showing loading indicator
    const intervalId = setInterval(() => fetchMetrics(false), 30000);
    
    return () => clearInterval(intervalId);
  }, [selectedCampusId, metricsPeriod]);
  
  // Fetch total user count whenever campus changes (for summary stats)
  useEffect(() => {
    const fetchUserCount = async () => {
      setIsLoadingUsers(true);
      try {
        // If no campus selected, fetch all consumers; otherwise filter by campus
        const url = selectedCampusId 
          ? `/admin/users?campusId=${selectedCampusId}`
          : '/admin/users';
        const response = await api.get<{ users: PlatformUser[]; pagination: { total: number } }>(url);
        setTotalUsersCount(response.pagination?.total || response.users?.length || 0);
      } catch (error) {
        console.error('Failed to fetch user count:', error);
        setTotalUsersCount(0);
      } finally {
        setIsLoadingUsers(false);
      }
    };
    
    fetchUserCount();
  }, [selectedCampusId]);
  
  // Fetch full user list when Users tab is selected
  useEffect(() => {
    const fetchUsers = async () => {
      if (adminView !== 'users') return;
      
      setIsLoadingUsers(true);
      try {
        // If no campus selected, fetch all consumers; otherwise filter by campus
        const url = selectedCampusId 
          ? `/admin/users?campusId=${selectedCampusId}`
          : '/admin/users';
        const response = await api.get<{ users: PlatformUser[]; pagination: { total: number } }>(url);
        setUsers(response.users || []);
        setTotalUsersCount(response.pagination?.total || response.users?.length || 0);
      } catch (error) {
        console.error('Failed to fetch users:', error);
        setUsers([]);
        setTotalUsersCount(0);
      } finally {
        setIsLoadingUsers(false);
      }
    };
    
    fetchUsers();
  }, [adminView, selectedCampusId]);
  
  const selectedCampus = useMemo(() => {
    return campuses.find(c => c.id === selectedCampusId);
  }, [campuses, selectedCampusId]);
  
  const filteredCampuses = useMemo(() => {
    if (!campusSearchQuery) return campuses;
    const query = campusSearchQuery.toLowerCase();
    return campuses.filter(c => 
      c.name.toLowerCase().includes(query) || 
      c.city.toLowerCase().includes(query)
    );
  }, [campuses, campusSearchQuery]);
  
  const filteredBarbers = useMemo(() => {
    if (!barberSearchQuery) return barbers;
    const query = barberSearchQuery.toLowerCase();
    return barbers.filter(b => 
      b.firstName.toLowerCase().includes(query) || 
      b.lastName.toLowerCase().includes(query) ||
      b.email.toLowerCase().includes(query)
    );
  }, [barbers, barberSearchQuery]);
  
  // Filtered barbers for the "all barbers" view (when no campus selected)
  const filteredAllBarbers = useMemo(() => {
    if (!allBarberSearchQuery) return barbers;
    const query = allBarberSearchQuery.toLowerCase();
    return barbers.filter(b => 
      b.firstName.toLowerCase().includes(query) || 
      b.lastName.toLowerCase().includes(query) ||
      b.email.toLowerCase().includes(query) ||
      (b.campusName && b.campusName.toLowerCase().includes(query))
    );
  }, [barbers, allBarberSearchQuery]);
  
  const filteredUsers = useMemo(() => {
    if (!userSearchQuery) return users;
    
    const query = userSearchQuery.toLowerCase();
    return users.filter(u => 
      u.first_name.toLowerCase().includes(query) || 
      u.last_name.toLowerCase().includes(query) ||
      u.email.toLowerCase().includes(query)
    );
  }, [users, userSearchQuery]);
  
  const handleAssignManager = async (barberUserId: string, assign: boolean) => {
    setIsAssigning(barberUserId);
    try {
      await api.post(`/admin/campuses/${selectedCampusId}/manager`, {
        barberUserId,
        action: assign ? 'assign' : 'remove'
      });
      
      toast.success(assign ? 'Campus manager assigned!' : 'Campus manager removed');
      
      // Refresh barbers list
      const response = await api.get<{ barbers: Barber[] } | Barber[]>(`/admin/campuses/${selectedCampusId}/barbers`);
      const barberList = Array.isArray(response) ? response : response.barbers || [];
      setBarbers(barberList);
      
      // Refresh campus list to update manager info
      const campusResponse = await api.get<{ campuses: Campus[] } | Campus[]>('/admin/campuses');
      const campusList = Array.isArray(campusResponse) ? campusResponse : campusResponse.campuses || [];
      setCampuses(campusList);
    } catch (error: any) {
      console.error('Failed to assign manager:', error);
      toast.error(error.message || 'Failed to update campus manager');
    } finally {
      setIsAssigning(null);
    }
  };
  
  const formatCurrency = (cents: number) => {
    return `$${(cents / 100).toFixed(2)}`;
  };
  
  // Format campus name for display - remove trailing "University" except for "University of X" names
  const formatCampusName = (name: string) => {
    // Keep "University of X" names intact
    if (name.startsWith('University of ')) return name;
    // Remove trailing " University" from other names
    if (name.endsWith(' University')) return name.slice(0, -11);
    return name;
  };
  
  // Format service type from SNAKE_CASE to Title Case (e.g., "HAIRCUT" -> "Haircut")
  const formatServiceType = (service: string) => {
    if (!service) return 'Service';
    return service.toLowerCase().replace(/_/g, ' ').replace(/\b\w/g, char => char.toUpperCase());
  };
  
  // Handle barber card click - fetch their bookings
  const handleBarberClick = async (barber: Barber) => {
    setSelectedBarber(barber);
    setBarberBookings([]);
    setSelectedBookingId(null);
    setSelectedBookingMessages([]);
    setIsLoadingBarberBookings(true);
    
    try {
      const response = await api.get<{ bookings: BarberBooking[] }>(`/admin/barbers/${barber.barberRecordId}/bookings`);
      setBarberBookings(response.bookings || []);
    } catch (error) {
      console.error('Failed to fetch barber bookings:', error);
      toast.error('Failed to load bookings');
    } finally {
      setIsLoadingBarberBookings(false);
    }
  };
  
  // Handle booking click - fetch messages
  const handleBookingClick = async (bookingId: string) => {
    if (selectedBookingId === bookingId) {
      // Toggle off
      setSelectedBookingId(null);
      setSelectedBookingMessages([]);
      return;
    }
    
    setSelectedBookingId(bookingId);
    setSelectedBookingMessages([]);
    setIsLoadingMessages(true);
    
    try {
      const response = await api.get<{ messages: BookingMessage[] }>(`/admin/bookings/${bookingId}/messages`);
      setSelectedBookingMessages(response.messages || []);
    } catch (error) {
      console.error('Failed to fetch messages:', error);
    } finally {
      setIsLoadingMessages(false);
    }
  };
  
  // Go back from barber detail view
  const handleBackToBarbers = () => {
    setSelectedBarber(null);
    setBarberBookings([]);
    setSelectedBookingId(null);
    setSelectedBookingMessages([]);
  };
  
  // Handle consumer click - fetch their bookings
  const handleConsumerClick = async (user: PlatformUser) => {
    setSelectedConsumer(user);
    setConsumerBookings([]);
    setIsLoadingConsumerBookings(true);
    
    try {
      const response = await api.get<{ bookings: ConsumerBooking[] }>(`/admin/users/${user.id}/bookings`);
      setConsumerBookings(response.bookings || []);
    } catch (error) {
      console.error('Failed to fetch consumer bookings:', error);
      toast.error('Failed to load bookings');
    } finally {
      setIsLoadingConsumerBookings(false);
    }
  };
  
  // Go back from consumer detail view
  const handleBackToConsumers = () => {
    setSelectedConsumer(null);
    setConsumerBookings([]);
    setSelectedBookingId(null);
    setSelectedBookingMessages([]);
  };
  
  // Prepare chart data
  const chartData = useMemo(() => {
    const labels = metrics.map(m => {
      // Parse date as UTC but display the UTC values directly (backend already converted to Pacific Time)
      const date = new Date(m.date);
      // Use UTC methods to avoid local timezone conversion since backend already did the conversion
      const monthNames = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      const month = monthNames[date.getUTCMonth()];
      const day = date.getUTCDate();
      const year = String(date.getUTCFullYear()).slice(-2);
      
      // Daily granularity periods: 1w, 4w, mtd, qtd
      if (['1w', '4w', 'mtd', 'qtd'].includes(metricsPeriod)) {
        return `${month} ${day}`;
      // Weekly granularity periods: 1y, ytd
      } else if (['1y', 'ytd'].includes(metricsPeriod)) {
        return `Week of ${month} ${day}`;
      // Monthly granularity: all
      } else {
        return `${month} '${year}`;
      }
    });
    
    const dataValues = metrics.map(m => 
      metricsView === 'revenue' ? m.revenue / 100 : m.bookings
    );
    
    return {
      labels,
      datasets: [
        {
          label: metricsView === 'revenue' ? 'Revenue ($)' : 'Bookings',
          data: dataValues,
          borderColor: '#708d81', // primary color for both views
          backgroundColor: 'rgba(112, 141, 129, 0.15)', // primary color with opacity
          fill: true,
          tension: 0.3,
          pointRadius: 4,
          pointHoverRadius: 6,
        },
      ],
    };
  }, [metrics, metricsPeriod, metricsView]);
  
  // Custom crosshair plugin for vertical line on hover
  const crosshairPlugin = useMemo(() => ({
    id: 'crosshair',
    afterDraw: (chart: any) => {
      if (chart.tooltip?._active?.length) {
        const activePoint = chart.tooltip._active[0];
        const ctx = chart.ctx;
        const x = activePoint.element.x;
        const topY = chart.scales.y.top;
        const bottomY = chart.scales.y.bottom;

        ctx.save();
        ctx.beginPath();
        ctx.moveTo(x, topY);
        ctx.lineTo(x, bottomY);
        ctx.lineWidth = 1;
        ctx.strokeStyle = 'rgba(112, 141, 129, 0.5)'; // Primary color with opacity
        ctx.setLineDash([4, 4]);
        ctx.stroke();
        ctx.restore();
      }
    },
  }), []);

  const chartOptions = useMemo(() => ({
    responsive: true,
    maintainAspectRatio: false,
    layout: {
      padding: {
        left: 0,
        right: 8, // Small padding so last point is easily hoverable
        top: 8,
        bottom: 0,
      },
    },
    interaction: {
      mode: 'index' as const,
      intersect: false,
    },
    plugins: {
      legend: {
        display: false,
      },
      tooltip: {
        enabled: false, // Disabled - showing data in header instead
      },
    },
    scales: {
      x: {
        grid: {
          display: false,
        },
        ticks: {
          maxRotation: 0,
          autoSkip: true,
          maxTicksLimit: 8,
        },
      },
      y: {
        beginAtZero: true,
        grid: {
          color: 'rgba(0, 0, 0, 0.05)',
        },
        ticks: {
          callback: (value: any) => {
            return metricsView === 'revenue' ? `$${value}` : value;
          },
        },
      },
    },
    hover: {
      mode: 'index' as const,
      intersect: false,
    },
    onHover: (_event: any, activeElements: any[], chart: any) => {
      if (activeElements.length > 0) {
        setIsChartHovered(true);
        const index = activeElements[0].index;
        if (metrics[index]) {
          const m = metrics[index];
          setHoveredDataPoint({
            label: chart.data.labels[index] || m.date,
            revenue: m.revenue,
            bookings: m.bookings,
            users: m.users || 0,
          });
        }
      } else {
        setIsChartHovered(false);
        setHoveredDataPoint(null);
      }
    },
  }), [metrics, metricsView]);
  
  return (
    <div className="space-y-4 sm:space-y-6">
      {/* All Universities Button - Show when campus is selected */}
      {selectedCampusId && (
        <button
          onClick={() => {
            setSelectedCampusId(null);
            setSelectedBarber(null);
            setBarberBookings([]);
          }}
          className="flex items-center gap-1.5 text-sm text-gray-600 hover:text-gray-900 transition-colors"
        >
          <ChevronLeft className="w-4 h-4" />
          All Universities
        </button>
      )}
      
      {/* View Tabs - Performance / Barbers / Users */}
      <div className="flex rounded-lg bg-gray-100 p-1">
        <button
          onClick={() => setAdminView('performance')}
          className={`flex-1 px-4 py-2 text-sm font-medium rounded-md transition-colors ${
            adminView === 'performance'
              ? 'bg-white text-gray-900 shadow-sm'
              : 'text-gray-600 hover:text-gray-900'
          }`}
        >
          Performance
        </button>
        <button
          onClick={() => setAdminView('barbers')}
          className={`flex-1 px-4 py-2 text-sm font-medium rounded-md transition-colors ${
            adminView === 'barbers'
              ? 'bg-white text-gray-900 shadow-sm'
              : 'text-gray-600 hover:text-gray-900'
          }`}
        >
          Barbers
        </button>
        <button
          onClick={() => setAdminView('users')}
          className={`flex-1 px-4 py-2 text-sm font-medium rounded-md transition-colors ${
            adminView === 'users'
              ? 'bg-white text-gray-900 shadow-sm'
              : 'text-gray-600 hover:text-gray-900'
          }`}
        >
          Consumers
        </button>
      </div>
      
      {/* Campus Selector - hidden when rendered in header */}
      {!hideHeader && (
      <div>
        {isLoadingCampuses ? (
          <div className="flex items-center justify-center py-6">
            <Loader2 className="w-5 h-5 animate-spin text-primary-500" />
          </div>
        ) : campusLoadError ? (
          <div className="bg-red-50 border border-red-200 rounded-lg p-4">
            <div className="flex items-start gap-3">
              <AlertCircle className="w-5 h-5 text-red-500 flex-shrink-0 mt-0.5" />
              <div className="flex-1">
                <p className="text-sm font-medium text-red-800">Failed to load campuses</p>
                <p className="text-xs text-red-600 mt-1">{campusLoadError}</p>
                <button
                  onClick={fetchCampuses}
                  className="mt-2 text-xs font-medium text-red-700 hover:text-red-800 underline"
                >
                  Try again
                </button>
              </div>
            </div>
          </div>
        ) : (
          <div className="relative" ref={campusDropdownRef}>
            <input
              type="text"
              value={showCampusDropdown ? campusSearchQuery : (selectedCampus ? formatCampusName(selectedCampus.name) : '')}
              onChange={(e) => {
                setCampusSearchQuery(e.target.value);
                if (!showCampusDropdown) setShowCampusDropdown(true);
              }}
              onFocus={() => setShowCampusDropdown(true)}
              placeholder="All Universities"
              className={`w-full text-base bg-gray-100 hover:bg-gray-200 focus:bg-white focus:ring-2 focus:ring-primary-500 px-3 py-2.5 rounded-lg transition-colors border border-transparent focus:border-primary-300 outline-none ${
                selectedCampus ? 'text-gray-900 pr-16' : 'text-gray-700 pr-8'
              }`}
            />
            {selectedCampus && !showCampusDropdown && (
              <button
                onClick={(e) => {
                  e.stopPropagation();
                  setSelectedCampusId(null);
                  setCampusSearchQuery('');
                }}
                className="absolute right-8 top-1/2 -translate-y-1/2 p-1 hover:bg-gray-300 rounded-full transition-colors"
                title="Clear selection"
              >
                <X className="w-3.5 h-3.5 text-gray-500" />
              </button>
            )}
            <ChevronDown className={`absolute right-2 top-1/2 -translate-y-1/2 w-4 h-4 text-gray-400 transition-transform ${showCampusDropdown ? 'rotate-180' : ''}`} />
            
            {showCampusDropdown && (
              <div className="absolute top-full left-0 right-0 mt-1 bg-white border border-gray-200 rounded-lg shadow-lg z-20 max-h-64 overflow-y-auto">
                {campusSearchQuery.trim() === '' ? (
                  // Show "Start typing to search" when no query
                  <div className="p-4 text-center text-gray-500">
                    <Search className="w-8 h-8 mx-auto mb-2 text-gray-300" />
                    <p>Start typing to search</p>
                    <p className="text-xs mt-1 text-gray-400">{campuses.length} universities available</p>
                  </div>
                ) : filteredCampuses.length > 0 ? (
                  filteredCampuses.map(campus => (
                    <button
                      key={campus.id}
                      onClick={() => {
                        setSelectedCampusId(campus.id);
                        setShowCampusDropdown(false);
                        setCampusSearchQuery('');
                      }}
                      className={`w-full px-3 py-2.5 text-left hover:bg-gray-100 flex items-center justify-between text-sm ${
                        campus.id === selectedCampusId ? 'bg-primary-50' : ''
                      }`}
                    >
                      <div>
                        <p className="font-medium text-gray-900">{formatCampusName(campus.name)}</p>
                        <p className="text-xs text-gray-500">{campus.city}, {campus.state}</p>
                      </div>
                      {campus.managerName && (
                        <span className="text-xs bg-green-100 text-green-700 px-2 py-0.5 rounded-full">
                          CM: {campus.managerName}
                        </span>
                      )}
                    </button>
                  ))
                ) : (
                  <p className="px-3 py-3 text-sm text-gray-500 text-center">No campuses found</p>
                )}
              </div>
            )}
          </div>
        )}
      </div>
      )}
      
      {/* Performance Chart & Summary */}
      {adminView === 'performance' && (
      <>
      {/* Summary Stats - Only visible on Performance tab */}
      <div className="grid grid-cols-5 gap-3 p-3 bg-gray-50 rounded-lg border border-gray-200 text-sm">
        <div>
          <p className="text-gray-500 text-xs">
            {selectedCampus ? `${formatCampusName(selectedCampus.name)} Volume` : 'Volume'}
          </p>
          <p className="font-semibold text-gray-900">
            {isLoadingPerformance ? '...' : formatCurrency(performance?.totalRevenue ?? 0)}
          </p>
        </div>
        <div>
          <p className="text-gray-500 text-xs">
            {selectedCampus ? 'Campus Net Revenue' : 'Profit'}
          </p>
          <p className={`font-semibold ${
            selectedCampus 
              ? (performance?.netPlatformRevenue ?? 0) >= 0 ? 'text-primary-600' : 'text-red-600'
              : (performance && (performance.netPlatformRevenue - performance.awsTotalCost) >= 0 
                ? 'text-primary-600' 
                : 'text-red-600')
          }`}>
            {isLoadingPerformance ? '...' : (
              selectedCampus 
                ? formatCurrency(performance?.netPlatformRevenue ?? 0)
                : formatCurrency((performance?.netPlatformRevenue ?? 0) - (performance?.awsTotalCost ?? 0))
            )}
          </p>
        </div>
        <div>
          <p className="text-gray-500 text-xs">Users</p>
          <p className="font-semibold text-gray-900">
            {isLoadingPerformance || isLoadingUsers ? '...' : (performance?.totalBarbers ?? 0) + totalUsersCount}
          </p>
        </div>
        <div>
          <p className="text-gray-500 text-xs">Barbers</p>
          <p className="font-semibold text-gray-900">
            {isLoadingPerformance ? '...' : performance?.totalBarbers ?? 0}
          </p>
        </div>
        <div>
          <p className="text-gray-500 text-xs">Consumers</p>
          <p className="font-semibold text-gray-900">
            {isLoadingUsers ? '...' : totalUsersCount}
          </p>
        </div>
      </div>
      <div>
        {/* Stats Header - shows hovered data or period totals */}
        <div className="flex items-center justify-center gap-4 sm:gap-6 mb-3">
          <div className="text-center">
            <p className="text-gray-500 text-xs">
              {hoveredDataPoint ? 'Date' : 'Period'}
            </p>
            <p className="text-base font-semibold text-gray-900">
              {hoveredDataPoint ? hoveredDataPoint.label : 
               metricsPeriod === '1w' ? '1 Week' : 
               metricsPeriod === '4w' ? '4 Weeks' : 
               metricsPeriod === 'mtd' ? 'MTD' : 
               metricsPeriod === 'qtd' ? 'QTD' : 
               metricsPeriod === 'ytd' ? 'YTD' : 
               metricsPeriod === '1y' ? '1 Year' : 'All Time'}
            </p>
          </div>
          <div className="text-center">
            <p className="text-gray-500 text-xs">Volume</p>
            <p className="text-base font-semibold text-gray-900">
              ${hoveredDataPoint 
                ? (hoveredDataPoint.revenue / 100).toFixed(2)
                : (metrics.reduce((sum, m) => sum + m.revenue, 0) / 100).toFixed(2)
              }
            </p>
          </div>
          <div className="text-center">
            <p className="text-gray-500 text-xs">Bookings</p>
            <p className="text-base font-semibold text-gray-900">
              {hoveredDataPoint 
                ? hoveredDataPoint.bookings
                : metrics.reduce((sum, m) => sum + m.bookings, 0)
              }
            </p>
          </div>
          <div className="text-center">
            <p className="text-gray-500 text-xs">Users</p>
            <p className="text-base font-semibold text-gray-900">
              {hoveredDataPoint 
                ? hoveredDataPoint.users
                : metricsTotalUsers
              }
            </p>
          </div>
        </div>
        
        {/* Period Selector */}
        <div className="flex flex-wrap items-center justify-center gap-2 mb-4">
          {/* Period Toggle */}
          <div className="flex flex-wrap rounded-lg bg-gray-100 p-0.5 gap-0.5">
            {[
              { key: '1w', label: '1W' },
              { key: '4w', label: '4W' },
              { key: 'mtd', label: 'MTD' },
              { key: 'qtd', label: 'QTD' },
              { key: 'ytd', label: 'YTD' },
              { key: '1y', label: '1Y' },
              { key: 'all', label: 'All' },
            ].map(({ key, label }) => (
              <button
                key={key}
                onClick={() => setMetricsPeriod(key as MetricsPeriod)}
                className={`px-2 py-1.5 text-xs font-medium rounded-md transition-colors ${
                  metricsPeriod === key 
                    ? 'bg-white text-gray-900 shadow-sm' 
                    : 'text-gray-600 hover:text-gray-900'
                }`}
              >
                {label}
              </button>
            ))}
          </div>
        </div>
        
        {/* Chart - directly under toggles */}
        {isLoadingMetrics ? (
          <div className="flex items-center justify-center py-12">
            <Loader2 className="w-5 h-5 animate-spin text-primary-500" />
          </div>
        ) : metrics.length > 0 ? (
          <div 
            ref={chartContainerRef} 
            className="h-40 sm:h-48 mb-4 max-w-2xl"
            onMouseLeave={() => { setIsChartHovered(false); setHoveredDataPoint(null); }}
            onTouchEnd={() => { setIsChartHovered(false); setHoveredDataPoint(null); }}
          >
            <Line data={chartData} options={chartOptions} plugins={[crosshairPlugin]} />
          </div>
        ) : (
          <div className="flex items-center justify-center py-12 text-gray-500 text-sm">
            <AlertCircle className="w-4 h-4 mr-2" />
            No data available for this period
          </div>
        )}
        
        {/* Performance Summary - Below chart */}
        {performance && (
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-3 text-sm">
            {/* Payment Methods - Card vs Cash (All Time) */}
            {(performance.cardCount > 0 || performance.cashCount > 0) && (
              <div className="p-3 bg-gray-50 rounded-lg border border-gray-200 sm:col-span-2">
                <p className="text-xs font-medium text-gray-700 mb-2">Payment Methods (All Time)</p>
                <div className="grid grid-cols-2 sm:grid-cols-4 gap-2 text-center">
                  <div>
                    <p className="text-[10px] text-gray-500">Card Volume</p>
                    <p className="text-sm font-semibold text-gray-900">{formatCurrency(performance.cardRevenue || 0)}</p>
                  </div>
                  <div>
                    <p className="text-[10px] text-gray-500">Card Bookings</p>
                    <p className="text-sm font-semibold text-gray-900">{performance.cardCount || 0}</p>
                  </div>
                  <div>
                    <p className="text-[10px] text-gray-500">Cash Volume</p>
                    <p className="text-sm font-semibold text-gray-900">{formatCurrency(performance.cashRevenue || 0)}</p>
                  </div>
                  <div>
                    <p className="text-[10px] text-gray-500">Cash Bookings</p>
                    <p className="text-sm font-semibold text-gray-900">{performance.cashCount || 0}</p>
                  </div>
                </div>
              </div>
            )}

            {/* Platform Revenue */}
            <div className="p-3 bg-gray-50 rounded-lg border border-gray-200">
              <p className="text-xs font-medium text-gray-700 mb-2">Platform Revenue</p>
              <div className="grid grid-cols-3 gap-2 text-center mb-3">
                <div>
                  <p className="text-[10px] text-gray-500">Gross (15%)</p>
                  <p className="text-sm font-semibold text-gray-900">{formatCurrency(performance.totalPlatformFees || 0)}</p>
                </div>
                <div>
                  <p className="text-[10px] text-gray-500">Total Stripe</p>
                  <p className="text-sm font-semibold text-red-600">-{formatCurrency(performance.estimatedStripeFees || 0)}</p>
                </div>
                <div>
                  <p className="text-[10px] text-gray-500">Net Revenue</p>
                  <p className="text-sm font-semibold text-green-600">{formatCurrency(performance.netPlatformRevenue || 0)}</p>
                </div>
              </div>
              
              {/* Stripe Fee Breakdown */}
              <div className="border-t border-gray-200 pt-2 mt-2">
                <p className="text-[10px] font-medium text-gray-600 mb-2">Stripe Fee Breakdown</p>
                <div className="space-y-1 text-[10px]">
                  <div className="flex justify-between">
                    <span className="text-gray-500">Processing (2.9% + $0.30/txn)</span>
                    <span className="text-gray-700">-{formatCurrency(performance.stripeProcessingFees || 0)}</span>
                  </div>
                  <div className="flex justify-between">
                    <span className="text-gray-500">Active Accounts ({performance.activeConnectAccounts || 0} × $2)</span>
                    <span className="text-gray-700">-{formatCurrency(performance.activeAccountBilling || 0)}</span>
                  </div>
                  <div className="flex justify-between">
                    <span className="text-gray-500">Volume Billing (0.25%)</span>
                    <span className="text-gray-700">-{formatCurrency(performance.volumeBilling || 0)}</span>
                  </div>
                  <div className="flex justify-between">
                    <span className="text-gray-500">Payouts ({performance.estimatedPayouts || 0} × $0.25 + 0.25%)</span>
                    <span className="text-gray-700">-{formatCurrency(performance.payoutFees || 0)}</span>
                  </div>
                  <div className="flex justify-between pt-1 border-t border-gray-200 font-medium">
                    <span className="text-gray-600">Connect Fees Total</span>
                    <span className="text-red-600">-{formatCurrency(performance.stripeConnectFees || 0)}</span>
                  </div>
                </div>
              </div>
            </div>

            {/* AWS Costs - Only show for platform-wide view */}
            {!selectedCampus && (
            <div className="p-3 bg-gray-50 rounded-lg border border-gray-200">
              <p className="text-xs font-medium text-gray-700 mb-2">AWS Infrastructure (Est. Monthly)</p>
              <div className="grid grid-cols-3 gap-2 text-center mb-3">
                <div>
                  <p className="text-[10px] text-gray-500">Fixed</p>
                  <p className="text-sm font-semibold text-gray-900">{formatCurrency(performance.awsFixedCosts || 0)}</p>
                </div>
                <div>
                  <p className="text-[10px] text-gray-500">Variable</p>
                  <p className="text-sm font-semibold text-gray-900">{formatCurrency(performance.awsVariableCosts || 0)}</p>
                </div>
                <div>
                  <p className="text-[10px] text-gray-500">Total</p>
                  <p className="text-sm font-semibold text-orange-600">{formatCurrency(performance.awsTotalCost || 0)}</p>
                </div>
              </div>
              
              {/* AWS Cost Breakdown */}
              <div className="border-t border-gray-200 pt-2 mt-2">
                <p className="text-[10px] font-medium text-gray-600 mb-2">AWS Breakdown</p>
                <div className="space-y-1 text-[10px]">
                  <div className="flex justify-between">
                    <span className="text-gray-500">EC2 (Server)</span>
                    <span className="text-gray-700">{formatCurrency(performance.awsEc2Cost || 0)}</span>
                  </div>
                  <div className="flex justify-between">
                    <span className="text-gray-500">VPC (Networking)</span>
                    <span className="text-gray-700">{formatCurrency(performance.awsVpcCost || 0)}</span>
                  </div>
                  <div className="flex justify-between">
                    <span className="text-gray-500">Route 53 (DNS)</span>
                    <span className="text-gray-700">{formatCurrency(performance.awsRoute53Cost || 0)}</span>
                  </div>
                  <div className="flex justify-between">
                    <span className="text-gray-500">Data Transfer</span>
                    <span className="text-gray-700">{formatCurrency(performance.awsDataTransferCost || 0)}</span>
                  </div>
                  <div className="flex justify-between">
                    <span className="text-gray-500">S3 Storage</span>
                    <span className="text-gray-700">{formatCurrency(performance.awsS3StorageCost || 0)}</span>
                  </div>
                  <div className="flex justify-between">
                    <span className="text-gray-500">S3 Requests</span>
                    <span className="text-gray-700">{formatCurrency(performance.awsS3RequestsCost || 0)}</span>
                  </div>
                </div>
              </div>
            </div>
            )}

            {/* Platform Profit Summary - Only show for platform-wide view */}
            {!selectedCampus && (
            <div className={`p-3 rounded-lg border-2 ${
              (performance.netPlatformRevenue - performance.awsTotalCost) >= 0 
                ? 'bg-primary-50 border-primary-300' 
                : 'bg-red-50 border-red-300'
            }`}>
              <p className="text-xs font-medium text-gray-700 mb-2">Platform Profit Summary</p>
              <div className="space-y-2 text-sm">
                <div className="flex justify-between">
                  <span className="text-gray-600">Gross Platform Fees (15%)</span>
                  <span className="text-gray-900 font-medium">{formatCurrency(performance.totalPlatformFees || 0)}</span>
                </div>
                <div className="flex justify-between">
                  <span className="text-gray-600">− Stripe Fees</span>
                  <span className="text-red-600 font-medium">-{formatCurrency(performance.estimatedStripeFees || 0)}</span>
                </div>
                <div className="flex justify-between border-t border-gray-200 pt-1">
                  <span className="text-gray-600">= Net Platform Revenue</span>
                  <span className="text-gray-900 font-medium">{formatCurrency(performance.netPlatformRevenue || 0)}</span>
                </div>
                <div className="flex justify-between">
                  <span className="text-gray-600">− AWS Infrastructure</span>
                  <span className="text-orange-600 font-medium">-{formatCurrency(performance.awsTotalCost || 0)}</span>
                </div>
                <div className={`flex justify-between border-t-2 pt-2 ${
                  (performance.netPlatformRevenue - performance.awsTotalCost) >= 0 
                    ? 'border-primary-400' 
                    : 'border-red-400'
                }`}>
                  <span className="font-bold text-gray-900">= Platform Profit</span>
                  <span className={`font-bold text-lg ${
                    (performance.netPlatformRevenue - performance.awsTotalCost) >= 0 
                      ? 'text-primary-600' 
                      : 'text-red-600'
                  }`}>
                    {formatCurrency((performance.netPlatformRevenue || 0) - (performance.awsTotalCost || 0))}
                  </span>
                </div>
              </div>
            </div>
            )}

            {/* Campus Revenue Summary - Only show for campus-specific view */}
            {selectedCampus && (
            <div className={`p-3 rounded-lg border-2 ${
              (performance.netPlatformRevenue || 0) >= 0 
                ? 'bg-primary-50 border-primary-300' 
                : 'bg-red-50 border-red-300'
            }`}>
              <p className="text-xs font-medium text-gray-700 mb-2">Campus Revenue Summary</p>
              <div className="space-y-2 text-sm">
                <div className="flex justify-between">
                  <span className="text-gray-600">Gross Revenue (15% of {formatCampusName(selectedCampus.name)})</span>
                  <span className="text-gray-900 font-medium">{formatCurrency(performance.totalPlatformFees || 0)}</span>
                </div>
                <div className="flex justify-between">
                  <span className="text-gray-600">− Stripe Fees</span>
                  <span className="text-red-600 font-medium">-{formatCurrency(performance.estimatedStripeFees || 0)}</span>
                </div>
                <div className={`flex justify-between border-t-2 pt-2 ${
                  (performance.netPlatformRevenue || 0) >= 0 
                    ? 'border-primary-400' 
                    : 'border-red-400'
                }`}>
                  <span className="font-bold text-gray-900">= Campus Net Revenue</span>
                  <span className={`font-bold text-lg ${
                    (performance.netPlatformRevenue || 0) >= 0 
                      ? 'text-primary-600' 
                      : 'text-red-600'
                  }`}>
                    {formatCurrency(performance.netPlatformRevenue || 0)}
                  </span>
                </div>
              </div>
              <p className="text-[10px] text-gray-500 mt-3 italic">
                Note: AWS infrastructure costs are shared across all campuses and shown in the platform-wide view.
              </p>
            </div>
            )}

            {/* Averages */}
            <div className="p-3 bg-gray-50 rounded-lg border border-gray-200">
              <p className="text-xs font-medium text-gray-700 mb-2">Averages</p>
              <div className="grid grid-cols-3 gap-2 text-center">
                <div>
                  <p className="text-[10px] text-gray-500">Per Cut</p>
                  <p className="text-sm font-semibold text-gray-900">{formatCurrency(performance.averageCostPerAppointment)}</p>
                </div>
                <div>
                  <p className="text-[10px] text-gray-500">
                    Cuts/{['1w', '4w', 'mtd'].includes(metricsPeriod) ? 'Day' : ['1y', 'ytd', 'qtd'].includes(metricsPeriod) ? 'Wk' : 'Mo'}
                  </p>
                  <p className="text-sm font-semibold text-gray-900">
                    {['1w', '4w', 'mtd'].includes(metricsPeriod)
                      ? performance.averageBookingsPerDay.toFixed(1)
                      : ['1y', 'ytd', 'qtd'].includes(metricsPeriod)
                      ? performance.averageBookingsPerWeek.toFixed(1)
                      : performance.averageBookingsPerMonth.toFixed(1)
                    }
                  </p>
                </div>
                <div>
                  <p className="text-[10px] text-gray-500">
                    Rev/{['1w', '4w', 'mtd'].includes(metricsPeriod) ? 'Day' : ['1y', 'ytd', 'qtd'].includes(metricsPeriod) ? 'Wk' : 'Mo'}
                  </p>
                  <p className="text-sm font-semibold text-gray-900">
                    {['1w', '4w', 'mtd'].includes(metricsPeriod)
                      ? formatCurrency(performance.averageRevenuePerDay)
                      : ['1y', 'ytd', 'qtd'].includes(metricsPeriod)
                      ? formatCurrency(performance.averageRevenuePerWeek)
                      : formatCurrency(performance.averageRevenuePerMonth)
                    }
                  </p>
                </div>
              </div>
              {/* Second row of averages */}
              <div className="grid grid-cols-3 gap-2 text-center mt-2 pt-2 border-t border-gray-200">
                <div>
                  <p className="text-[10px] text-gray-500">Avg Star Rating</p>
                  <p className="text-sm font-semibold text-gray-900">
                    {performance.averageRating > 0 ? performance.averageRating.toFixed(1) : '—'}
                  </p>
                </div>
                <div>
                  <p className="text-[10px] text-gray-500">Completion</p>
                  <p className="text-sm font-semibold text-gray-900">
                    {performance.completedBookings + performance.cancelledBookings > 0
                      ? `${Math.round((performance.completedBookings / (performance.completedBookings + performance.cancelledBookings)) * 100)}%`
                      : '—'}
                  </p>
                </div>
                <div>
                  <p className="text-[10px] text-gray-500">Avg Tip</p>
                  <p className="text-sm font-semibold text-gray-900">
                    {performance.completedTransactionCount > 0
                      ? formatCurrency(Math.round(performance.totalTips / performance.completedTransactionCount))
                      : '—'}
                  </p>
                </div>
              </div>
            </div>
          </div>
        )}
      </div>
      </>
      )}
      
      {/* Barber Management */}
      {adminView === 'barbers' && (
      <div>
        {selectedBarber ? (
          /* Barber Detail View */
          <div>
            {/* Back button and barber header */}
            <button 
              onClick={handleBackToBarbers}
              className="flex items-center gap-1 text-gray-600 hover:text-gray-900 mb-3 text-sm"
            >
              <ChevronLeft className="w-4 h-4" />
              Back to barbers
            </button>
            
            <div className="flex items-center gap-3 mb-4 p-3 bg-gray-50 rounded-lg">
              <div className="w-12 h-12 rounded-full bg-gray-200 flex items-center justify-center overflow-hidden flex-shrink-0">
                {selectedBarber.profileImageUrl ? (
                  <img src={selectedBarber.profileImageUrl} alt="" className="w-full h-full object-cover" />
                ) : (
                  <span className="text-sm font-bold text-gray-500">{selectedBarber.firstName.charAt(0)}{selectedBarber.lastName.charAt(0)}</span>
                )}
              </div>
              <div>
                <p className="font-semibold text-gray-900">
                  {selectedBarber.firstName} {selectedBarber.lastName}
                </p>
                <p className="text-xs text-gray-500">{selectedBarber.email}</p>
              </div>
            </div>
            
            {/* Bookings list */}
            <div className="flex items-center justify-between mb-3">
              <h3 className="text-base font-semibold text-gray-900">Booking History</h3>
              <span className="text-xs text-gray-500">{barberBookings.length} bookings</span>
            </div>
            
            {isLoadingBarberBookings ? (
              <div className="flex items-center justify-center py-8">
                <Loader2 className="w-5 h-5 animate-spin text-primary-500" />
              </div>
            ) : barberBookings.length > 0 ? (
              <div className="space-y-3 max-h-96 overflow-y-auto">
                {barberBookings.map(booking => (
                  <div 
                    key={booking.id} 
                    className="p-3 rounded-lg border border-gray-200 hover:bg-gray-50 cursor-pointer"
                    onClick={() => handleBookingClick(booking.id)}
                  >
                    <div className="flex items-center justify-between mb-2">
                      <div className="flex items-center gap-2">
                        <span className={`text-xs px-2 py-0.5 rounded-full font-medium ${
                          booking.status === 'COMPLETED' || booking.status === 'PAID' 
                            ? 'bg-green-100 text-green-700' 
                            : booking.status === 'CANCELLED'
                            ? 'bg-red-100 text-red-700'
                            : 'bg-gray-100 text-gray-700'
                        }`}>
                          {booking.status}
                        </span>
                        {(booking.status === 'COMPLETED' || booking.status === 'PAID') && booking.payment_method && (
                          <span className="text-xs px-2 py-0.5 rounded-full font-medium bg-primary-500 text-white">
                            {booking.payment_method === 'card' ? 'Card' : 'Cash'}
                          </span>
                        )}
                        {booking.review_rating && (
                          <span className="flex items-center gap-0.5 text-xs text-amber-600">
                            <Star className="w-3 h-3 fill-amber-400" />
                            {booking.review_rating}
                          </span>
                        )}
                      </div>
                      <span className="text-xs text-gray-500">
                        ${(booking.total_paid_cents / 100).toFixed(2)}
                      </span>
                    </div>
                    
                    <p className="font-medium text-sm text-gray-900 mb-1">
                      {booking.consumer_first_name} {booking.consumer_last_name}
                    </p>
                    <p className="text-xs text-gray-500">{formatServiceType(booking.service_type)}</p>
                    
                    <div className="flex items-center gap-3 mt-2 text-xs text-gray-500">
                      <span className="flex items-center gap-1">
                        <Clock className="w-3 h-3" />
                        {new Date(booking.scheduled_time).toLocaleDateString('en-US', { 
                          month: 'short', day: 'numeric', year: 'numeric', hour: 'numeric', minute: '2-digit'
                        })}
                      </span>
                      {booking.message_count > 0 && (
                        <span className="flex items-center gap-1">
                          <MessageSquare className="w-3 h-3" />
                          {booking.message_count}
                        </span>
                      )}
                    </div>
                    
                    {/* Expandable messages section */}
                    {selectedBookingId === booking.id && (
                      <div className="mt-3 pt-3 border-t border-gray-200">
                        <p className="text-xs font-semibold text-gray-700 mb-2">Messages</p>
                        {isLoadingMessages ? (
                          <div className="flex items-center justify-center py-2">
                            <Loader2 className="w-4 h-4 animate-spin text-primary-500" />
                          </div>
                        ) : selectedBookingMessages.length > 0 ? (
                          <div className="space-y-2 max-h-40 overflow-y-auto">
                            {selectedBookingMessages.map(msg => (
                              <div key={msg.id} className="text-xs p-2 bg-gray-100 rounded">
                                <div className="flex items-center gap-1 mb-1">
                                  <span className={`text-[10px] px-1 py-0.5 rounded ${
                                    ['BARBER', 'CAMPUS_MANAGER', 'ADMIN'].includes(msg.sender_role) 
                                      ? 'bg-green-100 text-green-700' 
                                      : 'bg-amber-100 text-amber-700'
                                  }`}>
                                    {['BARBER', 'CAMPUS_MANAGER', 'ADMIN'].includes(msg.sender_role) ? 'Barber' : 'Customer'}
                                  </span>
                                  <span className="text-[10px] text-gray-400 ml-auto">
                                    {new Date(msg.created_at).toLocaleTimeString('en-US', { 
                                      hour: 'numeric', minute: '2-digit'
                                    })}
                                  </span>
                                </div>
                                <p className="text-gray-700">{msg.content}</p>
                              </div>
                            ))}
                          </div>
                        ) : (
                          <p className="text-xs text-gray-400">No messages</p>
                        )}
                        
                        {booking.review_text && (
                          <div className="mt-2 p-2 bg-amber-50 rounded border border-amber-100">
                            <p className="text-xs font-semibold text-amber-700 mb-1">Review</p>
                            <p className="text-xs text-gray-700">{booking.review_text}</p>
                          </div>
                        )}
                      </div>
                    )}
                  </div>
                ))}
              </div>
            ) : (
              <div className="flex flex-col items-center justify-center py-8 text-gray-400">
                <Calendar className="w-8 h-8 mb-2" />
                <p className="text-sm">No bookings found</p>
              </div>
            )}
          </div>
        ) : !selectedCampusId ? (
          /* All Barbers View - organized by status with tabs */
          <div>
            {/* Search bar */}
            <div className="relative mb-3">
              <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-gray-400" />
              <input
                type="text"
                placeholder="Search barbers by name, email, or campus..."
                className="w-full pl-9 pr-4 py-2 border border-gray-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-primary-500"
                value={allBarberSearchQuery}
                onChange={(e) => setAllBarberSearchQuery(e.target.value)}
              />
            </div>
            
            <p className="text-xs text-gray-500 mb-2">Click on a barber to view their booking activity</p>
            
            {/* Main category tabs */}
            <nav className="flex justify-center gap-1 border-b border-gray-200 mb-4">
              <button
                onClick={() => { setBarberViewTab('managers'); setSelectedApplication(null); }}
                className={`py-2 px-3 border-b-2 font-medium text-sm transition-all duration-200 whitespace-nowrap ${
                  barberViewTab === 'managers'
                    ? 'border-primary-500 text-primary-600'
                    : 'border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300'
                }`}
              >
                Managers ({filteredAllBarbers.filter(b => b.isCampusManager).length})
              </button>
              <button
                onClick={() => { setBarberViewTab('barbers'); setSelectedApplication(null); }}
                className={`py-2 px-3 border-b-2 font-medium text-sm transition-all duration-200 whitespace-nowrap ${
                  barberViewTab === 'barbers'
                    ? 'border-primary-500 text-primary-600'
                    : 'border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300'
                }`}
              >
                Barbers ({filteredAllBarbers.filter(b => !b.isCampusManager).length})
              </button>
              <button
                onClick={() => { setBarberViewTab('applications'); setSelectedApplication(null); }}
                className={`py-2 px-3 border-b-2 font-medium text-sm transition-all duration-200 whitespace-nowrap ${
                  barberViewTab === 'applications'
                    ? 'border-primary-500 text-primary-600'
                    : 'border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300'
                }`}
              >
                Applications ({applications.length})
              </button>
            </nav>
            
            {/* Visibility toggle and Stripe filter for Barbers tab */}
            {barberViewTab === 'barbers' && (
              <div className="space-y-2 mb-3">
                {/* Visible/Hidden toggle */}
                <div className="flex rounded-lg bg-gray-100 p-1">
                  <button
                    onClick={() => setBarberVisibilityFilter('visible')}
                    className={`flex-1 px-3 py-1.5 text-xs font-medium rounded-md transition-colors ${
                      barberVisibilityFilter === 'visible'
                        ? 'bg-white text-gray-900 shadow-sm'
                        : 'text-gray-600 hover:text-gray-900'
                    }`}
                  >
                    Visible ({filteredAllBarbers.filter(b => b.isActive && !b.isCampusManager).length})
                  </button>
                  <button
                    onClick={() => setBarberVisibilityFilter('hidden')}
                    className={`flex-1 px-3 py-1.5 text-xs font-medium rounded-md transition-colors ${
                      barberVisibilityFilter === 'hidden'
                        ? 'bg-white text-gray-900 shadow-sm'
                        : 'text-gray-600 hover:text-gray-900'
                    }`}
                  >
                    Hidden ({filteredAllBarbers.filter(b => !b.isActive && !b.isCampusManager).length})
                  </button>
                </div>
                
                {/* Stripe filter - only for visible barbers */}
                {barberVisibilityFilter === 'visible' && (
                  <div className="flex rounded-lg bg-gray-100 p-1">
                    <button
                      onClick={() => setActiveBarberStripeFilter('all')}
                      className={`flex-1 px-3 py-1.5 text-xs font-medium rounded-md transition-colors ${
                        activeBarberStripeFilter === 'all'
                          ? 'bg-white text-gray-900 shadow-sm'
                          : 'text-gray-600 hover:text-gray-900'
                      }`}
                    >
                      All ({filteredAllBarbers.filter(b => b.isActive && !b.isCampusManager).length})
                    </button>
                    <button
                      onClick={() => setActiveBarberStripeFilter('setup')}
                      className={`flex-1 px-3 py-1.5 text-xs font-medium rounded-md transition-colors ${
                        activeBarberStripeFilter === 'setup'
                          ? 'bg-white text-gray-900 shadow-sm'
                          : 'text-gray-600 hover:text-gray-900'
                      }`}
                    >
                      Stripe ({filteredAllBarbers.filter(b => b.isActive && !b.isCampusManager && b.hasStripeSetup).length})
                    </button>
                    <button
                      onClick={() => setActiveBarberStripeFilter('not-setup')}
                      className={`flex-1 px-3 py-1.5 text-xs font-medium rounded-md transition-colors ${
                        activeBarberStripeFilter === 'not-setup'
                          ? 'bg-white text-gray-900 shadow-sm'
                          : 'text-gray-600 hover:text-gray-900'
                      }`}
                    >
                      No Stripe ({filteredAllBarbers.filter(b => b.isActive && !b.isCampusManager && !b.hasStripeSetup).length})
                    </button>
                  </div>
                )}
              </div>
            )}
            
            <div className="flex items-center justify-between mb-3">
              <h3 className="text-base font-semibold text-gray-900">
                {barberViewTab === 'managers' ? 'Campus Managers' : barberViewTab === 'barbers' ? (barberVisibilityFilter === 'visible' ? 'Visible Barbers' : 'Hidden Barbers') : 'Barber Applications'}
              </h3>
              <span className="text-xs text-gray-500">
                {barberViewTab === 'applications' ? `${applications.length} applications` : `${filteredAllBarbers.length} total barbers`}
              </span>
            </div>
            
            {isLoadingBarbers ? (
              <div className="flex items-center justify-center py-8">
                <Loader2 className="w-5 h-5 animate-spin text-primary-500" />
              </div>
            ) : (
              <div className="space-y-2 max-h-80 overflow-y-auto">
                {/* Campus Managers Tab */}
                {barberViewTab === 'managers' && (
                  filteredAllBarbers.filter(b => b.isCampusManager).length > 0 ? (
                    filteredAllBarbers.filter(b => b.isCampusManager).map(barber => (
                      <button
                        key={barber.id}
                        onClick={() => handleBarberClick(barber)}
                        className="w-full flex items-center justify-between p-2.5 rounded-lg border transition-colors text-left border-primary-200 bg-primary-50 hover:bg-primary-100"
                      >
                        <div className="flex items-center gap-2.5">
                          <div className="w-8 h-8 rounded-full bg-gray-200 flex items-center justify-center overflow-hidden flex-shrink-0">
                            {barber.profileImageUrl ? (
                              <img src={barber.profileImageUrl} alt="" className="w-full h-full object-cover" />
                            ) : (
                              <span className="text-xs font-bold text-gray-500">{barber.firstName.charAt(0)}{barber.lastName.charAt(0)}</span>
                            )}
                          </div>
                          <div className="min-w-0">
                            <p className="font-medium text-gray-900 text-sm flex items-center gap-1.5 truncate">
                              {barber.firstName} {barber.lastName}
                              <span className="text-[10px] text-primary-600 bg-primary-100 px-1.5 py-0.5 rounded">Manager</span>
                              {barber.hasStripeSetup && (
                                <span className="text-[10px] text-white bg-primary-500 px-1.5 py-0.5 rounded">Stripe</span>
                              )}
                            </p>
                            <p className="text-xs text-gray-500 truncate">{barber.email}</p>
                          </div>
                        </div>
                        <div className="flex items-center gap-2">
                          <div className="text-right mr-1">
                            <p className="text-[10px] text-gray-500">{barber.completedBookings ?? 0} {(barber.completedBookings ?? 0) === 1 ? 'cut' : 'cuts'} · {formatCurrency(barber.totalVolumeCents ?? 0)}</p>
                            <p className="text-[10px] text-gray-400">{barber.campusName ? formatCampusName(barber.campusName) : ''}</p>
                          </div>
                          <ChevronDown className="w-4 h-4 text-gray-400 -rotate-90" />
                        </div>
                      </button>
                    ))
                  ) : (
                    <div className="flex flex-col items-center justify-center py-8 text-gray-400">
                      <p className="text-sm">No campus managers</p>
                    </div>
                  )
                )}
                
                {/* Visible Barbers (within Barbers tab) */}
                {barberViewTab === 'barbers' && barberVisibilityFilter === 'visible' && (() => {
                  const activeBarbers = filteredAllBarbers.filter(b => b.isActive && !b.isCampusManager);
                  const stripeFilteredBarbers = activeBarberStripeFilter === 'all' 
                    ? activeBarbers
                    : activeBarberStripeFilter === 'setup'
                    ? activeBarbers.filter(b => b.hasStripeSetup)
                    : activeBarbers.filter(b => !b.hasStripeSetup);
                  
                  return stripeFilteredBarbers.length > 0 ? (
                    stripeFilteredBarbers.map(barber => (
                      <button
                        key={barber.id}
                        onClick={() => handleBarberClick(barber)}
                        className="w-full flex items-center justify-between p-2.5 rounded-lg border transition-colors text-left border-gray-200 hover:bg-gray-50"
                      >
                        <div className="flex items-center gap-2.5">
                          <div className="w-8 h-8 rounded-full bg-gray-200 flex items-center justify-center overflow-hidden flex-shrink-0">
                            {barber.profileImageUrl ? (
                              <img src={barber.profileImageUrl} alt="" className="w-full h-full object-cover" />
                            ) : (
                              <span className="text-xs font-bold text-gray-500">{barber.firstName.charAt(0)}{barber.lastName.charAt(0)}</span>
                            )}
                          </div>
                          <div className="min-w-0">
                            <p className="font-medium text-gray-900 text-sm flex items-center gap-1.5 truncate">
                              {barber.firstName} {barber.lastName}
                              {barber.hasStripeSetup && (
                                <span className="text-[10px] text-white bg-primary-500 px-1.5 py-0.5 rounded">Stripe</span>
                              )}
                            </p>
                            <p className="text-xs text-gray-500 truncate">{barber.email}</p>
                          </div>
                        </div>
                        <div className="flex items-center gap-2">
                          <div className="text-right mr-1">
                            <p className="text-[10px] text-gray-500">{barber.completedBookings ?? 0} {(barber.completedBookings ?? 0) === 1 ? 'cut' : 'cuts'} · {formatCurrency(barber.totalVolumeCents ?? 0)}</p>
                            <p className="text-[10px] text-gray-400">{barber.campusName ? formatCampusName(barber.campusName) : ''}</p>
                          </div>
                          <ChevronDown className="w-4 h-4 text-gray-400 -rotate-90" />
                        </div>
                      </button>
                    ))
                  ) : (
                    <div className="flex flex-col items-center justify-center py-8 text-gray-400">
                      <Scissors className="w-8 h-8 mb-2" />
                      <p className="text-sm">No {activeBarberStripeFilter === 'setup' ? 'barbers with Stripe' : activeBarberStripeFilter === 'not-setup' ? 'barbers without Stripe' : 'active barbers'}</p>
                    </div>
                  );
                })()}
                
                {/* Hidden Barbers (within Barbers tab) */}
                {barberViewTab === 'barbers' && barberVisibilityFilter === 'hidden' && (
                  filteredAllBarbers.filter(b => !b.isActive && !b.isCampusManager).length > 0 ? (
                    filteredAllBarbers.filter(b => !b.isActive && !b.isCampusManager).map(barber => (
                      <button
                        key={barber.id}
                        onClick={() => handleBarberClick(barber)}
                        className="w-full flex items-center justify-between p-2.5 rounded-lg border border-gray-200 bg-gray-50 opacity-60 hover:opacity-80 text-left transition-opacity"
                      >
                        <div className="flex items-center gap-2.5">
                          <div className="w-8 h-8 rounded-full bg-gray-200 flex items-center justify-center overflow-hidden flex-shrink-0">
                            {barber.profileImageUrl ? (
                              <img src={barber.profileImageUrl} alt="" className="w-full h-full object-cover" />
                            ) : (
                              <span className="text-xs font-bold text-gray-500">{barber.firstName.charAt(0)}{barber.lastName.charAt(0)}</span>
                            )}
                          </div>
                          <div className="min-w-0">
                            <p className="font-medium text-gray-600 text-sm flex items-center gap-1.5 truncate">
                              {barber.firstName} {barber.lastName}
                              {barber.hasStripeSetup && (
                                <span className="text-[10px] text-white bg-primary-500 px-1.5 py-0.5 rounded">Stripe</span>
                              )}
                            </p>
                            <p className="text-xs text-gray-400 truncate">{barber.email}</p>
                          </div>
                        </div>
                        <div className="flex items-center gap-2">
                          <div className="text-right mr-1">
                            <p className="text-[10px] text-gray-400">{barber.completedBookings ?? 0} {(barber.completedBookings ?? 0) === 1 ? 'cut' : 'cuts'} · {formatCurrency(barber.totalVolumeCents ?? 0)}</p>
                            <p className="text-[10px] text-gray-400">{barber.campusName ? formatCampusName(barber.campusName) : ''}</p>
                          </div>
                          <ChevronDown className="w-4 h-4 text-gray-400 -rotate-90" />
                        </div>
                      </button>
                    ))
                  ) : (
                    <div className="flex flex-col items-center justify-center py-8 text-gray-400">
                      <Scissors className="w-8 h-8 mb-2" />
                      <p className="text-sm">No inactive barbers</p>
                    </div>
                  )
                )}
                
                {/* Applications Tab */}
                {barberViewTab === 'applications' && (
                  isLoadingApplications ? (
                    <div className="flex items-center justify-center py-8">
                      <Loader2 className="w-5 h-5 animate-spin text-primary-500" />
                    </div>
                  ) : selectedApplication ? (
                    // Detailed Application View
                    <div className="space-y-4">
                      <button
                        onClick={() => setSelectedApplication(null)}
                        className="flex items-center gap-2 text-gray-600 hover:text-gray-900 transition-colors"
                      >
                        <ChevronLeft className="w-5 h-5" />
                        <span className="text-sm font-medium">Back to Applications</span>
                      </button>
                      
                      <div className="bg-white rounded-lg border border-gray-200 p-4 sm:p-6">
                        <div className="flex items-start justify-between gap-4">
                          <div className="flex items-center gap-4">
                            <div className="w-14 h-14 rounded-full bg-primary-100 flex items-center justify-center">
                              <Users className="w-7 h-7 text-primary-600" />
                            </div>
                            <div>
                              <h3 className="text-xl font-bold text-gray-900">
                                {selectedApplication.first_name || selectedApplication.user?.first_name || 'Unknown'} {selectedApplication.last_name || selectedApplication.user?.last_name || 'User'}
                              </h3>
                              <p className="text-gray-600">{selectedApplication.email || selectedApplication.user?.email || 'No email'}</p>
                              <span className={`inline-block mt-2 text-xs font-medium px-2 py-1 rounded-full ${
                                selectedApplication.status === 'pending' 
                                  ? 'bg-amber-100 text-amber-700' 
                                  : selectedApplication.status === 'approved'
                                    ? 'bg-green-100 text-green-700'
                                    : 'bg-gray-100 text-gray-700'
                              }`}>
                                {selectedApplication.status === 'pending' ? 'Pending' : selectedApplication.status === 'approved' ? 'Approved' : selectedApplication.status}
                              </span>
                            </div>
                          </div>
                          <button
                            type="button"
                            onClick={(e) => { e.stopPropagation(); setShowContactModal(selectedApplication); }}
                            className="hidden sm:flex items-center px-4 py-2 bg-primary-600 text-white rounded-lg font-medium text-sm hover:bg-primary-700 transition-colors flex-shrink-0"
                          >
                            Schedule Interview
                          </button>
                        </div>
                        <button
                          type="button"
                          onClick={(e) => { e.stopPropagation(); setShowContactModal(selectedApplication); }}
                          className="sm:hidden flex items-center justify-center w-full mt-4 px-4 py-2.5 bg-primary-600 text-white rounded-lg font-medium text-sm hover:bg-primary-700 transition-colors"
                        >
                          Schedule Interview
                        </button>
                      </div>

                      <div className="bg-white rounded-lg border border-gray-200 p-4 sm:p-6">
                        <h4 className="font-semibold text-gray-900 mb-4">Application Details</h4>
                        <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                          <div className="p-3 bg-gray-50 rounded-lg">
                            <p className="text-xs text-gray-500 mb-1">Campus</p>
                            <p className="font-semibold text-gray-900">{selectedApplication.campus_name || 'Unknown'}</p>
                          </div>
                          <div className="p-3 bg-gray-50 rounded-lg">
                            <p className="text-xs text-gray-500 mb-1">Experience</p>
                            <p className="font-semibold text-gray-900">{selectedApplication.years_experience || 'Not specified'} years</p>
                          </div>
                          <div className="p-3 bg-gray-50 rounded-lg">
                            <p className="text-xs text-gray-500 mb-1">Phone Number</p>
                            <p className="font-semibold text-gray-900">{selectedApplication.phone_number || 'Not provided'}</p>
                            {selectedApplication.phone_number && (
                              <div className="flex gap-2 mt-2">
                                <a href={`tel:${selectedApplication.phone_number}`} className="text-xs text-primary-600 hover:underline">Call</a>
                                <a href={`sms:${selectedApplication.phone_number}`} className="text-xs text-primary-600 hover:underline">Text</a>
                              </div>
                            )}
                          </div>
                          <div className="p-3 bg-gray-50 rounded-lg">
                            <p className="text-xs text-gray-500 mb-1">Available Hours</p>
                            <p className="font-semibold text-gray-900">{selectedApplication.available_hours || 'Not specified'}</p>
                          </div>
                          <div className="p-3 bg-gray-50 rounded-lg">
                            <p className="text-xs text-gray-500 mb-1">Has Own Tools</p>
                            <p className="font-semibold text-gray-900">{selectedApplication.has_own_tools ? 'Yes' : 'No'}</p>
                          </div>
                          <div className="p-3 bg-gray-50 rounded-lg">
                            <p className="text-xs text-gray-500 mb-1">Applied On</p>
                            <p className="font-semibold text-gray-900">
                              {new Date(selectedApplication.created_at).toLocaleDateString('en-US', { year: 'numeric', month: 'long', day: 'numeric' })}
                            </p>
                          </div>
                        </div>

                        {selectedApplication.specialties && selectedApplication.specialties.length > 0 && (
                          <div className="mt-4">
                            <p className="text-xs text-gray-500 mb-2">Specialties</p>
                            <div className="flex flex-wrap gap-2">
                              {selectedApplication.specialties.map((specialty, idx) => (
                                <span key={idx} className="px-3 py-1 bg-primary-100 text-primary-700 rounded-full text-sm font-medium">
                                  {specialty}
                                </span>
                              ))}
                            </div>
                          </div>
                        )}

                        {selectedApplication.why_be_barber && (
                          <div className="mt-4 p-4 bg-primary-50 rounded-lg border border-primary-100">
                            <p className="text-xs text-primary-600 font-semibold mb-2 uppercase tracking-wide">Why They Want to Join</p>
                            <p className="text-gray-700 italic">"{selectedApplication.why_be_barber}"</p>
                          </div>
                        )}
                      </div>

                      {selectedApplication.status === 'pending' && (
                        <div className="flex flex-col sm:flex-row gap-3">
                          <Button
                            onClick={() => {
                              requestApplicationAction(selectedApplication, 'approve');
                            }}
                            disabled={applicationActionLoading === selectedApplication.id}
                            className="flex-1 py-3 justify-center"
                          >
                            <CheckCircle className="w-5 h-5 mr-2" />
                            Approve Application
                          </Button>
                          <Button
                            variant="outline"
                            onClick={() => {
                              requestApplicationAction(selectedApplication, 'reject');
                            }}
                            disabled={applicationActionLoading === selectedApplication.id}
                            className="flex-1 py-3 justify-center text-red-600 border-red-300 hover:bg-red-50"
                          >
                            <XCircle className="w-5 h-5 mr-2" />
                            Reject Application
                          </Button>
                        </div>
                      )}
                    </div>
                  ) : applications.length > 0 ? (
                    applications.map(app => (
                      <div
                        key={app.id}
                        onClick={() => setSelectedApplication(app)}
                        className="p-3 rounded-lg border border-gray-200 bg-white hover:bg-gray-50 cursor-pointer transition-colors"
                      >
                        <div className="flex items-start justify-between gap-3">
                          <div className="flex-1 min-w-0">
                            <div className="flex items-center gap-2 mb-1">
                              <p className="font-medium text-gray-900 text-sm truncate">
                                {app.first_name || app.user?.first_name || 'Unknown'} {app.last_name || app.user?.last_name || 'User'}
                              </p>
                              <span className={`text-xs font-medium px-2 py-0.5 rounded-full ${
                                app.status === 'pending' 
                                  ? 'bg-amber-100 text-amber-700' 
                                  : 'bg-green-100 text-green-700'
                              }`}>
                                {app.status === 'pending' ? 'Pending' : 'Approved (Awaiting Signup)'}
                              </span>
                            </div>
                            <p className="text-xs text-gray-500 truncate">{app.email || app.user?.email || 'No email'}</p>
                            <p className="text-xs text-gray-400 truncate">{app.campus_name || 'Unknown campus'}</p>
                            {app.years_experience !== undefined && (
                              <p className="text-xs text-gray-600 mt-1">{app.years_experience} years experience</p>
                            )}
                          </div>
                          <div className="flex items-center gap-2 flex-shrink-0">
                            {app.status === 'pending' && (
                              <div className="flex items-center gap-1">
                                <button
                                  onClick={(e) => { e.stopPropagation(); requestApplicationAction(app, 'approve'); }}
                                  disabled={applicationActionLoading === app.id}
                                  className="p-1.5 rounded-full bg-green-100 text-green-600 hover:bg-green-200 transition-colors disabled:opacity-50"
                                  title="Approve"
                                >
                                  {applicationActionLoading === app.id ? (
                                    <Loader2 className="w-4 h-4 animate-spin" />
                                  ) : (
                                    <CheckCircle className="w-4 h-4" />
                                  )}
                                </button>
                                <button
                                  onClick={(e) => { e.stopPropagation(); requestApplicationAction(app, 'reject'); }}
                                  disabled={applicationActionLoading === app.id}
                                  className="p-1.5 rounded-full bg-red-100 text-red-600 hover:bg-red-200 transition-colors disabled:opacity-50"
                                  title="Reject"
                                >
                                  <XCircle className="w-4 h-4" />
                                </button>
                              </div>
                            )}
                            <ChevronDown className="w-4 h-4 text-gray-400 -rotate-90" />
                          </div>
                        </div>
                      </div>
                    ))
                  ) : (
                    <div className="flex flex-col items-center justify-center py-8 text-gray-400">
                      <p className="text-sm">No incoming barber applications yet</p>
                    </div>
                  )
                )}
              </div>
            )}
          </div>
        ) : (
          /* Barber List View (Campus-specific) */
          <>
            <div className="flex items-center justify-between mb-3">
              <h3 className="text-base font-semibold text-gray-900">Barber Management</h3>
            </div>
            
            {/* Main category tabs - same as all-barbers view */}
            <nav className="flex justify-center gap-1 border-b border-gray-200 mb-4">
              <button
                onClick={() => { setBarberViewTab('managers'); setSelectedApplication(null); }}
                className={`py-2 px-3 border-b-2 font-medium text-sm transition-all duration-200 whitespace-nowrap ${
                  barberViewTab === 'managers'
                    ? 'border-primary-500 text-primary-600'
                    : 'border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300'
                }`}
              >
                Managers ({filteredBarbers.filter(b => b.isCampusManager).length})
              </button>
              <button
                onClick={() => { setBarberViewTab('barbers'); setSelectedApplication(null); }}
                className={`py-2 px-3 border-b-2 font-medium text-sm transition-all duration-200 whitespace-nowrap ${
                  barberViewTab === 'barbers'
                    ? 'border-primary-500 text-primary-600'
                    : 'border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300'
                }`}
              >
                Barbers ({filteredBarbers.filter(b => !b.isCampusManager).length})
              </button>
              <button
                onClick={() => { setBarberViewTab('applications'); setSelectedApplication(null); }}
                className={`py-2 px-3 border-b-2 font-medium text-sm transition-all duration-200 whitespace-nowrap ${
                  barberViewTab === 'applications'
                    ? 'border-primary-500 text-primary-600'
                    : 'border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300'
                }`}
              >
                Applications ({applications.length})
              </button>
            </nav>
            
            {/* Visibility toggle for Barbers tab */}
            {barberViewTab === 'barbers' && (
              <div className="space-y-2 mb-3">
                <div className="flex rounded-lg bg-gray-100 p-1">
                  <button
                    onClick={() => setBarberVisibilityFilter('visible')}
                    className={`flex-1 px-3 py-1.5 text-xs font-medium rounded-md transition-colors ${
                      barberVisibilityFilter === 'visible'
                        ? 'bg-white text-gray-900 shadow-sm'
                        : 'text-gray-600 hover:text-gray-900'
                    }`}
                  >
                    Visible ({filteredBarbers.filter(b => b.isActive && !b.isCampusManager).length})
                  </button>
                  <button
                    onClick={() => setBarberVisibilityFilter('hidden')}
                    className={`flex-1 px-3 py-1.5 text-xs font-medium rounded-md transition-colors ${
                      barberVisibilityFilter === 'hidden'
                        ? 'bg-white text-gray-900 shadow-sm'
                        : 'text-gray-600 hover:text-gray-900'
                    }`}
                  >
                    Hidden ({filteredBarbers.filter(b => !b.isActive && !b.isCampusManager).length})
                  </button>
                </div>
                
                {/* Stripe filter - only for visible barbers */}
                {barberVisibilityFilter === 'visible' && (
                  <div className="flex rounded-lg bg-gray-100 p-1">
                    <button
                      onClick={() => setActiveBarberStripeFilter('all')}
                      className={`flex-1 px-3 py-1.5 text-xs font-medium rounded-md transition-colors ${
                        activeBarberStripeFilter === 'all'
                          ? 'bg-white text-gray-900 shadow-sm'
                          : 'text-gray-600 hover:text-gray-900'
                      }`}
                    >
                      All ({filteredBarbers.filter(b => b.isActive && !b.isCampusManager).length})
                    </button>
                    <button
                      onClick={() => setActiveBarberStripeFilter('setup')}
                      className={`flex-1 px-3 py-1.5 text-xs font-medium rounded-md transition-colors ${
                        activeBarberStripeFilter === 'setup'
                          ? 'bg-white text-gray-900 shadow-sm'
                          : 'text-gray-600 hover:text-gray-900'
                      }`}
                    >
                      Stripe ({filteredBarbers.filter(b => b.isActive && !b.isCampusManager && b.hasStripeSetup).length})
                    </button>
                    <button
                      onClick={() => setActiveBarberStripeFilter('not-setup')}
                      className={`flex-1 px-3 py-1.5 text-xs font-medium rounded-md transition-colors ${
                        activeBarberStripeFilter === 'not-setup'
                          ? 'bg-white text-gray-900 shadow-sm'
                          : 'text-gray-600 hover:text-gray-900'
                      }`}
                    >
                      No Stripe ({filteredBarbers.filter(b => b.isActive && !b.isCampusManager && !b.hasStripeSetup).length})
                    </button>
                  </div>
                )}
              </div>
            )}
            
            {(barberViewTab === 'managers' || barberViewTab === 'barbers') && (
              <>
                {/* Search */}
                <div className="relative mb-3">
                  <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-gray-400" />
                  <input
                    type="text"
                    value={barberSearchQuery}
                    onChange={(e) => setBarberSearchQuery(e.target.value)}
                    placeholder="Search barbers..."
                    className="w-full pl-9 pr-4 py-2 border border-gray-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-primary-500"
                  />
                </div>
                
                <p className="text-xs text-gray-500 mb-2">Click on a barber to view their booking activity</p>
            
            {isLoadingBarbers ? (
              <div className="flex items-center justify-center py-8">
                <Loader2 className="w-5 h-5 animate-spin text-purple-500" />
              </div>
            ) : filteredBarbers.length > 0 ? (
              <div className="space-y-4 max-h-80 overflow-y-auto">
                {/* Barbers Tab - Visible */}
                {barberViewTab === 'barbers' && barberVisibilityFilter === 'visible' && (() => {
                  const visibleBarbers = filteredBarbers.filter(b => b.isActive && !b.isCampusManager);
                  const stripeFilteredBarbers = activeBarberStripeFilter === 'all' 
                    ? visibleBarbers
                    : activeBarberStripeFilter === 'setup'
                    ? visibleBarbers.filter(b => b.hasStripeSetup)
                    : visibleBarbers.filter(b => !b.hasStripeSetup);
                  
                  return stripeFilteredBarbers.length > 0 ? (
                    <div className="space-y-2">
                      {stripeFilteredBarbers.map(barber => (
                        <button 
                          key={barber.id}
                          onClick={() => handleBarberClick(barber)}
                          className="w-full flex items-center justify-between p-2.5 rounded-lg border transition-colors text-left border-gray-200 hover:bg-gray-50"
                        >
                          <div className="flex items-center gap-2.5">
                            <div className="w-8 h-8 rounded-full bg-gray-200 flex items-center justify-center overflow-hidden flex-shrink-0">
                              {barber.profileImageUrl ? (
                                <img src={barber.profileImageUrl} alt="" className="w-full h-full object-cover" />
                              ) : (
                                <span className="text-xs font-bold text-gray-500">
                                  {barber.firstName.charAt(0)}{barber.lastName.charAt(0)}
                                </span>
                              )}
                            </div>
                            <div className="min-w-0">
                              <p className="font-medium text-gray-900 text-sm flex items-center gap-1.5 truncate">
                                {barber.firstName} {barber.lastName}
                                {barber.hasStripeSetup && (
                                  <span className="text-[10px] text-white bg-primary-500 px-1.5 py-0.5 rounded">Stripe</span>
                                )}
                              </p>
                              <p className="text-xs text-gray-500 truncate">{barber.email}</p>
                            </div>
                          </div>
                          <ChevronDown className="w-4 h-4 text-gray-400 -rotate-90" />
                        </button>
                      ))}
                    </div>
                  ) : (
                    <div className="flex flex-col items-center justify-center py-8 text-gray-500">
                      <Users className="w-10 h-10 text-gray-300 mb-2" />
                      <p className="text-sm">No barbers match this filter</p>
                    </div>
                  );
                })()}
                
                {/* Barbers Tab - Hidden */}
                {barberViewTab === 'barbers' && barberVisibilityFilter === 'hidden' && (() => {
                  const hiddenBarbers = filteredBarbers.filter(b => !b.isActive && !b.isCampusManager);
                  
                  return hiddenBarbers.length > 0 ? (
                    <div className="space-y-2">
                      {hiddenBarbers.map(barber => (
                        <button 
                          key={barber.id}
                          onClick={() => handleBarberClick(barber)}
                          className="w-full flex items-center justify-between p-2.5 rounded-lg border border-gray-200 bg-gray-50 opacity-60 hover:opacity-80 text-left transition-opacity"
                        >
                          <div className="flex items-center gap-2.5">
                            <div className="w-8 h-8 rounded-full bg-gray-200 flex items-center justify-center overflow-hidden flex-shrink-0">
                              {barber.profileImageUrl ? (
                                <img src={barber.profileImageUrl} alt="" className="w-full h-full object-cover" />
                              ) : (
                                <span className="text-xs font-bold text-gray-500">
                                  {barber.firstName.charAt(0)}{barber.lastName.charAt(0)}
                                </span>
                              )}
                            </div>
                            <div className="min-w-0">
                              <p className="font-medium text-gray-600 text-sm flex items-center gap-1.5 truncate">
                                {barber.firstName} {barber.lastName}
                              </p>
                              <p className="text-xs text-gray-400 truncate">{barber.email}</p>
                            </div>
                          </div>
                          <ChevronDown className="w-4 h-4 text-gray-400 -rotate-90" />
                        </button>
                      ))}
                    </div>
                  ) : (
                    <div className="flex flex-col items-center justify-center py-8 text-gray-500">
                      <Users className="w-10 h-10 text-gray-300 mb-2" />
                      <p className="text-sm">No hidden barbers</p>
                    </div>
                  );
                })()}
                
                {/* Managers Tab */}
                {barberViewTab === 'managers' && (() => {
                  const managers = filteredBarbers.filter(b => b.isCampusManager);
                  
                  return managers.length > 0 ? (
                    <div className="space-y-2">
                      {managers.map(barber => (
                        <button 
                          key={barber.id}
                          onClick={() => handleBarberClick(barber)}
                          className="w-full flex items-center justify-between p-2.5 rounded-lg border transition-colors text-left border-primary-200 bg-primary-50 hover:bg-primary-100"
                        >
                          <div className="flex items-center gap-2.5">
                            <div className="w-8 h-8 rounded-full bg-gray-200 flex items-center justify-center overflow-hidden flex-shrink-0">
                              {barber.profileImageUrl ? (
                                <img src={barber.profileImageUrl} alt="" className="w-full h-full object-cover" />
                              ) : (
                                <span className="text-xs font-bold text-gray-500">
                                  {barber.firstName.charAt(0)}{barber.lastName.charAt(0)}
                                </span>
                              )}
                            </div>
                            <div className="min-w-0">
                              <p className="font-medium text-gray-900 text-sm flex items-center gap-1.5 truncate">
                                {barber.firstName} {barber.lastName}
                                <span className="text-[10px] text-primary-600 bg-primary-100 px-1.5 py-0.5 rounded">Manager</span>
                              </p>
                              <p className="text-xs text-gray-500 truncate">{barber.email}</p>
                            </div>
                          </div>
                          <ChevronDown className="w-4 h-4 text-gray-400 -rotate-90" />
                        </button>
                      ))}
                    </div>
                  ) : (
                    <div className="flex flex-col items-center justify-center py-8 text-gray-500">
                      <Users className="w-10 h-10 text-gray-300 mb-2" />
                      <p className="text-sm">No campus manager assigned</p>
                    </div>
                  );
                })()}
              </div>
            ) : (
              <div className="flex flex-col items-center justify-center py-8 text-gray-500">
                <Users className="w-10 h-10 text-gray-300 mb-2" />
                <p className="text-sm">No barbers found</p>
              </div>
            )}
              </>
            )}
            
            {/* Applications Tab Content */}
            {barberViewTab === 'applications' && (
              isLoadingApplications ? (
                <div className="flex items-center justify-center py-8">
                  <Loader2 className="w-5 h-5 animate-spin text-primary-500" />
                </div>
              ) : selectedApplication ? (
                // Detailed Application View (Campus-specific)
                <div className="space-y-4">
                  <button
                    onClick={() => setSelectedApplication(null)}
                    className="flex items-center gap-2 text-gray-600 hover:text-gray-900 transition-colors"
                  >
                    <ChevronLeft className="w-5 h-5" />
                    <span className="text-sm font-medium">Back to Applications</span>
                  </button>
                  
                  <div className="bg-white rounded-lg border border-gray-200 p-4 sm:p-6">
                    <div className="flex items-start justify-between gap-4">
                      <div className="flex items-center gap-4">
                        <div className="w-14 h-14 rounded-full bg-primary-100 flex items-center justify-center">
                          <Users className="w-7 h-7 text-primary-600" />
                        </div>
                        <div>
                          <h3 className="text-xl font-bold text-gray-900">
                            {selectedApplication.first_name || selectedApplication.user?.first_name || 'Unknown'} {selectedApplication.last_name || selectedApplication.user?.last_name || 'User'}
                          </h3>
                          <p className="text-gray-600">{selectedApplication.email || selectedApplication.user?.email || 'No email'}</p>
                          <span className={`inline-block mt-2 text-xs font-medium px-2 py-1 rounded-full ${
                            selectedApplication.status === 'pending' 
                              ? 'bg-amber-100 text-amber-700' 
                              : selectedApplication.status === 'approved'
                                ? 'bg-green-100 text-green-700'
                                : 'bg-gray-100 text-gray-700'
                          }`}>
                            {selectedApplication.status === 'pending' ? 'Pending' : selectedApplication.status === 'approved' ? 'Approved' : selectedApplication.status}
                          </span>
                        </div>
                      </div>
                      <button
                        type="button"
                        onClick={(e) => { e.stopPropagation(); setShowContactModal(selectedApplication); }}
                        className="hidden sm:flex items-center px-4 py-2 bg-primary-600 text-white rounded-lg font-medium text-sm hover:bg-primary-700 transition-colors flex-shrink-0"
                      >
                        Schedule Interview
                      </button>
                    </div>
                    <button
                      type="button"
                      onClick={(e) => { e.stopPropagation(); setShowContactModal(selectedApplication); }}
                      className="sm:hidden flex items-center justify-center w-full mt-4 px-4 py-2.5 bg-primary-600 text-white rounded-lg font-medium text-sm hover:bg-primary-700 transition-colors"
                    >
                      Schedule Interview
                    </button>
                  </div>

                  <div className="bg-white rounded-lg border border-gray-200 p-4 sm:p-6">
                    <h4 className="font-semibold text-gray-900 mb-4">Application Details</h4>
                    <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                      <div className="p-3 bg-gray-50 rounded-lg">
                        <p className="text-xs text-gray-500 mb-1">Experience</p>
                        <p className="font-semibold text-gray-900">{selectedApplication.years_experience || 'Not specified'} years</p>
                      </div>
                      <div className="p-3 bg-gray-50 rounded-lg">
                        <p className="text-xs text-gray-500 mb-1">Phone Number</p>
                        <p className="font-semibold text-gray-900">{selectedApplication.phone_number || 'Not provided'}</p>
                        {selectedApplication.phone_number && (
                          <div className="flex gap-2 mt-2">
                            <a href={`tel:${selectedApplication.phone_number}`} className="text-xs text-primary-600 hover:underline">Call</a>
                            <a href={`sms:${selectedApplication.phone_number}`} className="text-xs text-primary-600 hover:underline">Text</a>
                          </div>
                        )}
                      </div>
                      <div className="p-3 bg-gray-50 rounded-lg">
                        <p className="text-xs text-gray-500 mb-1">Available Hours</p>
                        <p className="font-semibold text-gray-900">{selectedApplication.available_hours || 'Not specified'}</p>
                      </div>
                      <div className="p-3 bg-gray-50 rounded-lg">
                        <p className="text-xs text-gray-500 mb-1">Has Own Tools</p>
                        <p className="font-semibold text-gray-900">{selectedApplication.has_own_tools ? 'Yes' : 'No'}</p>
                      </div>
                      <div className="p-3 bg-gray-50 rounded-lg">
                        <p className="text-xs text-gray-500 mb-1">Applied On</p>
                        <p className="font-semibold text-gray-900">
                          {new Date(selectedApplication.created_at).toLocaleDateString('en-US', { year: 'numeric', month: 'long', day: 'numeric' })}
                        </p>
                      </div>
                    </div>

                    {selectedApplication.specialties && selectedApplication.specialties.length > 0 && (
                      <div className="mt-4">
                        <p className="text-xs text-gray-500 mb-2">Specialties</p>
                        <div className="flex flex-wrap gap-2">
                          {selectedApplication.specialties.map((specialty, idx) => (
                            <span key={idx} className="px-3 py-1 bg-primary-100 text-primary-700 rounded-full text-sm font-medium">
                              {specialty}
                            </span>
                          ))}
                        </div>
                      </div>
                    )}

                    {selectedApplication.why_be_barber && (
                      <div className="mt-4 p-4 bg-primary-50 rounded-lg border border-primary-100">
                        <p className="text-xs text-primary-600 font-semibold mb-2 uppercase tracking-wide">Why They Want to Join</p>
                        <p className="text-gray-700 italic">"{selectedApplication.why_be_barber}"</p>
                      </div>
                    )}
                  </div>

                  {selectedApplication.status === 'pending' && (
                    <div className="flex flex-col sm:flex-row gap-3">
                      <Button
                        onClick={() => {
                          requestApplicationAction(selectedApplication, 'approve');
                          setSelectedApplication(null);
                        }}
                        disabled={applicationActionLoading === selectedApplication.id}
                        className="flex-1 py-3 justify-center"
                      >
                        <CheckCircle className="w-5 h-5 mr-2" />
                        Approve Application
                      </Button>
                      <Button
                        variant="outline"
                        onClick={() => {
                          requestApplicationAction(selectedApplication, 'reject');
                          setSelectedApplication(null);
                        }}
                        disabled={applicationActionLoading === selectedApplication.id}
                        className="flex-1 py-3 justify-center text-red-600 border-red-300 hover:bg-red-50"
                      >
                        <XCircle className="w-5 h-5 mr-2" />
                        Reject Application
                      </Button>
                    </div>
                  )}
                </div>
              ) : applications.length > 0 ? (
                <div className="space-y-2 max-h-80 overflow-y-auto">
                  {applications.map(app => (
                    <div
                      key={app.id}
                      onClick={() => setSelectedApplication(app)}
                      className="p-3 rounded-lg border border-gray-200 bg-white hover:bg-gray-50 cursor-pointer transition-colors"
                    >
                      <div className="flex items-start justify-between gap-3">
                        <div className="flex-1 min-w-0">
                          <div className="flex items-center gap-2 mb-1">
                            <p className="font-medium text-gray-900 text-sm truncate">
                              {app.first_name || app.user?.first_name || 'Unknown'} {app.last_name || app.user?.last_name || 'User'}
                            </p>
                            <span className={`text-xs font-medium px-2 py-0.5 rounded-full ${
                              app.status === 'pending' 
                                ? 'bg-amber-100 text-amber-700' 
                                : 'bg-green-100 text-green-700'
                            }`}>
                              {app.status === 'pending' ? 'Pending' : 'Approved (Awaiting Signup)'}
                            </span>
                          </div>
                          <p className="text-xs text-gray-500 truncate">{app.email || app.user?.email || 'No email'}</p>
                          {app.years_experience !== undefined && (
                            <p className="text-xs text-gray-600 mt-1">{app.years_experience} years experience</p>
                          )}
                        </div>
                        <div className="flex items-center gap-2 flex-shrink-0">
                          {app.status === 'pending' && (
                            <div className="flex items-center gap-1">
                              <button
                                onClick={(e) => { e.stopPropagation(); requestApplicationAction(app, 'approve'); }}
                                disabled={applicationActionLoading === app.id}
                                className="p-1.5 rounded-full bg-green-100 text-green-600 hover:bg-green-200 transition-colors disabled:opacity-50"
                                title="Approve"
                              >
                                {applicationActionLoading === app.id ? (
                                  <Loader2 className="w-4 h-4 animate-spin" />
                                ) : (
                                  <CheckCircle className="w-4 h-4" />
                                )}
                              </button>
                              <button
                                onClick={(e) => { e.stopPropagation(); requestApplicationAction(app, 'reject'); }}
                                disabled={applicationActionLoading === app.id}
                                className="p-1.5 rounded-full bg-red-100 text-red-600 hover:bg-red-200 transition-colors disabled:opacity-50"
                                title="Reject"
                              >
                                <XCircle className="w-4 h-4" />
                              </button>
                            </div>
                          )}
                          <ChevronDown className="w-4 h-4 text-gray-400 -rotate-90" />
                        </div>
                      </div>
                    </div>
                  ))}
                </div>
              ) : (
                <div className="flex flex-col items-center justify-center py-8 text-gray-400">
                  <p className="text-sm">No incoming barber applications yet</p>
                </div>
              )
            )}
          </>
        )}
      </div>
      )}
      
      {/* Consumers View */}
      {adminView === 'users' && (
      <div>
        {selectedConsumer ? (
          // Consumer Detail View - show booking history
          <>
            <button
              onClick={handleBackToConsumers}
              className="flex items-center gap-1.5 text-sm text-gray-600 hover:text-gray-900 transition-colors mb-4"
            >
              <ChevronLeft className="w-4 h-4" />
              Back to Consumers
            </button>
            
            {/* Consumer Header */}
            <div className="flex items-center gap-4 mb-6 p-4 bg-gray-50 rounded-xl">
              <div className="w-14 h-14 rounded-full bg-primary-100 flex items-center justify-center overflow-hidden flex-shrink-0">
                {selectedConsumer.avatar_url ? (
                  <img src={selectedConsumer.avatar_url} alt="" className="w-full h-full object-cover" />
                ) : (
                  <span className="text-lg font-bold text-primary-600">
                    #{selectedConsumer.customer_number}
                  </span>
                )}
              </div>
              <div className="flex-1 min-w-0">
                <h3 className="text-lg font-bold text-gray-900">
                  {selectedConsumer.first_name} {selectedConsumer.last_name}
                </h3>
                <p className="text-sm text-gray-500 flex items-center gap-1">
                  <Mail className="w-3.5 h-3.5" />
                  {selectedConsumer.email}
                </p>
                {selectedConsumer.campus_name && (
                  <p className="text-xs text-gray-400 mt-1">
                    {selectedConsumer.campus_name}
                  </p>
                )}
              </div>
            </div>
            
            {/* Booking History */}
            <div className="flex items-center justify-between mb-3">
              <h3 className="text-base font-semibold text-gray-900">Booking History</h3>
              <span className="text-xs text-gray-500">{consumerBookings.length} bookings</span>
            </div>
            
            {isLoadingConsumerBookings ? (
              <div className="flex items-center justify-center py-8">
                <Loader2 className="w-5 h-5 animate-spin text-primary-500" />
              </div>
            ) : consumerBookings.length > 0 ? (
              <div className="space-y-3 max-h-96 overflow-y-auto">
                {consumerBookings.map(booking => (
                  <div 
                    key={booking.id} 
                    className="p-3 rounded-lg border border-gray-200 hover:bg-gray-50 cursor-pointer"
                    onClick={() => handleBookingClick(booking.id)}
                  >
                    <div className="flex items-center justify-between mb-2">
                      <div className="flex items-center gap-2">
                        <span className={`text-xs px-2 py-0.5 rounded-full font-medium ${
                          booking.status === 'COMPLETED' || booking.status === 'PAID' 
                            ? 'bg-green-100 text-green-700' 
                            : booking.status === 'CANCELLED'
                            ? 'bg-red-100 text-red-700'
                            : 'bg-gray-100 text-gray-700'
                        }`}>
                          {booking.status}
                        </span>
                        {(booking.status === 'COMPLETED' || booking.status === 'PAID') && booking.payment_method && (
                          <span className="text-xs px-2 py-0.5 rounded-full font-medium bg-primary-500 text-white">
                            {booking.payment_method === 'card' ? 'Card' : 'Cash'}
                          </span>
                        )}
                      </div>
                      <span className="text-xs text-gray-500">
                        {new Date(booking.scheduled_time).toLocaleDateString('en-US', {
                          month: 'short', day: 'numeric', year: 'numeric'
                        })}
                      </span>
                    </div>
                    
                    <div className="flex items-center gap-3">
                      <div className="w-8 h-8 rounded-full bg-gray-200 flex items-center justify-center overflow-hidden flex-shrink-0">
                        {booking.barber_avatar ? (
                          <img src={booking.barber_avatar} alt="" className="w-full h-full object-cover" />
                        ) : (
                          <span className="text-xs font-bold text-gray-500">
                            {booking.barber_first_name?.charAt(0) || 'B'}
                          </span>
                        )}
                      </div>
                      <div className="flex-1 min-w-0">
                        <p className="text-sm font-medium text-gray-900">
                          {booking.barber_first_name} {booking.barber_last_name}
                        </p>
                        <p className="text-xs text-gray-500">{booking.service_type}</p>
                      </div>
                      <div className="text-right">
                        <p className="text-sm font-semibold text-gray-900">
                          ${((booking.total_paid_cents || booking.price_cents || 0) / 100).toFixed(2)}
                        </p>
                        {booking.tip_cents > 0 && (
                          <p className="text-xs text-green-600">
                            +${(booking.tip_cents / 100).toFixed(2)} tip
                          </p>
                        )}
                      </div>
                    </div>
                    
                    {/* Review if exists */}
                    {booking.review_rating && (
                      <div className="mt-2 pt-2 border-t border-gray-100">
                        <div className="flex items-center gap-1 mb-1">
                          {[...Array(5)].map((_, i) => (
                            <Star 
                              key={i} 
                              className={`w-3 h-3 ${i < booking.review_rating! ? 'fill-amber-400 text-amber-400' : 'text-gray-300'}`} 
                            />
                          ))}
                        </div>
                        {booking.review_text && (
                          <p className="text-xs text-gray-600 italic">"{booking.review_text}"</p>
                        )}
                      </div>
                    )}
                    
                    {/* Expandable messages section */}
                    {selectedBookingId === booking.id && (
                      <div className="mt-3 pt-3 border-t border-gray-200">
                        <p className="text-xs font-semibold text-gray-700 mb-2">Messages</p>
                        {isLoadingMessages ? (
                          <div className="flex items-center justify-center py-2">
                            <Loader2 className="w-4 h-4 animate-spin text-primary-500" />
                          </div>
                        ) : selectedBookingMessages.length > 0 ? (
                          <div className="space-y-2 max-h-40 overflow-y-auto">
                            {selectedBookingMessages.map(msg => (
                              <div key={msg.id} className="text-xs p-2 bg-gray-100 rounded">
                                <div className="flex items-center gap-1 mb-1">
                                  <span className={`text-[10px] px-1 py-0.5 rounded ${
                                    msg.sender_id === booking.barber_user_id
                                      ? 'bg-green-100 text-green-700'
                                      : 'bg-amber-100 text-amber-700'
                                  }`}>
                                    {msg.sender_id === booking.barber_user_id ? 'Barber' : 'Customer'}
                                  </span>
                                  <span className="text-[10px] text-gray-400 ml-auto">
                                    {new Date(msg.created_at).toLocaleTimeString('en-US', {
                                      hour: 'numeric', minute: '2-digit'
                                    })}
                                  </span>
                                </div>
                                <p className="text-gray-700">{msg.content}</p>
                              </div>
                            ))}
                          </div>
                        ) : (
                          <p className="text-xs text-gray-400 italic">No messages in this booking</p>
                        )}
                      </div>
                    )}
                  </div>
                ))}
              </div>
            ) : (
              <div className="flex flex-col items-center justify-center py-8 text-gray-500">
                <Calendar className="w-10 h-10 text-gray-300 mb-2" />
                <p className="text-sm">No bookings yet</p>
              </div>
            )}
          </>
        ) : (
          // Consumer List View
          <>
            <div className="flex items-center justify-between mb-3">
              <h3 className="text-base font-semibold text-gray-900">Consumer Signups</h3>
              <span className="text-xs text-gray-500">
                {totalUsersCount} total consumers
              </span>
            </div>
            
            {/* Search */}
            <div className="relative mb-3">
              <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-gray-400" />
              <input
                type="text"
                value={userSearchQuery}
                onChange={(e) => setUserSearchQuery(e.target.value)}
                placeholder="Search consumers..."
                className="w-full pl-9 pr-4 py-2 border border-gray-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-primary-500"
              />
            </div>
            
            {isLoadingUsers ? (
              <div className="flex items-center justify-center py-8">
                <Loader2 className="w-5 h-5 animate-spin text-purple-500" />
              </div>
            ) : filteredUsers.length > 0 ? (
              <div className="space-y-2 max-h-96 overflow-y-auto overflow-x-hidden">
                {filteredUsers.map(user => (
                  <div 
                    key={user.id}
                    onClick={() => handleConsumerClick(user)}
                    className="flex items-center justify-between p-3 rounded-lg border border-gray-200 hover:bg-gray-50 w-full cursor-pointer transition-colors"
                  >
                    <div className="flex items-center gap-3 min-w-0 flex-1">
                      <div className="w-10 h-10 rounded-full bg-primary-100 flex items-center justify-center overflow-hidden flex-shrink-0">
                        <span className="text-xs font-bold text-primary-600">
                          #{user.customer_number}
                        </span>
                      </div>
                      <div className="min-w-0 flex-1">
                        <p className="font-medium text-gray-900 text-sm truncate">
                          {user.first_name} {user.last_name}
                        </p>
                        <p className="text-xs text-gray-500 flex items-center gap-1 min-w-0">
                          <Mail className="w-3 h-3 flex-shrink-0" />
                          <span className="truncate">{user.email}</span>
                        </p>
                      </div>
                    </div>
                    
                    <div className="flex items-center gap-2">
                      <div className="text-right flex-shrink-0">
                        <p className="text-xs text-gray-500">
                          {new Date(user.created_at).toLocaleDateString('en-US', {
                            month: 'short', day: 'numeric', year: 'numeric'
                          })}
                        </p>
                        <p className="text-[10px] text-gray-400">
                          {new Date(user.created_at).toLocaleTimeString('en-US', {
                            hour: 'numeric', minute: '2-digit'
                          })}
                        </p>
                        {user.campus_name && (
                          <p className="text-[10px] text-gray-400 truncate max-w-28 mt-0.5">
                            {user.campus_name}
                          </p>
                        )}
                      </div>
                      <ChevronRight className="w-4 h-4 text-gray-400 flex-shrink-0" />
                    </div>
                  </div>
                ))}
              </div>
            ) : (
              <div className="flex flex-col items-center justify-center py-8 text-gray-500">
                <UserPlus className="w-10 h-10 text-gray-300 mb-2" />
                <p className="text-sm">No consumers found</p>
              </div>
            )}
          </>
        )}
      </div>
      )}

      {/* Application Action Confirmation Modal */}
      {pendingApplicationAction && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4">
          <div className="bg-white rounded-xl shadow-2xl max-w-md w-full overflow-hidden">
            <div className={`px-6 py-4 ${pendingApplicationAction.action === 'approve' ? 'bg-primary-500' : 'bg-red-500'}`}>
              <h3 className="text-lg font-bold text-white">
                {pendingApplicationAction.action === 'approve' ? 'Approve Application' : 'Reject Application'}
              </h3>
            </div>
            <div className="p-6">
              <p className="text-gray-700 mb-4">
                Are you sure you want to <strong>{pendingApplicationAction.action}</strong> the application from{' '}
                <strong>
                  {pendingApplicationAction.app.first_name || pendingApplicationAction.app.user?.first_name || 'Unknown'}{' '}
                  {pendingApplicationAction.app.last_name || pendingApplicationAction.app.user?.last_name || 'User'}
                </strong>?
              </p>
              {pendingApplicationAction.action === 'approve' && (
                <p className="text-sm text-gray-500 mb-4">
                  This will grant them barber access and they will be able to set up their profile and receive bookings.
                </p>
              )}
              {pendingApplicationAction.action === 'reject' && (
                <p className="text-sm text-gray-500 mb-4">
                  This will reject their application. They will need to submit a new application if they want to apply again.
                </p>
              )}
              <div className="flex gap-3">
                <button
                  onClick={() => setPendingApplicationAction(null)}
                  className="flex-1 px-4 py-2.5 border border-gray-300 text-gray-700 rounded-lg font-medium hover:bg-gray-50 transition-colors"
                >
                  Cancel
                </button>
                <button
                  onClick={confirmApplicationAction}
                  className={`flex-1 px-4 py-2.5 text-white rounded-lg font-medium transition-colors ${
                    pendingApplicationAction.action === 'approve'
                      ? 'bg-primary-600 hover:bg-primary-700'
                      : 'bg-red-600 hover:bg-red-700'
                  }`}
                >
                  {pendingApplicationAction.action === 'approve' ? 'Yes, Approve' : 'Yes, Reject'}
                </button>
              </div>
            </div>
          </div>
        </div>
      )}

      {/* Contact Modal for Scheduling Interview */}
      {showContactModal && (
        <div className="fixed inset-0 min-h-[100dvh] flex items-center justify-center z-50 p-4 bg-black/50" onClick={() => { setShowContactModal(null); setCopiedField(null); }}>
          <div className="bg-white rounded-2xl shadow-2xl max-w-md w-full overflow-hidden" onClick={(e) => e.stopPropagation()}>
            <div className="px-6 py-4 bg-primary-600 flex items-center justify-between">
              <h2 className="text-xl font-bold text-white">Contact Applicant</h2>
              <button onClick={() => { setShowContactModal(null); setCopiedField(null); }} className="text-white/80 hover:text-white">
                <X className="w-6 h-6" />
              </button>
            </div>
            <div className="p-6 space-y-4">
              <p className="text-gray-600 text-sm mb-4">
                Reach out to <span className="font-semibold">{showContactModal.first_name || showContactModal.user?.first_name}</span> to schedule an interview:
              </p>
              
              {/* Email */}
              <div className="p-4 bg-gray-50 rounded-lg border border-gray-200">
                <div className="flex items-center justify-between">
                  <div className="flex-1 min-w-0">
                    <p className="text-xs text-gray-500 mb-1">Email</p>
                    <p className="font-medium text-gray-900 truncate">{showContactModal.email || showContactModal.user?.email || 'No email'}</p>
                  </div>
                  <button
                    onClick={() => {
                      navigator.clipboard.writeText(showContactModal.email || showContactModal.user?.email || '');
                      setCopiedField('email');
                      setTimeout(() => setCopiedField(null), 2000);
                    }}
                    className={`ml-3 p-2 rounded-lg transition-colors ${
                      copiedField === 'email' 
                        ? 'bg-green-100 text-green-700' 
                        : 'bg-primary-100 text-primary-700 hover:bg-primary-200'
                    }`}
                    title={copiedField === 'email' ? 'Copied!' : 'Copy to clipboard'}
                  >
                    {copiedField === 'email' ? <Check className="w-5 h-5" /> : <Copy className="w-5 h-5" />}
                  </button>
                </div>
              </div>

              {/* Phone */}
              <div className="p-4 bg-gray-50 rounded-lg border border-gray-200">
                <div className="flex items-center justify-between">
                  <div className="flex-1 min-w-0">
                    <p className="text-xs text-gray-500 mb-1">Phone</p>
                    <p className="font-medium text-gray-900 truncate">{showContactModal.phone_number || 'Not provided'}</p>
                  </div>
                  {showContactModal.phone_number && (
                    <button
                      onClick={() => {
                        navigator.clipboard.writeText(showContactModal.phone_number || '');
                        setCopiedField('phone');
                        setTimeout(() => setCopiedField(null), 2000);
                      }}
                      className={`ml-3 p-2 rounded-lg transition-colors ${
                        copiedField === 'phone' 
                          ? 'bg-green-100 text-green-700' 
                          : 'bg-primary-100 text-primary-700 hover:bg-primary-200'
                      }`}
                      title={copiedField === 'phone' ? 'Copied!' : 'Copy to clipboard'}
                    >
                      {copiedField === 'phone' ? <Check className="w-5 h-5" /> : <Copy className="w-5 h-5" />}
                    </button>
                  )}
                </div>
              </div>

              <p className="text-xs text-gray-500 mt-4 text-center">
                Use either contact method to reach out and schedule an interview to discuss their application.
              </p>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

