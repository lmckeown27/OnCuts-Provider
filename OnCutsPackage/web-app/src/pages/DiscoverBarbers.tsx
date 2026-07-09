// @ts-nocheck
// @ts-nocheck
/**
 * Discover Barbers Page
 * 
 * Progressive filtering system with questionnaire
 * Filters barbers by service, availability, and location in real-time
 */

import React, { useState, useEffect } from 'react';
import { MapPin, Award, Clock, MessageSquare, Calendar, Instagram, Users, DollarSign, TrendingDown } from 'lucide-react';
import Button from '../components/Button';
import Card from '../components/Card';
import TimePickerDropdown from '../components/TimePickerDropdown';
import BarberFilterQuestionnaire from '../components/BarberFilterQuestionnaire';
import type { FilterCriteria } from '../types/barber-filters';
import barberService from '../services/barber.service';
import toast from 'react-hot-toast';
import { SPECIALTY_OPTIONS } from '../config/services';

interface Barber {
  barberId: string;
  name: string;
  bio?: string;
  instagramHandle?: string;
  profileImageUrl?: string;
  avgRating: number;
  totalReviews: number;
  totalBookings: number;
  verified: boolean;
  specialties: string[];
  priceRange: string;
  location: string;
  availability: string;
  responseTime: string;
}

interface Props {
  customerId: string;
  customerName: string;
}

export default function DiscoverBarbers({ customerId, customerName }: Props) {
  const [allBarbers, setAllBarbers] = useState<Barber[]>([]);
  const [filteredBarbers, setFilteredBarbers] = useState<Barber[]>([]);
  const [filterCriteria, setFilterCriteria] = useState<FilterCriteria>({
    serviceType: null,
    date: null,
    time: null,
    location: null,
    locationDetails: null,
  });
  const [loading, setLoading] = useState(true);
  const [selectedBarber, setSelectedBarber] = useState<Barber | null>(null);
  const [showBookingModal, setShowBookingModal] = useState(false);

  useEffect(() => {
    fetchBarbers();
  }, []);

  const fetchBarbers = async () => {
    try {
      // Fetch real barbers from the API
      const response = await barberService.getBarbers({});
      
      // Map API response to component's Barber interface
      const barbers: Barber[] = (response.data || []).map((b: any) => ({
        barberId: b.id,
        name: b.name || `${b.first_name} ${b.last_name}`,
        bio: b.bio,
        instagramHandle: b.instagram_handle,
        profileImageUrl: b.profile_picture_url,
        avgRating: b.average_rating || 0,
        totalReviews: b.total_reviews || 0,
        totalBookings: b.total_bookings || 0,
        verified: b.is_verified || false,
        specialties: b.specialties || [],
        priceRange: b.pricing?.length 
          ? `$${Math.min(...b.pricing.map((p: any) => p.price))}-$${Math.max(...b.pricing.map((p: any) => p.price))}`
          : 'Contact for pricing',
        location: 'Campus',
        availability: 'Contact barber',
        responseTime: 'Varies',
      }));

      setAllBarbers(barbers);
      setFilteredBarbers(barbers);
      setLoading(false);
    } catch (error) {
      console.error('Failed to fetch barbers:', error);
      toast.error('Failed to load barbers');
      setAllBarbers([]);
      setFilteredBarbers([]);
      setLoading(false);
    }
  };

  // Filter barbers based on criteria
  useEffect(() => {
    let filtered = [...allBarbers];

    // Filter by service type
    if (filterCriteria.serviceType) {
      filtered = filtered.filter(barber =>
        barber.specialties.some(specialty =>
          specialty.toLowerCase().includes(filterCriteria.serviceType!.toLowerCase()) ||
          filterCriteria.serviceType!.toLowerCase().includes(specialty.toLowerCase())
        )
      );
    }

    // Filter by availability (date/time)
    // For now, this is mock logic - in production, check actual availability
    if (filterCriteria.date && filterCriteria.time) {
      // Mock: filter out barbers with "tomorrow" availability if date is today
      // In production, query actual calendar/availability
      filtered = filtered.filter(barber => {
        // All barbers are "available" for this demo
        return true;
      });
    }

    // Filter by location
    if (filterCriteria.location) {
      // Mock: all barbers support all locations
      // In production, check barber preferences
      filtered = filtered.filter(barber => {
        return true; // All barbers available for all locations in demo
      });
    }

    // Sort by rating (highest first) for top performers visibility
    filtered.sort((a, b) => b.avgRating - a.avgRating);

    setFilteredBarbers(filtered);
  }, [filterCriteria, allBarbers]);

  const handleFilterChange = (filters: FilterCriteria) => {
    setFilterCriteria(filters);
  };

  const handleSelectBarber = (barber: Barber) => {
    setSelectedBarber(barber);
    setShowBookingModal(true);
  };

  if (loading) {
    return (
      <div className="min-h-screen bg-gray-50 flex items-center justify-center">
        <div className="text-center">
          <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-primary-400 mx-auto"></div>
          <p className="mt-4 text-gray-600">Finding great barbers...</p>
        </div>
      </div>
    );
  }

  // Services from shared config
  const availableServices = SPECIALTY_OPTIONS;

  return (
    <div className="min-h-screen bg-gradient-to-br from-primary-50 to-primary-50">
      <div className="max-w-6xl mx-auto px-4 py-8">
        {/* Header */}
        <div className="text-center mb-8">
          <h1 className="text-4xl font-bold text-gray-900 mb-2">Discover Barbers</h1>
          <p className="text-gray-600">Answer a few questions to find the perfect match</p>
        </div>

        {/* Pricing Education Banner */}
        <Card className="bg-gradient-to-r from-blue-50 to-green-50 border-2 border-green-200 mb-6">
          <div className="flex items-start gap-4">
            <div className="bg-white rounded-full p-3 shadow-sm">
              <TrendingDown className="w-6 h-6 text-green-600" />
            </div>
            <div className="flex-1">
              <h3 className="text-lg font-bold text-gray-900 mb-2 flex items-center gap-2">
                Save 20% Compared to Traditional Barbershops
                <DollarSign className="w-5 h-5 text-green-600" />
              </h3>
              <div className="grid grid-cols-3 gap-3 mb-3">
                <div className="bg-white rounded-lg p-3 text-center border border-green-200">
                  <p className="text-xs text-gray-500 mb-1">Budget Services</p>
                  <p className="text-xl font-bold text-green-600">$23</p>
                  <p className="text-xs text-gray-500">Buzz cuts, line-ups, trim</p>
                </div>
                <div className="bg-white rounded-lg p-3 text-center border border-green-200">
                  <p className="text-xs text-gray-500 mb-1">Standard Haircuts</p>
                  <p className="text-xl font-bold text-green-600">$28</p>
                  <p className="text-xs text-gray-500">Most popular option</p>
                </div>
                <div className="bg-white rounded-lg p-3 text-center border border-green-200">
                  <p className="text-xs text-gray-500 mb-1">Premium Services</p>
                  <p className="text-xl font-bold text-green-600">$35-$45</p>
                  <p className="text-xs text-gray-500">Fades, color, specialty</p>
                </div>
              </div>
              <p className="text-sm text-gray-700">
                <strong>Why so affordable?</strong> Traditional shops charge $35+ and barbers only keep 40-60%. 
                We eliminated the middleman—barbers keep 85%, so they can charge less while earning more!
              </p>
            </div>
          </div>
        </Card>

        {/* Filter Questionnaire */}
        <BarberFilterQuestionnaire
          onFilterChange={handleFilterChange}
          availableServices={availableServices}
        />

        {/* Results Count */}
        <div className="flex items-center justify-between mb-6">
          <div className="flex items-center gap-2">
            <Users className="w-5 h-5 text-primary-400" />
            <h2 className="text-2xl font-bold text-gray-900">
              {filteredBarbers.length} {filteredBarbers.length === 1 ? 'Barber' : 'Barbers'} Available
            </h2>
          </div>
          {filterCriteria.serviceType && (
            <div className="text-sm text-gray-600">
              Sorted by top performers first
            </div>
          )}
        </div>

        {/* No Results */}
        {filteredBarbers.length === 0 && filterCriteria.serviceType && (
          <Card className="text-center py-12">
            <p className="text-gray-600 text-lg mb-2">No barbers match your criteria</p>
            <p className="text-sm text-gray-500">Try adjusting your filters or check back later</p>
          </Card>
        )}

        {/* Barber Grid */}
        <div className="grid md:grid-cols-2 lg:grid-cols-3 gap-6">
          {filteredBarbers.map((barber) => (
            <Card key={barber.barberId} className="overflow-hidden hover:shadow-xl transition-shadow">
              {/* Profile Image Placeholder */}
              <div className="h-48 bg-gradient-to-br from-primary-400 to-primary-400 flex items-center justify-center relative">
                <div className="text-white text-6xl font-bold">
                  {barber.name.charAt(0)}
                </div>
                {barber.verified && (
                  <div className="absolute top-3 right-3 bg-green-500 text-white px-2 py-1 rounded-full flex items-center gap-1 text-xs font-semibold">
                    <Award className="w-3 h-3" />
                    Verified
                  </div>
                )}
              </div>

              {/* Profile Info */}
              <div className="p-5">
                <div className="flex items-start justify-between mb-3">
                  <div>
                    <h3 className="text-xl font-bold text-gray-900">{barber.name}</h3>
                    <div className="flex items-center gap-1 mt-1">
                      <MapPin className="w-3 h-3 text-gray-500" />
                      <span className="text-sm text-gray-600">{barber.location}</span>
                    </div>
                  </div>
                  <div className="text-right">
                    <p className="text-xs text-gray-500">{barber.totalReviews} reviews</p>
                  </div>
                </div>

                {/* Bio */}
                <p className="text-sm text-gray-700 mb-3 line-clamp-2">{barber.bio}</p>

                {/* Specialties */}
                <div className="mb-3">
                  <div className="flex flex-wrap gap-1">
                    {(Array.isArray(barber.specialties) ? barber.specialties : []).slice(0, 3).map((specialty) => (
                      <span
                        key={specialty}
                        className="px-2 py-1 bg-primary-100 text-primary-500 rounded text-xs font-medium"
                      >
                        {specialty}
                      </span>
                    ))}
                  </div>
                </div>

                {/* Stats */}
                <div className="grid grid-cols-2 gap-2 mb-3 p-2 bg-gray-50 rounded-lg text-center">
                  <div>
                    <p className="text-xs text-gray-500">Price Range</p>
                    <p className="font-semibold text-sm text-gray-900">{barber.priceRange}</p>
                  </div>
                  <div>
                    <p className="text-xs text-gray-500">Total Cuts</p>
                    <p className="font-semibold text-sm text-gray-900">{barber.totalBookings}</p>
                  </div>
                </div>

                {/* Availability */}
                <div className="flex items-center gap-2 mb-3">
                  <Clock className="w-4 h-4 text-green-600" />
                  <span className="text-sm text-green-600 font-medium">{barber.availability}</span>
                </div>

                {/* Action Button */}
                <Button
                  onClick={() => handleSelectBarber(barber)}
                  className="w-full bg-green-600 hover:bg-green-700"
                >
                  <Calendar className="w-4 h-4 mr-2" />
                  Book Now
                </Button>
              </div>
            </Card>
          ))}
        </div>
      </div>

      {/* Booking Modal */}
      {showBookingModal && selectedBarber && (
        <BookingScheduleModal
          barber={selectedBarber}
          customerId={customerId}
          customerName={customerName}
          onClose={() => setShowBookingModal(false)}
          onSuccess={() => {
            setShowBookingModal(false);
            toast.success('Booking request sent!');
          }}
        />
      )}
    </div>
  );
}

/**
 * Barber Profile View Component
 */
interface ProfileViewProps {
  barber: Barber;
  customerId: string;
  customerName: string;
  onBack: () => void;
  onSchedule: () => void;
}

function BarberProfileView({ barber, customerId, customerName, onBack, onSchedule }: ProfileViewProps) {
  return (
    <div className="max-w-2xl mx-auto px-4 py-8">
      <Button onClick={onBack} variant="secondary" size="sm" className="mb-4">
        ← Back to Browse
      </Button>

      <Card className="overflow-hidden">
        {/* Header */}
        <div className="h-60 bg-gradient-to-br from-primary-400 to-primary-400 flex items-center justify-center relative">
          <div className="text-white text-9xl font-bold">
            {barber.name.charAt(0)}
          </div>
          {barber.verified && (
            <div className="absolute top-4 right-4 bg-green-500 text-white px-4 py-2 rounded-full flex items-center gap-2 font-semibold">
              <Award className="w-5 h-5" />
              Verified Barber
            </div>
          )}
        </div>

        {/* Content */}
        <div className="p-8">
          <div className="flex items-start justify-between mb-6">
            <div>
              <h1 className="text-3xl font-bold text-gray-900 mb-2">{barber.name}</h1>
              <div className="flex items-center gap-2 text-gray-600">
                <MapPin className="w-5 h-5" />
                <span className="text-lg">{barber.location}</span>
              </div>
            </div>
            <div className="text-right">
              <p className="text-sm text-gray-500">{barber.totalReviews} reviews</p>
            </div>
          </div>

          {/* Bio */}
          <div className="mb-6">
            <h3 className="font-semibold text-gray-900 mb-2">About</h3>
            <p className="text-gray-700 leading-relaxed">{barber.bio}</p>
            
            {/* Instagram Link - Only show if provided */}
            {barber.instagramHandle && (
              <a
                href={`https://instagram.com/${barber.instagramHandle}`}
                target="_blank"
                rel="noopener noreferrer"
                className="inline-flex items-center gap-2 mt-3 text-sm text-gray-600 hover:text-primary-400 transition-colors"
              >
                <Instagram className="w-4 h-4" />
                <span>@{barber.instagramHandle}</span>
              </a>
            )}
          </div>

          {/* Specialties */}
          <div className="mb-6">
            <h3 className="font-semibold text-gray-900 mb-3">Specialties</h3>
            <div className="flex flex-wrap gap-2">
              {barber.specialties.map((specialty) => (
                <span
                  key={specialty}
                  className="px-4 py-2 bg-primary-100 text-primary-500 rounded-lg font-medium"
                >
                  {specialty}
                </span>
              ))}
            </div>
          </div>

          {/* Stats Grid */}
          <div className="grid grid-cols-3 gap-4 mb-6">
            <div className="p-4 bg-gray-50 rounded-lg text-center">
              <p className="text-2xl font-bold text-gray-900">{barber.totalBookings}</p>
              <p className="text-sm text-gray-600">Total Cuts</p>
            </div>
            <div className="p-4 bg-gray-50 rounded-lg text-center">
              <p className="text-2xl font-bold text-gray-900">{barber.totalReviews}</p>
              <p className="text-sm text-gray-600">Reviews</p>
            </div>
            <div className="p-4 bg-gray-50 rounded-lg text-center">
              <p className="text-2xl font-bold text-gray-900">{barber.avgRating}</p>
              <p className="text-sm text-gray-600">Rating</p>
            </div>
          </div>

          {/* Additional Info */}
          <div className="space-y-3 mb-6 p-4 bg-blue-50 border border-blue-200 rounded-lg">
            <div className="flex items-center gap-3">
              <Clock className="w-5 h-5 text-green-600" />
              <div>
                <p className="font-medium text-gray-900">Availability</p>
                <p className="text-sm text-gray-600">{barber.availability}</p>
              </div>
            </div>
            <div className="flex items-center gap-3">
              <MessageSquare className="w-5 h-5 text-primary-400" />
              <div>
                <p className="font-medium text-gray-900">Response Time</p>
                <p className="text-sm text-gray-600">{barber.responseTime}</p>
              </div>
            </div>
            <div className="flex items-center gap-3">
              <span className="text-2xl">💰</span>
              <div>
                <p className="font-medium text-gray-900">Price Range</p>
                <p className="text-sm text-gray-600">{barber.priceRange}</p>
              </div>
            </div>
          </div>

          {/* Schedule Button */}
          <Button
            onClick={onSchedule}
            className="w-full bg-green-600 hover:bg-green-700 text-lg py-4"
          >
            <Calendar className="w-5 h-5 mr-2" />
            Schedule a Cut with {barber.name}
          </Button>
        </div>
      </Card>
    </div>
  );
}

/**
 * Booking Schedule Modal Component
 */
interface BookingModalProps {
  barber: Barber;
  customerId: string;
  customerName: string;
  onClose: () => void;
  onSuccess: () => void;
}

function BookingScheduleModal({ barber, customerId, customerName, onClose, onSuccess }: BookingModalProps) {
  const [formData, setFormData] = useState({
    serviceType: 'haircut',
    date: '',
    time: '',
    location: 'on-campus',
    locationDetails: '',
    message: '',
  });
  const [loading, setLoading] = useState(false);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setLoading(true);

    try {
      await axios.post('http://localhost:3001/api/booking-requests', {
        customerId,
        barberId: barber.barberId,
        serviceType: formData.serviceType,
        requestedDate: formData.date,
        requestedTime: formData.time,
        price: 30.00, // This should be calculated based on service
        message: formData.message || `Location: ${formData.location}${formData.locationDetails ? ` - ${formData.locationDetails}` : ''}`,
      });

      onSuccess();
    } catch (error) {
      console.error('Failed to send booking request:', error);
      toast.error('Failed to send booking request');
    } finally {
      setLoading(false);
    }
  };

  const getMinDate = () => {
    const tomorrow = new Date();
    tomorrow.setDate(tomorrow.getDate() + 1);
    return tomorrow.toISOString().split('T')[0];
  };

  return (
    <div 
      className="fixed inset-0 min-h-[100dvh] bg-gray-900 bg-opacity-60 flex items-center justify-center z-50 p-4"
      onClick={onClose}
    >
      <Card 
        className="w-full max-w-2xl max-h-[85dvh] sm:max-h-[90vh] overflow-y-auto bg-gray-50 rounded-xl p-6"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-center justify-between mb-6">
          <h2 className="text-2xl font-bold text-gray-900">Schedule with {barber.name}</h2>
          <button
            onClick={onClose}
            className="text-gray-400 hover:text-gray-600 text-2xl"
          >
            ×
          </button>
        </div>

        <form onSubmit={handleSubmit} className="space-y-6">
          {/* Service Type */}
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-2">
              Service Type
            </label>
            <select
              value={formData.serviceType}
              onChange={(e) => setFormData({ ...formData, serviceType: e.target.value })}
              className="w-full px-4 py-3 border border-gray-300 rounded-lg focus:ring-2 focus:ring-primary-500 focus:border-transparent"
              required
            >
              <option value="haircut">Haircut</option>
              <option value="fade">Fade</option>
              <option value="beard-trim">Beard Trim</option>
              <option value="full-service">Full Service (Cut + Beard)</option>
            </select>
          </div>

          {/* Enhanced Date Input */}
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-2">
              Preferred Date
            </label>
            <div 
              className="relative cursor-pointer group"
              onClick={() => {
                const input = document.getElementById('discover-date-picker') as HTMLInputElement;
                if (input) {
                  input.showPicker?.();
                }
              }}
            >
              <div className="absolute inset-0 bg-gradient-to-r from-primary-50 to-green-50 rounded-lg opacity-0 group-hover:opacity-100 transition-opacity pointer-events-none" />
              <div className="relative flex items-center">
                <Calendar className="absolute left-3 w-5 h-5 text-primary-400 pointer-events-none z-10" />
                <input
                  id="discover-date-picker"
                  type="date"
                  value={formData.date}
                  onChange={(e) => setFormData({ ...formData, date: e.target.value })}
                  min={getMinDate()}
                  className="w-full pl-11 pr-4 py-3.5 border-2 border-gray-300 rounded-lg focus:ring-2 focus:ring-primary-400 focus:border-primary-400 hover:border-primary-300 transition-all bg-white cursor-pointer text-gray-700 font-medium"
                  style={{
                    colorScheme: 'light',
                    accentColor: '#708d81',
                  }}
                  required
                />
              </div>
            </div>
          </div>

          {/* Enhanced Time Input */}
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-2">
              Preferred Time
            </label>
            <TimePickerDropdown
              value={formData.time}
              onChange={(value) => setFormData({ ...formData, time: value })}
            />
          </div>

          {/* Location */}
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-2">
              Where should the cut take place?
            </label>
            <select
              value={formData.location}
              onChange={(e) => setFormData({ ...formData, location: e.target.value })}
              className="w-full px-4 py-3 border border-gray-300 rounded-lg focus:ring-2 focus:ring-primary-500 focus:border-transparent mb-2"
              required
            >
              <option value="on-campus">On Campus</option>
              <option value="dorm">My Dorm/Apartment</option>
              <option value="barber-location">Barber's Location</option>
            </select>
            <input
              type="text"
              value={formData.locationDetails}
              onChange={(e) => setFormData({ ...formData, locationDetails: e.target.value })}
              placeholder="Specific location details (e.g., Building name, Room number)"
              className="w-full px-4 py-3 border border-gray-300 rounded-lg focus:ring-2 focus:ring-primary-500 focus:border-transparent"
            />
          </div>

          {/* Message */}
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-2">
              Message to Barber (Optional)
            </label>
            <textarea
              value={formData.message}
              onChange={(e) => setFormData({ ...formData, message: e.target.value })}
              placeholder="Tell the barber what style you're looking for, or any special requests..."
              className="w-full px-4 py-3 border border-gray-300 rounded-lg focus:ring-2 focus:ring-primary-500 focus:border-transparent"
              rows={4}
            />
          </div>

          {/* Info Box */}
          <div className="p-4 bg-blue-50 border border-blue-200 rounded-lg">
            <p className="text-sm text-blue-900">
              <strong>How it works:</strong> Your booking request will be sent to {barber.name}. 
              They'll review your profile and request, then accept or provide alternative times. 
              You'll receive a notification when they respond!
            </p>
          </div>

          {/* Price Estimate */}
          <div className="p-4 bg-gray-50 rounded-lg">
            <div className="flex justify-between items-center">
              <span className="text-gray-700">Estimated Price:</span>
              <span className="text-2xl font-bold text-green-600">{barber.priceRange}</span>
            </div>
            <p className="text-xs text-gray-500 mt-1">Final price confirmed by barber upon acceptance</p>
          </div>

          {/* Actions */}
          <div className="flex gap-3">
            <Button
              type="button"
              onClick={onClose}
              variant="secondary"
              className="flex-1"
              disabled={loading}
            >
              Cancel
            </Button>
            <Button
              type="submit"
              className="flex-1 bg-green-600 hover:bg-green-700"
              disabled={loading}
            >
              {loading ? 'Sending...' : 'Send Request'}
            </Button>
          </div>
        </form>
      </Card>
    </div>
  );
}

