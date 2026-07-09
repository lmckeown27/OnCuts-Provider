/**
 * useGeolocation Hook
 * 
 * Provides browser-based geolocation with permission handling.
 * Used to determine closest barbers to the user.
 * Automatically syncs location to backend for authenticated users.
 * 
 * LOCATION UPDATE POLICY:
 * - Fresh location is fetched every time the app is opened
 * - Location is synced to backend on every update
 * - This ensures users who move (e.g., between universities) always see nearby barbers
 */

import { useState, useEffect, useCallback, useRef } from 'react';
import { useAuthStore } from '../store/useAuthStore';
import locationService from '../services/location.service';

export interface GeolocationState {
  latitude: number | null;
  longitude: number | null;
  accuracy: number | null;
  error: string | null;
  loading: boolean;
  permissionStatus: 'prompt' | 'granted' | 'denied' | 'unavailable';
}

export interface UseGeolocationReturn extends GeolocationState {
  requestLocation: () => void;
  clearLocation: () => void;
  syncToBackend: () => Promise<void>;
  refreshLocation: () => void; // Force refresh location
}

const STORAGE_KEY = 'campuscut_user_location';
const PERMISSION_KEY = 'campuscut_location_permission';

// Calculate distance between two points using Haversine formula (returns km)
export function calculateDistance(
  lat1: number,
  lon1: number,
  lat2: number,
  lon2: number
): number {
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

// Convert km to miles
export function kmToMiles(km: number): number {
  return km * 0.621371;
}

export function useGeolocation(): UseGeolocationReturn {
  const [state, setState] = useState<GeolocationState>({
    latitude: null,
    longitude: null,
    accuracy: null,
    error: null,
    loading: false,
    permissionStatus: 'prompt',
  });
  
  const { isAuthenticated } = useAuthStore();
  const hasAutoRequestedRef = useRef(false);

  // Sync location to backend for authenticated users
  const syncToBackend = useCallback(async () => {
    if (!isAuthenticated) return;
    
    try {
      await locationService.updateLocation({
        latitude: state.latitude ?? undefined,
        longitude: state.longitude ?? undefined,
        permission: state.permissionStatus,
      });
    } catch (error) {
      console.warn('Failed to sync location to backend:', error);
      // Don't throw - this is a non-critical operation
    }
  }, [isAuthenticated, state.latitude, state.longitude, state.permissionStatus]);

  // Internal function to fetch fresh location
  const fetchFreshLocation = useCallback((isAutoRequest = false) => {
    if (!navigator.geolocation) {
      const newState = {
        latitude: null,
        longitude: null,
        accuracy: null,
        error: 'Geolocation is not supported by your browser',
        loading: false,
        permissionStatus: 'unavailable' as const,
      };
      setState(newState);
      localStorage.setItem(PERMISSION_KEY, 'unavailable');
      return;
    }

    setState(prev => ({ ...prev, loading: true, error: null }));

    navigator.geolocation.getCurrentPosition(
      async (position) => {
        const { latitude, longitude, accuracy } = position.coords;
        
        // Store location and permission status
        localStorage.setItem(STORAGE_KEY, JSON.stringify({
          latitude,
          longitude,
          accuracy,
          timestamp: Date.now(),
        }));
        localStorage.setItem(PERMISSION_KEY, 'granted');

        setState({
          latitude,
          longitude,
          accuracy,
          error: null,
          loading: false,
          permissionStatus: 'granted',
        });

        // Always sync to backend for authenticated users
        if (isAuthenticated) {
          try {
            await locationService.updateLocation({
              latitude,
              longitude,
              permission: 'granted',
            });
            console.log('[Geolocation] Location synced to backend:', { latitude, longitude });
          } catch (error) {
            console.warn('Failed to sync location to backend:', error);
          }
        }
      },
      async (error) => {
        let errorMessage = 'Unable to get your location';
        let permissionStatus: GeolocationState['permissionStatus'] = 'denied';

        switch (error.code) {
          case error.PERMISSION_DENIED:
            errorMessage = 'Location permission denied';
            permissionStatus = 'denied';
            localStorage.setItem(PERMISSION_KEY, 'denied');
            break;
          case error.POSITION_UNAVAILABLE:
            errorMessage = 'Location information unavailable';
            permissionStatus = 'prompt';
            break;
          case error.TIMEOUT:
            errorMessage = 'Location request timed out';
            permissionStatus = 'prompt';
            break;
        }

        setState(prev => ({
          ...prev,
          error: errorMessage,
          loading: false,
          permissionStatus,
        }));

        // Sync denied status to backend
        if (isAuthenticated && permissionStatus === 'denied') {
          try {
            await locationService.updateLocation({ permission: 'denied' });
          } catch (err) {
            console.warn('Failed to sync location denial to backend:', err);
          }
        }
      },
      {
        enableHighAccuracy: true,
        timeout: 10000,
        maximumAge: 0, // Always get fresh location, no caching
      }
    );
  }, [isAuthenticated]);

  // Check permission status on mount and auto-request if previously granted
  useEffect(() => {
    if (!navigator.geolocation) {
      setState(prev => ({ ...prev, permissionStatus: 'unavailable' }));
      return;
    }

    // Check stored permission status
    const storedPermission = localStorage.getItem(PERMISSION_KEY);
    
    // Check permission status via Permissions API
    if (navigator.permissions) {
      navigator.permissions.query({ name: 'geolocation' }).then((result) => {
        const currentPermission = result.state as 'prompt' | 'granted' | 'denied';
        setState(prev => ({ ...prev, permissionStatus: currentPermission }));
        
        // Auto-request fresh location if permission was previously granted
        // This ensures we always have fresh location on app open
        if (currentPermission === 'granted' && !hasAutoRequestedRef.current) {
          hasAutoRequestedRef.current = true;
          console.log('[Geolocation] Auto-requesting fresh location (permission already granted)');
          fetchFreshLocation(true);
        }
        
        result.onchange = () => {
          setState(prev => ({ ...prev, permissionStatus: result.state as any }));
        };
      }).catch(() => {
        // Permissions API not fully supported, check localStorage
        if (storedPermission === 'granted' && !hasAutoRequestedRef.current) {
          hasAutoRequestedRef.current = true;
          fetchFreshLocation(true);
        }
      });
    } else if (storedPermission === 'granted' && !hasAutoRequestedRef.current) {
      // Fallback: use stored permission status
      hasAutoRequestedRef.current = true;
      fetchFreshLocation(true);
    }
  }, [fetchFreshLocation]);

  // Public method to request location (for initial permission prompt)
  const requestLocation = useCallback(() => {
    fetchFreshLocation(false);
  }, [fetchFreshLocation]);

  // Force refresh location (e.g., when user wants to update)
  const refreshLocation = useCallback(() => {
    console.log('[Geolocation] Manual refresh requested');
    fetchFreshLocation(false);
  }, [fetchFreshLocation]);

  const clearLocation = useCallback(() => {
    localStorage.removeItem(STORAGE_KEY);
    localStorage.removeItem(PERMISSION_KEY);
    hasAutoRequestedRef.current = false;
    setState({
      latitude: null,
      longitude: null,
      accuracy: null,
      error: null,
      loading: false,
      permissionStatus: 'prompt',
    });
  }, []);

  return {
    ...state,
    requestLocation,
    clearLocation,
    syncToBackend,
    refreshLocation,
  };
}

export default useGeolocation;

