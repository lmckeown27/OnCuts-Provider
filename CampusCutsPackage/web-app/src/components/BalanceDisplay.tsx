/**
 * Balance Display Component
 * 
 * Shows wallet balance with available/pending split
 */

import React from 'react';
import { Wallet, Lock, AlertCircle } from 'lucide-react';
import type { WalletBalance } from '../services/wallet-v2.service';

interface BalanceDisplayProps {
  balance: WalletBalance;
  showDetails?: boolean;
  className?: string;
}

const BalanceDisplay: React.FC<BalanceDisplayProps> = ({
  balance,
  showDetails = true,
  className = '',
}) => {
  return (
    <div className={`bg-white rounded-lg shadow-md p-6 ${className}`}>
      {/* Total Balance */}
      <div className="flex items-center justify-between mb-4">
        <div className="flex items-center">
          <Wallet className="h-6 w-6 text-primary-400 mr-2" />
          <h3 className="text-lg font-semibold text-gray-900">
            Wallet Balance
          </h3>
        </div>
        <div className="text-3xl font-bold text-gray-900">
          ${balance.total_dollars.toFixed(2)}
        </div>
      </div>

      {showDetails && (
        <>
          {/* Available Balance */}
          <div className="flex items-center justify-between py-3 border-t border-gray-200">
            <div className="flex items-center">
              <div className="w-3 h-3 rounded-full bg-green-500 mr-3"></div>
              <div>
                <div className="text-sm font-medium text-gray-700">
                  Available
                </div>
                <div className="text-xs text-gray-500">
                  Ready to withdraw
                </div>
              </div>
            </div>
            <div className="text-xl font-semibold text-green-600">
              ${balance.available_dollars.toFixed(2)}
            </div>
          </div>

          {/* Pending Balance */}
          {balance.pending_dollars > 0 && (
            <div className="flex items-center justify-between py-3 border-t border-gray-200">
              <div className="flex items-center">
                <div className="w-3 h-3 rounded-full bg-yellow-500 mr-3"></div>
                <div>
                  <div className="text-sm font-medium text-gray-700">
                    Pending
                  </div>
                  <div className="text-xs text-gray-500">
                    Awaiting service completion
                  </div>
                </div>
              </div>
              <div className="text-xl font-semibold text-yellow-600">
                ${balance.pending_dollars.toFixed(2)}
              </div>
            </div>
          )}

          {/* Active Escrows */}
          {balance.active_escrows > 0 && (
            <div className="flex items-center justify-between py-3 border-t border-gray-200">
              <div className="flex items-center">
                <Lock className="h-4 w-4 text-blue-600 mr-3" />
                <div>
                  <div className="text-sm font-medium text-gray-700">
                    Active Holds
                  </div>
                  <div className="text-xs text-gray-500">
                    Funds secured for bookings
                  </div>
                </div>
              </div>
              <div className="text-sm font-semibold text-blue-600">
                {balance.active_escrows} {balance.active_escrows === 1 ? 'hold' : 'holds'}
              </div>
            </div>
          )}

          {/* Info Note */}
          {balance.pending_dollars > 0 && (
            <div className="mt-4 p-3 bg-blue-50 rounded-lg border border-blue-200">
              <div className="flex items-start">
                <AlertCircle className="h-5 w-5 text-blue-600 mr-2 flex-shrink-0 mt-0.5" />
                <div className="text-sm text-blue-800">
                  <strong>Pending funds</strong> will move to available balance once the
                  service is completed.
                </div>
              </div>
            </div>
          )}
        </>
      )}
    </div>
  );
};

export default BalanceDisplay;

