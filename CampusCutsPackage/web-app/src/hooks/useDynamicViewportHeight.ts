/**
 * useDynamicViewportHeight Hook
 * 
 * Handles dynamic viewport height changes on mobile browsers
 * when the address bar/search bar shows or hides during scroll.
 * 
 * Sets a CSS custom property --vh that can be used like:
 * height: calc(var(--vh, 1vh) * 100)
 */

import { useEffect, useCallback } from 'react';

export function useDynamicViewportHeight() {
  const updateViewportHeight = useCallback(() => {
    // Use visualViewport if available (more accurate on mobile)
    const vh = window.visualViewport?.height ?? window.innerHeight;
    // Set the --vh custom property to 1% of the viewport height
    document.documentElement.style.setProperty('--vh', `${vh * 0.01}px`);
  }, []);

  useEffect(() => {
    // Initial set
    updateViewportHeight();

    // Update on resize
    window.addEventListener('resize', updateViewportHeight);
    
    // Update on scroll (for mobile browser bar changes)
    window.addEventListener('scroll', updateViewportHeight);

    // Use visualViewport API if available (better for mobile)
    if (window.visualViewport) {
      window.visualViewport.addEventListener('resize', updateViewportHeight);
      window.visualViewport.addEventListener('scroll', updateViewportHeight);
    }

    // Cleanup
    return () => {
      window.removeEventListener('resize', updateViewportHeight);
      window.removeEventListener('scroll', updateViewportHeight);
      if (window.visualViewport) {
        window.visualViewport.removeEventListener('resize', updateViewportHeight);
        window.visualViewport.removeEventListener('scroll', updateViewportHeight);
      }
    };
  }, [updateViewportHeight]);
}

export default useDynamicViewportHeight;

