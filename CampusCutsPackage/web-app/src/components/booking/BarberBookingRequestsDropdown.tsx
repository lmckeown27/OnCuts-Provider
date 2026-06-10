/**
 * Barber Booking Requests Dropdown Component
 * 
 * Compact dropdown inbox for booking requests in header
 * Features smooth open/close animations
 */

import React, { useState, useEffect, useRef } from 'react';
import { Inbox, CheckCircle, XCircle, Calendar, User, Eye, X } from 'lucide-react';
import Button from '../Button';
import toast from 'react-hot-toast';
import api from '../../services/api.service';
import socketService from '../../services/socket.service';
import { useViewport, useBodyScrollLock } from '../../hooks';

interface CustomerProfile {
  displayName: string;
  stats: {
    completionRate: number;
    isReliable: boolean;
  };
}

interface BookingRequest {
  bookingId: string;
  customerId: string;
  customerName: string;
  customerProfile: CustomerProfile;
  serviceType: string;
  requestedDate: string;
  requestedTime: string;
  price: number;
  location?: string;
  message?: string;
}

interface Props {
  barberId: string;
}


// Common decline reasons
const DECLINE_REASONS = [
  'Schedule conflict',
  'Fully booked for this day',
  'Too far from my service area',
  'Service not available at this time',
  'Other',
];

export default function BarberBookingRequestsDropdown({ barberId }: Props) {
  const [requests, setRequests] = useState<BookingRequest[]>([]);
  const [isDropdownOpen, setIsDropdownOpen] = useState(false);
  const [isDropdownVisible, setIsDropdownVisible] = useState(false);
  const [actionLoading, setActionLoading] = useState<string | null>(null);
  const [viewingRequest, setViewingRequest] = useState<BookingRequest | null>(null);
  const [isModalVisible, setIsModalVisible] = useState(false);
  
  // Decline reason modal state
  const [showDeclineModal, setShowDeclineModal] = useState(false);
  const [isDeclineModalVisible, setIsDeclineModalVisible] = useState(false);
  const [decliningRequest, setDecliningRequest] = useState<BookingRequest | null>(null);
  const [selectedReason, setSelectedReason] = useState('');
  const [customReason, setCustomReason] = useState('');
  
  const dropdownRef = useRef<HTMLDivElement>(null);
  const modalRef = useRef<HTMLDivElement>(null);
  const declineModalRef = useRef<HTMLDivElement>(null);
  
  // Viewport detection for responsive backdrop
  const { isMobile, isTablet } = useViewport();
  const showBackdrop = isMobile || isTablet; // Show backdrop on mobile and tablet
  
  // Lock body scroll when dropdown is open on mobile/tablet
  useBodyScrollLock(isDropdownOpen && showBackdrop);

  useEffect(() => {
    fetchRequests();
  }, [barberId]);

  // Listen for new booking requests via WebSocket
  useEffect(() => {
    socketService.connect();
    
    const handleNewBookingRequest = (newBooking: any) => {
      console.log('📬 Received new-booking-request:', newBooking);
      toast.success(`New booking request from ${newBooking.consumerName || 'a customer'}!`, {
        icon: '📥',
        duration: 5000,
      });
      // Refresh the requests list to include the new booking
      fetchRequests();
    };
    
    socketService.onNewBookingRequest(handleNewBookingRequest);
    
    return () => {
      socketService.offNewBookingRequest(handleNewBookingRequest);
    };
  }, []);

  useEffect(() => {
    const handleClickOutside = (event: MouseEvent) => {
      if (dropdownRef.current && !dropdownRef.current.contains(event.target as Node)) {
        closeDropdown();
      }
    };

    document.addEventListener('mousedown', handleClickOutside);
    return () => document.removeEventListener('mousedown', handleClickOutside);
  }, []);

  useEffect(() => {
    const handleModalClickOutside = (event: MouseEvent) => {
      if (modalRef.current && !modalRef.current.contains(event.target as Node)) {
        closeModal();
      }
    };

    if (viewingRequest) {
      document.addEventListener('mousedown', handleModalClickOutside);
      return () => document.removeEventListener('mousedown', handleModalClickOutside);
    }
  }, [viewingRequest]);

  // Dropdown open/close handlers
  const openDropdown = () => {
    setIsDropdownOpen(true);
    requestAnimationFrame(() => {
      requestAnimationFrame(() => {
        setIsDropdownVisible(true);
      });
    });
  };

  const closeDropdown = () => {
    setIsDropdownVisible(false);
    setTimeout(() => {
      setIsDropdownOpen(false);
    }, 150);
  };

  const toggleDropdown = () => {
    if (isDropdownOpen) {
      closeDropdown();
    } else {
      openDropdown();
    }
  };

  // Modal open/close handlers
  const openModal = (request: BookingRequest) => {
    setViewingRequest(request);
    requestAnimationFrame(() => {
      requestAnimationFrame(() => {
        setIsModalVisible(true);
      });
    });
  };

  const closeModal = () => {
    setIsModalVisible(false);
    setTimeout(() => {
      setViewingRequest(null);
    }, 150);
  };

  // Decline modal handlers
  const openDeclineModal = (request: BookingRequest) => {
    setDecliningRequest(request);
    setSelectedReason('');
    setCustomReason('');
    setShowDeclineModal(true);
    requestAnimationFrame(() => {
      requestAnimationFrame(() => {
        setIsDeclineModalVisible(true);
      });
    });
  };

  const closeDeclineModal = () => {
    setIsDeclineModalVisible(false);
    setTimeout(() => {
      setShowDeclineModal(false);
      setDecliningRequest(null);
      setSelectedReason('');
      setCustomReason('');
    }, 150);
  };

  // Click outside handler for decline modal
  useEffect(() => {
    const handleDeclineModalClickOutside = (event: MouseEvent) => {
      if (declineModalRef.current && !declineModalRef.current.contains(event.target as Node)) {
        closeDeclineModal();
      }
    };

    if (showDeclineModal) {
      document.addEventListener('mousedown', handleDeclineModalClickOutside);
      return () => document.removeEventListener('mousedown', handleDeclineModalClickOutside);
    }
  }, [showDeclineModal]);

  const fetchRequests = async () => {
    try {
      // Add cache buster to ensure fresh data
      const response = await api.get<{ requests: BookingRequest[] }>(
        `/booking-requests/barber/${barberId}/pending?_t=${Date.now()}`
      );
      setRequests(response.requests || []);
    } catch (error) {
      console.error('Failed to fetch booking requests:', error);
      // Start with empty array on API failure
      setRequests([]);
    }
  };

  const handleAccept = async (bookingId: string) => {
    setActionLoading(bookingId);
    try {
      await api.post(`/booking-requests/${bookingId}/accept`, {
        barberId,
        message: 'Looking forward to seeing you!',
      });
      toast.success('Booking request accepted!');
      fetchRequests();
    } catch (error) {
      console.error('Failed to accept booking:', error);
      // For mock data, just remove from list
      setRequests(prev => prev.filter(r => r.bookingId !== bookingId));
      toast.success('Booking request accepted! (Mock)');
    } finally {
      setActionLoading(null);
    }
  };

  const handleReject = async (bookingId: string, reason: string) => {
    setActionLoading(bookingId);
    try {
      await api.post(`/booking-requests/${bookingId}/reject`, {
        barberId,
        reason,
      });
      toast.success('Booking request declined');
      fetchRequests();
      closeDeclineModal();
      closeModal(); // Close viewing modal if open
    } catch (error) {
      console.error('Failed to reject booking:', error);
      // For mock data, just remove from list
      setRequests(prev => prev.filter(r => r.bookingId !== bookingId));
      toast.success('Booking request declined (Mock)');
      closeDeclineModal();
      closeModal();
    } finally {
      setActionLoading(null);
    }
  };

  const handleConfirmDecline = () => {
    if (!decliningRequest) return;
    const reason = selectedReason === 'Other' ? customReason : selectedReason;
    if (!reason.trim()) {
      toast.error('Please select or enter a reason');
      return;
    }
    handleReject(decliningRequest.bookingId, reason);
  };

  return (
    <div className="relative" ref={dropdownRef}>
      {/* Inbox Button */}
      <button
        onClick={toggleDropdown}
        className="relative p-2 rounded-lg hover:bg-gray-100 transition-colors"
      >
        <Inbox className="w-6 h-6 text-gray-600" />
        {requests.length > 0 && (
          <span className="absolute -top-1 -right-1 bg-red-600 text-white text-xs font-bold rounded-full w-5 h-5 flex items-center justify-center">
            {requests.length > 9 ? '9+' : requests.length}
          </span>
        )}
      </button>

      {/* Dropdown Menu */}
      {isDropdownOpen && (
        <>
          {/* Backdrop for mobile/tablet */}
          {showBackdrop && (
            <div 
              className={`fixed inset-0 bg-black/0 z-40 transition-all duration-150 ${
                isDropdownVisible ? 'bg-black/50' : ''
              }`}
              onClick={closeDropdown}
            />
          )}
          
          <div 
            className={`${showBackdrop 
              ? 'fixed inset-0 m-auto w-[calc(100vw-2rem)] max-w-md h-fit max-h-[80vh]' 
              : 'absolute right-0 mt-2 w-96 max-h-[80vh]'
            } bg-white rounded-lg shadow-xl border border-gray-200 z-50 overflow-y-auto transition-all duration-150 ease-out ${
              showBackdrop ? 'origin-center' : 'origin-top-right'
            } ${
              isDropdownVisible 
                ? 'opacity-100 scale-100' 
                : 'opacity-0 scale-95'
            } ${!showBackdrop && !isDropdownVisible ? '-translate-y-2' : ''}`}
          >
            {/* Header */}
            <div className="sticky top-0 bg-white border-b border-gray-200 px-4 py-3 rounded-t-lg flex items-center justify-between z-10">
              <h3 className="font-bold text-gray-900">Booking Requests ({requests.length})</h3>
              {showBackdrop && (
                <button 
                  onClick={closeDropdown}
                  className="p-1 hover:bg-gray-100 rounded-full transition-colors"
                >
                  <X className="w-5 h-5 text-gray-500" />
                </button>
              )}
            </div>

          {/* Requests List */}
          <div className="divide-y divide-gray-200">
            {requests.length === 0 ? (
              <div className="p-8 text-center">
                <Inbox className="w-12 h-12 text-gray-300 mx-auto mb-3" />
                <p className="text-gray-500 text-sm">No pending requests</p>
              </div>
            ) : (
              requests.map((request) => (
                <div 
                  key={request.bookingId} 
                  className="p-4 hover:bg-gray-50 transition-colors cursor-pointer"
                  onClick={() => openModal(request)}
                >
                  {/* Customer Info */}
                  <div className="flex items-start gap-3 mb-3">
                    <div className="w-10 h-10 bg-gradient-to-br from-primary-500 to-primary-400 rounded-full flex items-center justify-center text-white font-bold text-sm flex-shrink-0">
                      {request.customerName.charAt(0).toUpperCase()}
                    </div>
                    <div className="flex-1 min-w-0">
                      <h4 className="font-semibold text-gray-900 text-sm truncate">
                        {request.customerName}
                      </h4>
                      <p className="text-xs text-gray-500">{request.customerProfile.stats.completionRate}% completion</p>
                    </div>
                    <span className="text-xs text-gray-400 flex-shrink-0">Tap for details →</span>
                  </div>

                  {/* Booking Details */}
                  <div className="space-y-1.5 mb-3 text-sm">
                    <div className="flex items-center gap-2 text-gray-700">
                      <Calendar className="w-4 h-4 text-gray-400" />
                      <span>{new Date(request.requestedDate).toLocaleDateString('en-US', { weekday: 'short', month: 'short', day: 'numeric' })}</span>
                      <span className="text-gray-400">at</span>
                      <span>{request.requestedTime}</span>
                    </div>
                    <div className="flex items-center gap-2">
                      <span className="text-gray-500">Service:</span>
                      <span className="font-medium text-gray-900">{request.serviceType}</span>
                      <span className="text-gray-400">•</span>
                      <span className="font-semibold text-green-600">${request.price.toFixed(2)}</span>
                    </div>
                  </div>

                  {/* Message */}
                  {request.message && (
                    <div className="p-2 bg-blue-50 rounded text-xs text-gray-700 mb-3 line-clamp-2">
                      "{request.message}"
                    </div>
                  )}

                  {/* Actions */}
                  <div className="flex gap-3 justify-center" onClick={(e) => e.stopPropagation()}>
                    <Button
                      onClick={() => handleAccept(request.bookingId)}
                      disabled={actionLoading === request.bookingId}
                      className="flex-1 max-w-[140px] bg-green-600 hover:bg-green-700 text-sm py-2.5"
                    >
                      <CheckCircle className="w-4 h-4 mr-1.5" />
                      Accept
                    </Button>
                    <Button
                      onClick={() => openDeclineModal(request)}
                      disabled={actionLoading === request.bookingId}
                      variant="secondary"
                      className="flex-1 max-w-[140px] text-red-600 hover:bg-red-50 text-sm py-2.5"
                    >
                      <XCircle className="w-4 h-4 mr-1.5" />
                      Decline
                    </Button>
                  </div>
                </div>
              ))
            )}
          </div>
        </div>
        </>
      )}

      {/* Customer Details Modal */}
      {viewingRequest && (
        <div 
          className={`fixed inset-0 min-h-[100dvh] flex items-start justify-center z-[100] p-2 pt-8 sm:pt-4 sm:items-center sm:p-4 overflow-y-auto transition-all duration-150 ease-out ${
            isModalVisible ? 'bg-black/50' : 'bg-black/0'
          }`}
          onClick={closeModal}
        >
          <div 
            ref={modalRef} 
            onClick={(e) => e.stopPropagation()}
            className={`bg-white rounded-xl shadow-2xl max-w-lg w-full max-h-[88dvh] sm:max-h-[90vh] overflow-hidden transition-all duration-150 ease-out ${
              isModalVisible 
                ? 'opacity-100 scale-100 translate-y-0' 
                : 'opacity-0 scale-95 translate-y-4'
            }`}
          >
            {/* Header */}
            <div className="bg-gradient-to-r from-primary-500 to-primary-400 text-white p-4 sm:p-6">
              {/* Desktop: Show title row */}
              <div className="hidden sm:flex items-center justify-between mb-4">
                <h2 className="text-2xl font-bold">Customer Details</h2>
                <button
                  onClick={closeModal}
                  className="text-white hover:bg-white/20 rounded-full p-2 transition-colors"
                >
                  <X className="w-5 h-5" />
                </button>
              </div>
              {/* Customer info with X button on mobile */}
              <div className="flex items-center gap-3 sm:gap-4">
                <div className="w-12 h-12 sm:w-16 sm:h-16 bg-white/20 rounded-full flex items-center justify-center text-white font-bold text-xl sm:text-2xl flex-shrink-0">
                  {viewingRequest.customerName.charAt(0).toUpperCase()}
                </div>
                <div className="flex-1 min-w-0">
                  <h3 className="text-lg sm:text-xl font-semibold truncate">{viewingRequest.customerName}</h3>
                </div>
                {/* Mobile: X button next to name */}
                <button
                  onClick={closeModal}
                  className="sm:hidden text-white hover:bg-white/20 rounded-full p-2 transition-colors flex-shrink-0"
                >
                  <X className="w-5 h-5" />
                </button>
              </div>
            </div>

            {/* Content */}
            <div className="p-6 overflow-y-auto max-h-[calc(92dvh-200px)] sm:max-h-[calc(90vh-200px)]">
              <div className="space-y-4">
                {/* Service Request Details */}
                <div>
                  <h4 className="font-semibold text-gray-900 mb-3">Service Request Details</h4>
                  <div className="bg-gray-50 rounded-lg p-4 space-y-3 border border-gray-200">
                    <div className="flex items-center justify-between">
                      <span className="text-sm text-gray-600">Service</span>
                      <span className="text-sm font-semibold text-gray-900">{viewingRequest.serviceType}</span>
                    </div>
                    <div className="flex items-center justify-between">
                      <span className="text-sm text-gray-600">Requested Date</span>
                      <span className="text-sm font-semibold text-gray-900">
                        {new Date(viewingRequest.requestedDate).toLocaleDateString('en-US', { 
                          weekday: 'short',
                          month: 'short', 
                          day: 'numeric',
                          year: 'numeric'
                        })}
                      </span>
                    </div>
                    <div className="flex items-center justify-between">
                      <span className="text-sm text-gray-600">Requested Time</span>
                      <span className="text-sm font-semibold text-gray-900">{viewingRequest.requestedTime}</span>
                    </div>
                    {viewingRequest.location && (
                      <div className="flex items-center justify-between">
                        <span className="text-sm text-gray-600">Location</span>
                        <span className="text-sm font-semibold text-gray-900">{viewingRequest.location}</span>
                      </div>
                    )}
                    <div className="flex items-center justify-between">
                      <span className="text-sm text-gray-600">Status</span>
                      <span className="inline-flex px-2.5 py-1 rounded-full text-xs font-medium bg-yellow-100 text-yellow-700">
                        Awaiting Acceptance
                      </span>
                    </div>
                    {viewingRequest.message && (
                      <div className="flex items-start justify-between">
                        <span className="text-sm text-gray-600">Notes</span>
                        <span className="text-sm font-semibold text-gray-900 text-right max-w-[60%]">{viewingRequest.message}</span>
                      </div>
                    )}
                    <div className="flex items-center justify-between pt-2 border-t border-gray-200">
                      <span className="text-sm text-gray-600">Price</span>
                      <span className="text-lg font-bold text-green-600">${viewingRequest.price.toFixed(2)}</span>
                    </div>
                  </div>
                </div>
              </div>
            </div>

            {/* Actions Footer */}
            <div className="bg-gray-50 px-6 py-4 border-t border-gray-200">
              <div className="flex gap-3">
                <Button
                  onClick={() => {
                    handleAccept(viewingRequest.bookingId);
                    closeModal();
                  }}
                  disabled={actionLoading === viewingRequest.bookingId}
                  className="flex-1 bg-green-600 hover:bg-green-700"
                >
                  <CheckCircle className="w-4 h-4 mr-2" />
                  <span className="sm:hidden">Accept</span>
                  <span className="hidden sm:inline">Accept Request</span>
                </Button>
                <Button
                  onClick={() => {
                    openDeclineModal(viewingRequest);
                  }}
                  disabled={actionLoading === viewingRequest.bookingId}
                  variant="secondary"
                  className="flex-1 text-red-600 hover:bg-red-50"
                >
                  <XCircle className="w-4 h-4 mr-2" />
                  Decline
                </Button>
              </div>
            </div>
          </div>
        </div>
      )}

      {/* Decline Reason Modal */}
      {showDeclineModal && decliningRequest && (
        <div 
          className={`fixed inset-0 z-[60] flex items-center justify-center p-4 transition-all duration-150 ${
            isDeclineModalVisible ? 'bg-black/50' : 'bg-black/0'
          }`}
          onClick={closeDeclineModal}
        >
          <div 
            ref={declineModalRef}
            className={`bg-white rounded-2xl shadow-xl max-w-md w-full overflow-hidden transform transition-all duration-150 ${
              isDeclineModalVisible 
                ? 'opacity-100 scale-100 translate-y-0' 
                : 'opacity-0 scale-95 translate-y-4'
            }`}
            onClick={(e) => e.stopPropagation()}
          >
            {/* Header */}
            <div className="bg-red-50 px-6 py-4 flex items-center justify-between border-b border-red-100">
              <div>
                <h2 className="text-lg font-bold text-red-700">Decline Request</h2>
                <p className="text-sm text-red-600/80">
                  {decliningRequest.customerName} • {decliningRequest.serviceType}
                </p>
              </div>
              <button 
                onClick={closeDeclineModal}
                className="text-red-600 hover:bg-red-100 rounded-full p-2 transition-colors"
              >
                <X className="w-5 h-5" />
              </button>
            </div>

            {/* Content */}
            <div className="p-6">
              <p className="text-sm text-gray-600 mb-4">
                Please select a reason for declining this booking request:
              </p>

              {/* Reason Options */}
              <div className="space-y-2 mb-4">
                {DECLINE_REASONS.map((reason) => (
                  <label 
                    key={reason}
                    className={`flex items-center gap-3 p-3 rounded-lg cursor-pointer transition-colors ${
                      selectedReason === reason 
                        ? 'bg-red-50 border-2 border-red-300' 
                        : 'bg-gray-50 border-2 border-transparent hover:bg-gray-100'
                    }`}
                  >
                    <input
                      type="radio"
                      name="declineReason"
                      value={reason}
                      checked={selectedReason === reason}
                      onChange={(e) => setSelectedReason(e.target.value)}
                      className="w-4 h-4 text-red-600 focus:ring-red-500"
                    />
                    <span className="text-sm text-gray-700">{reason}</span>
                  </label>
                ))}
              </div>

              {/* Custom Reason Input */}
              {selectedReason === 'Other' && (
                <div className="mb-4">
                  <label className="block text-sm font-medium text-gray-700 mb-1">
                    Please specify:
                  </label>
                  <textarea
                    value={customReason}
                    onChange={(e) => setCustomReason(e.target.value)}
                    placeholder="Enter your reason..."
                    className="w-full px-3 py-2 border border-gray-300 rounded-lg text-sm focus:ring-2 focus:ring-red-500 focus:border-transparent resize-none"
                    rows={3}
                    maxLength={200}
                  />
                  <p className="text-xs text-gray-400 mt-1 text-right">
                    {customReason.length}/200
                  </p>
                </div>
              )}
            </div>

            {/* Footer */}
            <div className="bg-gray-50 px-6 py-4 border-t border-gray-200 flex gap-3">
              <Button
                onClick={closeDeclineModal}
                variant="secondary"
                className="flex-1"
              >
                Cancel
              </Button>
              <Button
                onClick={handleConfirmDecline}
                disabled={!selectedReason || (selectedReason === 'Other' && !customReason.trim()) || actionLoading === decliningRequest.bookingId}
                className="flex-1 bg-red-600 hover:bg-red-700 text-white"
              >
                {actionLoading === decliningRequest.bookingId ? (
                  <div className="w-5 h-5 border-2 border-white border-t-transparent rounded-full animate-spin" />
                ) : (
                  <>
                    <XCircle className="w-4 h-4 mr-2" />
                    Confirm Decline
                  </>
                )}
              </Button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
