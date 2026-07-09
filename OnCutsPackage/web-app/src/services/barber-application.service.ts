import api from './api.service';

export interface BarberApplicationForm {
  campusId: string;
  phoneNumber: string;
  yearsExperience: string;
  hasLicense: boolean;
  licenseNumber?: string;
  specialties: string[];
  hasOwnTools: boolean;
  toolsNeeded?: string;
  availableHours: string;
  whyBeBarber: string;
  portfolioDescription?: string;
  socialMedia?: string;
  additionalNotes?: string;
}

export interface GuestBarberApplicationForm extends BarberApplicationForm {
  firstName: string;
  lastName: string;
  email: string;
  phoneNumber: string;
}

export interface GuestApplicationResponse {
  id: string;
  email: string;
  status: string;
  createdAt: string;
}

export interface BarberApplication {
  id: string;
  user_id: string | null; // null for guest applications where user hasn't signed up yet
  status: 'pending' | 'under_review' | 'interview_scheduled' | 'approved' | 'rejected';
  years_experience: number;
  has_license: boolean;
  license_number?: string;
  specialties: string[];
  has_own_tools: boolean;
  available_hours: string;
  why_be_barber: string;
  phone_number?: string;
  portfolio_description?: string;
  social_media?: string;
  additional_notes?: string;
  created_at: string;
  updated_at?: string;
  reviewed_at?: string;
  interview_scheduled_at?: string;
  // Application type: 'regular' (authenticated user) or 'guest' (landing page submission)
  application_type?: 'regular' | 'guest';
  // User fields returned flat from the backend JOIN
  email?: string;
  first_name?: string;
  last_name?: string;
  campus_name?: string;
  // Nested user object (for alternate response formats)
  user?: {
    id: string;
    email: string;
    first_name: string;
    last_name: string;
    profile_picture_url?: string;
  };
}

export interface SubmitApplicationResponse {
  success: boolean;
  message: string;
  data: {
    applicationId: string;
    status: string;
    submittedAt: string;
  };
}

export interface MyApplicationResponse {
  success: boolean;
  data: BarberApplication | null;
  message?: string;
}

class BarberApplicationService {
  /**
   * Submit a new barber application
   */
  async submit(form: BarberApplicationForm): Promise<{ applicationId: string; status: string; submittedAt: string }> {
    // api.post extracts response.data.data, so we get the inner data object directly
    return api.post<{ applicationId: string; status: string; submittedAt: string }>('/barber-applications', form);
  }

  /**
   * Get current user's application status
   */
  async getMyApplication(): Promise<BarberApplication | null> {
    // api.get extracts response.data.data
    return api.get<BarberApplication | null>('/barber-applications/my-application');
  }

  /**
   * Get all barber applications (admin/campus manager only)
   * @param campusId - Optional campus ID to filter applications by campus
   * @param status - Optional status to filter applications (e.g., 'pending')
   */
  async getAllApplications(campusId?: string, status?: string): Promise<BarberApplication[]> {
    // Backend returns { applications: [...], pagination: {...} }
    // api.get returns response.data when pagination is present
    const params: Record<string, string> = {};
    if (campusId) {
      params.campusId = campusId;
    }
    if (status) {
      params.status = status;
    }
    
    const response = await api.get<{ applications: BarberApplication[]; pagination: any }>('/barber-applications', params);
    
    // Handle different response formats
    if (Array.isArray(response)) {
      return response;
    }
    if (response && Array.isArray(response.applications)) {
      return response.applications;
    }
    return [];
  }

  /**
   * Update application status (admin/campus manager only)
   */
  async updateApplicationStatus(
    applicationId: string, 
    status: 'approved' | 'rejected' | 'interview_scheduled'
  ): Promise<void> {
    await api.put(`/barber-applications/${applicationId}/status`, { status });
  }

  /**
   * Submit a guest barber application (no authentication required)
   * Used from the landing page when user is not logged in
   */
  async submitGuestApplication(form: GuestBarberApplicationForm): Promise<GuestApplicationResponse> {
    return api.post<GuestApplicationResponse>('/barber-applications/guest', form);
  }
}

export const barberApplicationService = new BarberApplicationService();
export default barberApplicationService;

