/**
 * TimePickerDropdown Component
 * 
 * A scrollable dropdown for selecting times in 15-minute increments.
 * Similar to Airbnb's time picker UX.
 */

import { useState, useRef, useEffect } from 'react';
import { Clock, ChevronDown } from 'lucide-react';

interface TimeInterval {
  start: string; // HH:MM format (24-hour)
  end: string;   // HH:MM format (24-hour)
}

interface TimePickerDropdownProps {
  value: string; // HH:MM format (24-hour)
  onChange: (value: string) => void;
  label?: string;
  disabled?: boolean;
  minTime?: string; // Optional minimum time (HH:MM)
  maxTime?: string; // Optional maximum time (HH:MM)
  availableIntervals?: TimeInterval[]; // Optional: only show times within these intervals
  className?: string;
}

// Generate time slots in 15-minute increments
const generateTimeSlots = (): { value: string; label: string }[] => {
  const slots: { value: string; label: string }[] = [];
  
  for (let hour = 0; hour < 24; hour++) {
    for (let minute = 0; minute < 60; minute += 15) {
      const value = `${hour.toString().padStart(2, '0')}:${minute.toString().padStart(2, '0')}`;
      
      // Format for display (12-hour with am/pm)
      const displayHour = hour === 0 ? 12 : hour > 12 ? hour - 12 : hour;
      const period = hour < 12 ? 'am' : 'pm';
      const label = `${displayHour}:${minute.toString().padStart(2, '0')}${period}`;
      
      slots.push({ value, label });
    }
  }
  
  return slots;
};

const TIME_SLOTS = generateTimeSlots();

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

// Convert time string to minutes for comparison
const timeToMinutes = (time: string): number => {
  const [hour, minute] = time.split(':').map(Number);
  return hour * 60 + minute;
};

export default function TimePickerDropdown({
  value,
  onChange,
  label,
  disabled = false,
  minTime,
  maxTime,
  availableIntervals,
  className = '',
}: TimePickerDropdownProps) {
  const [isOpen, setIsOpen] = useState(false);
  const containerRef = useRef<HTMLDivElement>(null);
  const listRef = useRef<HTMLDivElement>(null);
  const selectedRef = useRef<HTMLButtonElement>(null);

  // Filter slots based on min/max time and available intervals
  const filteredSlots = TIME_SLOTS.filter((slot) => {
    const slotMinutes = timeToMinutes(slot.value);
    
    if (minTime) {
      const minMinutes = timeToMinutes(minTime);
      if (slotMinutes < minMinutes) return false;
    }
    
    if (maxTime) {
      const maxMinutes = timeToMinutes(maxTime);
      if (slotMinutes > maxMinutes) return false;
    }
    
    // If availableIntervals is provided, only show times within those intervals
    if (availableIntervals && availableIntervals.length > 0) {
      const isWithinInterval = availableIntervals.some((interval) => {
        const startMinutes = timeToMinutes(interval.start);
        const endMinutes = timeToMinutes(interval.end);
        // Time slot must be >= start and < end (can start at a time, but end time is exclusive)
        return slotMinutes >= startMinutes && slotMinutes < endMinutes;
      });
      if (!isWithinInterval) return false;
    }
    
    return true;
  });

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
      
      // Scroll so the selected item is in the middle of the visible area
      const scrollTop = selectedRef.current.offsetTop - (listRect.height / 2) + (selectedRect.height / 2);
      listRef.current.scrollTop = Math.max(0, scrollTop);
    }
  }, [isOpen]);

  const handleSelect = (timeValue: string) => {
    onChange(timeValue);
    setIsOpen(false);
  };

  return (
    <div ref={containerRef} className={`relative ${className}`}>
      {label && (
        <label className="block text-xs text-gray-600 mb-1">{label}</label>
      )}
      
      {/* Trigger Button */}
      <button
        type="button"
        onClick={() => !disabled && setIsOpen(!isOpen)}
        disabled={disabled}
        className={`
          w-full px-3 py-2 border rounded-lg text-sm text-left
          flex items-center justify-between gap-2
          transition-all duration-150
          ${disabled 
            ? 'bg-gray-100 text-gray-400 cursor-not-allowed border-gray-200' 
            : 'bg-white border-gray-300 hover:border-primary-400 focus:ring-2 focus:ring-primary-400 focus:border-transparent cursor-pointer'
          }
          ${isOpen ? 'ring-2 ring-primary-400 border-transparent' : ''}
        `}
      >
        <div className="flex items-center gap-2">
          <Clock className="w-4 h-4 text-gray-400" />
          <span className={value ? 'text-gray-900' : 'text-gray-400'}>
            {value ? formatTimeDisplay(value) : 'Select time'}
          </span>
        </div>
        <ChevronDown 
          className={`w-4 h-4 text-gray-400 transition-transform ${isOpen ? 'rotate-180' : ''}`} 
        />
      </button>

      {/* Dropdown List */}
      {isOpen && (
        <div
          ref={listRef}
          className="
            absolute z-[9999] mt-1 w-full
            bg-white border border-gray-200 rounded-lg shadow-xl
            max-h-60 overflow-y-auto
            py-1
          "
          style={{ position: 'absolute' }}
          role="listbox"
          aria-label="Time Options"
        >
          {filteredSlots.map((slot) => {
            const isSelected = slot.value === value;
            
            return (
              <button
                key={slot.value}
                ref={isSelected ? selectedRef : null}
                type="button"
                role="option"
                aria-selected={isSelected}
                onClick={() => handleSelect(slot.value)}
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
          
          {filteredSlots.length === 0 && (
            <div className="px-4 py-3 text-sm text-gray-500 text-center">
              No available times
            </div>
          )}
        </div>
      )}
    </div>
  );
}

