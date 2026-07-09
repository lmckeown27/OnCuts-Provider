/**
 * Location Service
 * 
 * Handles saving and retrieving user location data from the backend.
 */

import api from './api.service';

export interface LocationData {
  latitude: number | null;
  longitude: number | null;
  permission: 'granted' | 'denied' | 'prompt' | 'unavailable';
  updated_at?: string;
}

export interface UpdateLocationRequest {
  latitude?: number;
  longitude?: number;
  permission: 'granted' | 'denied' | 'prompt' | 'unavailable';
}

class LocationService {
  /**
   * Update user's location on the backend
   */
  async updateLocation(data: UpdateLocationRequest): Promise<LocationData> {
    const response = await api.put<{ success: boolean; data: LocationData }>('/users/location', data);
    return response.data;
  }

  /**
   * Get user's current location from backend
   */
  async getLocation(): Promise<LocationData> {
    const response = await api.get<{ success: boolean; data: LocationData }>('/users/location');
    return response.data;
  }

  /**
   * Update barber's service location
   */
  async updateBarberServiceLocation(data: {
    latitude?: number;
    longitude?: number;
    service_radius_km?: number;
  }): Promise<{ service_latitude: number; service_longitude: number; service_radius_km: number }> {
    const response = await api.put<{ success: boolean; data: any }>('/barbers/service-location', data);
    return response.data;
  }
}

export const locationService = new LocationService();
export default locationService;

