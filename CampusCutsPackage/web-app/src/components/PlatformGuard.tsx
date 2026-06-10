/**
 * Platform Guard Component
 * 
 * Ensures users stay within their chosen platform (web or app)
 * Prevents cross-platform navigation
 */

import { useEffect } from 'react';
import { useLocation, useNavigate } from 'react-router-dom';

interface PlatformGuardProps {
  children: React.ReactNode;
  requiredPlatform: 'web' | 'app';
}

export default function PlatformGuard({ children, requiredPlatform }: PlatformGuardProps) {
  const location = useLocation();
  const navigate = useNavigate();

  useEffect(() => {
    const currentPath = location.pathname;
    const isWebRoute = currentPath.startsWith('/web');
    const isAppRoute = currentPath.startsWith('/app');

    // If on wrong platform, redirect to correct entry point
    if (requiredPlatform === 'web' && isAppRoute) {
      console.warn('🚫 App route accessed from web platform. Redirecting to /web');
      navigate('/web', { replace: true });
    } else if (requiredPlatform === 'app' && isWebRoute) {
      console.warn('🚫 Web route accessed from app platform. Redirecting to /app');
      navigate('/app', { replace: true });
    }
  }, [location.pathname, requiredPlatform, navigate]);

  return <>{children}</>;
}

/**
 * Hook to get current platform context
 */
export function usePlatform(): 'web' | 'app' | null {
  const location = useLocation();
  
  if (location.pathname.startsWith('/web')) return 'web';
  if (location.pathname.startsWith('/app')) return 'app';
  return null;
}

/**
 * Hook to generate platform-aware routes
 */
export function usePlatformRoute() {
  const platform = usePlatform();
  
  return (route: string) => {
    if (!platform) return route;
    
    // Remove leading slash if present
    const cleanRoute = route.startsWith('/') ? route.slice(1) : route;
    
    return `/${platform}/${cleanRoute}`;
  };
}

