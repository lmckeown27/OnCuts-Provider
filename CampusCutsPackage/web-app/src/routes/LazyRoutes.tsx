/**
 * Lazy-Loaded Routes (Code Splitting)
 * 
 * Splits the app into smaller chunks for faster initial load.
 * Each route is loaded only when needed.
 * 
 * Benefits:
 * - Faster initial page load
 * - Smaller bundle size
 * - Better performance scores
 * - Improved UX
 */

import { lazy, Suspense } from 'react';
import { Routes, Route, Navigate } from 'react-router-dom';
import { SkeletonGrid, ProfileSkeleton } from '../components/Skeleton';

// Lazy load pages (code splitting)
const LoginPage = lazy(() => import('../pages/auth/LoginPage-blockchain'));
const SignupPage = lazy(() => import('../pages/auth/SignupPage-blockchain'));

// Student pages
const DiscoveryPage = lazy(() => import('../pages/student/DiscoveryPage'));
const StudentBookingsPage = lazy(() => import('../pages/student/StudentBookingsPage-blockchain'));
const StudentProfilePage = lazy(() => import('../pages/student/StudentProfilePage'));
const BarberDetailPage = lazy(() => import('../pages/student/BarberDetailPage'));

// Barber pages
const BarberDashboardPage = lazy(() => import('../pages/barber/BarberDashboardPage'));
const BarberProfilePage = lazy(() => import('../pages/barber/BarberProfilePage'));
const BarberEarningsPage = lazy(() => import('../pages/barber/BarberEarningsPage'));

// Common pages
const WalletPage = lazy(() => import('../pages/WalletPage'));

/**
 * Loading component for lazy routes
 */
function PageLoader() {
  return (
    <div className="min-h-screen bg-gray-50 p-8">
      <div className="max-w-7xl mx-auto">
        <ProfileSkeleton />
        <div className="mt-8">
          <SkeletonGrid count={6} type="booking" />
        </div>
      </div>
    </div>
  );
}

/**
 * Lazy routes with suspense boundaries
 */
export function LazyRoutes() {
  return (
    <Suspense fallback={<PageLoader />}>
      <Routes>
        {/* Public routes */}
        <Route path="/login" element={<LoginPage />} />
        <Route path="/signup" element={<SignupPage />} />

        {/* Student routes */}
        <Route 
          path="/student/discovery" 
          element={
            <Suspense fallback={<PageLoader />}>
              <DiscoveryPage />
            </Suspense>
          } 
        />
        <Route 
          path="/student/bookings" 
          element={
            <Suspense fallback={<PageLoader />}>
              <StudentBookingsPage />
            </Suspense>
          } 
        />
        <Route 
          path="/student/profile" 
          element={
            <Suspense fallback={<PageLoader />}>
              <StudentProfilePage />
            </Suspense>
          } 
        />
        <Route 
          path="/student/barber/:id" 
          element={
            <Suspense fallback={<PageLoader />}>
              <BarberDetailPage />
            </Suspense>
          } 
        />
        <Route 
          path="/student/wallet" 
          element={
            <Suspense fallback={<PageLoader />}>
              <WalletPage />
            </Suspense>
          } 
        />

        {/* Barber routes */}
        <Route 
          path="/barber/dashboard" 
          element={
            <Suspense fallback={<PageLoader />}>
              <BarberDashboardPage />
            </Suspense>
          } 
        />
        <Route 
          path="/barber/profile" 
          element={
            <Suspense fallback={<PageLoader />}>
              <BarberProfilePage />
            </Suspense>
          } 
        />
        <Route 
          path="/barber/earnings" 
          element={
            <Suspense fallback={<PageLoader />}>
              <BarberEarningsPage />
            </Suspense>
          } 
        />
        <Route 
          path="/barber/wallet" 
          element={
            <Suspense fallback={<PageLoader />}>
              <WalletPage />
            </Suspense>
          } 
        />

        {/* Default redirect */}
        <Route path="/" element={<Navigate to="/login" replace />} />
        <Route path="*" element={<Navigate to="/login" replace />} />
      </Routes>
    </Suspense>
  );
}

export default LazyRoutes;

