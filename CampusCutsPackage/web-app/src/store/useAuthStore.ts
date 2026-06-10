import { create } from 'zustand';
import type { User } from '../types';
import authService from '../services/auth.service';
import socketService from '../services/socket.service';

interface AuthState {
  user: User | null;
  isAuthenticated: boolean;
  isLoading: boolean;
  error: string | null;
  pendingVerificationEmail: string | null;
  activeRole: 'admin' | 'campus_manager' | 'barber' | 'consumer' | null;
  
  setUser: (user: User | null) => void;
  setActiveRole: (role: 'admin' | 'campus_manager' | 'barber' | 'consumer') => void;
  login: (email: string, password: string) => Promise<{ isAdmin: boolean; isCampusManager: boolean }>;
  signup: (data: any) => Promise<{ email: string; verificationCode?: string }>;
  verifyEmail: (email: string, code: string) => Promise<void>;
  resendVerificationCode: (email: string) => Promise<void>;
  logout: () => Promise<void>;
  loadUser: () => Promise<void>;
  clearError: () => void;
  getPendingVerificationEmail: () => string | null;
}

// Hardcoded admin credentials (empty - all auth goes through real API)
const ADMIN_CREDENTIALS: Array<{ email: string; password: string; user: User }> = [];

export const useAuthStore = create<AuthState>((set, get) => ({
  user: authService.getStoredUser(),
  isAuthenticated: authService.isAuthenticated(),
  isLoading: false,
  error: null,
  pendingVerificationEmail: authService.getPendingVerificationEmail(),
  activeRole: null,

  setUser: (user) => {
    // Persist to localStorage so changes survive page refresh
    if (user) {
      localStorage.setItem('user', JSON.stringify(user));
    } else {
      localStorage.removeItem('user');
    }
    set({ user, isAuthenticated: !!user });
  },
  
  setActiveRole: (role) => set({ activeRole: role }),

  login: async (email, password) => {
    set({ isLoading: true, error: null });
    
    // Check for hardcoded admin credentials
    const adminMatch = ADMIN_CREDENTIALS.find(
      admin => admin.email === email && admin.password === password
    );
    
    if (adminMatch) {
      const adminUser = adminMatch.user;
      // Store admin user in localStorage (using same keys as auth.service)
      localStorage.setItem('user', JSON.stringify(adminUser));
      localStorage.setItem('accessToken', 'admin-token-' + Date.now());
      
      set({ 
        user: adminUser, 
        isAuthenticated: true, 
        isLoading: false,
        activeRole: null // Will be selected on role page
      });
      socketService.connect();
      return { isAdmin: true, isCampusManager: false };
    }
    
    // Call real backend API for non-admin login
    try {
      const response = await authService.login({ email, password });
      
      // Map backend response to frontend User type
      // Backend uses uppercase roles (CONSUMER, BARBER, CAMPUS_MANAGER, ADMIN), frontend uses lowercase
      const rawRole = ((response.user as any).role || response.user.user_type || '').toString().toLowerCase();
      const mappedRole = rawRole === 'consumer' ? 'student' : rawRole; // Map CONSUMER to student for frontend
      
      // Admins have all privileges including campus manager at all campuses
      const isAdmin = mappedRole === 'admin';
      const isCampusManager = mappedRole === 'campus_manager' || isAdmin;
      
      const user = {
        id: response.user.id || (response as any).user.userId,
        email: response.user.email,
        first_name: (response.user as any).firstName || response.user.first_name,
        last_name: (response.user as any).lastName || response.user.last_name,
        user_type: mappedRole as 'student' | 'barber' | 'campus_manager' | 'admin',
        is_verified: (response.user as any).emailVerified ?? response.user.is_verified ?? true,
        is_admin: isAdmin,
        is_campus_manager: isCampusManager,
        has_barber_profile: (response.user as any).hasBarberProfile ?? false,
        created_at: response.user.created_at || new Date().toISOString(),
        campus_id: ((response.user as any).campusId || response.user.campus_id)?.toString(),
        profile_picture_url: (response.user as any).profile_picture_url || (response.user as any).avatarUrl,
        sui_address: (response.user as any).suiAddress ?? (response.user as any).sui_address ?? null,
      };
      
      set({ 
        user: user, 
        isAuthenticated: true, 
        isLoading: false,
        activeRole: null
      });
      socketService.connect();
      return { isAdmin: user.is_admin || false, isCampusManager: user.is_campus_manager || false };
    } catch (error: any) {
      const errorMessage = error.response?.data?.message || error.message || 'Invalid credentials';
      set({ 
        error: errorMessage, 
        isLoading: false 
      });
      throw error;
    }
  },

  signup: async (data) => {
    set({ isLoading: true, error: null });
    try {
      // Call real backend API for registration
      const response = await authService.signup(data);
      
      // Store pending verification email
      localStorage.setItem('pendingVerificationEmail', data.email);
      
      // Don't authenticate yet - user must verify email first
      set({ 
        isLoading: false, 
        pendingVerificationEmail: data.email 
      });
      
      // Return response from backend (includes verificationCode in dev mode)
      return { email: response.email, verificationCode: response.verificationCode };
    } catch (error: any) {
      const errorMessage = error.response?.data?.message || error.message || 'Signup failed';
      set({ 
        error: errorMessage, 
        isLoading: false 
      });
      throw error;
    }
  },

  verifyEmail: async (email, code) => {
    set({ isLoading: true, error: null });
    try {
      // Call real backend API for email verification
      const response = await authService.verifyEmail(email, code);
      
      // Map backend response to frontend User type
      // Backend uses uppercase roles (CONSUMER, BARBER, CAMPUS_MANAGER, ADMIN), frontend uses lowercase
      const rawRole = (response.user.role || '').toString().toLowerCase();
      const mappedRole = rawRole === 'consumer' ? 'student' : rawRole;
      
      // Admins have all privileges including campus manager at all campuses
      const isAdminRole = mappedRole === 'admin';
      const isCampusManagerRole = mappedRole === 'campus_manager' || isAdminRole;
      
      const user = {
        id: response.user.id,
        email: response.user.email,
        first_name: response.user.firstName,
        last_name: response.user.lastName,
        user_type: mappedRole as 'student' | 'barber' | 'campus_manager' | 'admin',
        is_verified: response.user.emailVerified,
        is_admin: isAdminRole,
        is_campus_manager: isCampusManagerRole,
        created_at: new Date().toISOString(),
        campus_id: response.user.campusId?.toString(),
        profile_picture_url: (response.user as any).profile_picture_url || (response.user as any).avatarUrl,
        sui_address: (response as { suiAddress?: string }).suiAddress ?? null,
      };
      
      // Auth data is already saved by authService.verifyEmail
      // Clear pending verification data
      localStorage.removeItem('pendingVerificationEmail');
      
      set({ 
        user: user, 
        isAuthenticated: true, 
        isLoading: false,
        pendingVerificationEmail: null
      });
      socketService.connect();
    } catch (error: any) {
      // Extract error message from various response formats
      let errorMessage = error.response?.data?.error?.message || 
                         error.response?.data?.message || 
                         error.message || 
                         'Verification failed';
      
      // Make error messages more user-friendly
      if (error.response?.status === 400 || errorMessage.toLowerCase().includes('invalid') || errorMessage.toLowerCase().includes('expired')) {
        errorMessage = 'Wrong verification code. Please check and try again.';
      }
      
      set({ 
        error: errorMessage, 
        isLoading: false 
      });
      throw error;
    }
  },

  resendVerificationCode: async (email) => {
    set({ isLoading: true, error: null });
    try {
      // Call real backend API to resend verification code
      await authService.resendVerificationCode(email);
      
      set({ isLoading: false });
    } catch (error: any) {
      const errorMessage = error.response?.data?.message || error.message || 'Failed to resend code';
      set({ 
        error: errorMessage, 
        isLoading: false 
      });
      throw error;
    }
  },

  getPendingVerificationEmail: () => {
    return get().pendingVerificationEmail || authService.getPendingVerificationEmail();
  },

  logout: async () => {
    set({ isLoading: true });
    try {
      await authService.logout();
      socketService.disconnect();
      set({ user: null, isAuthenticated: false, isLoading: false });
    } catch (error) {
      // Even if logout fails on server, clear local state
      socketService.disconnect();
      set({ user: null, isAuthenticated: false, isLoading: false });
    }
  },

  loadUser: async () => {
    if (!authService.isAuthenticated()) {
      set({ user: null, isAuthenticated: false });
      return;
    }

    set({ isLoading: true });
    try {
      const user = await authService.getCurrentUser();
      // Also persist to localStorage so role/profile data survives page refresh
      localStorage.setItem('user', JSON.stringify(user));
      set({ user, isAuthenticated: true, isLoading: false });
      socketService.connect();
    } catch (error) {
      set({ user: null, isAuthenticated: false, isLoading: false });
    }
  },

  clearError: () => set({ error: null }),
}));

