import { useState, useEffect, useRef } from 'react';
import { useNavigate, useLocation } from 'react-router-dom';
import { Settings, Calendar, Shield, LogOut, ChevronDown, Inbox, ArrowLeft, FileText } from 'lucide-react';
import { Link } from 'react-router-dom';
import { CampusCutLogo } from '@assets';
import { useAuthStore } from '../store/useAuthStore';

interface BarberHeaderProps {
  title: string;
  barberId?: string;
  isCampusManager?: boolean;
  campusName?: string;
  showBookingRequests?: boolean;
  bookingRequestsCount?: number;
  onBookingsClick?: () => void;
}

export default function BarberHeader({ 
  title, 
  barberId = 'barber-1',
  isCampusManager = false,
  campusName = '',
  showBookingRequests = false,
  bookingRequestsCount = 0,
  onBookingsClick
}: BarberHeaderProps) {
  const navigate = useNavigate();
  const location = useLocation();
  const { user } = useAuthStore();
  const [showProfileDropdown, setShowProfileDropdown] = useState(false);
  const dropdownRef = useRef<HTMLDivElement>(null);
  
  // Determine platform prefix based on current route
  const platformPrefix = location.pathname.startsWith('/app') ? '/app' : '/web';

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
    <div className="bg-white shadow-sm border-b border-gray-200">
      <div className="max-w-7xl mx-auto px-4 py-4">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-4">
            <img src={CampusCutLogo} alt="CampusCut" className="h-10 w-auto" />
            <div>
              <h1 className="text-2xl font-bold text-gray-900">{title}</h1>
              {isCampusManager && campusName && (
                <div className="flex items-center gap-2 mt-1">
                  <div className="inline-flex items-center gap-1.5 px-3 py-1 bg-primary-50 border border-primary-200 rounded-full">
                    <Shield className="w-3.5 h-3.5 text-primary-600" />
                    <span className="text-sm font-medium text-primary-700">Campus Manager</span>
                    <span className="text-sm text-gray-500">—</span>
                    <span className="text-sm text-gray-700">{campusName}</span>
                  </div>
                </div>
              )}
            </div>
          </div>

          <div className="flex items-center gap-4">
            {/* Switch to Consumer */}
            <button
              onClick={() => navigate(`${platformPrefix}/consumer`)}
              className="px-4 py-2 text-sm font-medium text-gray-700 hover:text-primary-600 hover:bg-gray-50 rounded-lg transition-colors"
            >
              Switch to Consumer
            </button>

            {/* Booking Requests Inbox (optional) */}
            {showBookingRequests && (
              <div className="relative">
                <button 
                  onClick={() => navigate(`${platformPrefix}/barber`)}
                  className="relative p-2 rounded-lg hover:bg-gray-100 transition-colors"
                >
                  <Inbox className="w-6 h-6 text-gray-600" />
                  {bookingRequestsCount > 0 && (
                    <span className="absolute -top-1 -right-1 bg-red-600 text-white text-xs font-bold rounded-full w-5 h-5 flex items-center justify-center">
                      {bookingRequestsCount}
                    </span>
                  )}
                </button>
              </div>
            )}

            {/* Profile Dropdown */}
            <div className="relative" ref={dropdownRef}>
              <button
                onClick={() => setShowProfileDropdown(!showProfileDropdown)}
                className="flex items-center gap-2 px-3 py-2 rounded-lg hover:bg-gray-100 transition-colors"
              >
                <div className="w-8 h-8 bg-primary-400 rounded-full flex items-center justify-center text-white font-semibold">
                  B
                </div>
                <ChevronDown className={`w-4 h-4 text-gray-600 transition-transform ${showProfileDropdown ? 'rotate-180' : ''}`} />
              </button>

              {showProfileDropdown && (
                <div className="absolute right-0 mt-2 w-56 bg-white rounded-lg shadow-lg border border-gray-200 py-1 z-50">
                  <button
                    onClick={() => {
                      navigate(`${platformPrefix}/barber`);
                      setShowProfileDropdown(false);
                    }}
                    className="w-full px-4 py-2 text-left text-sm text-gray-700 hover:bg-gray-100 flex items-center gap-3"
                  >
                    <Settings className="w-4 h-4 text-gray-500" />
                    Dashboard
                  </button>
                  <button
                    onClick={() => {
                      if (onBookingsClick) {
                        onBookingsClick();
                      } else {
                        navigate(`${platformPrefix}/barber/bookings`);
                      }
                      setShowProfileDropdown(false);
                    }}
                    className="w-full px-4 py-2 text-left text-sm text-gray-700 hover:bg-gray-100 flex items-center gap-3"
                  >
                    <Calendar className="w-4 h-4 text-gray-500" />
                    Bookings
                  </button>
                  
                  {isCampusManager && (
                    <>
                      <div className="border-t border-gray-200 my-1"></div>
                      <button
                        onClick={() => {
                          navigate(`${platformPrefix}/barber`);
                          setShowProfileDropdown(false);
                        }}
                        className="w-full px-4 py-2 text-left text-sm text-gray-700 hover:bg-gray-100 flex items-center gap-3"
                      >
                        <Shield className="w-4 h-4 text-primary-600" />
                        Campus Manager
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
  );
}

