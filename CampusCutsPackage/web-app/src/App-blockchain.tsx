/**
 * Main App Component (Blockchain-First Version)
 * 
 * Wraps the entire app with all necessary providers:
 * - React Query (blockchain data caching)
 * - Toast notifications
 * - Error boundary
 * 
 * This version uses the blockchain-first architecture.
 */

import { BrowserRouter as Router, Routes, Route, Navigate } from 'react-router-dom';
import { QueryProvider } from './providers/QueryProvider';
import { ToastProvider } from './components/Toast';
import { ErrorBoundary, BlockchainErrorBoundary } from './components/ErrorBoundary';

// Auth pages
import LoginPage from './pages/auth/LoginPage';
import SignupPage from './pages/auth/SignupPage';

// Student pages
import DiscoveryPage from './pages/student/DiscoveryPage';
import StudentBookingsPage from './pages/student/StudentBookingsPage';
import StudentProfilePage from './pages/student/StudentProfilePage';
import BarberDetailPage from './pages/student/BarberDetailPage';

// Barber pages
import BarberDashboardPage from './pages/barber/BarberDashboardPage';
import BarberProfilePage from './pages/barber/BarberProfilePage';
import BarberEarningsPage from './pages/barber/BarberEarningsPage';

// Common pages
import WalletPage from './pages/WalletPage';

// Import CSS
import './index.css';
import './styles/skeleton.css';

function App() {
  return (
    <BlockchainErrorBoundary>
      <QueryProvider>
        <ToastProvider>
          <ErrorBoundary>
            <Router>
              <Routes>
                {/* Public routes */}
                <Route path="/login" element={<LoginPage />} />
                <Route path="/signup" element={<SignupPage />} />

                {/* Student routes */}
                <Route path="/student/discovery" element={<DiscoveryPage />} />
                <Route path="/student/bookings" element={<StudentBookingsPage />} />
                <Route path="/student/profile" element={<StudentProfilePage />} />
                <Route path="/student/barber/:id" element={<BarberDetailPage />} />
                <Route path="/student/wallet" element={<WalletPage />} />

                {/* Barber routes */}
                <Route path="/barber/dashboard" element={<BarberDashboardPage />} />
                <Route path="/barber/profile" element={<BarberProfilePage />} />
                <Route path="/barber/earnings" element={<BarberEarningsPage />} />
                <Route path="/barber/wallet" element={<WalletPage />} />

                {/* Default redirect */}
                <Route path="/" element={<Navigate to="/login" replace />} />
                <Route path="*" element={<Navigate to="/login" replace />} />
              </Routes>
            </Router>
          </ErrorBoundary>
        </ToastProvider>
      </QueryProvider>
    </BlockchainErrorBoundary>
  );
}

export default App;

