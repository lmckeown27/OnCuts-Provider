import { useState, useEffect } from 'react';
import { useParams, useNavigate, useLocation } from 'react-router-dom';
import { Calendar, Clock, MapPin, DollarSign, CheckCircle, ArrowRight, ArrowLeft, CreditCard } from 'lucide-react';
import type { Barber, Service } from '../../types';
import barberService from '../../services/barber.service';
import bookingService from '../../services/booking.service';
import paymentService from '../../services/payment.service';
import Button from '../../components/Button';
import Card from '../../components/Card';
import Loading from '../../components/Loading';
import toast from 'react-hot-toast';
import { format, addDays, setHours, setMinutes, startOfDay } from 'date-fns';

type BookingStep = 'service' | 'datetime' | 'details' | 'payment' | 'confirmation';

interface BookingData {
  service: Service | null;
  date: Date | null;
  time: string | null;
  location: string;
  specialRequests: string;
}

export default function BookingPage() {
  const { barberId } = useParams<{ barberId: string }>();
  const navigate = useNavigate();
  const location = useLocation();
  const platformPrefix = location.pathname.startsWith('/app') ? '/app' : '/web';
  const [barber, setBarber] = useState<Barber | null>(null);
  const [currentStep, setCurrentStep] = useState<BookingStep>('service');
  const [isLoading, setIsLoading] = useState(true);
  const [isProcessing, setIsProcessing] = useState(false);
  const [bookingData, setBookingData] = useState<BookingData>({
    service: null,
    date: null,
    time: null,
    location: '',
    specialRequests: '',
  });
  const [availableTimeSlots, setAvailableTimeSlots] = useState<string[]>([]);

  useEffect(() => {
    if (barberId) loadBarber(barberId);
  }, [barberId]);

  useEffect(() => {
    if (bookingData.date && barberId) {
      loadAvailableTimeSlots();
    }
  }, [bookingData.date, barberId]);

  const loadBarber = async (id: string) => {
    try {
      const data = await barberService.getBarberById(id);
      setBarber(data);
    } catch (error) {
      toast.error('Failed to load barber information');
      navigate(`${platformPrefix}/consumer`);
    } finally {
      setIsLoading(false);
    }
  };

  const loadAvailableTimeSlots = () => {
    // Mock time slot generation (9 AM to 6 PM in 30-min intervals)
    const slots: string[] = [];
    for (let hour = 9; hour < 18; hour++) {
      slots.push(`${hour.toString().padStart(2, '0')}:00`);
      slots.push(`${hour.toString().padStart(2, '0')}:30`);
    }
    setAvailableTimeSlots(slots);
  };

  const handleServiceSelect = (service: Service) => {
    setBookingData({ ...bookingData, service });
    setCurrentStep('datetime');
  };

  const handleDateSelect = (date: Date) => {
    setBookingData({ ...bookingData, date, time: null });
  };

  const handleTimeSelect = (time: string) => {
    setBookingData({ ...bookingData, time });
  };

  const handleNext = () => {
    const steps: BookingStep[] = ['service', 'datetime', 'details', 'payment', 'confirmation'];
    const currentIndex = steps.indexOf(currentStep);
    if (currentIndex < steps.length - 1) {
      setCurrentStep(steps[currentIndex + 1]);
    }
  };

  const handleBack = () => {
    const steps: BookingStep[] = ['service', 'datetime', 'details', 'payment', 'confirmation'];
    const currentIndex = steps.indexOf(currentStep);
    if (currentIndex > 0) {
      setCurrentStep(steps[currentIndex - 1]);
    }
  };

  const handleSubmitBooking = async () => {
    if (!bookingData.service || !bookingData.date || !bookingData.time || !barberId) {
      toast.error('Please complete all required fields');
      return;
    }

    try {
      setIsProcessing(true);

      // Combine date and time
      const [hours, minutes] = bookingData.time.split(':');
      const scheduledTime = setMinutes(setHours(bookingData.date, parseInt(hours)), parseInt(minutes));

      // Create booking
      const booking = await bookingService.createBooking({
        barber_id: barberId,
        service_id: bookingData.service.id,
        service_name: bookingData.service.name,
        service_price: bookingData.service.price,
        scheduled_time: scheduledTime.toISOString(),
        duration_minutes: bookingData.service.duration_minutes,
        location: bookingData.location || 'TBD',
        special_requests: bookingData.specialRequests,
      });

      // Process payment (if post-payment model, skip this for now)
      // const paymentIntent = await paymentService.createPaymentIntent(booking.id);

      setCurrentStep('confirmation');
      toast.success('Booking confirmed!');
    } catch (error) {
      console.error('Booking failed:', error);
      toast.error('Failed to create booking');
    } finally {
      setIsProcessing(false);
    }
  };

  if (isLoading) {
    return <Loading fullScreen text="Loading booking details..." />;
  }

  if (!barber) {
    return <div className="text-center py-12">Barber not found</div>;
  }

  const nextDays = Array.from({ length: 7 }, (_, i) => addDays(startOfDay(new Date()), i));

  return (
    <div className="max-w-4xl mx-auto px-4 py-8">
      {/* Header */}
      <div className="mb-8">
        <button
          onClick={() => navigate(`/student/barbers/${barberId}`)}
          className="flex items-center gap-2 text-primary-600 hover:text-primary-700 mb-4"
        >
          <ArrowLeft className="w-4 h-4" />
          Back to Profile
        </button>
        <h1 className="text-3xl font-bold text-gray-900 mb-2">Book Appointment</h1>
        <p className="text-gray-600">
          with {barber.user?.first_name} {barber.user?.last_name}
        </p>
      </div>

      {/* Progress Steps */}
      <div className="mb-8">
        <div className="flex items-center justify-between">
          {[
            { id: 'service', label: 'Service', icon: DollarSign },
            { id: 'datetime', label: 'Date & Time', icon: Calendar },
            { id: 'details', label: 'Details', icon: MapPin },
            { id: 'payment', label: 'Payment', icon: CreditCard },
            { id: 'confirmation', label: 'Done', icon: CheckCircle },
          ].map((step, index, array) => (
            <div key={step.id} className="flex items-center flex-1">
              <div
                className={`flex items-center justify-center w-10 h-10 rounded-full ${
                  currentStep === step.id
                    ? 'bg-primary-600 text-white'
                    : array.findIndex((s) => s.id === currentStep) > index
                    ? 'bg-green-500 text-white'
                    : 'bg-gray-300 text-gray-600'
                }`}
              >
                <step.icon className="w-5 h-5" />
              </div>
              <div className="hidden md:block ml-2 text-sm font-medium text-gray-700">
                {step.label}
              </div>
              {index < array.length - 1 && (
                <div className="flex-1 h-1 mx-2 bg-gray-300 rounded-full overflow-hidden">
                  <div
                    className={`h-full ${
                      array.findIndex((s) => s.id === currentStep) > index
                        ? 'bg-green-500'
                        : 'bg-gray-300'
                    }`}
                  />
                </div>
              )}
            </div>
          ))}
        </div>
      </div>

      {/* Step Content */}
      <Card>
        {/* Step 1: Service Selection */}
        {currentStep === 'service' && (
          <div>
            <h2 className="text-2xl font-bold mb-6">Select a Service</h2>
            <div className="space-y-3">
              {barber.pricing.map((service) => (
                <button
                  key={service.id}
                  onClick={() => handleServiceSelect(service)}
                  className={`w-full p-4 border-2 rounded-lg text-left transition-all hover:shadow-md ${
                    bookingData.service?.id === service.id
                      ? 'border-primary-600 bg-primary-50'
                      : 'border-gray-200 hover:border-primary-300'
                  }`}
                >
                  <div className="flex justify-between items-start">
                    <div>
                      <h3 className="font-semibold text-lg text-gray-900">{service.name}</h3>
                      {service.description && (
                        <p className="text-sm text-gray-600 mt-1">{service.description}</p>
                      )}
                      <p className="text-sm text-gray-500 mt-2 flex items-center gap-1">
                        <Clock className="w-4 h-4" />
                        {service.duration_minutes} minutes
                      </p>
                    </div>
                    <div className="text-right">
                      <p className="text-2xl font-bold text-primary-600">${service.price}</p>
                    </div>
                  </div>
                </button>
              ))}
            </div>
          </div>
        )}

        {/* Step 2: Date & Time Selection */}
        {currentStep === 'datetime' && (
          <div>
            <h2 className="text-2xl font-bold mb-6">Select Date & Time</h2>
            
            {/* Date Selection */}
            <div className="mb-8">
              <h3 className="font-semibold text-lg mb-4">Choose a Date</h3>
              <div className="grid grid-cols-7 gap-3">
                {nextDays.map((day) => (
                  <button
                    key={day.toISOString()}
                    onClick={() => handleDateSelect(day)}
                    className={`p-4 border-2 rounded-lg text-center transition-all ${
                      bookingData.date?.toDateString() === day.toDateString()
                        ? 'border-primary-600 bg-primary-50'
                        : 'border-gray-200 hover:border-primary-300'
                    }`}
                  >
                    <p className="text-xs text-gray-600 font-medium">
                      {format(day, 'EEE')}
                    </p>
                    <p className="text-lg font-bold text-gray-900 mt-1">
                      {format(day, 'd')}
                    </p>
                  </button>
                ))}
              </div>
            </div>

            {/* Time Selection */}
            {bookingData.date && (
              <div>
                <h3 className="font-semibold text-lg mb-4">Choose a Time</h3>
                <div className="grid grid-cols-4 md:grid-cols-6 gap-3">
                  {availableTimeSlots.map((time) => (
                    <button
                      key={time}
                      onClick={() => handleTimeSelect(time)}
                      className={`p-3 border-2 rounded-lg text-center transition-all ${
                        bookingData.time === time
                          ? 'border-primary-600 bg-primary-50 font-semibold'
                          : 'border-gray-200 hover:border-primary-300'
                      }`}
                    >
                      {time}
                    </button>
                  ))}
                </div>
              </div>
            )}

            <div className="flex justify-between mt-8">
              <Button variant="secondary" onClick={handleBack}>
                <ArrowLeft className="w-4 h-4 mr-2" />
                Back
              </Button>
              <Button
                onClick={handleNext}
                disabled={!bookingData.date || !bookingData.time}
              >
                Next
                <ArrowRight className="w-4 h-4 ml-2" />
              </Button>
            </div>
          </div>
        )}

        {/* Step 3: Details */}
        {currentStep === 'details' && (
          <div>
            <h2 className="text-2xl font-bold mb-6">Appointment Details</h2>
            
            <div className="mb-6">
              <label className="block text-sm font-medium text-gray-700 mb-2">
                Location (Optional)
              </label>
              <input
                type="text"
                value={bookingData.location}
                onChange={(e) => setBookingData({ ...bookingData, location: e.target.value })}
                placeholder="e.g., Your dorm, campus barbershop..."
                className="w-full px-4 py-3 border border-gray-300 rounded-lg focus:ring-2 focus:ring-primary-500 focus:border-transparent outline-none"
              />
            </div>

            <div className="mb-6">
              <label className="block text-sm font-medium text-gray-700 mb-2">
                Special Requests (Optional)
              </label>
              <textarea
                value={bookingData.specialRequests}
                onChange={(e) => setBookingData({ ...bookingData, specialRequests: e.target.value })}
                placeholder="Any specific preferences or instructions..."
                rows={4}
                className="w-full px-4 py-3 border border-gray-300 rounded-lg focus:ring-2 focus:ring-primary-500 focus:border-transparent outline-none"
              />
            </div>

            <div className="flex justify-between">
              <Button variant="secondary" onClick={handleBack}>
                <ArrowLeft className="w-4 h-4 mr-2" />
                Back
              </Button>
              <Button onClick={handleNext}>
                Next
                <ArrowRight className="w-4 h-4 ml-2" />
              </Button>
            </div>
          </div>
        )}

        {/* Step 4: Payment */}
        {currentStep === 'payment' && (
          <div>
            <h2 className="text-2xl font-bold mb-6">Review & Pay</h2>
            
            <div className="bg-gray-50 rounded-lg p-6 mb-6">
              <h3 className="font-semibold text-lg mb-4">Booking Summary</h3>
              <div className="space-y-3">
                <div className="flex justify-between">
                  <span className="text-gray-600">Service:</span>
                  <span className="font-semibold">{bookingData.service?.name}</span>
                </div>
                <div className="flex justify-between">
                  <span className="text-gray-600">Date:</span>
                  <span className="font-semibold">
                    {bookingData.date && format(bookingData.date, 'MMM d, yyyy')}
                  </span>
                </div>
                <div className="flex justify-between">
                  <span className="text-gray-600">Time:</span>
                  <span className="font-semibold">{bookingData.time}</span>
                </div>
                <div className="flex justify-between">
                  <span className="text-gray-600">Duration:</span>
                  <span className="font-semibold">{bookingData.service?.duration_minutes} min</span>
                </div>
                {bookingData.location && (
                  <div className="flex justify-between">
                    <span className="text-gray-600">Location:</span>
                    <span className="font-semibold">{bookingData.location}</span>
                  </div>
                )}
                <div className="border-t border-gray-300 pt-3 mt-3 flex justify-between">
                  <span className="text-lg font-semibold">Total:</span>
                  <span className="text-2xl font-bold text-primary-600">
                    ${bookingData.service?.price}
                  </span>
                </div>
              </div>
            </div>

            <div className="bg-primary-50 border border-primary-200 rounded-lg p-4 mb-6">
              <p className="text-sm text-primary-800">
                <strong>Secure Payment:</strong> Your payment will be held in escrow until service completion. 
                You can also add a tip for your barber on the next screen.
              </p>
            </div>

            <div className="flex justify-between">
              <Button variant="secondary" onClick={handleBack}>
                <ArrowLeft className="w-4 h-4 mr-2" />
                Back
              </Button>
              <Button
                onClick={() => {
                  // Navigate to payment page with booking details
                  if (bookingData.service && bookingData.date && bookingData.time) {
                    const [hours, minutes] = bookingData.time.split(':');
                    const scheduledTime = setMinutes(setHours(bookingData.date, parseInt(hours)), parseInt(minutes));
                    
                    // Build barber name from available properties
                    const barberName = barber?.name 
                      || barber?.display_name 
                      || (barber?.user?.first_name ? `${barber.user.first_name} ${barber.user.last_name || ''}`.trim() : null)
                      || (barber?.first_name ? `${barber.first_name} ${barber.last_name || ''}`.trim() : null)
                      || 'Barber';
                    
                    navigate('/web/student/booking/payment', {
                      state: {
                        barberId: barberId,
                        barberUserId: barber?.user_id,
                        barberName: barberName,
                        barberProfilePicture: barber?.profile_picture_url || barber?.profile_photo_url,
                        serviceName: bookingData.service.name,
                        servicePrice: bookingData.service.price,
                        scheduledAt: scheduledTime.toISOString(),
                        duration: bookingData.service.duration_minutes,
                      }
                    });
                  }
                }}
                disabled={isProcessing}
              >
                Proceed to Payment
                <CreditCard className="w-4 h-4 ml-2" />
              </Button>
            </div>
          </div>
        )}

        {/* Step 5: Confirmation */}
        {currentStep === 'confirmation' && (
          <div className="text-center py-12">
            <div className="w-20 h-20 bg-green-100 rounded-full flex items-center justify-center mx-auto mb-6">
              <CheckCircle className="w-12 h-12 text-green-600" />
            </div>
            <h2 className="text-3xl font-bold text-gray-900 mb-4">Booking Confirmed!</h2>
            <p className="text-gray-600 mb-8">
              Your appointment with {barber.user?.first_name} is confirmed for{' '}
              {bookingData.date && format(bookingData.date, 'MMM d, yyyy')} at {bookingData.time}
            </p>
            <div className="flex flex-col gap-3 max-w-md mx-auto">
              <Button onClick={() => navigate('/student/bookings')} fullWidth>
                View My Bookings
              </Button>
              <Button variant="secondary" onClick={() => navigate(`${platformPrefix}/consumer`)} fullWidth>
                Back to Discovery
              </Button>
            </div>
          </div>
        )}
      </Card>
    </div>
  );
}

