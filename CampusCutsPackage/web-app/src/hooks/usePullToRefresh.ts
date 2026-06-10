/**
 * usePullToRefresh Hook
 * 
 * Implements native-style pull-to-refresh functionality for mobile devices.
 * Detects when user swipes down from the top of the page and triggers a refresh.
 */

import { useState, useEffect, useCallback, useRef } from 'react';

interface UsePullToRefreshOptions {
  onRefresh: () => Promise<void> | void;
  threshold?: number; // Distance in pixels to trigger refresh (default: 70)
  resistance?: number; // How much to resist the pull (default: 2.5)
  maxPull?: number; // Maximum pull distance (default: 120)
}

interface UsePullToRefreshReturn {
  isPulling: boolean;
  isRefreshing: boolean;
  pullDistance: number;
  pullProgress: number; // 0 to 1, where 1 means threshold reached
  containerRef: React.RefObject<HTMLDivElement>;
  indicatorStyle: React.CSSProperties;
}

export function usePullToRefresh({
  onRefresh,
  threshold = 70,
  resistance = 2.5,
  maxPull = 120,
}: UsePullToRefreshOptions): UsePullToRefreshReturn {
  const [isPulling, setIsPulling] = useState(false);
  const [isRefreshing, setIsRefreshing] = useState(false);
  const [pullDistance, setPullDistance] = useState(0);
  
  const containerRef = useRef<HTMLDivElement>(null);
  const startY = useRef(0);
  const currentY = useRef(0);
  const canPull = useRef(false);

  const handleTouchStart = useCallback((e: TouchEvent) => {
    // Don't activate if body scroll is locked (modal is open)
    // This is detected by checking if body has position: fixed (set by useBodyScrollLock)
    if (document.body.style.position === 'fixed') {
      canPull.current = false;
      return;
    }
    
    // Don't activate if touch started on an interactive element (buttons, cards, links, etc.)
    // This prevents pull-to-refresh from interfering with taps on clickable elements
    const target = e.target as HTMLElement;
    if (target?.closest?.('button, a, [role="button"], .cursor-pointer, [data-clickable]')) {
      canPull.current = false;
      return;
    }
    
    // Only activate if at the very top of the page (or nearly so)
    if (window.scrollY > 5) {
      canPull.current = false;
      return;
    }
    if (isRefreshing) {
      canPull.current = false;
      return;
    }
    
    canPull.current = true;
    startY.current = e.touches[0].clientY;
    setIsPulling(true);
  }, [isRefreshing]);

  const handleTouchMove = useCallback((e: TouchEvent) => {
    if (!canPull.current || isRefreshing) return;
    
    // If user scrolled down, cancel pull
    if (window.scrollY > 5) {
      canPull.current = false;
      setIsPulling(false);
      setPullDistance(0);
      return;
    }

    currentY.current = e.touches[0].clientY;
    const diff = currentY.current - startY.current;

    if (diff > 0) {
      // Apply resistance to make it feel natural (like rubber band)
      const resistedDiff = Math.min(diff / resistance, maxPull);
      setPullDistance(resistedDiff);
      
      // Prevent default scroll when pulling down
      if (resistedDiff > 5) {
        e.preventDefault();
      }
    } else {
      // User is scrolling up, reset
      setPullDistance(0);
    }
  }, [isRefreshing, resistance, maxPull]);

  const handleTouchEnd = useCallback(async () => {
    if (!canPull.current) return;
    
    setIsPulling(false);
    canPull.current = false;

    if (pullDistance >= threshold && !isRefreshing) {
      setIsRefreshing(true);
      // Keep spinner visible during refresh
      setPullDistance(threshold);
      
      try {
        await onRefresh();
      } catch (error) {
        console.error('Refresh failed:', error);
      } finally {
        // Small delay before hiding spinner for better UX
        await new Promise(resolve => setTimeout(resolve, 300));
        setIsRefreshing(false);
        setPullDistance(0);
      }
    } else {
      // Snap back to top
      setPullDistance(0);
    }
  }, [pullDistance, threshold, isRefreshing, onRefresh]);

  useEffect(() => {
    const container = containerRef.current;
    if (!container) return;

    // Use passive: false for touchmove to allow preventDefault
    container.addEventListener('touchstart', handleTouchStart, { passive: true });
    container.addEventListener('touchmove', handleTouchMove, { passive: false });
    container.addEventListener('touchend', handleTouchEnd, { passive: true });
    container.addEventListener('touchcancel', handleTouchEnd, { passive: true });

    return () => {
      container.removeEventListener('touchstart', handleTouchStart);
      container.removeEventListener('touchmove', handleTouchMove);
      container.removeEventListener('touchend', handleTouchEnd);
      container.removeEventListener('touchcancel', handleTouchEnd);
    };
  }, [handleTouchStart, handleTouchMove, handleTouchEnd]);

  const pullProgress = Math.min(pullDistance / threshold, 1);

  const indicatorStyle: React.CSSProperties = {
    transform: `translateY(${pullDistance}px)`,
    transition: isPulling ? 'none' : 'transform 0.3s ease-out',
  };

  return {
    isPulling,
    isRefreshing,
    pullDistance,
    pullProgress,
    containerRef,
    indicatorStyle,
  };
}

export default usePullToRefresh;
