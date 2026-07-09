/**
 * Customer Booking Tracker Component
 * 
 * Shows customer's booking requests and their status
 */

import React, { useState, useEffect } from 'react';
import { Clock, CheckCircle, XCircle, Calendar, MessageSquare } from 'lucide-react';
import Card from '../Card';
import axios from 'axios';
import BookingMessaging from './BookingMessaging';

interface Booking {
  bookingId: string;
  status: string;
  serviceType: string;
  bookingDate: string;
  bookingTime: string;
  price: number;
  requestedAt: string;
  respondedAt?: string;
  barber: {
    id: string;
    name: string;
  };
  unreadMessages: number;
}

interface Props {
  customerId: string;
}

export default function CustomerBookingTracker({ customerId }: Props) {
  const [bookings, setBookings] = useState<Booking[]>([]);
  const [loading, setLoading] = useState(true);
  const [selectedBooking, setSelectedBooking] = useState<Booking | null>(null);
  const [showMessaging, setShowMessaging] = useState(false);

  useEffect(() => {
    fetchBookings();
    const interval = setInterval(fetchBookings, 10000); // Poll every 10 seconds
    return () => clearInterval(interval);
  }, [customerId]);

  const fetchBookings = async () => {
    try {
      const response = await axios.get(
        `http://localhost:3001/api/booking-requests/customer/${customerId}/status`
      );
      setBookings(response.data.bookings || []);
      setLoading(false);
    } catch (error) {
      console.error('Failed to fetch bookings:', error);
      setLoading(false);
    }
  };

  const getStatusBadge = (status: string) => {
    switch (status) {
      case 'pending':
        return (
          <span className="flex items-center gap-1 px-3 py-1 bg-yellow-100 text-yellow-800 text-sm font-semibold rounded-full">
            <Clock className="w-3 h-3" />
            Pending
          </span>
        );
      case 'accepted':
        return (
          <span className="flex items-center gap-1 px-3 py-1 bg-green-100 text-green-800 text-sm font-semibold rounded-full">
            <CheckCircle className="w-3 h-3" />
            Accepted
          </span>
        );
      case 'rejected':
        return (
          <span className="flex items-center gap-1 px-3 py-1 bg-red-100 text-red-800 text-sm font-semibold rounded-full">
            <XCircle className="w-3 h-3" />
            Declined
          </span>
        );
      default:
        return null;
    }
  };

  const openMessaging = (booking: Booking) => {
    setSelectedBooking(booking);
    setShowMessaging(true);
  };

  if (loading) {
    return (
      <Card>
        <div className="text-center py-8">
          <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-primary-400 mx-auto"></div>
          <p className="mt-2 text-gray-600">Loading your bookings...</p>
        </div>
      </Card>
    );
  }

  if (bookings.length === 0) {
    return (
      <Card>
        <div className="text-center py-8">
          <Calendar className="w-12 h-12 text-gray-400 mx-auto mb-3" />
          <p className="text-gray-600">No active booking requests</p>
          <p className="text-sm text-gray-500 mt-1">Browse barbers and send a request to get started</p>
        </div>
      </Card>
    );
  }

  return (
    <div className="space-y-4">
      <h2 className="text-lg font-bold text-gray-900">Your Booking Requests</h2>

      {bookings.map((booking) => (
        <Card key={booking.bookingId} className="hover:shadow-md transition-shadow">
          <div className="flex flex-col md:flex-row md:items-center md:justify-between gap-4">
            <div className="flex-1">
              <div className="flex items-center gap-3 mb-3">
                {getStatusBadge(booking.status)}
                {booking.unreadMessages > 0 && (
                  <span className="px-2 py-1 bg-primary-100 text-primary-600 text-xs font-semibold rounded-full">
                    {booking.unreadMessages} new message{booking.unreadMessages > 1 ? 's' : ''}
                  </span>
                )}
              </div>

              <h3 className="font-semibold text-gray-900 text-lg mb-2">
                {booking.barber.name}
              </h3>

              <div className="space-y-1 text-sm text-gray-600">
                <div className="flex items-center gap-2">
                  <Calendar className="w-4 h-4" />
                  <span>
                    {new Date(booking.bookingDate).toLocaleDateString('en-US', {
                      weekday: 'long',
                      month: 'long',
                      day: 'numeric',
                    })}
                  </span>
                  <span>at {booking.bookingTime}</span>
                </div>
                <div>
                  <span className="text-gray-500">Service:</span>{' '}
                  <span className="font-medium text-gray-900">{booking.serviceType}</span>
                  <span className="text-gray-500"> • </span>
                  <span className="font-semibold text-green-600">${booking.price.toFixed(2)}</span>
                </div>
              </div>

              <div className="mt-3 text-xs text-gray-500">
                {booking.status === 'pending' && (
                  <p>Requested {new Date(booking.requestedAt).toLocaleString()}</p>
                )}
                {booking.status === 'accepted' && booking.respondedAt && (
                  <p>Accepted {new Date(booking.respondedAt).toLocaleString()}</p>
                )}
                {booking.status === 'rejected' && booking.respondedAt && (
                  <p>Declined {new Date(booking.respondedAt).toLocaleString()}</p>
                )}
              </div>
            </div>

            <div className="flex md:flex-col gap-2">
              <button
                onClick={() => openMessaging(booking)}
                className="flex items-center justify-center gap-2 px-4 py-2 bg-primary-100 text-primary-500 hover:bg-primary-200 rounded-lg font-medium transition-colors"
              >
                <MessageSquare className="w-4 h-4" />
                Message
              </button>
            </div>
          </div>
        </Card>
      ))}

      {/* Messaging Modal */}
      {showMessaging && selectedBooking && (
        <div 
          className="fixed inset-0 min-h-[100dvh] bg-black bg-opacity-50 flex items-center justify-center z-50 p-4"
          onClick={() => setShowMessaging(false)}
        >
          <div 
            className="w-full max-w-2xl max-h-[85dvh] sm:max-h-[90vh] overflow-y-auto"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="mb-2 flex justify-end">
              <button
                onClick={() => setShowMessaging(false)}
                className="text-white hover:text-gray-300 text-2xl"
              >
                ✕
              </button>
            </div>
            <BookingMessaging
              bookingId={selectedBooking.bookingId}
              userId={customerId}
              userType="customer"
              otherPartyName={selectedBooking.barber.name}
            />
          </div>
        </div>
      )}
    </div>
  );
}

