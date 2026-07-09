/**
 * UniversitySelector Component
 * 
 * Searchable dropdown for selecting a US university.
 * Fetches universities from the database API.
 * 
 * Features:
 * - Type-ahead search with autocomplete
 * - Shows university name, city, and state
 * - Keyboard navigation support
 * - Mobile-friendly touch targets
 * - Caches results to reduce API calls
 */

import { useState, useEffect, useRef, useCallback } from 'react';
import { Search, ChevronDown, X, GraduationCap, Loader2 } from 'lucide-react';
import campusService from '../services/campus.service';
import type { Campus } from '../types';

// Re-export Campus as University for backward compatibility
export type University = Campus;

interface UniversitySelectorProps {
  value: Campus | null;
  onChange: (university: Campus | null) => void;
  placeholder?: string;
  className?: string;
}

// Cache for all universities (loaded once)
let universitiesCache: Campus[] | null = null;
let cachePromise: Promise<Campus[]> | null = null;

// Load all universities (with caching)
async function loadUniversities(): Promise<Campus[]> {
  if (universitiesCache) {
    return universitiesCache;
  }
  
  if (cachePromise) {
    return cachePromise;
  }
  
  cachePromise = campusService.getCampuses().then(campuses => {
    universitiesCache = campuses;
    return campuses;
  });
  
  return cachePromise;
}

// Search universities client-side (after loading all)
function searchUniversities(universities: Campus[], query: string, limit: number = 8): Campus[] {
  if (!query || query.length < 1) return [];
  
  const lowerQuery = query.toLowerCase();
  
  // Split into exact start matches and contains matches
  const startsWithMatches: Campus[] = [];
  const containsMatches: Campus[] = [];
  
  for (const uni of universities) {
    const nameLower = uni.name.toLowerCase();
    const slugLower = uni.slug?.toLowerCase() || '';
    const cityLower = uni.city.toLowerCase();
    const shortNameLower = uni.shortName?.toLowerCase() || '';
    
    // Check if name, slug, or shortName STARTS with the query
    if (nameLower.startsWith(lowerQuery) || slugLower.startsWith(lowerQuery) || shortNameLower.startsWith(lowerQuery)) {
      startsWithMatches.push(uni);
    } 
    // Otherwise check if it contains the query anywhere
    else if (
      nameLower.includes(lowerQuery) ||
      slugLower.includes(lowerQuery) ||
      cityLower.includes(lowerQuery) ||
      shortNameLower.includes(lowerQuery)
    ) {
      containsMatches.push(uni);
    }
  }
  
  // Return starts-with matches first, then contains matches
  return [...startsWithMatches, ...containsMatches].slice(0, limit);
}

// Helper to get display name (use shortName from campus service if available)
function getDisplayName(uni: Campus): { shortName?: string; fullName: string } {
  // Use the shortName derived by campus.service.ts (from UNIVERSITY_SHORT_NAMES mapping)
  // This provides proper abbreviations like "UCLA", "USC", "Cal Poly SLO", etc.
  if (uni.shortName) {
    return { shortName: uni.shortName, fullName: uni.name };
  }
  // Otherwise just show the full name
  return { fullName: uni.name };
}

export default function UniversitySelector({
  value,
  onChange,
  placeholder = "Search for your university...",
  className = "",
}: UniversitySelectorProps) {
  const [isOpen, setIsOpen] = useState(false);
  const [searchQuery, setSearchQuery] = useState('');
  const [results, setResults] = useState<Campus[]>([]);
  const [highlightedIndex, setHighlightedIndex] = useState(0);
  const [allUniversities, setAllUniversities] = useState<Campus[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [loadError, setLoadError] = useState<string | null>(null);
  const inputRef = useRef<HTMLInputElement>(null);
  const dropdownRef = useRef<HTMLDivElement>(null);
  const containerRef = useRef<HTMLDivElement>(null);

  // Load universities on mount
  useEffect(() => {
    setIsLoading(true);
    setLoadError(null);
    
    loadUniversities()
      .then(unis => {
        setAllUniversities(unis);
        setIsLoading(false);
      })
      .catch(err => {
        console.error('Failed to load universities:', err);
        setLoadError('Failed to load universities');
        setIsLoading(false);
      });
  }, []);

  // Search universities when query changes
  useEffect(() => {
    if (searchQuery.length >= 1 && allUniversities.length > 0) {
      const matches = searchUniversities(allUniversities, searchQuery, 8);
      setResults(matches);
      setHighlightedIndex(0);
    } else {
      setResults([]);
    }
  }, [searchQuery, allUniversities]);

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

  // Handle keyboard navigation
  const handleKeyDown = useCallback((e: React.KeyboardEvent) => {
    if (!isOpen) {
      if (e.key === 'ArrowDown' || e.key === 'Enter') {
        setIsOpen(true);
      }
      return;
    }

    switch (e.key) {
      case 'ArrowDown':
        e.preventDefault();
        setHighlightedIndex(prev => Math.min(prev + 1, results.length - 1));
        break;
      case 'ArrowUp':
        e.preventDefault();
        setHighlightedIndex(prev => Math.max(prev - 1, 0));
        break;
      case 'Enter':
        e.preventDefault();
        if (results[highlightedIndex]) {
          handleSelect(results[highlightedIndex]);
        }
        break;
      case 'Escape':
        setIsOpen(false);
        inputRef.current?.blur();
        break;
    }
  }, [isOpen, results, highlightedIndex]);

  // Handle selection
  const handleSelect = (university: Campus) => {
    onChange(university);
    setSearchQuery('');
    setIsOpen(false);
    inputRef.current?.blur();
  };

  // Clear selection
  const handleClear = (e: React.MouseEvent) => {
    e.stopPropagation();
    onChange(null);
    setSearchQuery('');
    setResults([]);
    setIsOpen(true);
    inputRef.current?.focus();
  };

  // Get display value for input
  const getInputDisplayValue = () => {
    if (value) {
      return `${value.name} — ${value.city}, ${value.state}`;
    }
    return searchQuery;
  };

  return (
    <div ref={containerRef} className={`relative ${className}`}>
      {/* Input Field */}
      <div
        className={`relative flex items-center bg-white border-2 rounded-xl transition-all ${
          isOpen ? 'border-primary-500 shadow-lg' : 'border-gray-200 hover:border-gray-300'
        }`}
      >
        <input
          ref={inputRef}
          type="text"
          value={getInputDisplayValue()}
          onChange={(e) => {
            setSearchQuery(e.target.value);
            if (!isOpen) setIsOpen(true);
          }}
          onFocus={() => {
            if (!value) setIsOpen(true);
          }}
          onKeyDown={handleKeyDown}
          placeholder={placeholder}
          className="flex-1 pl-12 pr-3 py-3 text-gray-900 placeholder-gray-400 bg-transparent outline-none text-base text-center"
          readOnly={!!value}
          onClick={() => {
            if (value) {
              // Clear selection and allow re-search
              onChange(null);
              setSearchQuery('');
              setIsOpen(true);
            }
          }}
        />
        
        {value ? (
          <button
            onClick={handleClear}
            className="p-2 mr-2 text-gray-400 hover:text-gray-600 transition-colors"
          >
            <X className="w-5 h-5" />
          </button>
        ) : (
          <button
            type="button"
            onClick={(e) => {
              e.stopPropagation();
              if (isOpen) {
                setIsOpen(false);
                inputRef.current?.blur();
              } else {
                setIsOpen(true);
                inputRef.current?.focus();
              }
            }}
            className="pr-4 pl-2 py-3 text-gray-400 hover:text-gray-600 transition-colors"
          >
            {isLoading ? (
              <Loader2 className="w-5 h-5 animate-spin" />
            ) : (
              <ChevronDown className={`w-5 h-5 transition-transform ${isOpen ? 'rotate-180' : ''}`} />
            )}
          </button>
        )}
      </div>

      {/* Dropdown Results */}
      {isOpen && (
        <div
          ref={dropdownRef}
          className="absolute z-50 w-full mt-2 bg-white border border-gray-200 rounded-xl shadow-xl max-h-80 overflow-y-auto"
        >
          {isLoading ? (
            <div className="p-4 text-center text-gray-500">
              <Loader2 className="w-8 h-8 mx-auto mb-2 text-primary-400 animate-spin" />
              <p>Loading universities...</p>
            </div>
          ) : loadError ? (
            <div className="p-4 text-center text-red-500">
              <GraduationCap className="w-8 h-8 mx-auto mb-2 text-red-300" />
              <p>{loadError}</p>
              <button 
                onClick={() => {
                  universitiesCache = null;
                  cachePromise = null;
                  setIsLoading(true);
                  loadUniversities()
                    .then(unis => {
                      setAllUniversities(unis);
                      setIsLoading(false);
                      setLoadError(null);
                    })
                    .catch(() => setIsLoading(false));
                }}
                className="mt-2 text-sm text-primary-600 hover:underline"
              >
                Try again
              </button>
            </div>
          ) : searchQuery.length === 0 ? (
            <div className="p-4 text-center text-gray-500">
              <Search className="w-8 h-8 mx-auto mb-2 text-gray-300" />
              <p>Start typing to search</p>
              <p className="text-xs mt-1 text-gray-400">{allUniversities.length} universities available</p>
            </div>
          ) : results.length === 0 ? (
            <div className="p-4 text-center text-gray-500">
              <GraduationCap className="w-8 h-8 mx-auto mb-2 text-gray-300" />
              <p>No universities found</p>
              <p className="text-sm mt-1">Try a different search term</p>
            </div>
          ) : (
            <ul className="py-2">
              {results.map((university, index) => {
                const { shortName, fullName } = getDisplayName(university);
                return (
                  <li key={university.id}>
                    <button
                      onClick={() => handleSelect(university)}
                      onMouseEnter={() => setHighlightedIndex(index)}
                      className={`w-full px-4 py-3 text-left transition-colors ${
                        index === highlightedIndex
                          ? 'bg-primary-50 text-primary-900'
                          : 'hover:bg-gray-50'
                      }`}
                    >
                      <p className="font-medium text-gray-900">
                        {shortName ? (
                          <>
                            {shortName}
                            <span className="font-normal text-gray-500"> - {fullName}</span>
                          </>
                        ) : (
                          fullName
                        )}
                      </p>
                      <p className="text-sm text-gray-500">{university.city}, {university.state}</p>
                    </button>
                  </li>
                );
              })}
            </ul>
          )}
        </div>
      )}
    </div>
  );
}

// Export helper functions for external use
export function getUniversityById(id: string): Campus | undefined {
  return universitiesCache?.find(uni => uni.id === id);
}

export async function getNearestUniversity(lat: number, lng: number): Promise<Campus | undefined> {
  const universities = await loadUniversities();
  
  if (!lat || !lng || universities.length === 0) return undefined;
  
  let nearest: Campus | undefined;
  let minDistance = Infinity;
  
  for (const uni of universities) {
    if (!uni.latitude || !uni.longitude) continue;
    
    const distance = haversineDistance(lat, lng, uni.latitude, uni.longitude);
    if (distance < minDistance) {
      minDistance = distance;
      nearest = uni;
    }
  }
  
  return nearest;
}

// Haversine formula to calculate distance between two points
function haversineDistance(lat1: number, lon1: number, lat2: number, lon2: number): number {
  const R = 6371; // Earth's radius in km
  const dLat = toRad(lat2 - lat1);
  const dLon = toRad(lon2 - lon1);
  const a = 
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) *
    Math.sin(dLon / 2) * Math.sin(dLon / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return R * c;
}

function toRad(deg: number): number {
  return deg * (Math.PI / 180);
}
