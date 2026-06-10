import { Link, useNavigate } from 'react-router-dom';
import { User, MessageCircle, Calendar, LogOut, Home } from 'lucide-react';
import { useAuthStore } from '../store/useAuthStore';
import { useMessageStore } from '../store/useMessageStore';
import { ROUTES } from '../config/constants';
import { CampusCutLogo } from '@assets';

export default function Navbar() {
  const { user, logout } = useAuthStore();
  const { unreadCount } = useMessageStore();
  const navigate = useNavigate();

  const handleLogout = async () => {
    await logout();
    navigate(ROUTES.LOGIN);
  };

  if (!user) return null;

  const isBarber = user.user_type === 'barber';

  return (
    <nav className="bg-white shadow-md sticky top-0 z-40">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div className="flex justify-between items-center h-16">
          {/* Logo */}
          <Link to={isBarber ? ROUTES.BARBER_DASHBOARD : ROUTES.STUDENT_DISCOVERY} className="flex items-center gap-3">
            <img src={CampusCutLogo} alt="CampusCut" className="h-10 w-auto" />
          </Link>

          {/* Navigation Links */}
          <div className="flex items-center gap-4">
            {isBarber ? (
              <>
                <Link 
                  to={ROUTES.BARBER_DASHBOARD} 
                  className="flex items-center gap-1 px-3 py-2 rounded-lg hover:bg-gray-100 transition-colors"
                >
                  <Home className="w-5 h-5" />
                  <span className="hidden sm:inline">Dashboard</span>
                </Link>
                <Link 
                  to={ROUTES.BARBER_CALENDAR} 
                  className="flex items-center gap-1 px-3 py-2 rounded-lg hover:bg-gray-100 transition-colors"
                >
                  <Calendar className="w-5 h-5" />
                  <span className="hidden sm:inline">Calendar</span>
                </Link>
              </>
            ) : (
              <>
                <Link 
                  to={ROUTES.STUDENT_DISCOVERY} 
                  className="flex items-center gap-1 px-3 py-2 rounded-lg hover:bg-gray-100 transition-colors"
                >
                  <Home className="w-5 h-5" />
                  <span className="hidden sm:inline">Discover</span>
                </Link>
                <Link 
                  to={ROUTES.STUDENT_BOOKINGS} 
                  className="flex items-center gap-1 px-3 py-2 rounded-lg hover:bg-gray-100 transition-colors"
                >
                  <Calendar className="w-5 h-5" />
                  <span className="hidden sm:inline">Bookings</span>
                </Link>
              </>
            )}

            <Link 
              to={isBarber ? ROUTES.BARBER_MESSAGES : ROUTES.STUDENT_MESSAGES} 
              className="flex items-center gap-1 px-3 py-2 rounded-lg hover:bg-gray-100 transition-colors relative"
            >
              <MessageCircle className="w-5 h-5" />
              {unreadCount > 0 && (
                <span className="absolute -top-1 -right-1 bg-red-600 text-white text-xs rounded-full w-5 h-5 flex items-center justify-center">
                  {unreadCount > 9 ? '9+' : unreadCount}
                </span>
              )}
              <span className="hidden sm:inline">Messages</span>
            </Link>

            <Link 
              to={isBarber ? ROUTES.BARBER_PROFILE : ROUTES.STUDENT_PROFILE} 
              className="flex items-center gap-1 px-3 py-2 rounded-lg hover:bg-gray-100 transition-colors"
            >
              {user.profile_picture_url ? (
                <img src={user.profile_picture_url} alt={user.first_name} className="w-8 h-8 rounded-full" />
              ) : (
                <User className="w-5 h-5" />
              )}
              <span className="hidden sm:inline">{user.first_name}</span>
            </Link>

            <button
              onClick={handleLogout}
              className="flex items-center gap-1 px-3 py-2 rounded-lg hover:bg-red-50 text-red-600 transition-colors"
            >
              <LogOut className="w-5 h-5" />
            </button>
          </div>
        </div>
      </div>
    </nav>
  );
}

