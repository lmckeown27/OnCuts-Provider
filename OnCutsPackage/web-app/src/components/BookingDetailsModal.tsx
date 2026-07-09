/**
 * BookingDetailsModal - In-depth booking details popup for barbers
 * Allows viewing all booking details and editing/cancelling bookings
 */
import { useState, useEffect, useCallback } from 'react';
import { useNavigate } from 'react-router-dom';
import { 
  X, Calendar, Clock, MapPin, User, DollarSign, FileText, 
  Pencil, Trash2, Check, AlertTriangle, Star, MessageSquare,
  Phone, Mail, Save, RotateCcw
} from 'lucide-react';
import api from '../services/api.service';
import barberService from '../services/barber.service';
import toast from 'react-hot-toast';
import DatePicker from './DatePicker';
import AvailableTimePickerDropdown from './AvailableTimePickerDropdown';
import type { Barber } from '../types';

interface BookingDetailsModalProps {
  isOpen: boolean;
  onClose: () => void;
  booking: any;
  onBookingUpdated?: () => void;
  isAdmin?: boolean;
}

export default function BookingDetailsModal({ 
  isOpen, 
  onClose, 
  booking, 
  onBookingUpdated,
  isAdmin = false
}: BookingDetailsModalProps) {
  const navigate = useNavigate();
  const [isEditing, setIsEditing] = useState(false);
  const [isDeleting, setIsDeleting] = useState(false);
  const [isRemoving, setIsRemoving] = useState(false);
  const [isUndoingComplete, setIsUndoingComplete] = useState(false);
  const [isSaving, setIsSaving] = useState(false);
  const [cancelReason, setCancelReason] = useState('');
  
  // Animation states for smooth open/close
  const [isVisible, setIsVisible] = useState(false);
  const [shouldRender, setShouldRender] = useState(false);
  const [isClosing, setIsClosing] = useState(false);
  
  // Handle mount/unmount with animation
  useEffect(() => {
    if (isOpen && !isClosing) {
      setShouldRender(true);
      // Small delay to trigger CSS transition after mount
      requestAnimationFrame(() => {
        requestAnimationFrame(() => {
          setIsVisible(true);
        });
      });
    } else if (!isOpen) {
      setIsVisible(false);
      setIsClosing(false);
      // Wait for animation to complete before unmounting
      const timer = setTimeout(() => {
        setShouldRender(false);
      }, 200); // Match transition duration
      return () => clearTimeout(timer);
    }
  }, [isOpen, isClosing]);
  
  // Smooth close handler - animates out before calling onClose
  const handleClose = useCallback(() => {
    if (isClosing) return;
    setIsClosing(true);
    setIsVisible(false);
    // Wait for animation to complete before notifying parent
    setTimeout(() => {
      onClose();
      setIsClosing(false);
      // Reset to details view so modal opens in default state next time
      setIsEditing(false);
      setIsDeleting(false);
      setIsRemoving(false);
    }, 200);
  }, [isClosing, onClose]);
  
  // Editable fields (notes are read-only - set by consumer)
  const [editDate, setEditDate] = useState(''); // YYYY-MM-DD format for DatePicker
  const [editTime, setEditTime] = useState(''); // HH:MM (24-hour)
  const [editLocation, setEditLocation] = useState('');
  
  // Barber data for edit form (weekly_schedule, service_locations)
  const [editBarber, setEditBarber] = useState<Barber | null>(null);
  const [isLoadingBarber, setIsLoadingBarber] = useState(false);

  // Parse HH:MM (24-hour) to hours and minutes
  const parseTimeInput = (timeStr: string): { hours: number; minutes: number } | null => {
    const [hourStr, minuteStr] = timeStr.split(':');
    const hours = parseInt(hourStr);
    const minutes = parseInt(minuteStr);
    if (isNaN(hours) || isNaN(minutes)) return null;
    if (hours < 0 || hours > 23) return null;
    if (minutes < 0 || minutes > 59) return null;
    return { hours, minutes };
  };

  // Initialize editable fields when booking changes
  useEffect(() => {
    if (booking) {
      const scheduledTime = new Date(booking.scheduledTime);
      
      // Format date as YYYY-MM-DD for DatePicker
      const year = scheduledTime.getFullYear();
      const month = String(scheduledTime.getMonth() + 1).padStart(2, '0');
      const day = String(scheduledTime.getDate()).padStart(2, '0');
      setEditDate(`${year}-${month}-${day}`);
      
      // Format time as HH:MM (24-hour)
      const hours = String(scheduledTime.getHours()).padStart(2, '0');
      const minutes = String(scheduledTime.getMinutes()).padStart(2, '0');
      setEditTime(`${hours}:${minutes}`);
      
      setEditLocation(booking.location || '');
    }
  }, [booking]);

  // Fetch barber data (including weekly_schedule and service_locations) when editing starts
  useEffect(() => {
    const fetchBarberData = async () => {
      // Get barber ID from booking (try recordId first, then barberId)
      const barberId = booking?.barber?.recordId || booking?.barberId;
      if (!barberId || !isEditing) return;
      
      setIsLoadingBarber(true);
      try {
        const barber = await barberService.getBarberById(barberId);
        setEditBarber(barber);
        
        // If barber has service locations and current location matches one, keep it
        // Otherwise auto-select primary location
        if (barber.service_locations && barber.service_locations.length > 0) {
          const currentLocationMatch = barber.service_locations.find(
            loc => loc.name === editLocation
          );
          if (!currentLocationMatch) {
            const primaryLocation = barber.service_locations.find(loc => loc.is_primary);
            if (primaryLocation) {
              setEditLocation(primaryLocation.name);
            }
          }
        }
      } catch (error) {
        console.error('Failed to fetch barber data:', error);
      } finally {
        setIsLoadingBarber(false);
      }
    };
    
    if (isEditing && booking) {
      fetchBarberData();
    }
  }, [isEditing, booking]);

  // All hooks must be called before any early returns
  const handleSaveChanges = useCallback(async () => {
    if (!booking) return;
    
    // Validate date format (YYYY-MM-DD from DatePicker)
    if (!editDate) {
      toast.error('Please select a date');
      return;
    }
    
    const [yearStr, monthStr, dayStr] = editDate.split('-');
    const year = parseInt(yearStr);
    const month = parseInt(monthStr);
    const day = parseInt(dayStr);
    
    if (isNaN(year) || isNaN(month) || isNaN(day)) {
      toast.error('Please select a valid date');
      return;
    }

    // Validate time format (HH:MM from dropdown)
    const timeParts = parseTimeInput(editTime);
    if (!timeParts) {
      toast.error('Please select a valid time');
      return;
    }

    setIsSaving(true);
    try {
      // Combine date and time into scheduledTime
      const newScheduledTime = new Date(
        year,
        month - 1, // months are 0-indexed
        day,
        timeParts.hours,
        timeParts.minutes
      );
      
      await api.put(`/bookings-simple/${booking.id}`, {
        scheduledTime: newScheduledTime.toISOString(),
        location: editLocation || null,
      });

      toast.success('Booking updated successfully!');
      setIsEditing(false);
      onBookingUpdated?.();
    } catch (error: any) {
      console.error('Failed to update booking:', error);
      toast.error(error.message || 'Failed to update booking');
    } finally {
      setIsSaving(false);
    }
  }, [editDate, editTime, editLocation, booking, onBookingUpdated]);

  // Handle Enter key to save changes
  const handleKeyDown = useCallback((e: React.KeyboardEvent) => {
    if (e.key === 'Enter' && isEditing && !isSaving) {
      e.preventDefault();
      handleSaveChanges();
    }
  }, [isEditing, isSaving, handleSaveChanges]);

  // Early return AFTER all hooks
  if (!shouldRender || !booking) return null;

  const scheduledTime = new Date(booking.scheduledTime);
  const formattedDate = scheduledTime.toLocaleDateString('en-US', { 
    weekday: 'long', 
    year: 'numeric', 
    month: 'long', 
    day: 'numeric' 
  });
  const formattedTime = scheduledTime.toLocaleTimeString('en-US', { 
    hour: 'numeric', 
    minute: '2-digit',
    hour12: true 
  });

  const formatPrice = (cents: number) => `$${(cents / 100).toFixed(2)}`;
  
  const getStatusColor = (status: string) => {
    switch (status) {
      case 'ACCEPTED': return 'bg-blue-100 text-blue-700';
      case 'COMPLETED': return 'bg-green-100 text-green-700';
      case 'CANCELLED': return 'bg-red-100 text-red-700';
      case 'PENDING': return 'bg-yellow-100 text-yellow-700';
      default: return 'bg-gray-100 text-gray-700';
    }
  };

  const handleCancelBooking = async () => {
    setIsSaving(true);
    try {
      await api.delete(`/bookings-simple/${booking.id}`, {
        reason: cancelReason || undefined,
      });

      toast.success('Booking cancelled successfully');
      setIsDeleting(false);
      handleClose();
      onBookingUpdated?.();
    } catch (error: any) {
      console.error('Failed to cancel booking:', error);
      toast.error(error.message || 'Failed to cancel booking');
    } finally {
      setIsSaving(false);
    }
  };

  const handleRemoveBooking = async () => {
    setIsSaving(true);
    try {
      await api.delete(`/bookings-simple/${booking.id}`);

      toast.success('Booking removed from schedule');
      setIsRemoving(false);
      handleClose();
      onBookingUpdated?.();
    } catch (error: any) {
      console.error('Failed to remove booking:', error);
      toast.error(error.message || 'Failed to remove booking');
    } finally {
      setIsSaving(false);
    }
  };

  const handleUndoComplete = async () => {
    setIsSaving(true);
    try {
      await api.put(`/bookings-simple/${booking.id}/undo-complete`, {});

      toast.success('Booking reverted to accepted');
      setIsUndoingComplete(false);
      handleClose();
      onBookingUpdated?.();
    } catch (error: any) {
      console.error('Failed to undo complete:', error);
      toast.error(error.message || 'Failed to undo completion');
    } finally {
      setIsSaving(false);
    }
  };

  const handleCompleteBooking = async () => {
    try {
      // Request payment from consumer - this sends them a notification
      await api.post(`/bookings-simple/${booking.id}/request-payment`, {});
      toast.success('Payment request sent to customer');
      handleClose();
      // Navigate to barber's payment waiting page
      navigate(`/web/payment/${booking.id}`);
    } catch (error: any) {
      console.error('Failed to request payment:', error);
      toast.error(error.message || 'Failed to request payment');
    }
  };

  const canEdit = booking.status === 'ACCEPTED';
  const canCancel = booking.status === 'ACCEPTED' || booking.status === 'PENDING';
  const canComplete = booking.status === 'ACCEPTED';
  const canRemove = isAdmin && (booking.status === 'COMPLETED' || booking.status === 'PAID');
  const canUndoComplete = booking.status === 'COMPLETED';

  return (
    <div
      className={`fixed inset-0 min-h-[100dvh] z-[60] flex items-start justify-center p-2 pt-8 sm:pt-4 sm:items-center sm:p-4 overflow-y-auto transition-all duration-200 ease-out ${
        isVisible ? 'bg-black/50' : 'bg-black/0'
      }`}
      onClick={handleClose}
    >
      <div
        className={`bg-white rounded-2xl shadow-2xl max-w-lg w-full max-h-[88dvh] sm:max-h-[90vh] overflow-hidden transition-all duration-200 ease-out ${
          isVisible 
            ? 'opacity-100 scale-100 translate-y-0' 
            : 'opacity-0 scale-95 translate-y-4'
        }`}
        onClick={(e) => e.stopPropagation()}
      >
        {/* Header */}
        <div className="bg-gradient-to-r from-primary-600 to-primary-500 px-6 py-4 flex items-center justify-between">
          <div>
            <h2 className="text-xl font-bold text-white">Booking Details</h2>
            <span className={`inline-block mt-1 px-2 py-0.5 rounded-full text-xs font-semibold ${getStatusColor(booking.status)}`}>
              {booking.status}
            </span>
          </div>
          <button
            onClick={handleClose}
            className="text-white hover:bg-white/20 rounded-full p-2 transition-colors"
          >
            <X className="w-6 h-6" />
          </button>
        </div>

        <div className="p-6 overflow-y-auto max-h-[calc(92dvh-80px)] sm:max-h-[calc(90vh-80px)]">
          {/* Delete Confirmation View */}
          {isDeleting ? (
            <div className="space-y-4">
              <div className="flex items-center gap-3 p-4 bg-red-50 rounded-xl border border-red-200">
                <AlertTriangle className="w-8 h-8 text-red-500 flex-shrink-0" />
                <div>
                  <h3 className="font-bold text-red-800">Cancel this booking?</h3>
                  <p className="text-sm text-red-600">
                    The customer will be notified. This action cannot be undone.
                  </p>
                </div>
              </div>

              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">
                  Reason for cancellation (optional)
                </label>
                <textarea
                  value={cancelReason}
                  onChange={(e) => setCancelReason(e.target.value)}
                  placeholder="e.g., Schedule conflict, emergency..."
                  className="w-full px-4 py-3 border border-gray-300 rounded-lg focus:ring-2 focus:ring-red-400 focus:border-transparent resize-none"
                  rows={3}
                />
              </div>

              <div className="flex gap-3 pb-4 sm:pb-0">
                <button
                  onClick={() => setIsDeleting(false)}
                  className="flex-1 py-3 text-gray-700 bg-gray-100 hover:bg-gray-200 rounded-xl font-semibold transition-colors"
                  disabled={isSaving}
                >
                  Keep Booking
                </button>
                <button
                  onClick={handleCancelBooking}
                  disabled={isSaving}
                  className="flex-1 py-3 bg-red-500 hover:bg-red-600 text-white rounded-xl font-semibold transition-colors flex items-center justify-center gap-2"
                >
                  {isSaving ? (
                    <>
                      <div className="w-4 h-4 border-2 border-white/30 border-t-white rounded-full animate-spin" />
                      Cancelling...
                    </>
                  ) : (
                    <>
                      <Trash2 className="w-4 h-4" />
                      Cancel
                    </>
                  )}
                </button>
              </div>
            </div>
          ) : isEditing ? (
            /* Edit View - matches consumer edit booking UI */
            <div className="space-y-4">
              <h3 className="text-xl font-bold text-gray-900 flex items-center gap-2">
                <Pencil className="w-5 h-5 text-primary-500" />
                Edit Booking
              </h3>

              {/* Date Picker - shows calendar with barber's availability */}
              {isLoadingBarber ? (
                <div className="flex items-center justify-center py-8">
                  <div className="w-6 h-6 border-2 border-primary-200 border-t-primary-500 rounded-full animate-spin" />
                  <span className="ml-2 text-gray-500 text-sm">Loading availability...</span>
                </div>
              ) : (
                <DatePicker
                  label="Date"
                  value={editDate}
                  onChange={(newDate) => {
                    setEditDate(newDate);
                    // Reset time when date changes since availability may differ
                    setEditTime('');
                  }}
                  minDate={new Date().toISOString().split('T')[0]}
                  weeklySchedule={editBarber?.weekly_schedule}
                />
              )}

              {/* Time Picker - shows available times for selected date */}
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">Time</label>
                <AvailableTimePickerDropdown
                  barberId={booking.barber?.recordId || booking.barberId}
                  date={editDate}
                  value={editTime}
                  onChange={setEditTime}
                />
              </div>

              {/* Location - dropdown if barber has service locations */}
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">Location</label>
                {editBarber?.service_locations && editBarber.service_locations.length > 0 ? (
                  <select
                    value={editLocation}
                    onChange={(e) => setEditLocation(e.target.value)}
                    className="w-full px-4 py-3 border border-gray-300 rounded-lg focus:ring-2 focus:ring-primary-400 focus:border-transparent bg-white"
                  >
                    <option value="">Select a location</option>
                    {editBarber.service_locations.map((location) => (
                      <option key={location.id} value={location.name}>
                        {location.name}{location.is_primary ? ' (Primary)' : ''}
                      </option>
                    ))}
                  </select>
                ) : (
                  <input
                    type="text"
                    value={editLocation}
                    onChange={(e) => setEditLocation(e.target.value)}
                    placeholder="Enter location..."
                    className="w-full px-4 py-3 border border-gray-300 rounded-lg focus:ring-2 focus:ring-primary-400 focus:border-transparent"
                  />
                )}
              </div>

              {/* Consumer Notes - Read-only display */}
              {booking.notes && (
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-1">Customer Notes</label>
                  <div className="w-full px-4 py-3 bg-gray-100 border border-gray-200 rounded-lg text-gray-700 italic">
                    "{booking.notes}"
                  </div>
                </div>
              )}

              {/* Action Buttons */}
              <div className="flex gap-3 mt-6">
                <button
                  type="button"
                  onClick={() => setIsEditing(false)}
                  className="flex-1 py-3 bg-gray-100 hover:bg-gray-200 text-gray-700 font-semibold rounded-xl transition-colors"
                  disabled={isSaving}
                >
                  Cancel
                </button>
                <button
                  onClick={handleSaveChanges}
                  disabled={isSaving}
                  className="flex-1 py-3 bg-primary-500 hover:bg-primary-600 text-white font-semibold rounded-xl transition-colors flex items-center justify-center gap-2 disabled:opacity-50"
                >
                  {isSaving ? (
                    <>
                      <div className="w-4 h-4 border-2 border-white/30 border-t-white rounded-full animate-spin" />
                      Saving...
                    </>
                  ) : (
                    'Save Changes'
                  )}
                </button>
              </div>
            </div>
          ) : (
            /* View Mode */
            <div className="space-y-5">
              {/* Customer Info */}
              <div className="flex items-center gap-4 p-4 bg-gray-50 rounded-xl">
                <div className="w-14 h-14 rounded-full bg-primary-100 flex items-center justify-center overflow-hidden">
                  {(booking.consumer?.avatar || booking.consumer?.profileImageUrl) ? (
                    <img 
                      src={booking.consumer.avatar || booking.consumer.profileImageUrl} 
                      alt="Customer" 
                      className="w-14 h-14 rounded-full object-cover"
                    />
                  ) : (
                    <User className="w-7 h-7 text-primary-600" />
                  )}
                </div>
                <div className="flex-1">
                  <h3 className="font-bold text-gray-900 text-lg">
                    {booking.consumer?.firstName} {booking.consumer?.lastName}
                  </h3>
                  {booking.consumer?.email && (
                    <p className="text-sm text-gray-500 flex items-center gap-1">
                      <Mail className="w-3 h-3" />
                      {booking.consumer.email}
                    </p>
                  )}
                  {booking.consumer?.phone && (
                    <p className="text-sm text-gray-500 flex items-center gap-1">
                      <Phone className="w-3 h-3" />
                      {booking.consumer.phone}
                    </p>
                  )}
                </div>
              </div>

              {/* Service Details */}
              <div className="space-y-3">
                <h4 className="font-semibold text-gray-700 text-sm uppercase tracking-wide">Service</h4>
                <div className="flex items-center justify-between p-3 bg-primary-50 rounded-lg border border-primary-100">
                  <span className="font-semibold text-gray-900">
                    {booking.serviceName || booking.serviceType}
                  </span>
                  <span className="font-bold text-primary-600 text-lg">
                    {formatPrice(booking.priceUsdCents)}
                  </span>
                </div>
              </div>

              {/* Date & Time */}
              <div className="space-y-3">
                <h4 className="font-semibold text-gray-700 text-sm uppercase tracking-wide">When</h4>
                <div className="grid grid-cols-2 gap-3">
                  <div className="flex items-center gap-3 p-3 bg-gray-50 rounded-lg">
                    <Calendar className="w-5 h-5 text-primary-500" />
                    <div>
                      <p className="text-xs text-gray-500">Date</p>
                      <p className="font-semibold text-gray-900">{formattedDate}</p>
                    </div>
                  </div>
                  <div className="flex items-center gap-3 p-3 bg-gray-50 rounded-lg">
                    <Clock className="w-5 h-5 text-primary-500" />
                    <div>
                      <p className="text-xs text-gray-500">Time</p>
                      <p className="font-semibold text-gray-900">{formattedTime}</p>
                    </div>
                  </div>
                </div>
              </div>

              {/* Location */}
              {booking.location && (
                <div className="space-y-3">
                  <h4 className="font-semibold text-gray-700 text-sm uppercase tracking-wide">Where</h4>
                  <div className="flex items-center gap-3 p-3 bg-gray-50 rounded-lg">
                    <MapPin className="w-5 h-5 text-primary-500 flex-shrink-0" />
                    <p className="font-medium text-gray-900">{booking.location}</p>
                  </div>
                </div>
              )}

              {/* Notes */}
              {booking.notes && (
                <div className="space-y-3">
                  <h4 className="font-semibold text-gray-700 text-sm uppercase tracking-wide">Notes</h4>
                  <div className="flex items-start gap-3 p-3 bg-gray-50 rounded-lg">
                    <FileText className="w-5 h-5 text-primary-500 flex-shrink-0 mt-0.5" />
                    <p className="text-gray-700 italic">"{booking.notes}"</p>
                  </div>
                </div>
              )}

              {/* Review (for completed/paid bookings) */}
              {/* Handle both formats: booking.reviewRating OR booking.review.rating */}
              {(booking.status === 'COMPLETED' || booking.status === 'PAID') && (booking.reviewRating || booking.review?.rating) && (
                <div className="space-y-3">
                  <h4 className="font-semibold text-gray-700 text-sm uppercase tracking-wide">Customer Feedback</h4>
                  <div className="p-4 bg-yellow-50 rounded-xl border border-yellow-100">
                    <div className="flex items-center gap-1 mb-2">
                      {[1, 2, 3, 4, 5].map(star => (
                        <Star
                          key={star}
                          className={`w-5 h-5 ${star <= (booking.reviewRating || booking.review?.rating) ? 'text-yellow-400 fill-yellow-400' : 'text-gray-300'}`}
                        />
                      ))}
                      <span className="ml-2 font-semibold text-gray-700">
                        {(booking.reviewRating || booking.review?.rating)?.toFixed(1)}
                      </span>
                    </div>
                    {(booking.reviewComment || booking.review?.comment) && (
                      <p className="text-gray-700 italic">"{booking.reviewComment || booking.review?.comment}"</p>
                    )}
                  </div>
                </div>
              )}

              {/* Payment Info (for completed/paid bookings) */}
              {(booking.status === 'COMPLETED' || booking.status === 'PAID') && booking.paidAt && (
                <div className="space-y-3">
                  <h4 className="font-semibold text-gray-700 text-sm uppercase tracking-wide">Payment</h4>
                  <div className="p-4 bg-primary-50 rounded-xl border border-primary-100">
                    <div className="flex items-center justify-between">
                      <div className="flex items-center gap-2">
                        <DollarSign className="w-5 h-5 text-primary-600" />
                        <span className="font-medium text-gray-700">Total Paid</span>
                      </div>
                      <span className="font-bold text-primary-600 text-lg">
                        {formatPrice(booking.totalPaidCents || booking.priceUsdCents)}
                      </span>
                    </div>
                    {booking.tipAmountCents > 0 && (
                      <div className="flex items-center justify-between mt-2 pt-2 border-t border-primary-200">
                        <span className="text-sm text-gray-600">Includes tip</span>
                        <span className="font-semibold text-primary-600">
                          +{formatPrice(booking.tipAmountCents)}
                        </span>
                      </div>
                    )}
                  </div>
                </div>
              )}

              {/* Booking Reference */}
              <div className="text-center pt-2 pb-6">
                <p className="text-xs text-gray-400">Booking Reference</p>
                <p className="font-mono text-sm text-gray-600 font-medium">
                  {booking.id.slice(0, 8).toUpperCase()}
                </p>
              </div>

              {/* Action Buttons */}
              {(canComplete || canEdit || canCancel) && (
                <div className="space-y-3 pt-4 border-t border-gray-100">
                  {/* Complete & Message Buttons */}
                  {canComplete && (
                    <div className="flex gap-3">
                    <button
                      onClick={handleCompleteBooking}
                        className="flex-1 py-3 bg-green-500 hover:bg-green-600 text-white rounded-xl font-semibold transition-colors"
                    >
                      Request Payment
                    </button>
                      <button
                        onClick={() => {
                          if (booking.conversationId) {
                            navigate(`/web/barber/messages/${booking.conversationId}`);
                          } else {
                            // Navigate to messages page - it will find/show the conversation
                            navigate('/web/barber/messages');
                          }
                        }}
                        className="flex-1 py-3 bg-primary-500 hover:bg-primary-600 text-white rounded-xl font-semibold transition-colors flex items-center justify-center gap-2"
                      >
                        <MessageSquare className="w-4 h-4" />
                        Message
                      </button>
                    </div>
                  )}
                  
                  {/* Edit & Cancel Buttons */}
                  {(canEdit || canCancel) && (
                    <div className="flex gap-3 pb-4 sm:pb-0">
                      {canEdit && (
                        <button
                          onClick={() => setIsEditing(true)}
                          className="flex-1 py-3 bg-amber-50 hover:bg-amber-100 text-amber-700 rounded-xl font-semibold transition-colors flex items-center justify-center gap-2 border border-amber-200"
                        >
                          <Pencil className="w-4 h-4" />
                          Edit Booking
                        </button>
                      )}
                      {canCancel && (
                        <button
                          onClick={() => setIsDeleting(true)}
                          className="flex-1 py-3 bg-red-50 hover:bg-red-100 text-red-600 rounded-xl font-semibold transition-colors flex items-center justify-center gap-2 border border-red-200"
                        >
                          <Trash2 className="w-4 h-4" />
                          Cancel Booking
                        </button>
                      )}
                    </div>
                  )}
                </div>
              )}

              {/* Undo Complete Button (for COMPLETED bookings awaiting payment) */}
              {canUndoComplete && !isUndoingComplete && !isRemoving && (
                <div className="pt-4 border-t border-gray-100 pb-4 sm:pb-0 space-y-3">
                  <p className="text-sm text-gray-500 text-center">
                    Marked as complete by mistake?
                  </p>
                  <button
                    onClick={() => setIsUndoingComplete(true)}
                    className="w-full py-3 bg-primary-500 hover:bg-primary-600 text-white rounded-xl font-semibold transition-colors shadow-sm"
                  >
                    Undo Complete
                  </button>
                </div>
              )}

              {/* Undo Complete Confirmation */}
              {isUndoingComplete && (
                <div className="pt-4 border-t border-gray-100 space-y-4 pb-4 sm:pb-0">
                  <div className="p-4 bg-primary-50 rounded-xl border border-primary-200">
                    <h3 className="font-semibold text-gray-800">Undo completion?</h3>
                    <p className="text-sm text-gray-600">
                      This will revert the booking to accepted status.
                    </p>
                  </div>
                  <div className="flex gap-3">
                    <button
                      onClick={() => setIsUndoingComplete(false)}
                      className="flex-1 py-3 text-gray-700 bg-gray-100 hover:bg-gray-200 rounded-xl font-semibold transition-colors"
                      disabled={isSaving}
                    >
                      Cancel
                    </button>
                    <button
                      onClick={handleUndoComplete}
                      disabled={isSaving}
                      className="flex-1 py-3 bg-primary-500 hover:bg-primary-600 text-white rounded-xl font-semibold transition-colors flex items-center justify-center gap-2"
                    >
                      {isSaving ? (
                        <>
                          <div className="w-4 h-4 border-2 border-white/30 border-t-white rounded-full animate-spin" />
                          Reverting...
                        </>
                      ) : (
                        'Undo'
                      )}
                    </button>
                  </div>
                </div>
              )}

              {/* Remove from Schedule Button (for completed bookings) */}
              {canRemove && !isRemoving && !isUndoingComplete && (
                <div className="pt-4 border-t border-gray-100 pb-4 sm:pb-0">
                  <button
                    onClick={() => setIsRemoving(true)}
                    className="w-full py-3 bg-gray-100 hover:bg-gray-200 text-gray-600 rounded-xl font-semibold transition-colors"
                  >
                    Remove from Schedule
                  </button>
                </div>
              )}

              {/* Remove Confirmation */}
              {isRemoving && !isUndoingComplete && (
                <div className="pt-4 border-t border-gray-100 space-y-4 pb-4 sm:pb-0">
                  <div className="flex items-center gap-3 p-4 bg-gray-50 rounded-xl border border-gray-200">
                    <AlertTriangle className="w-6 h-6 text-gray-500 flex-shrink-0" />
                    <div>
                      <h3 className="font-semibold text-gray-800">Remove this booking?</h3>
                      <p className="text-sm text-gray-600">
                        This will permanently remove this booking from your schedule.
                      </p>
                    </div>
                  </div>
                  <div className="flex gap-3">
                    <button
                      onClick={() => setIsRemoving(false)}
                      className="flex-1 py-3 text-gray-700 bg-gray-100 hover:bg-gray-200 rounded-xl font-semibold transition-colors"
                      disabled={isSaving}
                    >
                      Keep
                    </button>
                    <button
                      onClick={handleRemoveBooking}
                      disabled={isSaving}
                      className="flex-1 py-3 bg-red-500 hover:bg-red-600 text-white rounded-xl font-semibold transition-colors flex items-center justify-center gap-2"
                    >
                      {isSaving ? (
                        <>
                          <div className="w-4 h-4 border-2 border-white/30 border-t-white rounded-full animate-spin" />
                          Removing...
                        </>
                      ) : (
                        <>
                          <Trash2 className="w-4 h-4" />
                          Remove
                        </>
                      )}
                    </button>
                  </div>
                </div>
              )}
            </div>
          )}
        </div>
      </div>
    </div>
  );
}

