/**
 * TimeInput Component
 * 
 * A text input for entering times manually (Calendly-style).
 * Accepts formats like "9am", "9:00am", "9:30pm", "14:00", etc.
 */

import { useState, useEffect, useRef } from 'react';

interface TimeInputProps {
  value: string; // HH:MM format (24-hour)
  onChange: (value: string) => void;
  label?: string;
  disabled?: boolean;
  placeholder?: string;
  className?: string;
  'aria-label'?: string;
  error?: boolean; // External error state (e.g., validation errors)
}

// Convert 24-hour time to 12-hour display format
const formatTimeDisplay = (time24: string): string => {
  if (!time24) return '';
  
  const [hourStr, minuteStr] = time24.split(':');
  const hour = parseInt(hourStr, 10);
  const minute = minuteStr || '00';
  
  if (isNaN(hour)) return '';
  
  const displayHour = hour === 0 ? 12 : hour > 12 ? hour - 12 : hour;
  const period = hour < 12 ? 'am' : 'pm';
  
  return `${displayHour}:${minute}${period}`;
};

// Parse various time input formats to 24-hour HH:MM
const parseTimeInput = (input: string): string | null => {
  if (!input) return null;
  
  // Clean up the input
  const cleaned = input.toLowerCase().replace(/\s+/g, '').trim();
  
  // Try various patterns
  
  // Pattern: 9am, 9pm, 12am, 12pm
  const simpleMatch = cleaned.match(/^(\d{1,2})(am|pm)$/);
  if (simpleMatch) {
    let hour = parseInt(simpleMatch[1], 10);
    const period = simpleMatch[2];
    
    if (hour < 1 || hour > 12) return null;
    
    if (period === 'am') {
      hour = hour === 12 ? 0 : hour;
    } else {
      hour = hour === 12 ? 12 : hour + 12;
    }
    
    return `${hour.toString().padStart(2, '0')}:00`;
  }
  
  // Pattern: 9:00am, 9:30pm, 12:00am
  const colonMatch = cleaned.match(/^(\d{1,2}):(\d{2})(am|pm)$/);
  if (colonMatch) {
    let hour = parseInt(colonMatch[1], 10);
    const minute = parseInt(colonMatch[2], 10);
    const period = colonMatch[3];
    
    if (hour < 1 || hour > 12 || minute < 0 || minute > 59) return null;
    
    if (period === 'am') {
      hour = hour === 12 ? 0 : hour;
    } else {
      hour = hour === 12 ? 12 : hour + 12;
    }
    
    return `${hour.toString().padStart(2, '0')}:${minute.toString().padStart(2, '0')}`;
  }
  
  // Pattern: 14:00, 9:30 (24-hour format)
  const militaryMatch = cleaned.match(/^(\d{1,2}):(\d{2})$/);
  if (militaryMatch) {
    const hour = parseInt(militaryMatch[1], 10);
    const minute = parseInt(militaryMatch[2], 10);
    
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
    
    return `${hour.toString().padStart(2, '0')}:${minute.toString().padStart(2, '0')}`;
  }
  
  // Pattern: Just a number (assume hour, round to nearest valid)
  const justNumber = cleaned.match(/^(\d{1,2})$/);
  if (justNumber) {
    const num = parseInt(justNumber[1], 10);
    
    // If it's 1-12, assume it's AM for morning hours, PM for common business hours
    if (num >= 1 && num <= 12) {
      // Default to AM
      const hour = num === 12 ? 0 : num;
      return `${hour.toString().padStart(2, '0')}:00`;
    }
    
    // If it's 13-23, it's military time
    if (num >= 13 && num <= 23) {
      return `${num.toString().padStart(2, '0')}:00`;
    }
    
    if (num === 0) {
      return '00:00';
    }
  }
  
  return null;
};

// Round time to nearest 15 minutes
const roundToNearest15 = (time24: string): string => {
  const [hourStr, minuteStr] = time24.split(':');
  const hour = parseInt(hourStr, 10);
  let minute = parseInt(minuteStr, 10);
  
  // Round to nearest 15
  minute = Math.round(minute / 15) * 15;
  
  // Handle overflow
  if (minute === 60) {
    return `${((hour + 1) % 24).toString().padStart(2, '0')}:00`;
  }
  
  return `${hour.toString().padStart(2, '0')}:${minute.toString().padStart(2, '0')}`;
};

export default function TimeInput({
  value,
  onChange,
  label,
  disabled = false,
  placeholder = '9:00am',
  className = '',
  'aria-label': ariaLabel,
  error = false,
}: TimeInputProps) {
  const [inputValue, setInputValue] = useState(formatTimeDisplay(value));
  const [isFocused, setIsFocused] = useState(false);
  const [hasParseError, setHasParseError] = useState(false);
  const inputRef = useRef<HTMLInputElement>(null);
  
  // Combined error state: external error OR parse error
  const hasError = error || hasParseError;

  // Update display when value changes externally
  useEffect(() => {
    if (!isFocused) {
      setInputValue(formatTimeDisplay(value));
      setHasParseError(false);
    }
  }, [value, isFocused]);

  const handleChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    setInputValue(e.target.value);
    setHasParseError(false);
  };

  const handleBlur = () => {
    setIsFocused(false);
    
    if (!inputValue.trim()) {
      // If empty, revert to previous value
      setInputValue(formatTimeDisplay(value));
      return;
    }
    
    const parsed = parseTimeInput(inputValue);
    
    if (parsed) {
      const rounded = roundToNearest15(parsed);
      onChange(rounded);
      setInputValue(formatTimeDisplay(rounded));
      setHasParseError(false);
    } else {
      // Invalid input - show error and revert
      setHasParseError(true);
      setTimeout(() => {
        setInputValue(formatTimeDisplay(value));
        setHasParseError(false);
      }, 1000);
    }
  };

  const handleFocus = () => {
    setIsFocused(true);
    // Select all text on focus for easy editing
    setTimeout(() => {
      inputRef.current?.select();
    }, 0);
  };

  const handleKeyDown = (e: React.KeyboardEvent<HTMLInputElement>) => {
    if (e.key === 'Enter') {
      inputRef.current?.blur();
    }
    if (e.key === 'Escape') {
      setInputValue(formatTimeDisplay(value));
      inputRef.current?.blur();
    }
  };

  return (
    <div className={className}>
      {label && (
        <label className="block text-xs text-gray-600 mb-1">{label}</label>
      )}
      
      <input
        ref={inputRef}
        type="text"
        value={inputValue}
        onChange={handleChange}
        onFocus={handleFocus}
        onBlur={handleBlur}
        onKeyDown={handleKeyDown}
        disabled={disabled}
        placeholder={placeholder}
        aria-label={ariaLabel || label || 'Time'}
        aria-invalid={hasError}
        autoComplete="off"
        autoCorrect="off"
        className={`
          w-full px-3 py-2 border rounded-lg text-sm text-center
          transition-all duration-150 font-medium
          ${disabled 
            ? 'bg-gray-100 text-gray-400 cursor-not-allowed border-gray-200' 
            : hasError
              ? 'bg-red-50 border-red-400 text-red-700 ring-2 ring-red-200'
              : isFocused
                ? 'bg-white border-primary-400 ring-2 ring-primary-100 text-gray-900'
                : 'bg-white border-gray-300 hover:border-gray-400 text-gray-900'
          }
        `}
      />
    </div>
  );
}

