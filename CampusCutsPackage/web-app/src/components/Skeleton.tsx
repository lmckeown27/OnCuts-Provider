/**
 * Skeleton Loading Components
 * 
 * Show while blockchain data is loading to hide latency.
 * Makes the app feel instant even when blockchain is slow.
 */

import '../styles/skeleton.css';

interface SkeletonProps {
  className?: string;
  width?: string;
  height?: string;
  variant?: 'text' | 'circular' | 'rectangular';
}

export function Skeleton({ 
  className = '', 
  width, 
  height, 
  variant = 'rectangular' 
}: SkeletonProps) {
  const style = {
    width: width || '100%',
    height: height || (variant === 'text' ? '1em' : '100px'),
  };

  return (
    <div 
      className={`skeleton skeleton-${variant} ${className}`} 
      style={style}
      aria-label="Loading..."
    />
  );
}

/**
 * Skeleton for booking card
 */
export function BookingCardSkeleton() {
  return (
    <div className="bg-white rounded-lg shadow-md p-6 space-y-4">
      <div className="flex items-start justify-between">
        <div className="flex items-center space-x-4">
          <Skeleton variant="circular" width="48px" height="48px" />
          <div className="space-y-2">
            <Skeleton width="150px" height="20px" />
            <Skeleton width="100px" height="16px" />
          </div>
        </div>
        <Skeleton width="80px" height="24px" />
      </div>
      
      <div className="space-y-2">
        <Skeleton width="100%" height="16px" />
        <Skeleton width="80%" height="16px" />
      </div>
      
      <div className="flex space-x-2">
        <Skeleton width="100px" height="36px" />
        <Skeleton width="100px" height="36px" />
      </div>
    </div>
  );
}

/**
 * Skeleton for barber card
 */
export function BarberCardSkeleton() {
  return (
    <div className="bg-white rounded-lg shadow-md overflow-hidden">
      <Skeleton height="200px" />
      
      <div className="p-4 space-y-3">
        <div className="flex items-center space-x-3">
          <Skeleton variant="circular" width="40px" height="40px" />
          <div className="space-y-2 flex-1">
            <Skeleton width="120px" height="18px" />
            <Skeleton width="80px" height="14px" />
          </div>
        </div>
        
        <Skeleton width="100%" height="14px" />
        <Skeleton width="90%" height="14px" />
        
        <div className="flex justify-between items-center pt-2">
          <Skeleton width="60px" height="16px" />
          <Skeleton width="80px" height="32px" />
        </div>
      </div>
    </div>
  );
}

/**
 * Skeleton for user profile
 */
export function ProfileSkeleton() {
  return (
    <div className="bg-white rounded-lg shadow-md p-6 space-y-6">
      <div className="flex items-center space-x-6">
        <Skeleton variant="circular" width="100px" height="100px" />
        
        <div className="flex-1 space-y-3">
          <Skeleton width="200px" height="24px" />
          <Skeleton width="150px" height="18px" />
          <Skeleton width="180px" height="16px" />
        </div>
      </div>
      
      <div className="space-y-4">
        <div>
          <Skeleton width="80px" height="16px" className="mb-2" />
          <Skeleton width="100%" height="20px" />
        </div>
        
        <div>
          <Skeleton width="60px" height="16px" className="mb-2" />
          <Skeleton width="100%" height="80px" />
        </div>
        
        <div className="flex space-x-3">
          <Skeleton width="120px" height="40px" />
          <Skeleton width="120px" height="40px" />
        </div>
      </div>
    </div>
  );
}

/**
 * Skeleton for transaction list item
 */
export function TransactionSkeleton() {
  return (
    <div className="flex items-center justify-between p-4 border-b">
      <div className="flex items-center space-x-4">
        <Skeleton variant="circular" width="40px" height="40px" />
        <div className="space-y-2">
          <Skeleton width="150px" height="16px" />
          <Skeleton width="100px" height="14px" />
        </div>
      </div>
      
      <div className="text-right space-y-2">
        <Skeleton width="80px" height="16px" />
        <Skeleton width="60px" height="14px" />
      </div>
    </div>
  );
}

/**
 * Skeleton grid for booking/barber lists
 */
export function SkeletonGrid({ count = 6, type = 'booking' }: { count?: number; type?: 'booking' | 'barber' }) {
  const SkeletonComponent = type === 'booking' ? BookingCardSkeleton : BarberCardSkeleton;
  
  return (
    <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
      {Array.from({ length: count }).map((_, i) => (
        <SkeletonComponent key={i} />
      ))}
    </div>
  );
}

export default Skeleton;

