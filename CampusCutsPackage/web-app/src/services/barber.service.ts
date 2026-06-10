import api from './api.service';
import type { Barber, PaginatedResponse, Review, PortfolioImage } from '../types';

interface BarberFilters {
  campus_id?: string;
  min_price?: number;
  max_price?: number;
  min_rating?: number;
  specialties?: string[];
  page?: number;
  limit?: number;
  // Location-based filtering
  lat?: number;
  lng?: number;
  maxDistance?: number; // Maximum distance in km (default: 8km / ~5 miles)
  // Campus manager option to include hidden barbers
  includeHidden?: boolean;
}

class BarberService {
  async getBarbers(filters: BarberFilters = {}): Promise<PaginatedResponse<Barber>> {
    return await api.get<PaginatedResponse<Barber>>('/barbers', filters);
  }

  /**
   * Get barbers sorted by distance from user's location
   * When campusId is provided, shows ALL barbers for that campus (regardless of distance)
   * Distance is still calculated for display purposes
   */
  async getBarbersByLocation(
    latitude: number, 
    longitude: number, 
    filters: Omit<BarberFilters, 'lat' | 'lng'> = {},
    maxDistanceKm: number = 8, // Default: 8km (~5 miles) - only applies when no campusId
    campusId?: string // When provided, shows all barbers for this campus
  ): Promise<PaginatedResponse<Barber>> {
    return await api.get<PaginatedResponse<Barber>>('/barbers', {
      ...filters,
      lat: latitude,
      lng: longitude,
      maxDistance: maxDistanceKm,
      campusId, // Pass campusId to disable distance filtering
    });
  }

  async getBarberById(id: string): Promise<Barber> {
    return await api.get<Barber>(`/barbers/${id}`);
  }

  async getBarberByUserId(userId: string): Promise<Barber | null> {
    try {
      return await api.get<Barber>(`/barbers/user/${userId}`);
    } catch {
      return null;
    }
  }

  async getMyBarberProfile(): Promise<Barber | null> {
    try {
      return await api.get<Barber>('/barbers/me');
    } catch {
      return null;
    }
  }

  async createBarberProfile(data: Partial<Barber>): Promise<Barber> {
    return await api.post<Barber>('/barbers', data);
  }

  async updateBarberProfile(id: string, data: Partial<Barber>): Promise<Barber> {
    return await api.put<Barber>(`/barbers/${id}`, data);
  }

  async getBarberReviews(barberId: string, page = 1, limit = 20): Promise<PaginatedResponse<Review>> {
    return await api.get<PaginatedResponse<Review>>(`/barbers/${barberId}/reviews`, { page, limit });
  }

  async getBarberAvailability(barberId: string, date?: string): Promise<any> {
    return await api.get(`/barbers/${barberId}/availability`, { date });
  }

  async uploadPortfolioImages(barberId: string, files: File[]): Promise<PortfolioImage[]> {
    const formData = new FormData();
    files.forEach(file => formData.append('images', file));
    return await api.upload<PortfolioImage[]>(`/upload/portfolio`, formData);
  }

  async deletePortfolioImage(imageId: string): Promise<void> {
    await api.delete(`/barbers/portfolio/${imageId}`);
  }

  async toggleVacationMode(barberId: string, isActive: boolean): Promise<Barber> {
    return await api.put<Barber>(`/barbers/${barberId}`, { is_active: isActive });
  }

  /**
   * Remove barber (demote to consumer) - Campus Manager only
   */
  async removeBarber(barberId: string): Promise<{ success: boolean; message: string }> {
    return await api.post<{ success: boolean; message: string }>(`/barbers/${barberId}/remove`, {});
  }

  // =====================================================
  // TIME BLOCKS - One-time date-specific availability blocks
  // =====================================================

  /**
   * Get barber's time blocks
   */
  async getTimeBlocks(barberId: string, startDate?: string, endDate?: string): Promise<TimeBlock[]> {
    const params: Record<string, string> = {};
    if (startDate) params.startDate = startDate;
    if (endDate) params.endDate = endDate;
    // api.get already extracts response.data.data, so we get TimeBlock[] directly
    const blocks = await api.get<TimeBlock[]>(`/barbers/${barberId}/time-blocks`, params);
    return blocks || [];
  }

  /**
   * Create a new time block
   */
  async createTimeBlock(barberId: string, block: CreateTimeBlockData): Promise<TimeBlock> {
    // api.post already extracts response.data.data
    return await api.post<TimeBlock>(`/barbers/${barberId}/time-blocks`, block);
  }

  /**
   * Delete a time block
   */
  async deleteTimeBlock(barberId: string, blockId: string): Promise<void> {
    await api.delete(`/barbers/${barberId}/time-blocks/${blockId}`);
  }
}

// Time block types
export interface TimeBlock {
  id: string;
  blockDate: string;
  startTime: string;
  endTime: string;
  reason?: string;
  createdAt: string;
}

export interface CreateTimeBlockData {
  blockDate: string;
  startTime: string;
  endTime: string;
  reason?: string;
}

export default new BarberService();

