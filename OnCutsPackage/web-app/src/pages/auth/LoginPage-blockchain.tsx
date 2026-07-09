/**
 * Blockchain-Powered Login Page
 * 
 * Example of blockchain authentication with optimistic UI.
 * Users have NO IDEA they're using blockchain!
 * 
 * Features:
 * - Instant feedback
 * - Friendly error messages
 * - Automatic retry
 * - Loading states
 */

import { useState } from 'react';
import { Link } from 'react-router-dom';
import { useBlockchainLogin } from '../../hooks/useBlockchainAuth';
import { useToast } from '../../components/Toast';

export default function LoginPageBlockchain() {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const login = useBlockchainLogin();
  const toast = useToast();

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();

    // Validate
    if (!email.endsWith('.edu')) {
      toast.error('Please use your .edu email address');
      return;
    }

    if (password.length < 6) {
      toast.error('Password must be at least 6 characters');
      return;
    }

    // Login with optimistic UI
    login.mutate(
      { email, password },
      {
        onSuccess: (response) => {
          if (response.success) {
            toast.success('Login successful!');
            // Navigation happens automatically in the hook
          } else {
            toast.error(response.message || 'Invalid email or password');
          }
        },
        onError: (error) => {
          toast.error('Login failed. Please try again.');
          console.error('Login error:', error);
        },
      }
    );
  };

  return (
    <div className="min-h-screen flex items-center justify-center bg-gradient-to-r from-blue-50 to-primary-50 px-4">
      <div className="max-w-md w-full space-y-8">
        {/* Header */}
        <div className="text-center">
          <h1 className="text-4xl font-bold text-gray-900">CampusCut</h1>
          <p className="mt-2 text-sm text-gray-600">
            Book haircuts with students on your campus
          </p>
        </div>

        {/* Login Form */}
        <div className="bg-white rounded-lg shadow-xl p-8 space-y-6">
          <div>
            <h2 className="text-2xl font-bold text-gray-900">Sign In</h2>
            <p className="mt-1 text-sm text-gray-600">
              Access your account
            </p>
          </div>

          <form onSubmit={handleSubmit} className="space-y-4">
            {/* Email */}
            <div>
              <label htmlFor="email" className="block text-sm font-medium text-gray-700 mb-1">
                University Email
              </label>
              <input
                id="email"
                type="email"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                placeholder="you@university.edu"
                className="w-full px-4 py-3 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent transition"
                required
                disabled={login.isPending}
              />
              <p className="mt-1 text-xs text-gray-500">
                Must end with .edu
              </p>
            </div>

            {/* Password */}
            <div>
              <label htmlFor="password" className="block text-sm font-medium text-gray-700 mb-1">
                Password
              </label>
              <input
                id="password"
                type="password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                placeholder="••••••••"
                className="w-full px-4 py-3 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent transition"
                required
                disabled={login.isPending}
              />
            </div>

            {/* Submit Button */}
            <button
              type="submit"
              disabled={login.isPending}
              className="w-full bg-blue-600 hover:bg-blue-700 text-white px-6 py-3 rounded-lg font-medium transition shadow-md hover:shadow-lg disabled:opacity-50 disabled:cursor-not-allowed flex items-center justify-center"
            >
              {login.isPending ? (
                <>
                  <svg className="animate-spin -ml-1 mr-3 h-5 w-5 text-white" fill="none" viewBox="0 0 24 24">
                    <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4"></circle>
                    <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                  </svg>
                  Signing in...
                </>
              ) : (
                'Sign In'
              )}
            </button>
          </form>

          {/* Sign Up Link */}
          <div className="text-center text-sm">
            <span className="text-gray-600">Don't have an account? </span>
            <Link to="/signup" className="text-blue-600 hover:text-blue-700 font-medium">
              Sign up
            </Link>
          </div>

          {/* Hidden blockchain info (users never see this) */}
          {import.meta.env.DEV && (
            <div className="mt-6 p-4 bg-gray-50 rounded-md border border-gray-200">
              <p className="text-xs text-gray-500 mb-2">
                <strong>Dev Mode:</strong> Behind the scenes
              </p>
              <ul className="text-xs text-gray-600 space-y-1">
                <li>Authenticates with your account</li>
                <li>Loads account from on-chain storage</li>
                <li>No wallet or crypto needed!</li>
                <li>User has NO IDEA they're using blockchain!</li>
              </ul>
            </div>
          )}
        </div>

        {/* Footer */}
        <p className="text-center text-xs text-gray-500">
          By signing in, you agree to our{' '}
          <Link to="/terms" className="text-emerald-600 hover:text-emerald-700 hover:underline">Terms of Service</Link>
          {' '}and{' '}
          <Link to="/privacy" className="text-emerald-600 hover:text-emerald-700 hover:underline">Privacy Policy</Link>
        </p>
      </div>
    </div>
  );
}

