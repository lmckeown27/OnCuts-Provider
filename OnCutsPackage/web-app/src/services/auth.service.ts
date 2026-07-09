import api from './api.service';
import type { User } from '../types';
import { STORAGE_KEYS } from '../config/constants';

interface LoginCredentials {
  email: string;
  password: string;
}

interface SignupData {
  email: string;
  password: string;
  first_name: string;
  last_name: string;
  user_type: 'student' | 'barber';
  campusId?: string; // User-selected campus
}

interface AuthResponse {
  user: User;
  accessToken: string;
  refreshToken: string;
}

interface RegistrationPendingResponse {
  email: string;
  expiresIn: number;
  verificationCode?: string; // Only in dev/auto-verify mode
}

interface VerifyEmailUserData {
  id: string;
  email: string;
  firstName: string;
  lastName: string;
  role: string;
  campusId: number;
  emailVerified: boolean;
}

interface VerifyEmailResponse {
  user: VerifyEmailUserData;
  accessToken: string;
  refreshToken: string;
  suiAddress?: string;
}

class AuthService {
  async login(credentials: LoginCredentials): Promise<AuthResponse> {
    const response = await api.post<AuthResponse>('/auth/login', credentials);
    this.saveAuthData(response);
    return response;
  }

  /**
   * Register a new user - sends email verification code
   * Does NOT authenticate the user - they must verify email first
   */
  async signup(data: SignupData): Promise<RegistrationPendingResponse> {
    // Get user's selected university from localStorage (set in FindBarberPage)
    const UNIVERSITY_STORAGE_KEY = 'campuscut_selected_university';
    let campusId = data.campusId;
    
    // If no campusId provided, try to get from localStorage (user's selected university)
    if (!campusId) {
      const savedUniversity = localStorage.getItem(UNIVERSITY_STORAGE_KEY);
      if (savedUniversity) {
        try {
          const university = JSON.parse(savedUniversity);
          campusId = university.id;
        } catch {
          // Ignore parse errors
        }
      }
    }
    
    const response = await api.post<RegistrationPendingResponse>('/auth/register', {
      email: data.email,
      password: data.password,
      firstName: data.first_name,
      lastName: data.last_name,
      role: data.user_type,
      campusId, // Pass user-selected campus
    });
    
    // Store email for verification page
    localStorage.setItem('pendingVerificationEmail', data.email);
    
    return response;
  }

  /**
   * Verify email with 6-digit code - creates the user account
   */
  async verifyEmail(email: string, code: string): Promise<VerifyEmailResponse> {
    // api.post already extracts the data field from the response
    const response = await api.post<VerifyEmailResponse>('/auth/verify-email', { email, code });
    
    // Save auth data after successful verification
    // Backend returns accessToken and refreshToken (not just "token")
    if (response.user && response.accessToken) {
      localStorage.setItem(STORAGE_KEYS.ACCESS_TOKEN, response.accessToken);
      localStorage.setItem(STORAGE_KEYS.USER, JSON.stringify(response.user));
      // Also save refresh token if provided
      if (response.refreshToken) {
        localStorage.setItem(STORAGE_KEYS.REFRESH_TOKEN, response.refreshToken);
      }
    }
    
    // Clear pending verification email
    localStorage.removeItem('pendingVerificationEmail');
    
    return response;
  }

  /**
   * Resend verification code to email
   */
  async resendVerificationCode(email: string): Promise<RegistrationPendingResponse> {
    // api.post already extracts the data field from the response
    const response = await api.post<RegistrationPendingResponse>('/auth/resend-verification', { email });
    return response;
  }

  /**
   * Get pending verification email from storage
   */
  getPendingVerificationEmail(): string | null {
    return localStorage.getItem('pendingVerificationEmail');
  }

  async getCurrentUser(): Promise<User> {
    return await api.get<User>('/auth/me');
  }

  async logout(): Promise<void> {
    // For JWT-based auth, we just clear local storage
    // No server-side session to invalidate
    this.clearAuthData();
  }

  async refreshToken(): Promise<string> {
    const refreshToken = localStorage.getItem(STORAGE_KEYS.REFRESH_TOKEN);
    if (!refreshToken) {
      throw new Error('No refresh token available');
    }
    
    const response = await api.post<{ accessToken: string }>('/auth/refresh-token', {
      refreshToken,
    });
    
    localStorage.setItem(STORAGE_KEYS.ACCESS_TOKEN, response.accessToken);
    return response.accessToken;
  }

  async requestPasswordReset(email: string): Promise<void> {
    await api.post('/auth/request-password-reset', { email });
  }

  async resetPassword(token: string, newPassword: string): Promise<void> {
    await api.post('/auth/reset-password', { token, newPassword });
  }

  private saveAuthData(data: AuthResponse): void {
    // Only save tokens if they are valid strings (not null/undefined)
    if (data.accessToken && typeof data.accessToken === 'string') {
      localStorage.setItem(STORAGE_KEYS.ACCESS_TOKEN, data.accessToken);
    } else {
      console.error('Invalid accessToken received from login:', data.accessToken);
    }
    if (data.refreshToken && typeof data.refreshToken === 'string') {
      localStorage.setItem(STORAGE_KEYS.REFRESH_TOKEN, data.refreshToken);
    } else {
      console.error('Invalid refreshToken received from login:', data.refreshToken);
    }
    if (data.user) {
      localStorage.setItem(STORAGE_KEYS.USER, JSON.stringify(data.user));
    }
  }

  private clearAuthData(): void {
    localStorage.removeItem(STORAGE_KEYS.ACCESS_TOKEN);
    localStorage.removeItem(STORAGE_KEYS.REFRESH_TOKEN);
    localStorage.removeItem(STORAGE_KEYS.USER);
  }

  getStoredUser(): User | null {
    const userStr = localStorage.getItem(STORAGE_KEYS.USER);
    return userStr ? JSON.parse(userStr) : undefined;
  }

  isAuthenticated(): boolean {
    return !!localStorage.getItem(STORAGE_KEYS.ACCESS_TOKEN);
  }
}

export default new AuthService();

