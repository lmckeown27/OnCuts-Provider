import { useState, useEffect } from 'react';
import { useNavigate, useParams, useLocation } from 'react-router-dom';
import { ArrowLeft, Clock, MapPin, Scissors, Instagram } from 'lucide-react';
import Card from '../components/Card';
import Button from '../components/Button';
import AvailableTimePickerDropdown from '../components/AvailableTimePickerDropdown';
import DatePicker from '../components/DatePicker';
import toast from 'react-hot-toast';
import barberService from '../services/barber.service';
import type { Barber } from '../types';
import type { FilterCriteria } from '../types/barber-filters';
import { CampusCutLogo } from '@assets';
import { SPECIALTY_OPTIONS } from '../config/services';

export default function ScheduleServicePage() {
  const navigate = useNavigate();
  const { barberId } = useParams<{ barberId: string }>();
  const location = useLocation();
  
  // Determine platform prefix for navigation
  const platformPrefix = location.pathname.startsWith('/app') ? '/app' : '/web';
  
  // Get passed data from state
  const passedBarber = location.state?.barber as Barber | undefined;
  const passedFilters = location.state?.filters as FilterCriteria | undefined;
  const preservedFormData = location.state?.preservedFormData;

  const [barber, setBarber] = useState<Barber | null>(passedBarber || null);
  const [isLoading, setIsLoading] = useState(!passedBarber);

  // Fetch barber by ID if not passed in state (e.g., when navigating back)
  useEffect(() => {
    const fetchBarber = async () => {
      if (!passedBarber && barberId) {
        try {
          const barberData = await barberService.getBarberById(barberId);
          if (barberData) {
            setBarber(barberData);
          }
        } catch (error) {
          console.error('Failed to fetch barber:', error);
        }
        setIsLoading(false);
      }
    };
    fetchBarber();
  }, [barberId, passedBarber]);
  const [serviceType, setServiceType] = useState<string>(
    preservedFormData?.serviceType || passedFilters?.serviceType || ''
  );
  const [date, setDate] = useState<string>(
    preservedFormData?.date || passedFilters?.date || ''
  );
  const [time, setTime] = useState<string>(
    preservedFormData?.time || passedFilters?.time || ''
  );
  const [location_, setLocation] = useState<string>(
    preservedFormData?.location || passedFilters?.location || ''
  );
  const [locationDetails, setLocationDetails] = useState<string>(
    preservedFormData?.locationDetails || passedFilters?.locationDetails || ''
  );
  const [notes, setNotes] = useState<string>(preservedFormData?.notes || '');
  const [isSubmitting, setIsSubmitting] = useState(false);
  
  // Validation error states
  const [errors, setErrors] = useState<{
    serviceType?: string;
    date?: string;
    time?: string;
    location?: string;
  }>({});
  
  // Available locations for this barber
  interface BarberLocation {
    id: string;
    name: string;
    description: string | null;
    address: string | null;
  }
  const [barberLocations, setBarberLocations] = useState<BarberLocation[]>([]);
  const [locationsLoading, setLocationsLoading] = useState(false);

  // Available services based on barber's specialties (fallback to shared config)
  // Filter to only show services that have pricing info (excludes deleted services)
  const rawServices = (Array.isArray(barber?.specialties) && barber.specialties.length > 0)
    ? barber.specialties 
    : SPECIALTY_OPTIONS;
  
  const availableServices = rawServices.filter((service: string) => {
    // Only show services that have pricing info from this barber
    if (!barber?.pricing || barber.pricing.length === 0) return true;
    return barber.pricing.some((p: any) => p.name?.toLowerCase() === service.toLowerCase());
  });

  // Fetch locations when barber is available
  useEffect(() => {
    const fetchLocations = async () => {
      if (!barber?.id) return;
      
      try {
        setLocationsLoading(true);
        const response = await fetch(`/api/locations/for-booking/${barber.id}`);
        if (response.ok) {
          const data = await response.json();
          setBarberLocations(data.data || []);
          // Auto-select first location if available and no location is set
          if (!location_ && data.data?.length > 0) {
            const firstLoc = data.data[0];
            if (firstLoc) {
              setLocation(firstLoc.name);
              setLocationDetails(firstLoc.name);
            }
          }
        }
      } catch (error) {
        console.error('Failed to fetch barber locations:', error);
      } finally {
        setLocationsLoading(false);
      }
    };
    
    fetchLocations();
  }, [barber?.id]);

  // Get minimum date (today)
  const today = new Date().toISOString().split('T')[0];

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();

    // Validation - check all fields at once
    const newErrors: typeof errors = {};
    
    if (!serviceType) {
      newErrors.serviceType = 'Please select a service type';
    }
    if (!date) {
      newErrors.date = 'Please select a date';
    }
    if (!time) {
      newErrors.time = 'Please select a time';
    }
    if (!location_) {
      newErrors.location = 'Please select a location';
    }
    
    // If there are errors, set them and scroll to top
    if (Object.keys(newErrors).length > 0) {
      setErrors(newErrors);
      window.scrollTo({ top: 0, behavior: 'smooth' });
      toast.error('Please fill in all required fields');
      return;
    }
    
    // Clear any previous errors
    setErrors({});

    setIsSubmitting(true);

    try {
      // Get service price from barber's pricing
      const servicePrice = barber?.pricing?.find(
        p => p.name?.toLowerCase() === serviceType.toLowerCase()
      )?.price || 30;

      // Combine date and time for scheduled datetime
      // IMPORTANT: All times are in Pacific timezone (Cal Poly SLO)
      // We pass date and time separately so the backend can correctly interpret as Pacific time
      // This avoids browser timezone issues
      const scheduledAt = `${date}T${time}:00`; // ISO format without timezone - backend will interpret as Pacific

      // Build barber name from available properties
      const barberName = barber?.name 
        || barber?.display_name 
        || (barber?.user?.first_name ? `${barber.user.first_name} ${barber.user.last_name || ''}`.trim() : null)
        || (barber?.first_name ? `${barber.first_name} ${barber.last_name || ''}`.trim() : null)
        || 'Barber';

      // Navigate to payment page with booking details
      navigate(`${platformPrefix}/student/booking/payment`, {
        state: {
          barberId: barberId,
          barberUserId: barber?.user_id, // User ID for messaging
          barberName: barberName,
          barberProfilePicture: barber?.profile_picture_url || barber?.profile_photo_url,
          serviceName: serviceType,
          servicePrice: servicePrice,
          scheduledAt: scheduledAt,
          duration: 30, // Default 30 minutes
          location: location_,
          locationDetails: locationDetails,
          notes: notes,
        }
      });
    } catch (error) {
      console.error('Failed to create booking:', error);
      toast.error('Failed to create booking. Please try again.');
      setIsSubmitting(false);
    }
  };

  if (isLoading) {
    return (
      <div className="min-h-[100dvh] bg-gray-50 flex items-center justify-center">
        <div className="text-center">
          <p className="text-gray-600">Loading barber info...</p>
        </div>
      </div>
    );
  }

  if (!barber) {
    return (
      <div className="min-h-[100dvh] bg-gray-50 flex items-center justify-center">
        <div className="text-center">
          <p className="text-gray-600 mb-4">Barber not found</p>
          <Button onClick={() => navigate(`${platformPrefix}/consumer`)}>
            Back to Discovery
          </Button>
        </div>
      </div>
    );
  }

  return (
    <div className="min-h-[100dvh] bg-gray-50">
      {/* Header */}
      <div className="bg-white shadow-sm border-b border-gray-200">
        <div className="max-w-4xl mx-auto px-4 py-4">
          <div className="flex items-center gap-4">
            <button
              onClick={() => navigate(`${platformPrefix}/consumer`, {
                state: {
                  preservedFormData: {
                    barberId,
                    serviceType,
                    date,
                    time,
                    location: location_,
                    locationDetails,
                    notes
                  }
                }
              })}
              className="p-2 hover:bg-gray-100 rounded-lg transition-colors"
            >
              <ArrowLeft className="w-5 h-5 text-gray-600" />
            </button>
            <img src={CampusCutLogo} alt="CampusCut" className="h-10 w-auto" />
            <h1 className="text-2xl font-bold text-gray-900">Schedule Service</h1>
          </div>
        </div>
      </div>

      {/* Content */}
      <div className="max-w-4xl mx-auto px-4 py-8">
        <div className="grid md:grid-cols-3 gap-6">
          {/* Barber Info Sidebar */}
          <div className="md:col-span-1">
            <Card className="sticky top-4">
              <div className="p-6">
                <div className="w-48 aspect-square mx-auto rounded-lg overflow-hidden bg-gray-200 mb-4">
                  {barber.profile_picture_url || barber.profile_photo_url ? (
                    <img
                      src={barber.profile_picture_url || barber.profile_photo_url}
                      alt="Barber"
                      className="w-full h-full object-cover"
                    />
                  ) : barber.portfolio && barber.portfolio.length > 0 ? (
                    <img
                      src={barber.portfolio[0].url}
                      alt="Barber"
                      className="w-full h-full object-cover"
                    />
                  ) : (
                    <div className="w-full h-full flex items-center justify-center">
                      <Scissors className="w-24 h-24 text-gray-400" />
                    </div>
                  )}
                </div>

                <h2 className="text-xl font-bold text-gray-900 mb-2">
                  {barber.user?.first_name} {barber.user?.last_name}
                </h2>


                {barber.instagram_handle && (
                  <a
                    href={`https://instagram.com/${barber.instagram_handle}`}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="flex items-center justify-center gap-2 px-4 py-2 bg-gradient-to-r from-purple-500 to-pink-500 text-white rounded-lg hover:from-purple-600 hover:to-pink-600 transition-all shadow-sm hover:shadow-md w-full"
                  >
                    <Instagram className="w-4 h-4" />
                    <span className="text-sm font-medium">@{barber.instagram_handle}</span>
                  </a>
                )}
              </div>
            </Card>
          </div>

          {/* Booking Form */}
          <div className="md:col-span-2">
            <Card>
              <form onSubmit={handleSubmit} className="p-6 space-y-6">
                <div>
                  <h3 className="text-lg font-bold text-gray-900 mb-4">Service Details</h3>

                  {/* Service Type */}
                  <div className="mb-6">
                    <label className="block text-sm font-medium text-gray-700 mb-2">
                      <div className="flex items-center gap-2">
                        <Scissors className="w-4 h-4" />
                        Service Type *
                      </div>
                    </label>
                    <select
                      value={serviceType}
                      onChange={(e) => {
                        setServiceType(e.target.value);
                        if (e.target.value) setErrors(prev => ({ ...prev, serviceType: undefined }));
                      }}
                      className={`w-full px-4 py-3 border rounded-lg focus:ring-2 focus:ring-primary-500 focus:border-transparent ${
                        errors.serviceType ? 'border-red-500' : 'border-gray-300'
                      }`}
                      required
                    >
                      <option value="">Select a service</option>
                      {availableServices.map((service) => {
                        // Get price for this service from barber's pricing
                        const priceInfo = barber?.pricing?.find(
                          p => p.name?.toLowerCase() === service.toLowerCase()
                        );
                        const priceDisplay = priceInfo?.price ? ` - $${priceInfo.price}` : '';
                        return (
                          <option key={service} value={service}>
                            {service}{priceDisplay}
                          </option>
                        );
                      })}
                    </select>
                    {errors.serviceType && (
                      <p className="text-red-500 text-sm mt-1">{errors.serviceType}</p>
                    )}
                  </div>

                  {/* Date */}
                  <div className="mb-6">
                    <DatePicker
                      label="Date"
                      value={date}
                      onChange={(newDate) => {
                        setDate(newDate);
                        // Reset time when date changes
                        setTime('');
                        if (newDate) setErrors(prev => ({ ...prev, date: undefined }));
                      }}
                      minDate={today}
                      required
                      weeklySchedule={barber.weekly_schedule}
                    />
                    {errors.date && (
                      <p className="text-red-500 text-sm mt-1">{errors.date}</p>
                    )}
                  </div>

                  {/* Time - Shows available slots based on barber's schedule and existing bookings */}
                  <div className="mb-6">
                    <label className="block text-sm font-medium text-gray-700 mb-2">
                      <div className="flex items-center gap-2">
                        <Clock className="w-4 h-4" />
                        Time *
                      </div>
                    </label>
                    <AvailableTimePickerDropdown
                      barberId={barber.id}
                      date={date}
                      value={time}
                      onChange={(value) => {
                        setTime(value);
                        if (value) setErrors(prev => ({ ...prev, time: undefined }));
                      }}
                      disabled={!date}
                    />
                    {errors.time && (
                      <p className="text-red-500 text-sm mt-1">{errors.time}</p>
                    )}
                    <p className="text-xs text-gray-500 mt-1">
                      Times shown are based on the barber's availability and existing bookings
                    </p>
                  </div>

                  {/* Location */}
                  <div className="mb-6">
                    <label className="block text-sm font-medium text-gray-700 mb-2">
                      <div className="flex items-center gap-2">
                        <MapPin className="w-4 h-4" />
                        Location *
                      </div>
                    </label>
                    {locationsLoading ? (
                      <div className="w-full px-4 py-3 border border-gray-300 rounded-lg bg-gray-50 text-gray-500">
                        Loading locations...
                      </div>
                    ) : barberLocations.length > 0 ? (
                      <select
                        value={locationDetails}
                        onChange={(e) => {
                          setLocationDetails(e.target.value);
                          setLocation(e.target.value);
                          if (e.target.value) setErrors(prev => ({ ...prev, location: undefined }));
                        }}
                        className={`w-full px-4 py-3 border rounded-lg focus:ring-2 focus:ring-primary-500 focus:border-transparent bg-white ${
                          errors.location ? 'border-red-500' : 'border-gray-300'
                        }`}
                        required
                      >
                        <option value="">Select a location</option>
                        {barberLocations.map((loc) => (
                          <option key={loc.id} value={loc.name}>
                            {loc.name}
                          </option>
                        ))}
                      </select>
                    ) : (
                      <div className="w-full px-4 py-3 border border-amber-300 rounded-lg bg-amber-50 text-amber-700 text-sm">
                        <MapPin className="w-4 h-4 inline mr-2" />
                        This barber hasn't set up service locations yet. Please contact them directly.
                      </div>
                    )}
                    {errors.location && (
                      <p className="text-red-500 text-sm mt-1">{errors.location}</p>
                    )}
                    <p className="text-xs text-gray-500 mt-1">
                      Where the service will take place
                    </p>
                  </div>

                  {/* Additional Notes */}
                  <div className="mb-6">
                    <label className="block text-sm font-medium text-gray-700 mb-2">
                      Additional Notes (Optional)
                    </label>
                    <textarea
                      value={notes}
                      onChange={(e) => setNotes(e.target.value)}
                      rows={4}
                      className="w-full px-4 py-3 border border-gray-300 rounded-lg focus:ring-2 focus:ring-primary-500 focus:border-transparent resize-none"
                      placeholder="Any special requests or details for the barber..."
                    />
                  </div>
                </div>

                {/* Submit Button */}
                <div className="flex gap-4 pt-4 border-t border-gray-200">
                  <Button
                    type="button"
                    variant="secondary"
                    onClick={() => navigate(`${platformPrefix}/consumer`)}
                    className="flex-1"
                  >
                    Cancel
                  </Button>
                  <Button
                    type="submit"
                    disabled={isSubmitting}
                    className="flex-1"
                  >
                    {isSubmitting ? 'Processing...' : 'Continue to Confirmation'}
                  </Button>
                </div>

                <p className="text-xs text-gray-500 text-center">
                  The barber will review your request and confirm availability
                </p>
              </form>
            </Card>
          </div>
        </div>
      </div>
    </div>
  );
}

