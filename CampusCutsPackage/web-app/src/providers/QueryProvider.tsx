/**
 * React Query Provider
 * 
 * Configures React Query with optimized settings for blockchain data.
 * Includes retry logic, caching, and background refetching.
 */

import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { lazy, ReactNode, Suspense } from 'react';

/** Only instantiated when `import.meta.env.DEV` — production builds drop the lazy `import()` entirely. */
const ReactQueryDevtoolsPanel = import.meta.env.DEV
  ? lazy(() =>
      import('@tanstack/react-query-devtools').then((d) => ({
        default: d.ReactQueryDevtools,
      })),
    )
  : () => null;

// Create a client with custom defaults optimized for blockchain
const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      // Retry failed requests (blockchain can be slow)
      retry: 3,
      retryDelay: (attemptIndex) => Math.min(1000 * 2 ** attemptIndex, 30000),
      
      // Stale time - how long data is considered fresh
      staleTime: 30 * 1000, // 30 seconds (blockchain updates slowly)
      
      // Cache time - how long unused data stays in memory
      gcTime: 5 * 60 * 1000, // 5 minutes
      
      // Refetch on window focus (good for live data)
      refetchOnWindowFocus: true,
      
      // Refetch on reconnect
      refetchOnReconnect: true,
      
      // Don't refetch on mount if data is fresh
      refetchOnMount: false,
    },
    mutations: {
      // Retry failed mutations once
      retry: 1,
      retryDelay: 2000,
    },
  },
});

interface QueryProviderProps {
  children: ReactNode;
}

export function QueryProvider({ children }: QueryProviderProps) {
  return (
    <QueryClientProvider client={queryClient}>
      {children}
      {import.meta.env.DEV && (
        <Suspense fallback={null}>
          <ReactQueryDevtoolsPanel initialIsOpen={false} />
        </Suspense>
      )}
    </QueryClientProvider>
  );
}

export default QueryProvider;

