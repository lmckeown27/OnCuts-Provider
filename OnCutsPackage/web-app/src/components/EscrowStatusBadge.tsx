/**
 * Escrow Status Badge
 * 
 * Displays the current escrow status with appropriate styling
 */

import React from 'react';

interface EscrowStatusBadgeProps {
  status: 'held' | 'released' | 'refunded' | 'expired';
  expiresAt?: string;
  className?: string;
}

const EscrowStatusBadge: React.FC<EscrowStatusBadgeProps> = ({
  status,
  expiresAt,
  className = '',
}) => {
  const getStatusColor = () => {
    switch (status) {
      case 'held':
        return 'bg-yellow-100 text-yellow-800 border-yellow-300';
      case 'released':
        return 'bg-green-100 text-green-800 border-green-300';
      case 'refunded':
        return 'bg-blue-100 text-blue-800 border-blue-300';
      case 'expired':
        return 'bg-gray-100 text-gray-800 border-gray-300';
      default:
        return 'bg-gray-100 text-gray-800 border-gray-300';
    }
  };

  const getStatusLabel = () => {
    switch (status) {
      case 'held':
        return 'Funds Held';
      case 'released':
        return 'Released';
      case 'refunded':
        return 'Refunded';
      case 'expired':
        return 'Expired';
      default:
        return status;
    }
  };

  const getStatusDescription = () => {
    switch (status) {
      case 'held':
        return 'Payment secured in escrow';
      case 'released':
        return 'Funds released to barber';
      case 'refunded':
        return 'Full refund issued';
      case 'expired':
        return 'Auto-refunded';
      default:
        return '';
    }
  };

  const formatExpiryTime = () => {
    if (!expiresAt || status !== 'held') return null;

    const expiryDate = new Date(expiresAt);
    const now = new Date();
    const diffMs = expiryDate.getTime() - now.getTime();
    const diffHours = Math.floor(diffMs / (1000 * 60 * 60));
    const diffMinutes = Math.floor((diffMs % (1000 * 60 * 60)) / (1000 * 60));

    if (diffMs < 0) {
      return 'Expired';
    }

    if (diffHours > 24) {
      const days = Math.floor(diffHours / 24);
      return `${days}d ${diffHours % 24}h remaining`;
    }

    if (diffHours > 0) {
      return `${diffHours}h ${diffMinutes}m remaining`;
    }

    return `${diffMinutes}m remaining`;
  };

  return (
    <div className={`inline-flex flex-col ${className}`}>
      <div
        className={`
          inline-flex items-center px-3 py-1.5 rounded-full border
          text-sm font-medium
          ${getStatusColor()}
        `}
      >
        <span className="w-2 h-2 rounded-full bg-current mr-2"></span>
        {getStatusLabel()}
      </div>
      
      <div className="mt-1 text-xs text-gray-600">
        {getStatusDescription()}
        {expiresAt && status === 'held' && (
          <span className="ml-2 font-semibold">
            • {formatExpiryTime()}
          </span>
        )}
      </div>
    </div>
  );
};

export default EscrowStatusBadge;

