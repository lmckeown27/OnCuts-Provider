// @ts-nocheck
/**
 * React Query Hooks for Blockchain Authentication
 * 
 * Provides optimistic updates and caching for auth operations.
 * Hides blockchain latency from users.
 */

import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import blockchainAuthService, { SignupData, LoginData, User } from '../services/blockchain-auth.service';
import { useNavigate } from 'react-router-dom';
import { useState } from 'react';

/**
 * Hook for user signup (creates blockchain account)
 * Provides optimistic feedback while tx confirms in background
 */
export function useBlockchainSignup() {
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const [isOptimisticSuccess, setIsOptimisticSuccess] = useState(false);

  return useMutation({
    mutationFn: (data: SignupData) => blockchainAuthService.signup(data),
    
    // Optimistic update - show success immediately
    onMutate: async (newUser) => {
      setIsOptimisticSuccess(true);
      
      // Show optimistic success message
      return { 
        optimistic: true,
        timestamp: Date.now(),
      };
    },
    
    // On success, update cache and navigate
    onSuccess: (response) => {
      if (response.success && response.data) {
        // Set user in cache
        queryClient.setQueryData(['user'], response.data.user);
        
        // Navigate to dashboard after short delay (feels instant!)
        setTimeout(() => {
          if (response.data?.user.role === 'barber') {
            navigate('/barber/dashboard');
          } else {
            navigate('/student/discovery');
          }
        }, 500);
      }
    },
    
    // On error, show error and revert optimistic state
    onError: (error) => {
      console.error('Signup failed:', error);
      setIsOptimisticSuccess(false);
    },
  });
}

/**
 * Hook for user login
 */
export function useBlockchainLogin() {
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const [isOptimisticSuccess, setIsOptimisticSuccess] = useState(false);

  return useMutation({
    mutationFn: (data: LoginData) => blockchainAuthService.login(data),
    
    onMutate: async () => {
      setIsOptimisticSuccess(true);
    },
    
    onSuccess: (response) => {
      if (response.success && response.data) {
        queryClient.setQueryData(['user'], response.data.user);
        
        setTimeout(() => {
          if (response.data?.user.role === 'barber') {
            navigate('/barber/dashboard');
          } else {
            navigate('/student/discovery');
          }
        }, 300);
      }
    },
    
    onError: () => {
      setIsOptimisticSuccess(false);
    },
  });
}

/**
 * Hook to get current user (from blockchain)
 * Uses React Query caching to avoid repeated blockchain queries
 */
export function useCurrentUser() {
  return useQuery({
    queryKey: ['user'],
    queryFn: async () => {
      const result = await blockchainAuthService.getMe();
      if (!result.success) throw new Error(result.message);
      return result.user;
    },
    staleTime: 5 * 60 * 1000, // Consider fresh for 5 minutes
    gcTime: 30 * 60 * 1000, // Keep in cache for 30 minutes
    retry: 3, // Retry failed requests 3 times
    retryDelay: (attemptIndex) => Math.min(1000 * 2 ** attemptIndex, 30000),
  });
}

/**
 * Hook for updating profile (on-chain transaction)
 * Uses optimistic updates to show changes immediately
 */
export function useUpdateProfile() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (data: {
      username?: string;
      bio?: string;
      campusDomain?: string;
      role?: string;
    }) => blockchainAuthService.updateProfile(data),
    
    // Optimistic update - update cache immediately
    onMutate: async (newData) => {
      // Cancel any outgoing refetches
      await queryClient.cancelQueries({ queryKey: ['user'] });
      
      // Snapshot the previous value
      const previousUser = queryClient.getQueryData<User>(['user']);
      
      // Optimistically update to the new value
      queryClient.setQueryData<User>(['user'], (old) => {
        if (!old) return old;
        return { ...old, ...newData };
      });
      
      // Return context with snapshot
      return { previousUser };
    },
    
    // On error, roll back to previous value
    onError: (err, newData, context: any) => {
      if (context?.previousUser) {
        queryClient.setQueryData(['user'], context.previousUser);
      }
    },
    
    // Always refetch after error or success
    onSettled: () => {
      queryClient.invalidateQueries({ queryKey: ['user'] });
    },
  });
}

/**
 * Hook for uploading profile photo (IPFS + on-chain)
 * Shows optimistic preview while IPFS upload happens
 */
export function useUploadProfilePhoto() {
  const queryClient = useQueryClient();
  const [optimisticPreview, setOptimisticPreview] = useState<string | null>(null);

  return useMutation({
    mutationFn: (file: File) => blockchainAuthService.uploadProfilePhoto(file),
    
    // Show preview immediately
    onMutate: async (file) => {
      const previewUrl = URL.createObjectURL(file);
      setOptimisticPreview(previewUrl);
      
      return { previewUrl };
    },
    
    // On success, update with actual IPFS URL
    onSuccess: (response) => {
      if (response.success && response.url) {
        queryClient.setQueryData<User>(['user'], (old) => {
          if (!old) return old;
          return { ...old, profilePhotoCid: response.cid };
        });
        
        // Clean up optimistic preview
        if (optimisticPreview) {
          URL.revokeObjectURL(optimisticPreview);
          setOptimisticPreview(null);
        }
      }
    },
    
    // On error, remove preview
    onError: () => {
      if (optimisticPreview) {
        URL.revokeObjectURL(optimisticPreview);
        setOptimisticPreview(null);
      }
    },
  });
}

/**
 * Hook for logout
 */
export function useBlockchainLogout() {
  const navigate = useNavigate();
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: () => blockchainAuthService.logout(),
    
    onSuccess: () => {
      // Clear all cached data
      queryClient.clear();
      
      // Navigate to login
      navigate('/login');
    },
  });
}

