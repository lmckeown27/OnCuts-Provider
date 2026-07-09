import { useEffect } from 'react';

/**
 * Hook to lock body scroll when a modal/popup is open
 * Prevents users from scrolling or interacting with background content
 * Also prevents pull-to-refresh behavior on mobile
 */
export function useBodyScrollLock(isLocked: boolean) {
  useEffect(() => {
    if (isLocked) {
      // Save current scroll position and body styles
      const scrollY = window.scrollY;
      const originalStyle = window.getComputedStyle(document.body).overflow;
      const originalPaddingRight = window.getComputedStyle(document.body).paddingRight;
      
      // Calculate scrollbar width to prevent layout shift
      const scrollbarWidth = window.innerWidth - document.documentElement.clientWidth;
      
      // Lock scroll
      document.body.style.overflow = 'hidden';
      document.body.style.paddingRight = `${scrollbarWidth}px`;
      document.body.style.position = 'fixed';
      document.body.style.top = `-${scrollY}px`;
      document.body.style.left = '0';
      document.body.style.right = '0';
      
      // Prevent pull-to-refresh on mobile
      document.body.style.overscrollBehavior = 'none';
      document.documentElement.style.overscrollBehavior = 'none';
      
      return () => {
        // Restore original styles
        document.body.style.overflow = originalStyle;
        document.body.style.paddingRight = originalPaddingRight;
        document.body.style.position = '';
        document.body.style.top = '';
        document.body.style.left = '';
        document.body.style.right = '';
        
        // Restore pull-to-refresh behavior
        document.body.style.overscrollBehavior = '';
        document.documentElement.style.overscrollBehavior = '';
        
        // Restore scroll position
        window.scrollTo(0, scrollY);
      };
    }
  }, [isLocked]);
}

export default useBodyScrollLock;

