/**
 * Student Bookings Page (Blockchain-Powered)
 * 
 * Shows bookings from blockchain with optimistic UI.
 * Features:
 * - Instant updates when creating/cancelling
 * - Skeleton loading screens
 * - Auto-refresh every 30 seconds
 * - Offline support (shows cached data)
 */

import { useState } from 'react';
import { useUserBookings, useCancelBooking } from '../../hooks/useBlockchainBookings';
import { OptimisticBookingCard } from '../../components/OptimisticBookingCard';
import { SkeletonGrid } from '../../components/Skeleton';
import { useToast } from '../../components/Toast';

export default function StudentBookingsPageBlockchain() {
  const { data: bookings, isLoading, error, refetch } = useUserBookings();
  const cancelBooking = useCancelBooking();
  const toast = useToast();
  const [filter, setFilter] = useState<'all' | 'upcoming' | 'past'>('all');

  const handleCancelBooking = (bookingId: string) => {
    if (!confirm('Are you sure you want to cancel this booking? You will be refunded automatically.')) {
      return;
    }

    cancelBooking.mutate(
      { bookingId, reason: 'Cancelled by student' },
      {
        onSuccess: () => {
          toast.success('Booking cancelled! Refund processed.');
        },
        onError: () => {
          toast.error('Failed to cancel booking. Please try again.');
        },
      }
    );
  };

  // Filter bookings
  const filteredBookings = bookings?.filter((booking) => {
    if (filter === 'upcoming') {
      return booking.status === 0; // Pending
    } else if (filter === 'past') {
      return booking.status === 1 || booking.status === 2; // Completed or Cancelled
    }
    return true; // All
  }) || [];

  return (
    <div className="min-h-screen bg-gray-50">
      {/* Header */}
      <div className="bg-white shadow-sm border-b">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-6">
          <div className="flex items-center justify-between">
            <div>
              <h1 className="text-3xl font-bold text-gray-900">My Bookings</h1>
              <p className="mt-1 text-sm text-gray-600">
                {bookings?.length || 0} total bookings
              </p>
            </div>

            <button
              onClick={() => refetch()}
              className="flex items-center space-x-2 bg-blue-600 hover:bg-blue-700 text-white px-4 py-2 rounded-lg font-medium transition shadow-md"
            >
              <svg className="h-5 w-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
              </svg>
              <span>Refresh</span>
            </button>
          </div>

          {/* Filter Tabs */}
          <div className="mt-6 flex space-x-4">
            <button
              onClick={() => setFilter('all')}
              className={`px-4 py-2 rounded-lg font-medium transition ${
                filter === 'all'
                  ? 'bg-blue-600 text-white'
                  : 'bg-gray-200 text-gray-700 hover:bg-gray-300'
              }`}
            >
              All
            </button>
            <button
              onClick={() => setFilter('upcoming')}
              className={`px-4 py-2 rounded-lg font-medium transition ${
                filter === 'upcoming'
                  ? 'bg-blue-600 text-white'
                  : 'bg-gray-200 text-gray-700 hover:bg-gray-300'
              }`}
            >
              Upcoming
            </button>
            <button
              onClick={() => setFilter('past')}
              className={`px-4 py-2 rounded-lg font-medium transition ${
                filter === 'past'
                  ? 'bg-blue-600 text-white'
                  : 'bg-gray-200 text-gray-700 hover:bg-gray-300'
              }`}
            >
              Past
            </button>
          </div>
        </div>
      </div>

      {/* Content */}
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        {/* Loading State */}
        {isLoading && (
          <div>
            <p className="text-sm text-gray-600 mb-4">Loading bookings from blockchain...</p>
            <SkeletonGrid count={3} type="booking" />
          </div>
        )}

        {/* Error State */}
        {error && (
          <div className="bg-red-50 border border-red-200 rounded-lg p-6 text-center">
            <svg className="mx-auto h-12 w-12 text-red-500 mb-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
            </svg>
            <h3 className="text-lg font-medium text-red-900 mb-2">
              Failed to load bookings
            </h3>
            <p className="text-sm text-red-700 mb-4">
              {(error as Error).message}
            </p>
            <button
              onClick={() => refetch()}
              className="bg-red-600 hover:bg-red-700 text-white px-6 py-2 rounded-lg font-medium transition"
            >
              Try Again
            </button>
          </div>
        )}

        {/* Empty State */}
        {!isLoading && !error && filteredBookings.length === 0 && (
          <div className="bg-white rounded-lg shadow-md p-12 text-center">
            <svg className="mx-auto h-16 w-16 text-gray-400 mb-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z" />
            </svg>
            <h3 className="text-lg font-medium text-gray-900 mb-2">
              No bookings found
            </h3>
            <p className="text-gray-600 mb-6">
              {filter === 'all' && "You haven't booked any haircuts yet."}
              {filter === 'upcoming' && "You don't have any upcoming bookings."}
              {filter === 'past' && "You don't have any past bookings."}
            </p>
            <a
              href="/student/discovery"
              className="inline-flex items-center bg-blue-600 hover:bg-blue-700 text-white px-6 py-3 rounded-lg font-medium transition shadow-md"
            >
              Find a Barber
            </a>
          </div>
        )}

        {/* Bookings Grid */}
        {!isLoading && !error && filteredBookings.length > 0 && (
          <div>
            {/* Auto-refresh indicator */}
            <div className="mb-4 flex items-center justify-between">
              <p className="text-sm text-gray-600">
                Showing {filteredBookings.length} {filter} booking{filteredBookings.length !== 1 ? 's' : ''}
              </p>
              <p className="text-xs text-gray-500 flex items-center">
                <svg className="animate-spin h-4 w-4 mr-2 text-gray-400" fill="none" viewBox="0 0 24 24">
                  <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4"></circle>
                  <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                </svg>
                Auto-refreshing from blockchain every 30s
              </p>
            </div>

            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
              {filteredBookings.map((booking) => (
                <OptimisticBookingCard
                  key={booking.id}
                  booking={booking}
                  onCancel={handleCancelBooking}
                />
              ))}
            </div>
          </div>
        )}

        {/* Blockchain Info (Dev Mode) */}
        {import.meta.env.DEV && bookings && bookings.length > 0 && (
          <div className="mt-8 p-6 bg-blue-50 border border-blue-200 rounded-lg">
            <p className="text-sm font-medium text-blue-900 mb-2">
              Blockchain Integration Active
            </p>
            <ul className="text-xs text-blue-800 space-y-1">
              <li>Bookings loaded from your account</li>
              <li>Data cached for 30 seconds (React Query)</li>
              <li>Auto-refetches in background</li>
              <li>Optimistic UI on cancel (instant feedback)</li>
              <li>Works offline (shows cached data)</li>
            </ul>
          </div>
        )}
      </div>
    </div>
  );
}

