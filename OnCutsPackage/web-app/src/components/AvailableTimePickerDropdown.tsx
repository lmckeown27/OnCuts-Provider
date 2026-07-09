/**
 * AvailableTimePickerDropdown Component
 * 
 * An enhanced time picker that shows available time slots based on:
 * 1. Barber's weekly schedule (with multiple intervals per day)
 * 2. Existing accepted bookings (blocked out)
 * 
 * Similar to Calendly's booking experience.
 */

import { useState, useRef, useEffect } from 'react';
import { Clock, ChevronDown, Loader2 } from 'lucide-react';
import api from '../services/api.service';

interface TimeSlot {
  time: string;
  label: string;
  available: boolean;
}

interface TimeInterval {
  id: string;
  start: string;
  end: string;
}

interface AvailabilityResponse {
  date: string;
  dayOfWeek: string;
  available: boolean;
  intervals: TimeInterval[];
  bookedSlots: { start: string; end: string }[];
  slots: { time: string; available: boolean }[];
}

interface AvailableTimePickerDropdownProps {
  barberId: string;
  date: string; // YYYY-MM-DD format
  value: string; // HH:MM format (24-hour)
  onChange: (value: string) => void;
  label?: string;
  disabled?: boolean;
  className?: string;
}

// Convert 24-hour time to 12-hour display format
const formatTimeDisplay = (time24: string): string => {
  if (!time24) return '';
  
  const [hourStr, minuteStr] = time24.split(':');
  const hour = parseInt(hourStr, 10);
  const minute = minuteStr || '00';
  
  const displayHour = hour === 0 ? 12 : hour > 12 ? hour - 12 : hour;
  const period = hour < 12 ? 'am' : 'pm';
  
  return `${displayHour}:${minute}${period}`;
};

export default function AvailableTimePickerDropdown({
  barberId,
  date,
  value,
  onChange,
  label,
  disabled = false,
  className = '',
}: AvailableTimePickerDropdownProps) {
  const [isOpen, setIsOpen] = useState(false);
  const [isLoading, setIsLoading] = useState(false);
  const [slots, setSlots] = useState<TimeSlot[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [intervals, setIntervals] = useState<TimeInterval[]>([]);
  const containerRef = useRef<HTMLDivElement>(null);
  const listRef = useRef<HTMLDivElement>(null);
  const selectedRef = useRef<HTMLButtonElement>(null);

  // Fetch availability when date changes
  useEffect(() => {
    console.log('[AvailableTimePickerDropdown] barberId:', barberId, 'date:', date);
    if (barberId && date) {
      fetchAvailability();
    } else {
      console.log('[AvailableTimePickerDropdown] Missing barberId or date, not fetching');
    }
  }, [barberId, date]);

  const fetchAvailability = async () => {
    if (!barberId || !date) return;
    
    setIsLoading(true);
    setError(null);
    
    try {
      // api.get already extracts response.data.data, so we get the AvailabilityResponse directly
      const response = await api.get<AvailabilityResponse>(`/barbers/${barberId}/availability?date=${date}`);
      
      console.log('[AvailableTimePickerDropdown] Fetched availability:', response);
      
      if (response) {
        const { available, slots: apiSlots, intervals: apiIntervals } = response;
        
        if (!available || !apiSlots || apiSlots.length === 0) {
          // No availability - just show empty state without specific error message
          setSlots([]);
          setIntervals([]);
          setError(null);
        } else {
          // Convert API slots to our format
          const formattedSlots: TimeSlot[] = apiSlots.map(slot => ({
            time: slot.time,
            label: formatTimeDisplay(slot.time),
            available: slot.available
          }));
          
          setSlots(formattedSlots);
          setIntervals(apiIntervals || []);
          setError(null);
          
          // Reset selected time if it's no longer available
          if (value && formattedSlots.length > 0) {
            const selectedSlot = formattedSlots.find(s => s.time === value);
            if (selectedSlot && !selectedSlot.available) {
              onChange('');
            }
          }
        }
      } else {
        setSlots([]);
        setIntervals([]);
        setError('No availability data received');
      }
    } catch (err) {
      console.error('Failed to fetch availability:', err);
      setError('Failed to load available times');
      setSlots([]);
    } finally {
      setIsLoading(false);
    }
  };

  // Close dropdown when clicking outside
  useEffect(() => {
    const handleClickOutside = (event: MouseEvent) => {
      if (containerRef.current && !containerRef.current.contains(event.target as Node)) {
        setIsOpen(false);
      }
    };

    document.addEventListener('mousedown', handleClickOutside);
    return () => document.removeEventListener('mousedown', handleClickOutside);
  }, []);

  // Scroll to selected time when dropdown opens
  useEffect(() => {
    if (isOpen && selectedRef.current && listRef.current) {
      const listRect = listRef.current.getBoundingClientRect();
      const selectedRect = selectedRef.current.getBoundingClientRect();
      
      const scrollTop = selectedRef.current.offsetTop - (listRect.height / 2) + (selectedRect.height / 2);
      listRef.current.scrollTop = Math.max(0, scrollTop);
    }
  }, [isOpen]);

  const handleSelect = (timeValue: string) => {
    onChange(timeValue);
    setIsOpen(false);
  };

  // Group slots by interval for better UX
  const availableSlots = slots.filter(s => s.available);
  const hasAvailableSlots = availableSlots.length > 0;

  return (
    <div ref={containerRef} className={`relative ${className}`}>
      {label && (
        <label className="block text-xs text-gray-600 mb-1">{label}</label>
      )}
      
      {/* Trigger Button */}
      <button
        type="button"
        onClick={() => !disabled && !isLoading && setIsOpen(!isOpen)}
        disabled={disabled || isLoading}
        className={`
          w-full px-3 py-2 border rounded-lg text-sm text-left
          flex items-center justify-between gap-2
          transition-all duration-150
          ${disabled || isLoading
            ? 'bg-gray-100 text-gray-400 cursor-not-allowed border-gray-200' 
            : error 
              ? 'bg-red-50 border-red-300 text-red-600 cursor-pointer'
              : 'bg-white border-gray-300 hover:border-primary-400 focus:ring-2 focus:ring-primary-400 focus:border-transparent cursor-pointer'
          }
          ${isOpen ? 'ring-2 ring-primary-400 border-transparent' : ''}
        `}
      >
        <div className="flex items-center gap-2">
          {isLoading ? (
            <Loader2 className="w-4 h-4 text-gray-400 animate-spin" />
          ) : (
            <Clock className="w-4 h-4 text-gray-400" />
          )}
          <span className={value ? 'text-gray-900' : 'text-gray-400'}>
            {isLoading 
              ? 'Loading...' 
              : error 
                ? error 
                : value 
                  ? formatTimeDisplay(value) 
                  : !date 
                    ? 'Select a date first'
                    : !hasAvailableSlots 
                      ? 'No available times' 
                      : 'Select time'
            }
          </span>
        </div>
        <ChevronDown 
          className={`w-4 h-4 text-gray-400 transition-transform ${isOpen ? 'rotate-180' : ''}`} 
        />
      </button>

      {/* Dropdown List */}
      {isOpen && !isLoading && hasAvailableSlots && (
        <div
          ref={listRef}
          className="
            absolute z-50 mt-1 w-full
            bg-white border border-gray-200 rounded-lg shadow-lg
            max-h-60 overflow-y-auto
            py-1
          "
          role="listbox"
          aria-label="Available Times"
        >
          {/* Show intervals as headers */}
          {intervals.length > 1 && (
            <div className="px-3 py-2 bg-gray-50 border-b border-gray-200">
              <p className="text-xs text-gray-500 font-medium">
                Available times: {intervals.map(i => `${formatTimeDisplay(i.start)} - ${formatTimeDisplay(i.end)}`).join(', ')}
              </p>
            </div>
          )}
          
          {slots.map((slot) => {
            const isSelected = slot.time === value;
            
            if (!slot.available) {
              // Show unavailable slots as disabled
              return (
                <div
                  key={slot.time}
                  className="px-4 py-2 text-sm text-gray-400 bg-gray-50 cursor-not-allowed flex items-center justify-between"
                >
                  <span className="line-through">{slot.label}</span>
                  <span className="text-xs text-red-400">Booked</span>
                </div>
              );
            }
            
            return (
              <button
                key={slot.time}
                ref={isSelected ? selectedRef : null}
                type="button"
                role="option"
                aria-selected={isSelected}
                onClick={() => handleSelect(slot.time)}
                className={`
                  w-full px-4 py-2 text-left text-sm
                  transition-colors duration-100
                  ${isSelected 
                    ? 'bg-primary-100 text-primary-700 font-medium' 
                    : 'text-gray-700 hover:bg-gray-100'
                  }
                `}
              >
                {slot.label}
              </button>
            );
          })}
        </div>
      )}

      {/* Empty state in dropdown */}
      {isOpen && !isLoading && !hasAvailableSlots && !error && (
        <div className="
          absolute z-50 mt-1 w-full
          bg-white border border-gray-200 rounded-lg shadow-lg
          py-6 px-4 text-center
        ">
          <Clock className="w-8 h-8 text-gray-300 mx-auto mb-2" />
          <p className="text-sm text-gray-500">No available times for this date</p>
          <p className="text-xs text-gray-400 mt-1">Try selecting a different date</p>
        </div>
      )}
    </div>
  );
}

