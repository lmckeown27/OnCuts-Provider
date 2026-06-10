/**
 * Mobile Barber Page
 * 
 * Touch-optimized mobile interface for barbers to manage their business.
 * Features:
 * - Swipe to accept/reject bookings
 * - Bottom navigation
 * - Mobile-optimized calendar
 * - Quick actions with bottom sheets
 * - Pull-to-refresh
 */

import { useState, useEffect } from 'react';
import { useNavigate, useLocation } from 'react-router-dom';
import { useAuthStore } from '../../store/useAuthStore';
import toast from 'react-hot-toast';
import MobilePhotoUpload from '../../components/MobilePhotoUpload';
import BarberProfileEditor from '../../components/BarberProfileEditor';
import BlockTimeModal from '../../components/BlockTimeModal';
import userService from '../../services/user.service';
import api from '../../services/api.service';
import {
  Calendar,
  Clock,
  DollarSign,
  TrendingUp,
  MessageCircle,
  User as UserIcon,
  Home,
  Check,
  X,
  ChevronRight,
  MapPin,
  MoreVertical,
  ArrowLeft,
  AlertTriangle
} from 'lucide-react';

interface BookingRequest {
  id: string;
  customerName: string;
  customerImage: string;
  service: string;
  date: string;
  time: string;
  location: string;
  price: number;
  customerRating: number;
}

interface Appointment {
  id: string;
  customerName: string;
  service: string;
  time: string;
  price: number;
  status: 'upcoming' | 'completed';
}


export default function MobileBarberPage() {
  const navigate = useNavigate();
  const location = useLocation();
  const platformPrefix = location.pathname.startsWith('/app') ? '/app' : '/web';
  const { user, setUser, isLoading: isAuthLoading } = useAuthStore();
  
  const [activeTab, setActiveTab] = useState<'schedule' | 'requests' | 'earnings' | 'profile'>('schedule');
  const [requests, setRequests] = useState<BookingRequest[]>([]);
  const [appointments, setAppointments] = useState<Appointment[]>([]);
  const [showRequestDetail, setShowRequestDetail] = useState<BookingRequest | null>(null);
  const [swipingRequest, setSwipingRequest] = useState<string | null>(null);
  const [swipeDirection, setSwipeDirection] = useState<'left' | 'right' | null>(null);
  const [showFullEditor, setShowFullEditor] = useState(false);
  const [isUploadingPhoto, setIsUploadingPhoto] = useState(false);
  const [showBlockTimeModal, setShowBlockTimeModal] = useState(false);
  const [barberProfileId, setBarberProfileId] = useState<string>('');

  const todayEarnings = 0;
  const weekEarnings = 0;
  const todayAppointments = appointments.length;
  
  // Role-based access control: Only barbers, campus managers, and admins can access this page
  const isAuthorizedForBarberPage = 
    user?.user_type === 'barber' || 
    user?.user_type === 'campus_manager' || 
    user?.user_type === 'admin' ||
    user?.has_barber_profile;
  
  useEffect(() => {
    // Don't redirect while auth is still loading - wait for fresh user data
    if (isAuthLoading) return;
    
    if (user && !isAuthorizedForBarberPage) {
      console.warn('Unauthorized access to MobileBarberPage. Redirecting to consumer page.', {
        userId: user.id,
        userType: user.user_type,
        hasBarberProfile: user.has_barber_profile
      });
      toast.error('You need a barber profile to access this page');
      navigate(`${platformPrefix}/consumer`);
    }
  }, [user, isAuthorizedForBarberPage, isAuthLoading, navigate, platformPrefix]);

  // Fetch barber profile ID for time blocking
  useEffect(() => {
    const fetchBarberProfileId = async () => {
      if (!user?.id) return;
      try {
        const response = await api.get<{ id: string }>(`/barbers/user/${user.id}`);
        if (response?.id) {
          setBarberProfileId(response.id);
        }
      } catch (error) {
        console.error('Failed to fetch barber profile:', error);
      }
    };
    fetchBarberProfileId();
  }, [user?.id]);

  const handleAcceptRequest = (requestId: string) => {
    setRequests(requests.filter(r => r.id !== requestId));
    setShowRequestDetail(null);
    // Show success toast
  };

  const handleRejectRequest = (requestId: string) => {
    setRequests(requests.filter(r => r.id !== requestId));
    setShowRequestDetail(null);
    // Show toast
  };

  const handleSwipeRequest = (requestId: string, direction: 'accept' | 'reject') => {
    setSwipingRequest(requestId);
    setSwipeDirection(direction === 'accept' ? 'right' : 'left');
    
    setTimeout(() => {
      if (direction === 'accept') {
        handleAcceptRequest(requestId);
      } else {
        handleRejectRequest(requestId);
      }
      setSwipingRequest(null);
      setSwipeDirection(null);
    }, 300);
  };

  // Handle profile photo upload
  const handlePhotoUpload = async (file: File) => {
    console.log('[MobileBarberPage] handlePhotoUpload called with file:', { name: file.name, size: file.size, type: file.type });
    
    if (!user?.id) {
      console.error('[MobileBarberPage] User not found');
      toast.error('User not found');
      return;
    }

    try {
      setIsUploadingPhoto(true);
      console.log('[MobileBarberPage] Calling userService.uploadProfilePhoto');
      const result = await userService.uploadProfilePhoto(user.id, file);
      console.log('[MobileBarberPage] Upload result:', result);
      
      // Update user profile with new photo URL
      console.log('[MobileBarberPage] Updating user profile with new URL');
      await userService.updateUserProfile(user.id, { profile_picture_url: result.url });
      
      // Update auth store
      setUser({
        ...user,
        profile_picture_url: result.url,
      });
      
      toast.success('Profile photo updated!');
    } catch (error: any) {
      console.error('[MobileBarberPage] Failed to upload photo:', error);
      console.error('[MobileBarberPage] Error details:', error.response?.data || error.message);
      toast.error('Failed to upload photo');
    } finally {
      setIsUploadingPhoto(false);
    }
  };

  return (
    <div className="fixed inset-0 bg-gray-50 flex flex-col">
      {/* Header */}
      <header className="bg-white border-b border-gray-200 px-4 py-3 safe-area-inset-top">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-3">
            <img src="/src/assets/logos/Logo1.png" alt="CampusCut" className="h-8" />
            <div>
              <p className="text-xs text-gray-500">California Polytechnic State University</p>
            </div>
          </div>
          <button className="p-2 hover:bg-gray-100 rounded-full transition-colors">
            <MoreVertical className="w-5 h-5 text-gray-600" />
          </button>
        </div>

        {/* Quick Stats */}
        <div className="grid grid-cols-3 gap-2 mt-3">
          <div className="bg-primary-50 rounded-lg p-3">
            <div className="text-2xl font-bold text-primary-700">${todayEarnings}</div>
            <div className="text-xs text-gray-600">Today</div>
          </div>
          <div className="bg-green-50 rounded-lg p-3">
            <div className="text-2xl font-bold text-green-700">${weekEarnings}</div>
            <div className="text-xs text-gray-600">This Week</div>
          </div>
          <div className="bg-blue-50 rounded-lg p-3">
            <div className="text-2xl font-bold text-blue-700">{todayAppointments}</div>
            <div className="text-xs text-gray-600">Appointments</div>
          </div>
        </div>
      </header>

      {/* Content Area */}
      <div className="flex-1 overflow-y-auto">
        {activeTab === 'schedule' && (
          <div className="p-4 space-y-4">
            <div className="flex items-center justify-between">
              <h2 className="text-xl font-bold text-gray-900">Today's Schedule</h2>
              <button className="text-primary-600 text-sm font-medium">View Calendar</button>
            </div>

            {appointments.map((appointment) => (
              <div
                key={appointment.id}
                className="bg-white rounded-xl p-4 shadow-sm border border-gray-200 active:scale-98 transition-transform"
                onClick={() => {/* Navigate to appointment details */}}
              >
                <div className="flex items-start justify-between mb-3">
                  <div className="flex items-center gap-3">
                    <div className="w-12 h-12 bg-primary-100 rounded-full flex items-center justify-center">
                      <UserIcon className="w-6 h-6 text-primary-600" />
                    </div>
                    <div>
                      <h3 className="font-semibold text-gray-900">{appointment.customerName}</h3>
                      <p className="text-sm text-gray-600">{appointment.service}</p>
                    </div>
                  </div>
                  <ChevronRight className="w-5 h-5 text-gray-400" />
                </div>

                <div className="flex items-center justify-between text-sm">
                  <div className="flex items-center gap-1 text-gray-600">
                    <Clock className="w-4 h-4" />
                    <span>{appointment.time}</span>
                  </div>
                  <div className="flex items-center gap-1 text-primary-600 font-semibold">
                    <DollarSign className="w-4 h-4" />
                    <span>${appointment.price}</span>
                  </div>
                </div>
              </div>
            ))}
          </div>
        )}

        {activeTab === 'requests' && (
          <div className="p-4">
            <div className="flex items-center justify-between mb-4">
              <h2 className="text-xl font-bold text-gray-900">Booking Requests</h2>
              <span className="text-sm text-gray-500">{requests.length} pending</span>
            </div>

            {requests.length === 0 ? (
              <div className="text-center py-12">
                <Calendar className="w-16 h-16 text-gray-300 mx-auto mb-3" />
                <p className="text-gray-500">No pending requests</p>
              </div>
            ) : (
              <div className="space-y-3">
                {requests.map((request) => (
                  <div
                    key={request.id}
                    className={`bg-white rounded-xl shadow-sm border border-gray-200 overflow-hidden transition-transform duration-300 ${
                      swipingRequest === request.id ? (
                        swipeDirection === 'left' ? '-translate-x-full opacity-0' :
                        swipeDirection === 'right' ? 'translate-x-full opacity-0' : ''
                      ) : ''
                    }`}
                    onClick={() => setShowRequestDetail(request)}
                  >
                    <div className="p-4">
                      <div className="flex items-center gap-3 mb-3">
                        <img
                          src={request.customerImage}
                          alt={request.customerName}
                          className="w-14 h-14 rounded-full"
                        />
                        <div className="flex-1">
                          <h3 className="font-semibold text-gray-900">{request.customerName}</h3>
                        </div>
                        <div className="text-right">
                          <div className="text-lg font-bold text-primary-600">${request.price}</div>
                          <div className="text-xs text-gray-500">{request.date}</div>
                        </div>
                      </div>

                      <div className="space-y-2 text-sm text-gray-600 mb-4">
                        <div className="flex items-center gap-2">
                          <Clock className="w-4 h-4" />
                          <span>{request.time}</span>
                        </div>
                        <div className="flex items-center gap-2">
                          <MapPin className="w-4 h-4" />
                          <span>{request.location}</span>
                        </div>
                      </div>

                      <div className="flex gap-2">
                        <button
                          onClick={(e) => {
                            e.stopPropagation();
                            handleSwipeRequest(request.id, 'reject');
                          }}
                          className="flex-1 py-3 bg-red-50 text-red-600 font-semibold rounded-lg hover:bg-red-100 active:scale-95 transition-all"
                        >
                          Decline
                        </button>
                        <button
                          onClick={(e) => {
                            e.stopPropagation();
                            handleSwipeRequest(request.id, 'accept');
                          }}
                          className="flex-1 py-3 bg-primary-400 text-white font-semibold rounded-lg hover:bg-primary-500 active:scale-95 transition-all"
                        >
                          Accept
                        </button>
                      </div>
                    </div>
                  </div>
                ))}
              </div>
            )}
          </div>
        )}

        {activeTab === 'earnings' && (
          <div className="p-4 space-y-4">
            <h2 className="text-xl font-bold text-gray-900">Earnings</h2>
            
            <div className="bg-gradient-to-br from-primary-400 to-primary-600 rounded-2xl p-6 text-white">
              <div className="text-sm opacity-90 mb-1">Total Earnings</div>
              <div className="text-4xl font-bold mb-4">${weekEarnings}</div>
              <div className="flex items-center gap-2 text-sm">
                <TrendingUp className="w-4 h-4" />
                <span>+23% from last week</span>
              </div>
            </div>

            <div className="bg-white rounded-xl p-4 border border-gray-200">
              <h3 className="font-semibold text-gray-900 mb-3">Recent Payments</h3>
              <div className="space-y-3">
                {[1, 2, 3].map((i) => (
                  <div key={i} className="flex items-center justify-between py-2 border-b border-gray-100 last:border-0">
                    <div>
                      <div className="font-medium text-gray-900">Haircut Service</div>
                      <div className="text-xs text-gray-500">Dec 17, 2025</div>
                    </div>
                    <div className="text-primary-600 font-semibold">+$22</div>
                  </div>
                ))}
              </div>
            </div>
          </div>
        )}

        {activeTab === 'profile' && !showFullEditor && (
          <div className="p-4 space-y-4">
            {/* Profile Photo with Camera/Gallery Upload */}
            <div className="bg-white rounded-xl p-6 border border-gray-200">
              <MobilePhotoUpload
                currentPhotoUrl={user?.profile_picture_url}
                onPhotoSelected={handlePhotoUpload}
                isUploading={isUploadingPhoto}
                shape="square"
              />
              <h2 className="text-xl font-bold text-gray-900 text-center mt-4">
                {user?.first_name} {user?.last_name}
              </h2>
              <p className="text-gray-500 text-sm text-center mt-1">{user?.email}</p>
            </div>

            <div className="space-y-2">
              <button 
                onClick={() => setShowFullEditor(true)}
                className="w-full bg-white p-4 rounded-xl border border-gray-200 text-left flex items-center justify-between active:scale-98 transition-transform"
              >
                <span className="font-medium text-gray-900">Edit Full Profile</span>
                <ChevronRight className="w-5 h-5 text-gray-400" />
              </button>
              
              <button 
                onClick={() => navigate(`${platformPrefix}/barber/services`)}
                className="w-full bg-white p-4 rounded-xl border border-gray-200 text-left flex items-center justify-between active:scale-98 transition-transform"
              >
                <span className="font-medium text-gray-900">Services</span>
                <ChevronRight className="w-5 h-5 text-gray-400" />
              </button>
              
              <button 
                onClick={() => navigate(`${platformPrefix}/barber/availability`)}
                className="w-full bg-white p-4 rounded-xl border border-gray-200 text-left flex items-center justify-between active:scale-98 transition-transform"
              >
                <span className="font-medium text-gray-900">Availability</span>
                <ChevronRight className="w-5 h-5 text-gray-400" />
              </button>
              
              <button 
                onClick={() => setShowBlockTimeModal(true)}
                className="w-full bg-white p-4 rounded-xl border border-gray-200 text-left flex items-center justify-between active:scale-98 transition-transform"
              >
                <div className="flex items-center gap-2">
                  <AlertTriangle className="w-4 h-4 text-amber-500" />
                  <span className="font-medium text-gray-900">Block Time</span>
                </div>
                <ChevronRight className="w-5 h-5 text-gray-400" />
              </button>
            </div>

            <button
              onClick={() => navigate(`${platformPrefix}/consumer`)}
              className="w-full py-3 text-primary-600 font-medium"
            >
              Switch to Student
            </button>
          </div>
        )}

        {/* Full Profile Editor */}
        {activeTab === 'profile' && showFullEditor && (
          <div className="p-4">
            <div className="flex items-center gap-3 mb-4">
              <button 
                onClick={() => setShowFullEditor(false)}
                className="p-2 hover:bg-gray-100 rounded-full transition-colors"
              >
                <ArrowLeft className="w-5 h-5 text-gray-600" />
              </button>
              <h2 className="text-xl font-bold text-gray-900">Edit Profile</h2>
            </div>
            <BarberProfileEditor 
              userId={user?.id}
              onClose={() => setShowFullEditor(false)}
            />
          </div>
        )}
      </div>

      {/* Bottom Navigation */}
      <nav className="bg-white border-t border-gray-200 px-2 py-2 safe-area-inset-bottom">
        <div className="flex items-center justify-around">
          <button
            onClick={() => setActiveTab('schedule')}
            className={`flex flex-col items-center gap-1 px-4 py-2 rounded-lg transition-colors ${
              activeTab === 'schedule' ? 'text-primary-600 bg-primary-50' : 'text-gray-600'
            }`}
          >
            <Calendar className="w-6 h-6" />
            <span className="text-xs font-medium">Schedule</span>
          </button>
          
          <button
            onClick={() => setActiveTab('requests')}
            className={`relative flex flex-col items-center gap-1 px-4 py-2 rounded-lg transition-colors ${
              activeTab === 'requests' ? 'text-primary-600 bg-primary-50' : 'text-gray-600'
            }`}
          >
            {requests.length > 0 && (
              <span className="absolute -top-1 -right-1 w-5 h-5 bg-red-500 text-white text-xs font-bold rounded-full flex items-center justify-center">
                {requests.length}
              </span>
            )}
            <MessageCircle className="w-6 h-6" />
            <span className="text-xs font-medium">Requests</span>
          </button>
          
          <button
            onClick={() => setActiveTab('earnings')}
            className={`flex flex-col items-center gap-1 px-4 py-2 rounded-lg transition-colors ${
              activeTab === 'earnings' ? 'text-primary-600 bg-primary-50' : 'text-gray-600'
            }`}
          >
            <DollarSign className="w-6 h-6" />
            <span className="text-xs font-medium">Earnings</span>
          </button>
          
          <button
            onClick={() => setActiveTab('profile')}
            className={`flex flex-col items-center gap-1 px-4 py-2 rounded-lg transition-colors ${
              activeTab === 'profile' ? 'text-primary-600 bg-primary-50' : 'text-gray-600'
            }`}
          >
            <UserIcon className="w-6 h-6" />
            <span className="text-xs font-medium">Profile</span>
          </button>
        </div>
      </nav>

      {/* Request Detail Bottom Sheet */}
      {showRequestDetail && (
        <div
          className="fixed inset-0 min-h-[100dvh] bg-black/50 z-50 animate-fade-in"
          onClick={() => setShowRequestDetail(null)}
        >
          <div
            className="absolute bottom-0 left-0 right-0 bg-white rounded-t-3xl p-6 max-h-[85dvh] overflow-y-auto safe-area-bottom"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="w-12 h-1 bg-gray-300 rounded-full mx-auto mb-6" />
            
            <div className="flex items-center gap-4 mb-6">
              <img
                src={showRequestDetail.customerImage}
                alt={showRequestDetail.customerName}
                className="w-20 h-20 rounded-full"
              />
              <div className="flex-1">
                <h3 className="text-2xl font-bold text-gray-900">{showRequestDetail.customerName}</h3>
              </div>
            </div>

            <div className="space-y-4 mb-6">
              <div className="flex items-start gap-3">
                <Clock className="w-5 h-5 text-gray-400 mt-0.5" />
                <div>
                  <div className="text-sm text-gray-500">When</div>
                  <div className="font-semibold text-gray-900">{showRequestDetail.date} at {showRequestDetail.time}</div>
                </div>
              </div>

              <div className="flex items-start gap-3">
                <MapPin className="w-5 h-5 text-gray-400 mt-0.5" />
                <div>
                  <div className="text-sm text-gray-500">Where</div>
                  <div className="font-semibold text-gray-900">{showRequestDetail.location}</div>
                </div>
              </div>

              <div className="flex items-start gap-3">
                <DollarSign className="w-5 h-5 text-gray-400 mt-0.5" />
                <div>
                  <div className="text-sm text-gray-500">Service & Price</div>
                  <div className="font-semibold text-gray-900">{showRequestDetail.service} - ${showRequestDetail.price}</div>
                </div>
              </div>
            </div>

            <div className="flex gap-3">
              <button
                onClick={() => handleRejectRequest(showRequestDetail.id)}
                className="flex-1 py-4 bg-red-50 text-red-600 font-semibold rounded-xl hover:bg-red-100 active:scale-98 transition-all"
              >
                Decline
              </button>
              <button
                onClick={() => handleAcceptRequest(showRequestDetail.id)}
                className="flex-1 py-4 bg-primary-400 text-white font-semibold rounded-xl hover:bg-primary-500 active:scale-98 transition-all shadow-lg"
              >
                Accept Booking
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Block Time Modal */}
      {barberProfileId && (
        <BlockTimeModal
          isVisible={showBlockTimeModal}
          onClose={() => setShowBlockTimeModal(false)}
          barberId={barberProfileId}
        />
      )}
    </div>
  );
}

