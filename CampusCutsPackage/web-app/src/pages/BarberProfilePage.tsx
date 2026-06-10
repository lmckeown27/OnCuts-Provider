// @ts-nocheck
/**
 * Individual Barber Profile Page
 * 
 * Detailed view of a specific barber with booking capability
 */

import React, { useState, useEffect } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { MapPin, Award, Clock, MessageSquare, Calendar, ArrowLeft, Instagram } from 'lucide-react';
import Button from '../components/Button';
import Card from '../components/Card';
import TimePickerDropdown from '../components/TimePickerDropdown';
import { LocationSelector } from '../components/LocationSelector';
import barberService from '../services/barber.service';
import toast from 'react-hot-toast';

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

export default function BarberProfilePage() {
  const { barberId } = useParams<{ barberId: string }>();
  const navigate = useNavigate();
  const [barber, setBarber] = useState<Barber | null>(null);
  const [loading, setLoading] = useState(true);
  const [showBookingModal, setShowBookingModal] = useState(false);

  // Get current user from context/props - for now using mock
  const currentUser = {
    id: 'user-temp',
    name: 'Current User',
  };

  useEffect(() => {
    fetchBarber();
  }, [barberId]);

  const fetchBarber = async () => {
    try {
      if (!barberId) {
        toast.error('No barber ID provided');
        setLoading(false);
        return;
      }

      // Fetch real barber data from API
      const response = await barberService.getBarberById(barberId);
      const b = response;
      
      const barberData: Barber = {
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
      };

      setBarber(barberData);
      setLoading(false);
    } catch (error) {
      console.error('Failed to fetch barber:', error);
      toast.error('Failed to load barber profile');
      setLoading(false);
    }
  };

  const handleSchedule = () => {
    setShowBookingModal(true);
  };

  if (loading) {
    return (
      <div className="min-h-screen bg-gradient-to-br from-primary-50 to-primary-50 flex items-center justify-center">
        <div className="text-center">
          <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-primary-400 mx-auto"></div>
          <p className="mt-4 text-gray-600">Loading barber profile...</p>
        </div>
      </div>
    );
  }

  if (!barber) {
    return (
      <div className="min-h-screen bg-gradient-to-br from-primary-50 to-primary-50 flex items-center justify-center p-4">
        <Card className="text-center max-w-md">
          <p className="text-gray-600">Barber not found</p>
          <Button onClick={() => navigate('/discover')} className="mt-4">
            Browse Barbers
          </Button>
        </Card>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-gradient-to-br from-primary-50 to-primary-50">
      <div className="max-w-2xl mx-auto px-4 py-8">
        <Button onClick={() => navigate(-1)} variant="secondary" size="sm" className="mb-4">
          <ArrowLeft className="w-4 h-4 mr-2" />
          Back
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
                Verified
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
              onClick={handleSchedule}
              className="w-full bg-green-600 hover:bg-green-700 text-lg py-4"
            >
              <Calendar className="w-5 h-5 mr-2" />
              Schedule a Cut with {barber.name}
            </Button>
          </div>
        </Card>
      </div>

      {/* Booking Modal */}
      {showBookingModal && (
        <BookingScheduleModal
          barber={barber}
          customerId={currentUser.id}
          customerName={currentUser.name}
          onClose={() => setShowBookingModal(false)}
          onSuccess={() => {
            setShowBookingModal(false);
            toast.success('Booking request sent!');
            navigate('/discover');
          }}
        />
      )}
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
    locationId: '',
    locationName: '',
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
        locationId: formData.locationId,
        price: 30.00,
        message: formData.message || `Location: ${formData.locationName}`,
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
                const input = document.getElementById('booking-date-picker') as HTMLInputElement;
                if (input) {
                  input.showPicker?.();
                }
              }}
            >
              <div className="absolute inset-0 bg-gradient-to-r from-primary-50 to-green-50 rounded-lg opacity-0 group-hover:opacity-100 transition-opacity pointer-events-none" />
              <div className="relative flex items-center">
                <Calendar className="absolute left-3 w-5 h-5 text-primary-400 pointer-events-none z-10" />
                <input
                  id="booking-date-picker"
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

          {/* Time Input */}
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
            <LocationSelector
              universityId={barber.universityId || 'calpoly-slo'} 
              selectedLocationId={formData.locationId}
              onLocationSelect={(locationId, locationName) => {
                setFormData({ ...formData, locationId, locationName });
              }}
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

