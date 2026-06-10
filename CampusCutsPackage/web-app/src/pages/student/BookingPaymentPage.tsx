/**
 * Booking Confirmation Page
 * 
 * Simple booking confirmation flow:
 * 1. Consumer reviews service details (receipt)
 * 2. Consumer confirms booking
 * 3. Payment is handled directly between consumer and barber
 */

import { useState } from 'react';
import { useNavigate, useLocation } from 'react-router-dom';
import { 
  CheckCircle, 
  ArrowLeft, 
  AlertCircle, 
  Calendar,
  Clock,
  MapPin,
  User,
  Scissors,
  MessageCircle,
  Loader2,
  Mail
} from 'lucide-react';
import Button from '../../components/Button';
import Card from '../../components/Card';
import messageService from '../../services/message.service';
import api from '../../services/api.service';
import { useAuthStore } from '../../store/useAuthStore';

interface BookingDetails {
  barberId: string;
  barberUserId?: string;
  barberName: string;
  barberProfilePicture?: string;
  serviceName: string;
  servicePrice: number;
  scheduledAt: string;
  duration: number;
  location?: string;
  locationDetails?: string;
  notes?: string;
}

export default function BookingPaymentPage() {
  const navigate = useNavigate();
  const location = useLocation();
  const bookingDetails = location.state as BookingDetails;
  const { user, isLoading: isAuthLoading } = useAuthStore();

  const [step, setStep] = useState<'confirm' | 'processing' | 'success' | 'error'>('confirm');
  const [bookingId, setBookingId] = useState<string>('');
  const [errorMessage, setErrorMessage] = useState<string>('');

  // Handle booking confirmation
  const handleConfirmBooking = async () => {
    setStep('processing');
    
    try {
      const barberUserId = bookingDetails.barberUserId || bookingDetails.barberId;
      
      // 1. Create booking in database
      const bookingResponse = await api.post<{ booking: { id: string } }>('/bookings-simple', {
        barberId: barberUserId,
        serviceType: bookingDetails.serviceName,
        priceUsdCents: Math.round(bookingDetails.servicePrice * 100),
        scheduledTime: bookingDetails.scheduledAt,
        location: bookingDetails.location,
        notes: bookingDetails.notes,
      });
      
      const newBookingId = bookingResponse.booking.id;
      console.log('✅ Booking created in database:', newBookingId);
      
      // 2. Create conversation with booking reference
      if (barberUserId) {
        try {
          await messageService.startBookingConversation(barberUserId, {
            bookingId: newBookingId,
            serviceName: bookingDetails.serviceName,
            servicePrice: bookingDetails.servicePrice,
            scheduledTime: bookingDetails.scheduledAt,
            location: bookingDetails.location,
            notes: bookingDetails.notes,
            barberName: bookingDetails.barberName,
            consumerName: user?.first_name ? `${user.first_name} ${user.last_name || ''}`.trim() : 'Customer',
          });
          console.log('✅ Booking conversation created');
        } catch (convError) {
          console.error('Failed to create conversation (booking still created):', convError);
        }
      }
      
      setBookingId(newBookingId);
      // Navigate directly to booking status page instead of showing success screen
      navigate('/web/consumer/booking-status', { replace: true });
    } catch (error: any) {
      console.error('Failed to confirm booking:', error);
      setErrorMessage(error?.response?.data?.error || 'Failed to confirm booking. Please try again.');
      setStep('error');
    }
  };

  // Wait for auth to finish loading before rendering
  // This check is placed after all hooks to comply with React's Rules of Hooks
  if (isAuthLoading) {
    return (
      <div className="min-h-screen flex items-center justify-center">
        <Loader2 className="w-8 h-8 text-primary-500 animate-spin" />
      </div>
    );
  }

  // Not authenticated - redirect to login
  if (!user) {
    return (
      <div className="min-h-[100dvh] bg-gray-50 flex items-center justify-center p-6">
        <Card className="text-center max-w-md">
          <AlertCircle className="w-12 h-12 text-amber-500 mx-auto mb-4" />
          <h2 className="text-xl font-bold text-gray-900 mb-2">Session Expired</h2>
          <p className="text-gray-600 mb-4">
            Please sign in again to complete your booking
          </p>
          <Button onClick={() => navigate('/web')}>
            Sign In
          </Button>
        </Card>
      </div>
    );
  }

  // No booking details
  if (!bookingDetails) {
    return (
      <div className="min-h-[100dvh] bg-gray-50 flex items-center justify-center p-6">
        <Card className="text-center max-w-md">
          <AlertCircle className="w-12 h-12 text-red-500 mx-auto mb-4" />
          <h2 className="text-xl font-bold text-gray-900 mb-2">No Booking Details</h2>
          <p className="text-gray-600 mb-4">
            Please start from the barber selection page
          </p>
          <Button onClick={() => navigate('/web/consumer')}>
            Back to Dashboard
          </Button>
        </Card>
      </div>
    );
  }

  // Format date and time
  const scheduledDate = new Date(bookingDetails.scheduledAt);
  const formattedDate = scheduledDate.toLocaleDateString('en-US', {
    weekday: 'long',
    year: 'numeric',
    month: 'long',
    day: 'numeric'
  });
  const formattedTime = scheduledDate.toLocaleTimeString('en-US', {
    hour: 'numeric',
    minute: '2-digit',
    hour12: true
  });

  // Success Screen
  if (step === 'success') {
    return (
      <div className="min-h-[100dvh] bg-gray-50 flex items-center justify-center p-6">
        <Card className="text-center max-w-md">
          <div className="bg-green-100 rounded-full p-4 w-16 h-16 mx-auto mb-4 flex items-center justify-center">
            <CheckCircle className="w-8 h-8 text-green-600" />
          </div>
          <h2 className="text-2xl font-bold text-gray-900 mb-2">Booking Confirmed!</h2>
          <p className="text-gray-600 mb-6">
            Your appointment with {bookingDetails.barberName} has been confirmed. You'll pay ${bookingDetails.servicePrice.toFixed(2)} directly to the barber.
          </p>

          <div className="text-left bg-gray-50 p-4 rounded-lg mb-6">
            <h3 className="font-semibold text-gray-900 mb-3">Booking Details</h3>
            <div className="space-y-2 text-sm">
              <div className="flex justify-between">
                <span className="text-gray-600">Barber:</span>
                <span className="font-medium">{bookingDetails.barberName}</span>
              </div>
              <div className="flex justify-between">
                <span className="text-gray-600">Service:</span>
                <span className="font-medium">{bookingDetails.serviceName}</span>
              </div>
              <div className="flex justify-between">
                <span className="text-gray-600">Date:</span>
                <span className="font-medium">{formattedDate}</span>
              </div>
              <div className="flex justify-between">
                <span className="text-gray-600">Time:</span>
                <span className="font-medium">{formattedTime}</span>
              </div>
              <div className="flex justify-between font-bold border-t border-gray-200 pt-2 mt-2">
                <span>Amount Due:</span>
                <span className="text-primary-600">${bookingDetails.servicePrice.toFixed(2)}</span>
              </div>
              <div className="flex justify-between text-xs text-gray-500 mt-2">
                <span>Booking ID:</span>
                <span className="font-mono">{bookingId.slice(0, 8)}...</span>
              </div>
            </div>
          </div>

          <div className="p-3 rounded-lg mb-6 text-sm bg-amber-50 border border-amber-200">
            <p className="text-amber-700 font-medium mb-1">Payment Due at Appointment</p>
            <p className="text-amber-600">
              Please pay your barber directly when your service is complete.
            </p>
          </div>

          <div className="space-y-3">
            <Button 
              onClick={() => {
                navigate('/web/consumer/messages', { 
                  state: { 
                    startConversation: true,
                    otherUserId: bookingDetails.barberUserId || bookingDetails.barberId,
                    bookingId: bookingId,
                    serviceName: bookingDetails.serviceName,
                    servicePrice: bookingDetails.servicePrice,
                    scheduledAt: bookingDetails.scheduledAt,
                    location: bookingDetails.location,
                    locationDetails: bookingDetails.locationDetails,
                    notes: bookingDetails.notes,
                    barberName: bookingDetails.barberName,
                  }
                });
              }} 
              variant="secondary"
              className="w-full flex items-center justify-center gap-2"
            >
              <MessageCircle className="w-4 h-4" />
              Message {bookingDetails.barberName?.split(' ')[0] || 'Barber'}
            </Button>
            <Button onClick={() => navigate('/web/consumer')} className="w-full">
              Back to Dashboard
            </Button>
          </div>
        </Card>
      </div>
    );
  }

  // Error Screen
  if (step === 'error') {
    return (
      <div className="min-h-[100dvh] bg-gray-50 flex items-center justify-center p-6">
        <Card className="text-center max-w-md">
          <div className="bg-red-100 rounded-full p-4 w-16 h-16 mx-auto mb-4 flex items-center justify-center">
            <AlertCircle className="w-8 h-8 text-red-600" />
          </div>
          <h2 className="text-2xl font-bold text-gray-900 mb-2">Something Went Wrong</h2>
          <p className="text-gray-600 mb-6">{errorMessage}</p>
          <div className="space-y-2">
            <Button onClick={() => setStep('confirm')} className="w-full">
              Try Again
            </Button>
            <Button onClick={() => navigate(-1)} variant="secondary" className="w-full">
              Go Back
            </Button>
          </div>
        </Card>
      </div>
    );
  }

  // Processing Screen
  if (step === 'processing') {
    return (
      <div className="min-h-[100dvh] bg-gray-50 flex items-center justify-center p-6">
        <Card className="text-center max-w-md">
          <div className="w-16 h-16 border-4 border-primary-200 border-t-primary-500 rounded-full animate-spin mx-auto mb-4" />
          <h2 className="text-2xl font-bold text-gray-900 mb-2">Confirming Booking...</h2>
          <p className="text-gray-600">Setting up your appointment.</p>
        </Card>
      </div>
    );
  }

  // Confirmation Screen (Receipt)
  return (
    <div className="min-h-[100dvh] bg-gray-50 p-6">
      <div className="max-w-lg mx-auto">
        {/* Header */}
        <div className="mb-8 flex items-center gap-4">
          <Button 
            onClick={() => {
              const scheduledDate = new Date(bookingDetails.scheduledAt);
              const date = scheduledDate.toISOString().split('T')[0];
              const time = scheduledDate.toTimeString().slice(0, 5);
              
              navigate(`/web/consumer/book/${bookingDetails.barberId}`, {
                state: {
                  preservedFormData: {
                    barberId: bookingDetails.barberId,
                    serviceType: bookingDetails.serviceName,
                    date: date,
                    time: time,
                    location: bookingDetails.location || '',
                    locationDetails: bookingDetails.locationDetails || '',
                    notes: bookingDetails.notes || '',
                  }
                }
              });
            }} 
            variant="secondary"
          >
            <ArrowLeft className="w-4 h-4 mr-2" />
            Back
          </Button>
        </div>

        {/* Receipt Card */}
        <Card className="mb-6">
          {/* Receipt Header */}
          <div className="text-center border-b border-gray-200 pb-4 mb-4">
            <h2 className="text-xl font-bold text-gray-900">Booking Summary</h2>
          </div>

          {/* Barber Info */}
          <div className="flex items-center gap-3 p-3 bg-gray-50 rounded-lg mb-4">
            <div className="w-12 h-12 bg-primary-100 rounded-full flex items-center justify-center overflow-hidden">
              {bookingDetails.barberProfilePicture ? (
                <img 
                  src={bookingDetails.barberProfilePicture} 
                  alt={bookingDetails.barberName}
                  className="w-full h-full object-cover"
                />
              ) : (
                <User className="w-6 h-6 text-primary-600" />
              )}
            </div>
            <div>
              <p className="font-semibold text-gray-900">{bookingDetails.barberName}</p>
            </div>
          </div>

          {/* Service Details */}
          <div className="space-y-4 mb-6">
            <div className="flex items-start gap-3">
              <Scissors className="w-5 h-5 text-gray-400 mt-0.5" />
              <div>
                <p className="text-sm text-gray-500">Service</p>
                <p className="font-medium text-gray-900">{bookingDetails.serviceName}</p>
              </div>
            </div>

            <div className="flex items-start gap-3">
              <Calendar className="w-5 h-5 text-gray-400 mt-0.5" />
              <div>
                <p className="text-sm text-gray-500">Date</p>
                <p className="font-medium text-gray-900">{formattedDate}</p>
              </div>
            </div>

            <div className="flex items-start gap-3">
              <Clock className="w-5 h-5 text-gray-400 mt-0.5" />
              <div>
                <p className="text-sm text-gray-500">Time</p>
                <p className="font-medium text-gray-900">{formattedTime}</p>
              </div>
            </div>

            {bookingDetails.location && (
              <div className="flex items-start gap-3">
                <MapPin className="w-5 h-5 text-gray-400 mt-0.5" />
                <div>
                  <p className="text-sm text-gray-500">Location</p>
                  <p className="font-medium text-gray-900">{bookingDetails.location}</p>
                </div>
              </div>
            )}

            {bookingDetails.notes && (
              <div className="p-3 bg-yellow-50 border border-yellow-200 rounded-lg">
                <p className="text-sm text-yellow-800">
                  <span className="font-medium">Note:</span> {bookingDetails.notes}
                </p>
              </div>
            )}
          </div>

          {/* Price */}
          <div className="border-t border-dashed border-gray-300 pt-4">
            <div className="flex justify-between items-center">
              <span className="text-lg font-medium text-gray-700">Amount Due</span>
              <span className="text-2xl font-bold text-primary-600">
                ${bookingDetails.servicePrice.toFixed(2)}
              </span>
            </div>
            <p className="text-xs text-gray-500 mt-1 text-right">
              Pay directly to barber after service
            </p>
          </div>
        </Card>

        {/* Email Notification Info */}
        <div className="mb-6 p-4 bg-primary-50 border border-primary-200 rounded-lg flex items-start gap-3">
          <div className="flex-shrink-0 w-10 h-10 bg-primary-100 rounded-full flex items-center justify-center">
            <Mail className="w-5 h-5 text-primary-600" />
          </div>
          <div>
            <p className="font-semibold text-primary-900 text-sm">Check Your Email</p>
            <p className="text-primary-700 text-sm mt-1">
              After booking, you'll receive service details and appointment information at your registered email. 
              Your barber may also send updates about your appointment via email.
            </p>
          </div>
        </div>

        {/* Confirm Button */}
        <Button 
          onClick={handleConfirmBooking}
          className="w-full py-4 text-lg"
        >
          <CheckCircle className="w-5 h-5 mr-2" />
          Confirm Booking
        </Button>

        {/* Info Text */}
        <div className="text-xs text-gray-500 text-center mt-4 space-y-1">
          <p>No payment is required until after your service is complete.</p>
          <p>By confirming, you agree to pay ${bookingDetails.servicePrice.toFixed(2)} directly to {bookingDetails.barberName?.split(' ')[0] || 'your barber'} upon completion.</p>
          <p>A receipt will be sent to your registered email.</p>
        </div>
      </div>
    </div>
  );
}
