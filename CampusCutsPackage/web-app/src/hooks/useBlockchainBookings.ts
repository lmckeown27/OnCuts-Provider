/**
 * React Query Hooks for Blockchain Bookings
 * 
 * Provides optimistic updates for booking operations.
 * Shows instant feedback while blockchain confirms in background.
 */

import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import blockchainBookingService, { CreateBookingData, Booking } from '../services/blockchain-booking.service';
import { useState } from 'react';

/**
 * Hook to get user's bookings (from blockchain)
 * Automatically refetches every 30 seconds to stay in sync
 */
export function useUserBookings() {
  return useQuery({
    queryKey: ['bookings'],
    queryFn: async () => {
      const result = await blockchainBookingService.getUserBookings();
      if (!result.success) throw new Error(result.message);
      return result.bookings || [];
    },
    staleTime: 30 * 1000, // Consider fresh for 30 seconds
    gcTime: 5 * 60 * 1000, // Keep in cache for 5 minutes
    refetchInterval: 30 * 1000, // Refetch every 30 seconds (blockchain sync)
    retry: 3,
    retryDelay: (attemptIndex) => Math.min(1000 * 2 ** attemptIndex, 30000),
  });
}

/**
 * Hook to create a booking (smart contract escrow)
 * Shows optimistic booking immediately while blockchain confirms
 */
export function useCreateBooking() {
  const queryClient = useQueryClient();
  const [optimisticBooking, setOptimisticBooking] = useState<Booking | null>(null);

  return useMutation({
    mutationFn: (data: CreateBookingData) => blockchainBookingService.createBooking(data),
    
    // Optimistic update - add booking to list immediately
    onMutate: async (newBooking) => {
      // Cancel any outgoing refetches
      await queryClient.cancelQueries({ queryKey: ['bookings'] });
      
      // Snapshot the previous value
      const previousBookings = queryClient.getQueryData<Booking[]>(['bookings']);
      
      // Create optimistic booking object
      const optimistic: Booking = {
        id: `temp-${Date.now()}`, // Temporary ID
        student: 'pending...', // Will be filled by backend
        barber: newBooking.barberAddress,
        serviceName: newBooking.serviceName,
        amount: (newBooking.amount * 100_000_000).toString(), // Convert to scaled
        status: 0, // Pending
        scheduledTime: newBooking.scheduledTime.toString(),
        createdAt: Date.now().toString(),
      };
      
      setOptimisticBooking(optimistic);
      
      // Optimistically update the bookings list
      queryClient.setQueryData<Booking[]>(['bookings'], (old = []) => {
        return [optimistic, ...old];
      });
      
      // Return context with snapshot
      return { previousBookings };
    },
    
    // On success, replace optimistic booking with real one
    onSuccess: (response, variables) => {
      if (response.success) {
        // Remove optimistic booking
        setOptimisticBooking(null);
        
        // Invalidate and refetch to get actual blockchain data
        setTimeout(() => {
          queryClient.invalidateQueries({ queryKey: ['bookings'] });
        }, 2000); // Wait 2 seconds for blockchain confirmation
      }
    },
    
    // On error, roll back optimistic update
    onError: (err, newBooking, context: any) => {
      setOptimisticBooking(null);
      
      if (context?.previousBookings) {
        queryClient.setQueryData(['bookings'], context.previousBookings);
      }
    },
  });
}

/**
 * Hook to complete a booking (releases escrow to barber)
 */
export function useCompleteBooking() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (bookingId: string) => blockchainBookingService.completeBooking(bookingId),
    
    // Optimistic update
    onMutate: async (bookingId) => {
      await queryClient.cancelQueries({ queryKey: ['bookings'] });
      
      const previousBookings = queryClient.getQueryData<Booking[]>(['bookings']);
      
      // Update booking status to completed
      queryClient.setQueryData<Booking[]>(['bookings'], (old = []) => {
        return old.map(booking =>
          booking.id === bookingId
            ? { ...booking, status: 1, completedAt: Date.now().toString() }
            : booking
        );
      });
      
      return { previousBookings };
    },
    
    // On success, refetch to sync with blockchain
    onSuccess: () => {
      setTimeout(() => {
        queryClient.invalidateQueries({ queryKey: ['bookings'] });
      }, 2000);
    },
    
    // On error, roll back
    onError: (err, bookingId, context: any) => {
      if (context?.previousBookings) {
        queryClient.setQueryData(['bookings'], context.previousBookings);
      }
    },
  });
}

/**
 * Hook to cancel a booking (auto-refunds student)
 */
export function useCancelBooking() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: ({ bookingId, reason }: { bookingId: string; reason: string }) =>
      blockchainBookingService.cancelBooking(bookingId, reason),
    
    // Optimistic update
    onMutate: async ({ bookingId }) => {
      await queryClient.cancelQueries({ queryKey: ['bookings'] });
      
      const previousBookings = queryClient.getQueryData<Booking[]>(['bookings']);
      
      // Update booking status to cancelled
      queryClient.setQueryData<Booking[]>(['bookings'], (old = []) => {
        return old.map(booking =>
          booking.id === bookingId
            ? { ...booking, status: 2, cancelledAt: Date.now().toString() }
            : booking
        );
      });
      
      return { previousBookings };
    },
    
    // On success, refetch
    onSuccess: () => {
      setTimeout(() => {
        queryClient.invalidateQueries({ queryKey: ['bookings'] });
      }, 2000);
    },
    
    // On error, roll back
    onError: (err, { bookingId }, context: any) => {
      if (context?.previousBookings) {
        queryClient.setQueryData(['bookings'], context.previousBookings);
      }
    },
  });
}

/**
 * Hook to check if a booking is in "optimistic" state
 * (still waiting for blockchain confirmation)
 */
export function useIsBookingOptimistic(bookingId: string): boolean {
  // If booking ID starts with "temp-", it's optimistic
  return bookingId.startsWith('temp-');
}

