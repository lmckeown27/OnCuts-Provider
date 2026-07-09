import React, { useState, useMemo, useEffect } from 'react';
import { ChevronLeft, ChevronRight } from 'lucide-react';
import type { WeeklySchedule } from '../types';

interface DatePickerProps {
  value: string; // ISO date string (YYYY-MM-DD)
  onChange: (date: string) => void;
  minDate?: string; // ISO date string
  maxDate?: string; // ISO date string
  label?: string;
  required?: boolean;
  weeklySchedule?: WeeklySchedule; // Barber's availability schedule
}

// Helper to get today at midnight
const getTodayAtMidnight = () => {
  const now = new Date();
  now.setHours(0, 0, 0, 0);
  return now;
};

// Map day index (0=Sunday) to weeklySchedule key
const dayIndexToKey = ['sunday', 'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday'] as const;

export default function DatePicker({
  value,
  onChange,
  minDate,
  maxDate,
  label = 'Select Date',
  required = false,
  weeklySchedule,
}: DatePickerProps) {
  // State for today that updates at midnight
  const [today, setToday] = useState(getTodayAtMidnight);

  // Auto-update "today" at midnight
  useEffect(() => {
    const now = new Date();
    const tomorrow = new Date(now);
    tomorrow.setDate(tomorrow.getDate() + 1);
    tomorrow.setHours(0, 0, 0, 0);
    
    // Time until midnight
    const msUntilMidnight = tomorrow.getTime() - now.getTime();
    
    const timeoutId = setTimeout(() => {
      setToday(getTodayAtMidnight());
    }, msUntilMidnight);

    return () => clearTimeout(timeoutId);
  }, [today]); // Re-run when today changes (after midnight)
  
  const selectedDate = value ? new Date(value + 'T00:00:00') : null;
  
  const [viewDate, setViewDate] = useState(() => {
    if (selectedDate) return new Date(selectedDate);
    return new Date(today);
  });

  const monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
  ];

  const dayNames = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

  // Calculate calendar days for the current view month
  const calendarDays = useMemo(() => {
    const year = viewDate.getFullYear();
    const month = viewDate.getMonth();
    
    // First day of the month
    const firstDay = new Date(year, month, 1);
    // Last day of the month
    const lastDay = new Date(year, month + 1, 0);
    
    // Start from the Sunday of the week containing the first day
    const startDate = new Date(firstDay);
    startDate.setDate(startDate.getDate() - firstDay.getDay());
    
    // End on the Saturday of the week containing the last day
    const endDate = new Date(lastDay);
    endDate.setDate(endDate.getDate() + (6 - lastDay.getDay()));
    
    const days: Date[] = [];
    const current = new Date(startDate);
    
    while (current <= endDate) {
      days.push(new Date(current));
      current.setDate(current.getDate() + 1);
    }
    
    return days;
  }, [viewDate]);

  const goToPreviousMonth = () => {
    setViewDate(prev => {
      const newDate = new Date(prev);
      newDate.setMonth(newDate.getMonth() - 1);
      return newDate;
    });
  };

  const goToNextMonth = () => {
    setViewDate(prev => {
      const newDate = new Date(prev);
      newDate.setMonth(newDate.getMonth() + 1);
      return newDate;
    });
  };

  const isDateDisabled = (date: Date): boolean => {
    // Check min/max date constraints
    if (minDate) {
      const min = new Date(minDate + 'T00:00:00');
      if (date < min) return true;
    }
    if (maxDate) {
      const max = new Date(maxDate + 'T00:00:00');
      if (date > max) return true;
    }
    
    // Check if barber is available on this day of the week
    if (weeklySchedule) {
      const dayOfWeek = date.getDay(); // 0 = Sunday, 1 = Monday, etc.
      const dayKey = dayIndexToKey[dayOfWeek];
      const daySchedule = weeklySchedule[dayKey];
      
      // If the day is not enabled in the barber's schedule, disable it
      if (!daySchedule?.enabled) {
        return true;
      }
      
      // For new multi-interval format: check if there are any intervals
      // (supports both new format with intervals array and legacy format with start/end)
      if (daySchedule.intervals !== undefined) {
        // New format: check if intervals array has any entries
        if (!Array.isArray(daySchedule.intervals) || daySchedule.intervals.length === 0) {
          return true;
        }
      } else if (!daySchedule.start || !daySchedule.end) {
        // Legacy format: check if start and end are defined
        return true;
      }
    }
    
    return false;
  };

  const isToday = (date: Date): boolean => {
    return date.toDateString() === today.toDateString();
  };

  const isSelected = (date: Date): boolean => {
    return selectedDate ? date.toDateString() === selectedDate.toDateString() : false;
  };

  const isCurrentMonth = (date: Date): boolean => {
    return date.getMonth() === viewDate.getMonth();
  };

  const handleDateClick = (date: Date) => {
    if (isDateDisabled(date)) return;
    
    // Format as YYYY-MM-DD
    const year = date.getFullYear();
    const month = String(date.getMonth() + 1).padStart(2, '0');
    const day = String(date.getDate()).padStart(2, '0');
    onChange(`${year}-${month}-${day}`);
  };

  // Group days into weeks
  const weeks: Date[][] = [];
  for (let i = 0; i < calendarDays.length; i += 7) {
    weeks.push(calendarDays.slice(i, i + 7));
  }

  return (
    <div className="w-full">
      {label && (
        <label className="block text-sm font-medium text-gray-700 mb-3">
          {label}
        </label>
      )}
      
      <div className="bg-white border border-gray-200 rounded-xl p-4 shadow-sm">
        {/* Header with month/year and navigation */}
        <div className="flex items-center justify-between mb-4">
          <button
            type="button"
            onClick={goToPreviousMonth}
            className="p-2 hover:bg-gray-100 rounded-lg transition-colors"
            aria-label="Previous month"
          >
            <ChevronLeft className="w-5 h-5 text-gray-600" />
          </button>
          
          <h3 className="text-lg font-semibold text-gray-900">
            {monthNames[viewDate.getMonth()]} {viewDate.getFullYear()}
          </h3>
          
          <button
            type="button"
            onClick={goToNextMonth}
            className="p-2 hover:bg-gray-100 rounded-lg transition-colors"
            aria-label="Next month"
          >
            <ChevronRight className="w-5 h-5 text-gray-600" />
          </button>
        </div>

        {/* Day headers */}
        <div className="grid grid-cols-7 mb-2">
          {dayNames.map(day => (
            <div
              key={day}
              className="text-center text-xs font-medium text-gray-500 py-2"
            >
              {day}
            </div>
          ))}
        </div>

        {/* Calendar grid */}
        <div className="space-y-1">
          {weeks.map((week, weekIndex) => (
            <div key={weekIndex} className="grid grid-cols-7 gap-1">
              {week.map((date, dayIndex) => {
                const disabled = isDateDisabled(date);
                const selected = isSelected(date);
                const todayDate = isToday(date);
                const currentMonth = isCurrentMonth(date);

                return (
                  <button
                    key={dayIndex}
                    type="button"
                    onClick={() => handleDateClick(date)}
                    disabled={disabled}
                    className={`
                      relative w-full aspect-square flex items-center justify-center
                      text-sm font-medium rounded-lg transition-all
                      ${disabled 
                        ? 'text-gray-300 cursor-not-allowed' 
                        : 'hover:bg-primary-50 cursor-pointer'
                      }
                      ${!currentMonth && !disabled ? 'text-gray-400' : ''}
                      ${currentMonth && !disabled && !selected ? 'text-gray-900' : ''}
                      ${selected 
                        ? 'bg-primary-500 text-white hover:bg-primary-600' 
                        : ''
                      }
                    `}
                  >
                    <span>{date.getDate()}</span>
                    {/* Today indicator dot */}
                    {todayDate && !selected && (
                      <div className="absolute bottom-1 left-1/2 transform -translate-x-1/2 w-1 h-1 bg-primary-500 rounded-full" />
                    )}
                  </button>
                );
              })}
            </div>
          ))}
        </div>

        {/* Selected date display */}
        {selectedDate && (
          <div className="mt-4 pt-4 border-t border-gray-100 text-center">
            <p className="text-sm text-gray-600">
              Selected: <span className="font-semibold text-gray-900">
                {selectedDate.toLocaleDateString('en-US', { 
                  weekday: 'long', 
                  month: 'long', 
                  day: 'numeric',
                  year: 'numeric'
                })}
              </span>
            </p>
          </div>
        )}
      </div>
    </div>
  );
}

