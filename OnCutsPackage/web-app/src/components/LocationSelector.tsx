/**
 * Location Selector Component
 * 
 * Purpose: Allow users to type and select service locations
 * Features:
 * - Typable input with autocomplete
 * - Shows suggestions as user types
 * - Crowd-sourced + automatically enriched system
 */

import React, { useState, useEffect, useRef } from 'react';
import { MapPin } from 'lucide-react';
import apiService from '../services/api.service';

interface LocationOption {
  id: string;
  name: string;
  category: string;
  cohort: string;
  usageCount: number;
  confidence: number;
  isVerified: boolean;
  aliases?: string[];
}

interface LocationSelectorProps {
  universityId: string;
  selectedLocationId?: string;
  onLocationSelect: (locationId: string, locationName: string) => void;
  className?: string;
}

export const LocationSelector: React.FC<LocationSelectorProps> = ({
  universityId,
  selectedLocationId,
  onLocationSelect,
  className = '',
}) => {
  const [inputValue, setInputValue] = useState('');
  const [suggestions, setSuggestions] = useState<LocationOption[]>([]);
  const [showSuggestions, setShowSuggestions] = useState(false);
  const [selectedLocation, setSelectedLocation] = useState<LocationOption | null>(null);
  const [loading, setLoading] = useState(false);
  const inputRef = useRef<HTMLInputElement>(null);
  const suggestionsRef = useRef<HTMLDivElement>(null);

  // Fetch initial locations
  useEffect(() => {
    fetchLocations();
  }, [universityId]);

  // Handle clicks outside to close suggestions
  useEffect(() => {
    const handleClickOutside = (event: MouseEvent) => {
      if (
        inputRef.current &&
        !inputRef.current.contains(event.target as Node) &&
        suggestionsRef.current &&
        !suggestionsRef.current.contains(event.target as Node)
      ) {
        setShowSuggestions(false);
      }
    };

    document.addEventListener('mousedown', handleClickOutside);
    return () => document.removeEventListener('mousedown', handleClickOutside);
  }, []);

  const fetchLocations = async () => {
    try {
      const response = await apiService.get<{ locations: LocationOption[] }>('/locations', {
        universityId,
      });

      if (response.locations) {
        setSuggestions(response.locations);
      }
    } catch (error: any) {
      console.error('Failed to fetch locations:', error);
      console.error('Error response:', error.response?.data);
      console.error('Validation errors:', error.response?.data?.errors);
    }
  };

  const handleInputChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const value = e.target.value;
    setInputValue(value);
    setShowSuggestions(true);

    // Filter suggestions based on input
    if (value.trim()) {
      fetchLocations();
    }
  };

  const handleSelectSuggestion = (location: LocationOption) => {
    setInputValue(location.name);
    setSelectedLocation(location);
    setShowSuggestions(false);
    onLocationSelect(location.id, location.name);
  };

  const handleCreateNew = async () => {
    if (!inputValue.trim()) return;

    setLoading(true);
    try {
      const newLocation = await apiService.post<{ location: LocationOption }>('/locations/submit', {
        universityId,
        locationName: inputValue.trim(),
        category: 'OTHER', // Default category for user-submitted locations
      });

      if (newLocation?.location) {
        setSelectedLocation(newLocation.location);
        onLocationSelect(newLocation.location.id, newLocation.location.name);
        setShowSuggestions(false);
      }
    } catch (error) {
      console.error('Failed to create location:', error);
      alert('Failed to add location. Please try again.');
    } finally {
      setLoading(false);
    }
  };

  // Filter suggestions based on input
  const filteredSuggestions = suggestions.filter(loc =>
    loc.name.toLowerCase().includes(inputValue.toLowerCase())
  );

  const showCreateNew = inputValue.trim() && 
    !filteredSuggestions.some(loc => 
      loc.name.toLowerCase() === inputValue.toLowerCase()
    );

  return (
    <div className={`flex items-stretch gap-4 ${className}`}>
      {/* Input Field */}
      <div className="relative flex-1 flex items-center">
        <MapPin className="absolute left-3 top-1/2 transform -translate-y-1/2 w-5 h-5 text-gray-400 pointer-events-none z-10" />
        <input
          ref={inputRef}
          type="text"
          value={inputValue}
          onChange={handleInputChange}
          onFocus={() => setShowSuggestions(true)}
          placeholder="Type your location..."
          className="w-full h-full pl-11 pr-4 py-3 border-2 border-gray-300 rounded-lg focus:ring-2 focus:ring-primary-400 focus:border-primary-400 hover:border-primary-300 transition-all bg-white text-gray-700 font-medium"
          autoComplete="off"
        />
      </div>

      {/* Autocomplete Suggestions - Side by Side */}
      {showSuggestions && (filteredSuggestions.length > 0 || showCreateNew) && (
        <div
          ref={suggestionsRef}
          className="flex-1 z-50 bg-white border-2 border-gray-200 rounded-lg shadow-xl overflow-y-auto flex flex-col"
        >
          {filteredSuggestions.length > 0 && (
            <div>
              {filteredSuggestions.map((location) => (
                <button
                  key={location.id}
                  type="button"
                  onClick={() => handleSelectSuggestion(location)}
                  className="w-full text-left px-4 py-3 hover:bg-primary-50 transition-colors border-b border-gray-100 last:border-b-0"
                >
                  <div className="flex items-center justify-between">
                    <div className="flex items-center gap-2">
                      <MapPin className="w-4 h-4 text-gray-400" />
                      <span className="text-gray-900 font-medium">{location.name}</span>
                    </div>
                    {location.isVerified && (
                      <span className="text-xs text-green-600 font-semibold">✓ Verified</span>
                    )}
                  </div>
                  {location.usageCount > 0 && (
                    <div className="text-xs text-gray-500 mt-1 ml-6">
                      Used {location.usageCount} time{location.usageCount !== 1 ? 's' : ''}
                    </div>
                  )}
                </button>
              ))}
            </div>
          )}

          {showCreateNew && (
            <button
              type="button"
              onClick={handleCreateNew}
              disabled={loading}
              className="w-full text-left px-4 py-3 hover:bg-green-50 transition-colors border-t border-gray-200 text-green-600 font-medium"
            >
              <div className="flex items-center gap-2">
                <span className="text-lg">+</span>
                <span>Add "{inputValue}"</span>
              </div>
            </button>
          )}
        </div>
      )}
    </div>
  );
};
