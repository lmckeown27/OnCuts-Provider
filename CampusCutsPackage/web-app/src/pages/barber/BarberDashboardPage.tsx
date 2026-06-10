// @ts-nocheck
import { useState, useEffect } from 'react';
import { Calendar, DollarSign, TrendingUp, Users, Award, Clock, CheckCircle, XCircle, MessageCircle, Heart } from 'lucide-react';
import type { Booking, EarningsReport, Review } from '../../types';
import bookingService from '../../services/booking.service';
import paymentService from '../../services/payment.service';
import barberService from '../../services/barber.service';
import { useAuthStore } from '../../store/useAuthStore';
import Loading from '../../components/Loading';
import Card from '../../components/Card';
import Button from '../../components/Button';
import { format, startOfWeek, endOfWeek, startOfMonth, endOfMonth } from 'date-fns';
import toast from 'react-hot-toast';

export default function BarberDashboardPage() {
  const { user } = useAuthStore();
  const [upcomingBookings, setUpcomingBookings] = useState<Booking[]>([]);
  const [pendingBookings, setPendingBookings] = useState<Booking[]>([]);
  const [recentReviews, setRecentReviews] = useState<Review[]>([]);
  const [weeklyEarnings, setWeeklyEarnings] = useState<EarningsReport | null>(null);
  const [monthlyEarnings, setMonthlyEarnings] = useState<EarningsReport | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [timeframe, setTimeframe] = useState<'week' | 'month'>('week');

  useEffect(() => {
    if (user) loadDashboardData();
  }, [user]);

  const loadDashboardData = async () => {
    try {
      // Load bookings
      const bookings = await bookingService.getUpcomingBookings(user!.id, 'barber');
      setUpcomingBookings(bookings.filter(b => b.status === 'confirmed'));
      setPendingBookings(bookings.filter(b => b.status === 'pending'));

      // Load earnings reports
      const weekStart = startOfWeek(new Date()).toISOString();
      const weekEnd = endOfWeek(new Date()).toISOString();
      const monthStart = startOfMonth(new Date()).toISOString();
      const monthEnd = endOfMonth(new Date()).toISOString();

      const weeklyReport = await paymentService.getEarningsReport(weekStart, weekEnd);
      const monthlyReport = await paymentService.getEarningsReport(monthStart, monthEnd);
      setWeeklyEarnings(weeklyReport);
      setMonthlyEarnings(monthlyReport);

      // Load recent reviews (if barber ID is available)
      // For now, we'll skip this since we'd need the barber ID
    } catch (error) {
      console.error('Failed to load dashboard data:', error);
      toast.error('Failed to load dashboard');
    } finally {
      setIsLoading(false);
    }
  };

  const handleAcceptBooking = async (bookingId: string) => {
    try {
      await bookingService.updateBookingStatus(bookingId, 'confirmed');
      toast.success('Booking accepted!');
      loadDashboardData(); // Reload data
    } catch (error) {
      toast.error('Failed to accept booking');
    }
  };

  const handleDeclineBooking = async (bookingId: string) => {
    try {
      await bookingService.updateBookingStatus(bookingId, 'cancelled');
      toast.success('Booking declined');
      loadDashboardData(); // Reload data
    } catch (error) {
      toast.error('Failed to decline booking');
    }
  };

  if (isLoading) return <Loading fullScreen text="Loading dashboard..." />;

  const currentEarnings = timeframe === 'week' ? weeklyEarnings : monthlyEarnings;
  const todayBookings = upcomingBookings.filter(b => 
    format(new Date(b.scheduled_time), 'yyyy-MM-dd') === format(new Date(), 'yyyy-MM-dd')
  );
  const todayEarnings = todayBookings.reduce((sum, b) => sum + b.service_price, 0);

  return (
    <div className="max-w-7xl mx-auto px-4 py-8">
      <div className="flex items-center justify-between mb-8">
        <h1 className="text-3xl font-bold text-gray-900">Dashboard</h1>
        <div className="flex items-center gap-2">
          <button
            onClick={() => setTimeframe('week')}
            className={`px-4 py-2 rounded-lg font-medium transition-colors ${
              timeframe === 'week'
                ? 'bg-primary-600 text-white'
                : 'bg-gray-100 text-gray-700 hover:bg-gray-200'
            }`}
          >
            This Week
          </button>
          <button
            onClick={() => setTimeframe('month')}
            className={`px-4 py-2 rounded-lg font-medium transition-colors ${
              timeframe === 'month'
                ? 'bg-primary-600 text-white'
                : 'bg-gray-100 text-gray-700 hover:bg-gray-200'
            }`}
          >
            This Month
          </button>
        </div>
      </div>

      {/* Stats Grid */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6 mb-8">
        <Card className="bg-gradient-to-br from-blue-50 to-blue-100 border-blue-200">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-blue-700 text-sm font-medium">Today's Bookings</p>
              <p className="text-3xl font-bold text-blue-900">{todayBookings.length}</p>
              <p className="text-xs text-blue-600 mt-1">{pendingBookings.length} pending</p>
            </div>
            <Calendar className="w-12 h-12 text-blue-600" />
          </div>
        </Card>

        <Card className="bg-gradient-to-br from-green-50 to-green-100 border-green-200">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-green-700 text-sm font-medium">Today's Earnings</p>
              <p className="text-3xl font-bold text-green-900">${todayEarnings.toFixed(2)}</p>
              <p className="text-xs text-green-600 mt-1">
                {timeframe === 'week' ? 'Week' : 'Month'}: ${currentEarnings?.total_earnings.toFixed(2) || '0.00'}
              </p>
            </div>
            <DollarSign className="w-12 h-12 text-green-600" />
          </div>
        </Card>

        <Card className="bg-gradient-to-br from-yellow-50 to-yellow-100 border-yellow-200">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-yellow-700 text-sm font-medium">Tips Earned</p>
              <p className="text-3xl font-bold text-yellow-900">
                ${currentEarnings?.total_tips.toFixed(2) || '0.00'}
              </p>
              <p className="text-xs text-yellow-600 mt-1">
                {currentEarnings?.total_bookings || 0} completed bookings
              </p>
            </div>
            <Heart className="w-12 h-12 text-yellow-600" />
          </div>
        </Card>

        <Card className="bg-gradient-to-br from-primary-50 to-primary-100 border-primary-200">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-primary-500 text-sm font-medium">Growth</p>
              <p className="text-3xl font-bold text-primary-700">
                <TrendingUp className="w-6 h-6 inline mr-1" />
                12%
              </p>
              <p className="text-xs text-primary-400 mt-1">vs last {timeframe}</p>
            </div>
            <Award className="w-12 h-12 text-primary-400" />
          </div>
        </Card>
      </div>

      {/* Pending Booking Requests */}
      {pendingBookings.length > 0 && (
        <Card className="mb-8 bg-yellow-50 border-yellow-200">
          <div className="flex items-center justify-between mb-4">
            <h2 className="text-xl font-semibold text-gray-900 flex items-center gap-2">
              <Clock className="w-6 h-6 text-yellow-600" />
              Pending Requests ({pendingBookings.length})
            </h2>
          </div>
          <div className="space-y-3">
            {pendingBookings.map((booking) => (
              <div key={booking.id} className="flex justify-between items-center p-4 bg-white rounded-lg shadow-sm">
                <div className="flex-1">
                  <h3 className="font-semibold text-gray-900">
                    {booking.student?.first_name} {booking.student?.last_name}
                  </h3>
                  <p className="text-sm text-gray-600">{booking.service_name}</p>
                  <p className="text-sm text-gray-600">
                    {format(new Date(booking.scheduled_time), 'MMM d, yyyy h:mm a')}
                  </p>
                  {booking.special_requests && (
                    <p className="text-sm text-gray-500 mt-1 italic">"{booking.special_requests}"</p>
                  )}
                </div>
                <div className="flex flex-col gap-2 ml-4">
                  <Button
                    size="sm"
                    onClick={() => handleAcceptBooking(booking.id)}
                    className="flex items-center gap-1"
                  >
                    <CheckCircle className="w-4 h-4" />
                    Accept
                  </Button>
                  <Button
                    size="sm"
                    variant="secondary"
                    onClick={() => handleDeclineBooking(booking.id)}
                    className="flex items-center gap-1"
                  >
                    <XCircle className="w-4 h-4" />
                    Decline
                  </Button>
                </div>
              </div>
            ))}
          </div>
        </Card>
      )}

      <div className="grid lg:grid-cols-2 gap-8 mb-8">
        {/* Revenue Breakdown */}
        <Card>
          <h2 className="text-xl font-semibold mb-4">Revenue Breakdown</h2>
          {currentEarnings && currentEarnings.daily_breakdown ? (
            <div className="space-y-3">
              {currentEarnings.daily_breakdown.map((day, idx) => (
                <div key={idx} className="flex items-center justify-between p-3 bg-gray-50 rounded-lg">
                  <div>
                    <p className="font-medium text-gray-900">
                      {format(new Date(day.date), 'EEE, MMM d')}
                    </p>
                    <p className="text-sm text-gray-600">{day.bookings} bookings</p>
                  </div>
                  <div className="text-right">
                    <p className="font-semibold text-green-600">${day.earnings.toFixed(2)}</p>
                    {day.tips > 0 && (
                      <p className="text-sm text-gray-600">+${day.tips.toFixed(2)} tips</p>
                    )}
                  </div>
                </div>
              ))}
            </div>
          ) : (
            <p className="text-gray-500 text-center py-8">No earnings data yet</p>
          )}
        </Card>

        {/* Quick Stats */}
        <Card>
          <h2 className="text-xl font-semibold mb-4">Performance Metrics</h2>
          <div className="space-y-4">
            <div className="flex items-center justify-between p-4 bg-blue-50 rounded-lg">
              <div className="flex items-center gap-3">
                <Users className="w-8 h-8 text-blue-600" />
                <div>
                  <p className="font-semibold text-gray-900">Total Clients</p>
                  <p className="text-sm text-gray-600">This {timeframe}</p>
                </div>
              </div>
              <p className="text-2xl font-bold text-blue-600">
                {currentEarnings?.total_bookings || 0}
              </p>
            </div>

            <div className="flex items-center justify-between p-4 bg-green-50 rounded-lg">
              <div className="flex items-center gap-3">
                <DollarSign className="w-8 h-8 text-green-600" />
                <div>
                  <p className="font-semibold text-gray-900">Avg. Booking Value</p>
                  <p className="text-sm text-gray-600">Per appointment</p>
                </div>
              </div>
              <p className="text-2xl font-bold text-green-600">
                ${currentEarnings && currentEarnings.total_bookings > 0
                  ? (currentEarnings.total_earnings / currentEarnings.total_bookings).toFixed(2)
                  : '0.00'}
              </p>
            </div>

            <div className="flex items-center justify-between p-4 bg-yellow-50 rounded-lg">
              <div className="flex items-center gap-3">
                <MessageCircle className="w-8 h-8 text-yellow-600" />
                <div>
                  <p className="font-semibold text-gray-900">Recent Reviews</p>
                  <p className="text-sm text-gray-600">Last 7 days</p>
                </div>
              </div>
              <p className="text-2xl font-bold text-yellow-600">
                {recentReviews.length}
              </p>
            </div>

            <div className="flex items-center justify-between p-4 bg-primary-50 rounded-lg">
              <div className="flex items-center gap-3">
                <TrendingUp className="w-8 h-8 text-primary-400" />
                <div>
                  <p className="font-semibold text-gray-900">Repeat Clients</p>
                  <p className="text-sm text-gray-600">Loyalty rate</p>
                </div>
              </div>
              <p className="text-2xl font-bold text-primary-400">65%</p>
            </div>
          </div>
        </Card>
      </div>

      {/* Upcoming Appointments */}
      <Card>
        <div className="flex items-center justify-between mb-4">
          <h2 className="text-xl font-semibold">Today's Schedule</h2>
          <Button size="sm" variant="secondary" onClick={() => window.location.href = '/barber/calendar'}>
            View Calendar
          </Button>
        </div>
        {todayBookings.length === 0 ? (
          <div className="text-center py-12">
            <Calendar className="w-16 h-16 text-gray-400 mx-auto mb-4" />
            <p className="text-gray-600">No appointments today</p>
            <p className="text-sm text-gray-500 mt-2">Enjoy your day off!</p>
          </div>
        ) : (
          <div className="space-y-3">
            {todayBookings.map((booking) => (
              <div key={booking.id} className="flex justify-between items-center p-4 bg-gradient-to-r from-gray-50 to-white rounded-lg border border-gray-200 hover:shadow-md transition-shadow">
                <div className="flex items-center gap-4">
                  <div className="w-12 h-12 bg-primary-500 rounded-full flex items-center justify-center text-white font-bold text-lg">
                    {booking.student?.first_name?.[0]}{booking.student?.last_name?.[0]}
                  </div>
                  <div>
                    <h3 className="font-semibold text-gray-900">
                      {booking.student?.first_name} {booking.student?.last_name}
                    </h3>
                    <p className="text-sm text-gray-600">{booking.service_name}</p>
                    <p className="text-sm text-gray-500 flex items-center gap-1">
                      <Clock className="w-3 h-3" />
                      {format(new Date(booking.scheduled_time), 'h:mm a')} • {booking.duration_minutes} min
                    </p>
                  </div>
                </div>
                <div className="text-right flex flex-col items-end gap-2">
                  <p className="font-semibold text-primary-600 text-lg">${booking.service_price}</p>
                  <p className="text-sm text-gray-600">{booking.location}</p>
                  <Button size="sm" variant="secondary">
                    <MessageCircle className="w-4 h-4 mr-1" />
                    Message
                  </Button>
                </div>
              </div>
            ))}
          </div>
        )}
      </Card>
    </div>
  );
}

