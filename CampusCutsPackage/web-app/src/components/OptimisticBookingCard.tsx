/**
 * Optimistic Booking Card Component
 * 
 * Example of optimistic UI in action.
 * Shows instant feedback while blockchain confirms transaction.
 * 
 * User Experience:
 * 1. User clicks "Book" → Card appears instantly
 * 2. Shows "Confirming..." badge for 2-5 seconds
 * 3. Updates to "Confirmed" when blockchain confirms
 * 4. If error, shows error and removes card
 */

import { useState } from 'react';
import { useCreateBooking, useIsBookingOptimistic } from '../hooks/useBlockchainBookings';
import { Skeleton } from './Skeleton';

interface BookingCardProps {
  booking: {
    id: string;
    barber: string;
    serviceName: string;
    amount: string;
    status: number;
    scheduledTime: string;
  };
  onCancel?: (id: string) => void;
}

export function OptimisticBookingCard({ booking, onCancel }: BookingCardProps) {
  const isOptimistic = useIsBookingOptimistic(booking.id);
  const [showCancelModal, setShowCancelModal] = useState(false);

  // Get status display
  const getStatusBadge = () => {
    if (isOptimistic) {
      return (
        <span className="inline-flex items-center px-3 py-1 rounded-full text-sm font-medium bg-yellow-100 text-yellow-800 animate-pulse">
          <svg className="animate-spin -ml-1 mr-2 h-4 w-4 text-yellow-600" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
            <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4"></circle>
            <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
          </svg>
          Confirming...
        </span>
      );
    }

    const statusMap: Record<number, { text: string; color: string }> = {
      0: { text: 'Pending', color: 'bg-yellow-100 text-yellow-800' },
      1: { text: 'Completed', color: 'bg-green-100 text-green-800' },
      2: { text: 'Cancelled', color: 'bg-gray-100 text-gray-800' },
      3: { text: 'No Show (Student)', color: 'bg-red-100 text-red-800' },
      4: { text: 'No Show (Barber)', color: 'bg-red-100 text-red-800' },
    };

    const status = statusMap[booking.status] || statusMap[0];

    return (
      <span className={`inline-flex items-center px-3 py-1 rounded-full text-sm font-medium ${status.color}`}>
        {isOptimistic === false && (
          <svg className="mr-2 h-4 w-4 text-green-600" fill="currentColor" viewBox="0 0 20 20">
            <path fillRule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clipRule="evenodd" />
          </svg>
        )}
        {status.text}
      </span>
    );
  };

  const formattedDate = new Date(parseInt(booking.scheduledTime) * 1000).toLocaleString();
  const amountUsd = (parseInt(booking.amount) / 100_000_000).toFixed(2);

  return (
    <div className={`bg-white rounded-lg shadow-md p-6 transition-all duration-300 ${
      isOptimistic ? 'opacity-90 border-2 border-yellow-400' : 'opacity-100'
    }`}>
      <div className="flex items-start justify-between mb-4">
        <div>
          <h3 className="text-lg font-semibold text-gray-900">{booking.serviceName}</h3>
          <p className="text-sm text-gray-600">Barber: {booking.barber.substring(0, 10)}...</p>
        </div>
        {getStatusBadge()}
      </div>

      <div className="space-y-2 text-sm text-gray-600 mb-4">
        <div className="flex items-center">
          <svg className="h-4 w-4 mr-2 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z" />
          </svg>
          {formattedDate}
        </div>
        
        <div className="flex items-center">
          <svg className="h-4 w-4 mr-2 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 8c-1.657 0-3 .895-3 2s1.343 2 3 2 3 .895 3 2-1.343 2-3 2m0-8c1.11 0 2.08.402 2.599 1M12 8V7m0 1v8m0 0v1m0-1c-1.11 0-2.08-.402-2.599-1M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
          </svg>
          ${amountUsd}
        </div>
      </div>

      {isOptimistic && (
        <div className="bg-yellow-50 border border-yellow-200 rounded-md p-3 mb-4">
          <p className="text-xs text-yellow-800 flex items-center">
            <svg className="animate-spin h-4 w-4 mr-2 text-yellow-600" fill="none" viewBox="0 0 24 24">
              <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4"></circle>
              <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
            </svg>
            Transaction being confirmed on blockchain... Your funds are securely escrowed.
          </p>
        </div>
      )}

      <div className="flex space-x-2">
        <button
          className="flex-1 bg-blue-600 hover:bg-blue-700 text-white px-4 py-2 rounded-md text-sm font-medium transition disabled:opacity-50 disabled:cursor-not-allowed"
          disabled={isOptimistic}
        >
          View Details
        </button>
        
        {booking.status === 0 && (
          <button
            onClick={() => onCancel?.(booking.id)}
            className="flex-1 bg-gray-200 hover:bg-gray-300 text-gray-700 px-4 py-2 rounded-md text-sm font-medium transition disabled:opacity-50 disabled:cursor-not-allowed"
            disabled={isOptimistic}
          >
            {isOptimistic ? 'Confirming...' : 'Cancel'}
          </button>
        )}
      </div>

      {/* Optimistic loading indicator at bottom */}
      {isOptimistic && (
        <div className="mt-4 h-1 w-full bg-gray-200 rounded-full overflow-hidden">
          <div className="h-full bg-blue-600 animate-pulse" style={{ width: '60%', animation: 'slide 2s ease-in-out infinite' }}></div>
        </div>
      )}
    </div>
  );
}

/**
 * Example: Booking Form with Optimistic UI
 */
export function BookingFormWithOptimisticUI() {
  const createBooking = useCreateBooking();
  const [formData, setFormData] = useState({
    barberAddress: '',
    serviceName: 'Classic Haircut',
    amount: 30,
    scheduledTime: Date.now() + 3600, // 1 hour from now
  });

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();

    // Submit - this will show optimistic booking immediately!
    createBooking.mutate(formData, {
      onSuccess: (response) => {
        if (response.success) {
          console.log('Booking created!', response);
          // Form is automatically updated with optimistic booking
          // User sees instant feedback!
        }
      },
      onError: (error) => {
        console.error('Booking failed:', error);
        alert('Booking failed. Please try again.');
      },
    });
  };

  return (
    <form onSubmit={handleSubmit} className="space-y-4 bg-white p-6 rounded-lg shadow-md">
      <h2 className="text-xl font-bold">Book a Haircut</h2>
      
      <div>
        <label className="block text-sm font-medium text-gray-700 mb-1">
          Barber Address
        </label>
        <input
          type="text"
          value={formData.barberAddress}
          onChange={(e) => setFormData({ ...formData, barberAddress: e.target.value })}
          className="w-full px-3 py-2 border border-gray-300 rounded-md"
          placeholder="0x..."
          required
        />
      </div>

      <div>
        <label className="block text-sm font-medium text-gray-700 mb-1">
          Service
        </label>
        <select
          value={formData.serviceName}
          onChange={(e) => setFormData({ ...formData, serviceName: e.target.value })}
          className="w-full px-3 py-2 border border-gray-300 rounded-md"
        >
          <option>Classic Haircut</option>
          <option>Fade</option>
          <option>Buzz Cut</option>
          <option>Trim</option>
        </select>
      </div>

      <button
        type="submit"
        disabled={createBooking.isPending}
        className="w-full bg-blue-600 hover:bg-blue-700 text-white px-4 py-3 rounded-md font-medium transition disabled:opacity-50 disabled:cursor-not-allowed"
      >
        {createBooking.isPending ? (
          <span className="flex items-center justify-center">
            <svg className="animate-spin -ml-1 mr-3 h-5 w-5 text-white" fill="none" viewBox="0 0 24 24">
              <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4"></circle>
              <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
            </svg>
            Creating booking...
          </span>
        ) : (
          'Book Now ($' + formData.amount + ')'
        )}
      </button>

      {createBooking.isSuccess && (
        <div className="bg-green-50 border border-green-200 rounded-md p-4">
          <p className="text-sm text-green-800 flex items-center">
            <svg className="h-5 w-5 mr-2 text-green-600" fill="currentColor" viewBox="0 0 20 20">
              <path fillRule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clipRule="evenodd" />
            </svg>
            Booking confirmed! Funds securely escrowed on blockchain.
          </p>
        </div>
      )}
    </form>
  );
}

export default OptimisticBookingCard;

