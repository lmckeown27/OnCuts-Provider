/**
 * Blockchain Balance Card Component
 * 
 * Displays user's on-chain balance in a user-friendly way.
 * Users see USD; settlement may be on-chain when enabled.
 * 
 * Features:
 * - Real-time balance from blockchain
 * - Cached for performance
 * - Automatic refresh
 * - Add funds button (Stripe)
 * - Withdraw funds button
 */

import { useQuery } from '@tanstack/react-query';
import axios from 'axios';
import { Skeleton } from './Skeleton';
import { useState } from 'react';

const API_BASE_URL = import.meta.env.VITE_API_BASE_URL || 'http://localhost:3001';

interface Balance {
  availableUsd: number;
  lockedUsd: number;
  totalUsd: number;
}

export function BlockchainBalanceCard() {
  const [showDetails, setShowDetails] = useState(false);

  // Fetch balance from blockchain (via backend)
  const { data: balance, isLoading, error, refetch } = useQuery<Balance>({
    queryKey: ['balance'],
    queryFn: async () => {
      const response = await axios.get(`${API_BASE_URL}/api/fiat-bridge/balance`);
      if (!response.data.success) throw new Error(response.data.message);
      return response.data.balance;
    },
    staleTime: 60 * 1000, // Fresh for 1 minute
    gcTime: 5 * 60 * 1000, // Cache for 5 minutes
    refetchInterval: 60 * 1000, // Auto-refresh every minute
    retry: 3,
  });

  if (isLoading) {
    return (
      <div className="bg-gradient-to-r from-blue-600 to-primary-400 rounded-lg shadow-lg p-6 text-white">
        <Skeleton width="120px" height="20px" />
        <Skeleton width="180px" height="40px" className="mt-2" />
        <div className="mt-4 flex space-x-3">
          <Skeleton width="100px" height="36px" />
          <Skeleton width="100px" height="36px" />
        </div>
      </div>
    );
  }

  if (error) {
    return (
      <div className="bg-red-50 border border-red-200 rounded-lg p-6">
        <p className="text-red-800 text-sm mb-4">
          Failed to load balance. Please try again.
        </p>
        <button
          onClick={() => refetch()}
          className="bg-red-600 hover:bg-red-700 text-white px-4 py-2 rounded-md font-medium transition"
        >
          Retry
        </button>
      </div>
    );
  }

  return (
    <div className="bg-gradient-to-r from-blue-600 to-primary-400 rounded-lg shadow-lg p-6 text-white">
      {/* Balance Display */}
      <div className="flex items-center justify-between mb-4">
        <div>
          <p className="text-sm font-medium text-blue-100">Available Balance</p>
          <p className="text-4xl font-bold mt-1">
            ${balance?.availableUsd.toFixed(2) || '0.00'}
          </p>
          
          {balance && balance.lockedUsd > 0 && (
            <p className="text-xs text-blue-100 mt-2">
              ${balance.lockedUsd.toFixed(2)} locked in active bookings
            </p>
          )}
        </div>

        <button
          onClick={() => setShowDetails(!showDetails)}
          className="p-2 hover:bg-white/20 rounded-full transition"
          title="View details"
        >
          <svg className="h-6 w-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
          </svg>
        </button>
      </div>

      {/* Details Panel (Expandable) */}
      {showDetails && balance && (
        <div className="bg-white/10 rounded-lg p-4 mb-4 space-y-2">
          <div className="flex justify-between text-sm">
            <span className="text-blue-100">Available:</span>
            <span className="font-semibold">${balance.availableUsd.toFixed(2)}</span>
          </div>
          <div className="flex justify-between text-sm">
            <span className="text-blue-100">Locked (Escrow):</span>
            <span className="font-semibold">${balance.lockedUsd.toFixed(2)}</span>
          </div>
          <div className="border-t border-white/20 pt-2 flex justify-between text-sm font-bold">
            <span>Total:</span>
            <span>${balance.totalUsd.toFixed(2)}</span>
          </div>
        </div>
      )}

      {/* Actions */}
      <div className="flex space-x-3">
        <a
          href="/wallet?action=deposit"
          className="flex-1 bg-white text-blue-600 px-4 py-3 rounded-lg font-medium text-center hover:bg-blue-50 transition shadow-md flex items-center justify-center"
        >
          <svg className="h-5 w-5 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 6v6m0 0v6m0-6h6m-6 0H6" />
          </svg>
          Add Funds
        </a>
        
        <a
          href="/wallet?action=withdraw"
          className="flex-1 bg-white/20 hover:bg-white/30 text-white px-4 py-3 rounded-lg font-medium text-center transition backdrop-blur-sm flex items-center justify-center"
        >
          <svg className="h-5 w-5 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M17 9V7a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2m2 4h10a2 2 0 002-2v-6a2 2 0 00-2-2H9a2 2 0 00-2 2v6a2 2 0 002 2zm7-5a2 2 0 11-4 0 2 2 0 014 0z" />
          </svg>
          Withdraw
        </a>
      </div>

      {/* Blockchain Info (Dev Mode) */}
      {import.meta.env.DEV && balance && (
        <div className="mt-4 p-3 bg-black/20 rounded-md">
          <p className="text-xs text-blue-100 mb-1">
            <strong>Behind the scenes:</strong>
          </p>
          <ul className="text-xs text-blue-50 space-y-1">
            <li>Balance tracked in your account</li>
            <li>Locked funds in smart contract escrow</li>
            <li>Auto-refreshes every 60 seconds</li>
            <li>User thinks: "Normal balance"</li>
          </ul>
        </div>
      )}
    </div>
  );
}

export default BlockchainBalanceCard;

