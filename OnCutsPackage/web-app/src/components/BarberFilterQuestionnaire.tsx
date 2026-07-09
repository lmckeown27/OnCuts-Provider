/**
 * Barber Filter Questionnaire Component
 * 
 * Progressive popup questionnaire that asks:
 * 1. What type of haircut?
 * 2. When do you want it?
 * 3. Where do you want it?
 * 
 * Features:
 * - Popup modal that progresses through 3 steps
 * - Auto-closes after completing all questions
 * - Can be reopened to edit filters
 */

import React, { useState, useEffect } from 'react';
import { Scissors, Calendar, MapPin, X, ChevronRight, ChevronLeft, Check, Filter } from 'lucide-react';
import Button from './Button';
import TimePickerDropdown from './TimePickerDropdown';
import { LocationSelector } from './LocationSelector';
import { useBodyScrollLock } from '../hooks';
import type { FilterCriteria } from '../types/barber-filters';

interface BarberFilterQuestionnaireProps {
  onFilterChange: (filters: FilterCriteria) => void;
  availableServices: string[];
  availableCount: number;
}

export default function BarberFilterQuestionnaire({ 
  onFilterChange, 
  availableServices,
  availableCount 
}: BarberFilterQuestionnaireProps) {
  const [isOpen, setIsOpen] = useState(false);
  const [isVisible, setIsVisible] = useState(false);
  const [currentStep, setCurrentStep] = useState(1);
  
  // Filter state
  const [serviceType, setServiceType] = useState<string | null>(null);
  const [date, setDate] = useState<string | null>(null);
  const [time, setTime] = useState<string | null>(null);
  const [locationId, setLocationId] = useState<string | null>(null);
  const [locationName, setLocationName] = useState<string | null>(null);

  // Lock body scroll when popup is open
  useBodyScrollLock(isOpen);

  // Open popup with animation
  const openPopup = () => {
    setIsOpen(true);
    setCurrentStep(1);
    requestAnimationFrame(() => {
      requestAnimationFrame(() => {
        setIsVisible(true);
      });
    });
  };

  // Close popup with animation
  const closePopup = () => {
    setIsVisible(false);
    setTimeout(() => {
      setIsOpen(false);
    }, 150);
  };

  // Format date for display
  const formatDateDisplay = (dateString: string): string => {
    const dateObj = new Date(dateString + 'T00:00:00');
    return dateObj.toLocaleDateString('en-US', { 
      month: 'short', 
      day: 'numeric' 
    });
  };

  // Format time for display
  const formatTimeDisplay = (timeString: string): string => {
    const [hours, minutes] = timeString.split(':').map(Number);
    const period = hours >= 12 ? 'PM' : 'AM';
    const displayHours = hours % 12 || 12;
    return `${displayHours}:${minutes.toString().padStart(2, '0')} ${period}`;
  };

  const notifyFilterChange = (filters: FilterCriteria) => {
    onFilterChange(filters);
  };

  // Handle service selection
  const handleServiceSelect = (service: string) => {
    setServiceType(service);
    notifyFilterChange({
      serviceType: service,
      date,
      time,
      location: locationName,
      locationDetails: locationName,
    });
    // Auto-advance to next step
    setCurrentStep(2);
  };

  // Handle date/time confirmation
  const handleDateTimeConfirm = () => {
    if (date && time) {
      notifyFilterChange({
        serviceType,
        date,
        time,
        location: locationName,
        locationDetails: locationName,
      });
      setCurrentStep(3);
    }
  };

  // Handle location selection
  const handleLocationSelect = (newLocationId: string, newLocationName: string) => {
    setLocationId(newLocationId);
    setLocationName(newLocationName);
  };

  // Handle final confirmation
  const handleComplete = () => {
    notifyFilterChange({
      serviceType,
      date,
      time,
      location: locationName,
      locationDetails: locationName,
    });
    closePopup();
  };

  // Clear all filters
  const handleClearFilters = () => {
    setServiceType(null);
    setDate(null);
    setTime(null);
    setLocationId(null);
    setLocationName(null);
    notifyFilterChange({
      serviceType: null,
      date: null,
      time: null,
      location: null,
      locationDetails: null,
    });
  };

  // Skip current step
  const handleSkip = () => {
    if (currentStep === 2) {
      setDate(null);
      setTime(null);
      setCurrentStep(3);
    } else if (currentStep === 3) {
      setLocationId(null);
      setLocationName(null);
      handleComplete();
    }
  };

  // Go back to previous step
  const handleBack = () => {
    if (currentStep > 1) {
      setCurrentStep(currentStep - 1);
    }
  };

  // Check if filters are active
  const hasActiveFilters = serviceType || date || locationName;

  // Get today's date for min date
  const today = new Date().toISOString().split('T')[0];

  return (
    <>
      {/* Filter Trigger Button & Active Filters Display */}
      <div className="bg-gradient-to-br from-primary-50 to-primary-50 -mx-3 sm:-mx-4 px-3 sm:px-4 py-4 sm:py-6">
        <div className="flex flex-col gap-4">
          {/* Find Barber Button - Always Visible */}
          {!hasActiveFilters && (
            <div className="flex justify-center">
            <Button onClick={openPopup} variant="primary" className="px-8 sm:px-12 py-4 sm:py-5 text-lg sm:text-xl font-bold">
              Find Barber
            </Button>
            </div>
          )}

          {/* Active Filters Row */}
          {hasActiveFilters && (
            <div className="flex flex-col sm:flex-row items-center justify-between gap-3">
              <div className="flex flex-wrap items-center gap-2">
                {serviceType && (
                  <span className="inline-flex items-center gap-1.5 px-3 py-1.5 bg-primary-100 text-primary-700 rounded-full text-sm font-medium">
                    <Scissors className="w-4 h-4" />
                    {serviceType}
                  </span>
                )}
                {date && time && (
                  <span className="inline-flex items-center gap-1.5 px-3 py-1.5 bg-primary-100 text-primary-700 rounded-full text-sm font-medium">
                    <Calendar className="w-4 h-4" />
                    {formatDateDisplay(date)} at {formatTimeDisplay(time)}
                  </span>
                )}
                {locationName && (
                  <span className="inline-flex items-center gap-1.5 px-3 py-1.5 bg-primary-100 text-primary-700 rounded-full text-sm font-medium">
                    <MapPin className="w-4 h-4" />
                    {locationName}
                  </span>
                )}
                <button
                  onClick={handleClearFilters}
                  className="text-sm text-gray-500 hover:text-red-600 transition-colors"
                >
                  Clear all
                </button>
              </div>
              <Button onClick={openPopup} variant="secondary" className="px-4 py-2">
                <Filter className="w-4 h-4 mr-2" />
                Edit Filters
              </Button>
            </div>
          )}
        </div>
      </div>

      {/* Barbers Available Count - Sticky */}
      <div className="sticky top-0 z-20 bg-white/95 backdrop-blur-sm border-b border-gray-200 -mx-3 sm:-mx-4 px-3 sm:px-4 py-3">
        <div className="flex items-center justify-center">
          <span className="inline-flex items-center gap-2 px-4 py-2 bg-primary-50 border border-primary-200 rounded-full">
            <span className="text-sm sm:text-base font-medium text-primary-700">
              Barbers Available:
            </span>
            <span className="text-base sm:text-lg font-bold text-primary-600">{availableCount}</span>
          </span>
        </div>
      </div>

      {/* Popup Modal */}
      {isOpen && (
        <div 
          className={`fixed inset-0 min-h-[100dvh] flex items-center justify-center z-50 p-4 transition-all duration-150 ease-out ${
            isVisible ? 'bg-black/50' : 'bg-black/0'
          }`}
          onClick={closePopup}
        >
          <div 
            className={`bg-white rounded-2xl shadow-2xl w-full max-w-lg max-h-[85dvh] sm:max-h-[85vh] overflow-hidden transition-all duration-150 ease-out ${
              isVisible 
                ? 'opacity-100 scale-100 translate-y-0' 
                : 'opacity-0 scale-95 translate-y-4'
            }`}
            onClick={(e) => e.stopPropagation()}
          >
            {/* Header */}
            <div className="sticky top-0 bg-gradient-to-r from-primary-500 to-primary-400 px-6 py-4 flex items-center justify-between">
              <div>
                <h2 className="text-xl font-bold text-white">Find Your Barber</h2>
                <p className="text-white/80 text-sm">Step {currentStep} of 3</p>
              </div>
              <button 
                onClick={closePopup}
                className="text-white/80 hover:text-white hover:bg-white/20 rounded-full p-2 transition-colors"
              >
                <X className="w-6 h-6" />
              </button>
            </div>

            {/* Progress Bar */}
            <div className="h-1 bg-gray-200">
              <div 
                className="h-full bg-primary-400 transition-all duration-300"
                style={{ width: `${(currentStep / 3) * 100}%` }}
              />
            </div>

            {/* Content */}
            <div className="p-6 overflow-y-auto max-h-[calc(85vh-180px)]">
              {/* Step 1: Service Type */}
              {currentStep === 1 && (
                <div className="space-y-4 animate-fade-in">
                  <div className="text-center mb-6">
                    <div className="w-16 h-16 bg-primary-100 rounded-full flex items-center justify-center mx-auto mb-4">
                      <Scissors className="w-8 h-8 text-primary-500" />
                    </div>
                    <h3 className="text-xl font-bold text-gray-900">What type of haircut?</h3>
                    <p className="text-gray-600 mt-1">Select the service you're looking for</p>
                  </div>
                  <div className="grid grid-cols-2 gap-3">
                    {availableServices.map((service) => (
                      <button
                        key={service}
                        onClick={() => handleServiceSelect(service)}
                        className={`px-4 py-4 rounded-xl font-semibold text-base transition-all ${
                          serviceType === service
                            ? 'bg-primary-400 text-white shadow-lg'
                            : 'bg-white text-primary-400 border-2 border-primary-400 hover:bg-primary-400 hover:text-white hover:shadow-lg'
                        }`}
                      >
                        {service}
                      </button>
                    ))}
                  </div>
                </div>
              )}

              {/* Step 2: Date & Time */}
              {currentStep === 2 && (
                <div className="space-y-4 animate-fade-in">
                  <div className="text-center mb-6">
                    <div className="w-16 h-16 bg-primary-100 rounded-full flex items-center justify-center mx-auto mb-4">
                      <Calendar className="w-8 h-8 text-primary-500" />
                    </div>
                    <h3 className="text-xl font-bold text-gray-900">When do you want it?</h3>
                    <p className="text-gray-600 mt-1">Select your preferred date and time</p>
                  </div>
                  
                  <div className="space-y-4">
                    <div>
                      <label className="block text-sm font-medium text-gray-700 mb-2">Date</label>
                      <input
                        type="date"
                        value={date || ''}
                        onChange={(e) => setDate(e.target.value)}
                        min={today}
                        className="w-full px-4 py-3 border border-gray-300 rounded-xl focus:ring-2 focus:ring-primary-400 focus:border-transparent text-lg"
                      />
                    </div>
                    <div>
                      <label className="block text-sm font-medium text-gray-700 mb-2">Time</label>
                      <TimePickerDropdown
                        value={time || ''}
                        onChange={(value) => setTime(value)}
                      />
                    </div>
                  </div>
                </div>
              )}

              {/* Step 3: Location */}
              {currentStep === 3 && (
                <div className="space-y-4 animate-fade-in">
                  <div className="text-center mb-6">
                    <div className="w-16 h-16 bg-primary-100 rounded-full flex items-center justify-center mx-auto mb-4">
                      <MapPin className="w-8 h-8 text-primary-500" />
                    </div>
                    <h3 className="text-xl font-bold text-gray-900">Where do you want it?</h3>
                    <p className="text-gray-600 mt-1">Select your preferred location</p>
                  </div>
                  
                  <LocationSelector
                    universityId="calpoly"
                    selectedLocationId={locationId}
                    onLocationSelect={handleLocationSelect}
                  />
                </div>
              )}
            </div>

            {/* Footer */}
            <div className="sticky bottom-0 bg-white border-t border-gray-200 px-6 py-4 flex items-center justify-between">
              <div>
                {currentStep > 1 && (
                  <Button variant="secondary" onClick={handleBack}>
                    <ChevronLeft className="w-4 h-4 mr-1" />
                    Back
                  </Button>
                )}
              </div>
              <div className="flex gap-3">
                {currentStep > 1 && (
                  <Button variant="secondary" onClick={handleSkip}>
                    Skip
                  </Button>
                )}
                {currentStep === 2 && (
                  <Button 
                    onClick={handleDateTimeConfirm}
                    disabled={!date || !time}
                  >
                    Next
                    <ChevronRight className="w-4 h-4 ml-1" />
                  </Button>
                )}
                {currentStep === 3 && (
                  <Button onClick={handleComplete}>
                    <Check className="w-4 h-4 mr-1" />
                    Done
                  </Button>
                )}
              </div>
            </div>
          </div>
        </div>
      )}
    </>
  );
}
