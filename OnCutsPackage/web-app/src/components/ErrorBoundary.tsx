/**
 * Error Boundary Component
 * 
 * Catches React errors and blockchain errors gracefully.
 * Provides friendly error messages and retry options.
 * 
 * Handles:
 * - Blockchain transaction failures
 * - Network errors
 * - Component crashes
 * - IPFS upload failures
 */

import { Component } from 'react';
import type { ReactNode } from 'react';

interface Props {
  children: ReactNode;
  fallback?: ReactNode;
  onError?: (error: Error, errorInfo: any) => void;
}

interface State {
  hasError: boolean;
  error: Error | null;
  errorInfo: any;
  retryCount: number;
}

export class ErrorBoundary extends Component<Props, State> {
  constructor(props: Props) {
    super(props);
    this.state = {
      hasError: false,
      error: null,
      errorInfo: null,
      retryCount: 0,
    };
  }

  static getDerivedStateFromError(error: Error): Partial<State> {
    return { hasError: true, error };
  }

  componentDidCatch(error: Error, errorInfo: any) {
    console.error('Error caught by boundary:', error, errorInfo);
    
    this.setState({ errorInfo });
    
    // Call custom error handler if provided
    this.props.onError?.(error, errorInfo);
    
    // Log to error tracking service (e.g., Sentry)
    if (import.meta.env.PROD) {
      // window.Sentry?.captureException(error);
    }
  }

  handleRetry = () => {
    this.setState(prev => ({
      hasError: false,
      error: null,
      errorInfo: null,
      retryCount: prev.retryCount + 1,
    }));
  };

  handleReload = () => {
    window.location.reload();
  };

  render() {
    if (this.state.hasError) {
      // Use custom fallback if provided
      if (this.props.fallback) {
        return this.props.fallback;
      }

      // Default error UI
      return (
        <div className="min-h-screen flex items-center justify-center bg-gray-50 px-4">
          <div className="max-w-md w-full bg-white rounded-lg shadow-lg p-6 space-y-4">
            <div className="flex items-center space-x-3">
              <div className="flex-shrink-0">
                <svg className="h-10 w-10 text-red-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
                </svg>
              </div>
              <div>
                <h3 className="text-lg font-medium text-gray-900">
                  Oops! Something went wrong
                </h3>
                <p className="text-sm text-gray-500 mt-1">
                  {this.getErrorMessage()}
                </p>
              </div>
            </div>

            {import.meta.env.DEV && this.state.error && (
              <div className="bg-gray-50 rounded-md p-4 text-xs font-mono text-gray-700 overflow-auto max-h-40">
                <p className="font-semibold mb-2">Error details (dev mode):</p>
                <p>{this.state.error.toString()}</p>
                {this.state.errorInfo && (
                  <pre className="mt-2 text-xs overflow-auto">
                    {this.state.errorInfo.componentStack}
                  </pre>
                )}
              </div>
            )}

            <div className="flex space-x-3">
              <button
                onClick={this.handleRetry}
                className="flex-1 bg-blue-600 hover:bg-blue-700 text-white px-4 py-2 rounded-md font-medium transition"
              >
                Try Again
              </button>
              <button
                onClick={this.handleReload}
                className="flex-1 bg-gray-200 hover:bg-gray-300 text-gray-700 px-4 py-2 rounded-md font-medium transition"
              >
                Reload Page
              </button>
            </div>

            {this.state.retryCount > 0 && (
              <p className="text-xs text-gray-500 text-center">
                Retry attempt: {this.state.retryCount}
              </p>
            )}
          </div>
        </div>
      );
    }

    return this.props.children;
  }

  private getErrorMessage(): string {
    const error = this.state.error;
    
    if (!error) return 'An unexpected error occurred';

    // Blockchain-specific errors
    if (error.message.includes('blockchain')) {
      return 'Blockchain connection error. Please check your network and try again.';
    }
    
    if (error.message.includes('IPFS')) {
      return 'File upload failed. Please check your connection and try again.';
    }
    
    if (error.message.includes('insufficient balance')) {
      return 'Insufficient balance. Please add funds to your account.';
    }
    
    if (error.message.includes('transaction failed')) {
      return 'Transaction failed. Your funds are safe. Please try again.';
    }
    
    if (error.message.includes('unauthorized')) {
      return 'Session expired. Please log in again.';
    }

    // Network errors
    if (error.message.includes('Network')) {
      return 'Network error. Please check your internet connection.';
    }

    // Generic error
    return 'Something went wrong. We\'re working on it!';
  }
}

/**
 * Hook-based error boundary for functional components
 */
export function useErrorHandler() {
  return (error: Error) => {
    throw error; // Will be caught by ErrorBoundary
  };
}

/**
 * Blockchain-specific error boundary
 * Provides tailored messages for blockchain errors
 */
export function BlockchainErrorBoundary({ children }: { children: ReactNode }) {
  return (
    <ErrorBoundary
      fallback={
        <div className="min-h-screen flex items-center justify-center bg-gradient-to-r from-blue-50 to-primary-50 px-4">
          <div className="max-w-md w-full bg-white rounded-lg shadow-xl p-8 space-y-6">
            <div className="text-center">
              <svg className="mx-auto h-16 w-16 text-yellow-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
              </svg>
              <h3 className="mt-4 text-xl font-bold text-gray-900">
                Blockchain Connection Issue
              </h3>
              <p className="mt-2 text-gray-600">
                We're having trouble connecting to the blockchain.
                Don't worry, your data is safe!
              </p>
            </div>

            <div className="bg-blue-50 border border-blue-200 rounded-md p-4">
              <p className="text-sm text-blue-800">
                <strong>What this means:</strong> The blockchain network might be experiencing high traffic.
                Your account and funds are secure.
              </p>
            </div>

            <button
              onClick={() => window.location.reload()}
              className="w-full bg-blue-600 hover:bg-blue-700 text-white px-6 py-3 rounded-md font-medium transition shadow-md hover:shadow-lg"
            >
              Reconnect to Blockchain
            </button>

            <p className="text-xs text-center text-gray-500">
              Still having issues? <a href="/support" className="text-blue-600 hover:underline">Contact Support</a>
            </p>
          </div>
        </div>
      }
      onError={(error, errorInfo) => {
        console.error('Blockchain error:', error, errorInfo);
        // Log to analytics
      }}
    >
      {children}
    </ErrorBoundary>
  );
}

export default ErrorBoundary;

