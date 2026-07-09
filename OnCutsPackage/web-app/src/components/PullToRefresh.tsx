/**
 * PullToRefresh Component
 * 
 * Native-style pull-to-refresh functionality for mobile devices.
 * Matches iOS/Android native behavior with a spinner that appears when pulling down.
 */

import { ReactNode } from 'react';
import usePullToRefresh from '../hooks/usePullToRefresh';

interface PullToRefreshProps {
  children: ReactNode;
  onRefresh: () => Promise<void> | void;
  className?: string;
  style?: React.CSSProperties;
  disabled?: boolean;
}

export default function PullToRefresh({
  children,
  onRefresh,
  className = '',
  style,
  disabled = false,
}: PullToRefreshProps) {
  const {
    isPulling,
    isRefreshing,
    pullDistance,
    pullProgress,
    containerRef,
  } = usePullToRefresh({
    onRefresh: disabled ? async () => {} : onRefresh,
    threshold: 70,
  });

  // Only show on touch devices
  const isTouchDevice = 'ontouchstart' in window || navigator.maxTouchPoints > 0;

  if (!isTouchDevice || disabled) {
    return <div className={className} style={style}>{children}</div>;
  }

  // Calculate spinner rotation based on pull progress
  const spinnerRotation = pullProgress * 360;
  
  // Show spinner when pulling or refreshing
  const showSpinner = pullDistance > 10 || isRefreshing;
  
  // Spinner stays at fixed position during refresh
  const spinnerTranslateY = isRefreshing ? 60 : Math.min(pullDistance, 80);

  return (
    <div ref={containerRef} className={`relative ${className}`} style={style}>
      {/* Native-style Pull Indicator - appears from top center */}
      <div
        className="fixed left-1/2 -translate-x-1/2 z-[9999] pointer-events-none"
        style={{
          top: 0,
          transform: `translateX(-50%) translateY(${spinnerTranslateY - 50}px)`,
          opacity: showSpinner ? 1 : 0,
          transition: isPulling ? 'opacity 0.1s ease-out' : 'all 0.3s ease-out',
        }}
      >
        <div
          className={`
            w-10 h-10 rounded-full bg-white shadow-lg 
            flex items-center justify-center
            border border-gray-100
          `}
          style={{
            boxShadow: '0 2px 10px rgba(0, 0, 0, 0.15)',
          }}
        >
          {/* Native-style spinner */}
          <svg
            className="w-6 h-6"
            viewBox="0 0 24 24"
            style={{
              transform: isRefreshing ? 'none' : `rotate(${spinnerRotation}deg)`,
              transition: isPulling ? 'none' : 'transform 0.1s linear',
            }}
          >
            {isRefreshing ? (
              // Animated spinning loader during refresh
              <g>
                <circle
                  cx="12"
                  cy="12"
                  r="9"
                  fill="none"
                  stroke="#e5e7eb"
                  strokeWidth="2.5"
                />
                <path
                  d="M12 3a9 9 0 0 1 9 9"
                  fill="none"
                  stroke="#708d81"
                  strokeWidth="2.5"
                  strokeLinecap="round"
                >
                  <animateTransform
                    attributeName="transform"
                    type="rotate"
                    from="0 12 12"
                    to="360 12 12"
                    dur="0.8s"
                    repeatCount="indefinite"
                  />
                </path>
              </g>
            ) : (
              // Static progress indicator while pulling
              <g>
                <circle
                  cx="12"
                  cy="12"
                  r="9"
                  fill="none"
                  stroke="#e5e7eb"
                  strokeWidth="2.5"
                />
                <circle
                  cx="12"
                  cy="12"
                  r="9"
                  fill="none"
                  stroke="#708d81"
                  strokeWidth="2.5"
                  strokeLinecap="round"
                  strokeDasharray={`${pullProgress * 56.5} 56.5`}
                  style={{
                    transform: 'rotate(-90deg)',
                    transformOrigin: 'center',
                  }}
                />
              </g>
            )}
          </svg>
        </div>
      </div>

      {/* Content - no transform needed for native feel */}
      {children}
    </div>
  );
}

