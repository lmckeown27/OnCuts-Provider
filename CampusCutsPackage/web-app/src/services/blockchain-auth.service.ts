/**
 * Blockchain-First Authentication Service
 * 
 * Handles authentication using the blockchain-backed auth endpoints.
 * Users sign up with email/password, backend creates blockchain accounts.
 * 
 * Key Features:
 * - Optimistic responses
 * - Automatic retry on failure
 * - Caching with React Query
 */

import axios from 'axios';

const API_BASE_URL = import.meta.env.VITE_API_BASE_URL || 'http://localhost:3001';

export interface SignupData {
  email: string;
  password: string;
  username: string;
  campus_domain: string;
  role: 'student' | 'barber';
}

export interface LoginData {
  email: string;
  password: string;
}

export interface User {
  address: string; // Legacy hex wallet id
  email: string;
  username?: string;
  role: 'student' | 'barber';
  campusDomain?: string;
  profilePhotoCid?: string;
  balance?: string;
}

export interface AuthResponse {
  success: boolean;
  message?: string;
  data?: {
    token: string;
    user: User;
  };
}

class BlockchainAuthService {
  private token: string | null = null;

  constructor() {
    // Load token from localStorage on init
    this.token = localStorage.getItem('auth_token');
    
    // Set up axios interceptor to include token
    axios.interceptors.request.use((config) => {
      if (this.token) {
        config.headers.Authorization = `Bearer ${this.token}`;
      }
      return config;
    });
  }

  /**
   * Sign up a new user (creates blockchain account behind the scenes)
   */
  async signup(data: SignupData): Promise<AuthResponse> {
    try {
      const response = await axios.post<AuthResponse>(
        `${API_BASE_URL}/api/auth-blockchain/signup`,
        data,
        {
          headers: { 'Content-Type': 'application/json' },
          timeout: 30000, // 30 second timeout for blockchain tx
        }
      );

      if (response.data.success && response.data.data) {
        // Store token
        this.token = response.data.data.token;
        localStorage.setItem('auth_token', this.token);
        localStorage.setItem('user', JSON.stringify(response.data.data.user));
      }

      return response.data;
    } catch (error: any) {
      console.error('Signup error:', error);
      return {
        success: false,
        message: error.response?.data?.message || 'Failed to create account. Please try again.',
      };
    }
  }

  /**
   * Login (authenticates and loads blockchain account)
   */
  async login(data: LoginData): Promise<AuthResponse> {
    try {
      const response = await axios.post<AuthResponse>(
        `${API_BASE_URL}/api/auth-blockchain/login`,
        data,
        {
          headers: { 'Content-Type': 'application/json' },
          timeout: 30000,
        }
      );

      if (response.data.success && response.data.data) {
        // Store token
        this.token = response.data.data.token;
        localStorage.setItem('auth_token', this.token);
        localStorage.setItem('user', JSON.stringify(response.data.data.user));
      }

      return response.data;
    } catch (error: any) {
      console.error('Login error:', error);
      return {
        success: false,
        message: error.response?.data?.message || 'Invalid email or password.',
      };
    }
  }

  /**
   * Logout
   */
  async logout(): Promise<void> {
    try {
      await axios.post(`${API_BASE_URL}/api/auth-blockchain/logout`);
    } catch (error) {
      console.error('Logout error:', error);
    } finally {
      this.token = null;
      localStorage.removeItem('auth_token');
      localStorage.removeItem('user');
    }
  }

  /**
   * Get current user (from blockchain)
   */
  async getMe(): Promise<{ success: boolean; user?: User; message?: string }> {
    try {
      const response = await axios.get(`${API_BASE_URL}/api/auth-blockchain/me`, {
        timeout: 15000,
      });

      return {
        success: true,
        user: response.data.user,
      };
    } catch (error: any) {
      console.error('Get user error:', error);
      return {
        success: false,
        message: error.response?.data?.message || 'Failed to fetch user data.',
      };
    }
  }

  /**
   * Update profile (on-chain transaction)
   */
  async updateProfile(data: {
    username?: string;
    bio?: string;
    campusDomain?: string;
    role?: string;
  }): Promise<{ success: boolean; message?: string }> {
    try {
      const response = await axios.put(
        `${API_BASE_URL}/api/auth-blockchain/profile`,
        data,
        { timeout: 30000 } // Blockchain tx might take time
      );

      return {
        success: true,
        message: 'Profile updated successfully!',
      };
    } catch (error: any) {
      console.error('Update profile error:', error);
      return {
        success: false,
        message: error.response?.data?.message || 'Failed to update profile.',
      };
    }
  }

  /**
   * Upload profile photo (IPFS + on-chain CID)
   */
  async uploadProfilePhoto(file: File): Promise<{
    success: boolean;
    cid?: string;
    url?: string;
    message?: string;
  }> {
    try {
      const formData = new FormData();
      formData.append('profilePhoto', file);

      const response = await axios.post(
        `${API_BASE_URL}/api/auth-blockchain/profile/photo`,
        formData,
        {
          headers: { 'Content-Type': 'multipart/form-data' },
          timeout: 60000, // IPFS upload + blockchain tx
        }
      );

      return {
        success: true,
        cid: response.data.cid,
        url: response.data.url,
        message: 'Profile photo updated!',
      };
    } catch (error: any) {
      console.error('Upload photo error:', error);
      return {
        success: false,
        message: error.response?.data?.message || 'Failed to upload profile photo.',
      };
    }
  }

  /**
   * Check if user is authenticated
   */
  isAuthenticated(): boolean {
    return !!this.token;
  }

  /**
   * Get stored user data
   */
  getCurrentUser(): User | null {
    const userStr = localStorage.getItem('user');
    if (!userStr) return null;
    try {
      return JSON.parse(userStr);
    } catch {
      return null;
    }
  }

  /**
   * Get auth token
   */
  getToken(): string | null {
    return this.token;
  }
}

// Singleton instance
export const blockchainAuthService = new BlockchainAuthService();
export default blockchainAuthService;

