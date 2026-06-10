/**
 * Blockchain-Powered Signup Page
 * 
 * Creates a blockchain account behind the scenes!
 * Users think they're just signing up normally.
 * 
 * What happens behind the scenes:
 * 1. Derives wallet id from email (legacy flow)
 * 2. Encrypts private key with password
 * 3. Submits transaction to create on-chain account
 * 4. Returns JWT token (normal Web2 auth)
 * 
 * User experience: Feels exactly like any other app!
 */

import { useState } from 'react';
import { Link } from 'react-router-dom';
import { useBlockchainSignup } from '../../hooks/useBlockchainAuth';
import { useToast } from '../../components/Toast';

export default function SignupPageBlockchain() {
  const [formData, setFormData] = useState({
    email: '',
    password: '',
    confirmPassword: '',
    username: '',
    role: 'student' as 'student' | 'barber',
  });
  
  const signup = useBlockchainSignup();
  const toast = useToast();

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();

    // Validation
    if (!formData.email.endsWith('.edu')) {
      toast.error('Please use your .edu email address');
      return;
    }

    if (formData.password.length < 8) {
      toast.error('Password must be at least 8 characters');
      return;
    }

    if (formData.password !== formData.confirmPassword) {
      toast.error('Passwords do not match');
      return;
    }

    if (formData.username.length < 3) {
      toast.error('Username must be at least 3 characters');
      return;
    }

    // Extract campus domain
    const campusDomain = formData.email.split('@')[1];

    // Sign up with optimistic UI
    signup.mutate(
      {
        email: formData.email,
        password: formData.password,
        username: formData.username,
        campus_domain: campusDomain,
        role: formData.role,
      },
      {
        onSuccess: (response) => {
          if (response.success) {
            toast.success('Account created! Welcome to CampusCut!');
            // Navigation happens automatically in the hook
          } else {
            toast.error(response.message || 'Failed to create account');
          }
        },
        onError: (error) => {
          toast.error('Signup failed. Please try again.');
          console.error('Signup error:', error);
        },
      }
    );
  };

  return (
    <div className="min-h-screen flex items-center justify-center bg-gradient-to-r from-blue-50 to-primary-50 px-4 py-12">
      <div className="max-w-md w-full space-y-8">
        {/* Header */}
        <div className="text-center">
          <h1 className="text-4xl font-bold text-gray-900">Join CampusCut</h1>
          <p className="mt-2 text-sm text-gray-600">
            Get haircuts from talented students on your campus
          </p>
        </div>

        {/* Signup Form */}
        <div className="bg-white rounded-lg shadow-xl p-8 space-y-6">
          <div>
            <h2 className="text-2xl font-bold text-gray-900">Create your account</h2>
            <p className="mt-1 text-sm text-gray-600">
              Get started in less than a minute
            </p>
          </div>

          <form onSubmit={handleSubmit} className="space-y-4">
            {/* Role Selection */}
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-2">
                I am a:
              </label>
              <div className="grid grid-cols-2 gap-3">
                <button
                  type="button"
                  onClick={() => setFormData({ ...formData, role: 'student' })}
                  className={`px-4 py-3 rounded-lg border-2 font-medium transition ${
                    formData.role === 'student'
                      ? 'border-blue-600 bg-blue-50 text-blue-700'
                      : 'border-gray-300 text-gray-700 hover:border-gray-400'
                  }`}
                  disabled={signup.isPending}
                >
                  Student
                </button>
                <button
                  type="button"
                  onClick={() => setFormData({ ...formData, role: 'barber' })}
                  className={`px-4 py-3 rounded-lg border-2 font-medium transition ${
                    formData.role === 'barber'
                      ? 'border-blue-600 bg-blue-50 text-blue-700'
                      : 'border-gray-300 text-gray-700 hover:border-gray-400'
                  }`}
                  disabled={signup.isPending}
                >
                  Barber
                </button>
              </div>
            </div>

            {/* Username */}
            <div>
              <label htmlFor="username" className="block text-sm font-medium text-gray-700 mb-1">
                Username
              </label>
              <input
                id="username"
                type="text"
                value={formData.username}
                onChange={(e) => setFormData({ ...formData, username: e.target.value })}
                placeholder="john_doe"
                className="w-full px-4 py-3 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent transition"
                required
                disabled={signup.isPending}
              />
            </div>

            {/* Email */}
            <div>
              <label htmlFor="email" className="block text-sm font-medium text-gray-700 mb-1">
                University Email
              </label>
              <input
                id="email"
                type="email"
                value={formData.email}
                onChange={(e) => setFormData({ ...formData, email: e.target.value })}
                placeholder="you@university.edu"
                className="w-full px-4 py-3 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent transition"
                required
                disabled={signup.isPending}
              />
              <p className="mt-1 text-xs text-gray-500">
                Must be a .edu email address
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
                value={formData.password}
                onChange={(e) => setFormData({ ...formData, password: e.target.value })}
                placeholder="••••••••"
                className="w-full px-4 py-3 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent transition"
                required
                disabled={signup.isPending}
              />
              <p className="mt-1 text-xs text-gray-500">
                At least 8 characters
              </p>
            </div>

            {/* Confirm Password */}
            <div>
              <label htmlFor="confirmPassword" className="block text-sm font-medium text-gray-700 mb-1">
                Confirm Password
              </label>
              <input
                id="confirmPassword"
                type="password"
                value={formData.confirmPassword}
                onChange={(e) => setFormData({ ...formData, confirmPassword: e.target.value })}
                placeholder="••••••••"
                className="w-full px-4 py-3 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent transition"
                required
                disabled={signup.isPending}
              />
            </div>

            {/* Submit Button */}
            <button
              type="submit"
              disabled={signup.isPending}
              className="w-full bg-blue-600 hover:bg-blue-700 text-white px-6 py-3 rounded-lg font-medium transition shadow-md hover:shadow-lg disabled:opacity-50 disabled:cursor-not-allowed flex items-center justify-center"
            >
              {signup.isPending ? (
                <>
                  <svg className="animate-spin -ml-1 mr-3 h-5 w-5 text-white" fill="none" viewBox="0 0 24 24">
                    <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4"></circle>
                    <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                  </svg>
                  Creating your account...
                </>
              ) : (
                'Create Account'
              )}
            </button>
          </form>

          {/* Login Link */}
          <div className="text-center text-sm">
            <span className="text-gray-600">Already have an account? </span>
            <Link to="/login" className="text-blue-600 hover:text-blue-700 font-medium">
              Sign in
            </Link>
          </div>

          {/* Hidden blockchain info (users never see this) */}
          {import.meta.env.DEV && (
            <div className="mt-6 p-4 bg-yellow-50 rounded-md border border-yellow-200">
              <p className="text-xs text-yellow-800 mb-2">
                <strong>The Illusion:</strong> What's really happening
              </p>
              <ul className="text-xs text-yellow-700 space-y-1">
                <li>1. Deriving wallet id from email</li>
                <li>2. Encrypting private key with password</li>
                <li>3. Creating on-chain account (if enabled)</li>
                <li>4. Storing metadata securely</li>
                <li>5. User thinks: "Normal signup"</li>
                <li>6. Reality: They own a blockchain account!</li>
              </ul>
            </div>
          )}
        </div>

        {/* Footer */}
        <p className="text-center text-xs text-gray-500">
          By creating an account, you agree to our{' '}
          <Link to="/terms" className="text-emerald-600 hover:text-emerald-700 hover:underline">Terms of Service</Link>
          {' '}and{' '}
          <Link to="/privacy" className="text-emerald-600 hover:text-emerald-700 hover:underline">Privacy Policy</Link>
        </p>
      </div>
    </div>
  );
}

