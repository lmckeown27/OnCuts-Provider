/**
 * @deprecated Use Payout Settings (`PaymentManagementModal`) and Stripe Connect; this legacy UI is unused.
 * Kept for reference — prefer Stripe Connect and Payout Settings on the barber dashboard.
 */

import { useState, useEffect } from 'react';
import {
  DollarSign,
  TrendingUp,
  Clock,
  CheckCircle,
  AlertCircle,
  ExternalLink,
  RefreshCw,
  CreditCard,
} from 'lucide-react';
import Button from './Button';
import Card from './Card';

interface BarberWithdrawalProps {
  barberId: string;
  stripeAccountId?: string;
}

interface Balance {
  available: number;
  pending: number;
}

interface Payout {
  id: string;
  amount: number;
  created: string;
  metadata: Record<string, string>;
}

export default function BarberWithdrawal({ barberId, stripeAccountId }: BarberWithdrawalProps) {
  const [isOnboarded, setIsOnboarded] = useState(false);
  const [isLoading, setIsLoading] = useState(true);
  const [balance, setBalance] = useState<Balance>({ available: 0, pending: 0 });
  const [payouts, setPayouts] = useState<Payout[]>([]);
  const [withdrawAmount, setWithdrawAmount] = useState('');
  const [isWithdrawing, setIsWithdrawing] = useState(false);

  useEffect(() => {
    if (stripeAccountId) {
      loadAccountData();
    } else {
      setIsLoading(false);
    }
  }, [stripeAccountId]);

  const loadAccountData = async () => {
    if (!stripeAccountId) return;

    try {
      // Get account status
      const statusRes = await fetch(
        `http://localhost:3001/api/payments/barber/${stripeAccountId}/status`
      );
      const statusData = await statusRes.json();

      if (statusData.success) {
        setIsOnboarded(statusData.data.isOnboarded);
      }

      // Get balance
      const balanceRes = await fetch(
        `http://localhost:3001/api/payments/barber/${stripeAccountId}/balance`
      );
      const balanceData = await balanceRes.json();

      if (balanceData.success) {
        setBalance(balanceData.data);
      }

      // Get payout history
      const payoutsRes = await fetch(
        `http://localhost:3001/api/payments/barber/${stripeAccountId}/payouts`
      );
      const payoutsData = await payoutsRes.json();

      if (payoutsData.success) {
        setPayouts(payoutsData.data);
      }
    } catch (error) {
      console.error('Error loading account data:', error);
    } finally {
      setIsLoading(false);
    }
  };

  const handleOnboarding = async () => {
    try {
      const response = await fetch('http://localhost:3001/api/payments/barber/connect', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          userId: barberId,
          email: `${barberId}@demo.com`,
          firstName: 'Demo',
          lastName: 'Barber',
        }),
      });

      const data = await response.json();

      if (data.success) {
        // Redirect to Stripe onboarding
        window.location.href = data.data.onboardingUrl;
      }
    } catch (error) {
      console.error('Error creating Connect account:', error);
      alert('Failed to start onboarding');
    }
  };

  const handleWithdraw = async () => {
    if (!stripeAccountId || !withdrawAmount) return;

    const amount = parseFloat(withdrawAmount);
    if (isNaN(amount) || amount <= 0 || amount > balance.available) {
      alert('Invalid withdrawal amount');
      return;
    }

    setIsWithdrawing(true);

    try {
      const response = await fetch(
        `http://localhost:3001/api/payments/barber/${stripeAccountId}/payout`,
        {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ amount }),
        }
      );

      const data = await response.json();

      if (data.success) {
        alert(`Withdrawal of $${amount} initiated successfully!`);
        setWithdrawAmount('');
        loadAccountData(); // Reload balance
      } else {
        alert(data.message || 'Withdrawal failed');
      }
    } catch (error) {
      console.error('Error withdrawing:', error);
      alert('Withdrawal failed');
    } finally {
      setIsWithdrawing(false);
    }
  };

  const openDashboard = async () => {
    if (!stripeAccountId) return;

    try {
      const response = await fetch(
        `http://localhost:3001/api/payments/barber/${stripeAccountId}/dashboard-link`
      );
      const data = await response.json();

      if (data.success) {
        window.open(data.data.url, '_blank');
      }
    } catch (error) {
      console.error('Error opening dashboard:', error);
      alert('Failed to open Stripe dashboard');
    }
  };

  if (isLoading) {
    return (
      <Card>
        <div className="flex items-center justify-center p-8">
          <RefreshCw className="w-6 h-6 animate-spin text-primary-400" />
          <span className="ml-2 text-gray-600">Loading earnings...</span>
        </div>
      </Card>
    );
  }

  // Not onboarded - show onboarding prompt
  if (!isOnboarded) {
    return (
      <Card className="text-center p-8">
        <div className="bg-primary-100 rounded-full p-4 w-16 h-16 mx-auto mb-4 flex items-center justify-center">
          <CreditCard className="w-8 h-8 text-primary-400" />
        </div>
        <h2 className="text-2xl font-bold text-gray-900 mb-2">Setup Payouts</h2>
        <p className="text-gray-600 mb-6 max-w-md mx-auto">
          Connect your bank account via Stripe to receive payments from completed bookings.
          It takes less than 5 minutes.
        </p>
        <Button onClick={handleOnboarding} className="px-8">
          <ExternalLink className="w-4 h-4 mr-2" />
          Connect Bank Account
        </Button>
        <p className="text-xs text-gray-500 mt-4">
          Powered by Stripe • Secure & Encrypted
        </p>
      </Card>
    );
  }

  return (
    <div className="space-y-6">
      {/* Balance Cards */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
        <Card>
          <div className="flex items-center gap-4">
            <div className="bg-green-100 rounded-full p-3">
              <DollarSign className="w-6 h-6 text-green-600" />
            </div>
            <div>
              <p className="text-sm text-gray-600 mb-1">Available Balance</p>
              <p className="text-3xl font-bold text-gray-900">
                ${balance.available.toFixed(2)}
              </p>
              <p className="text-xs text-gray-500 mt-1">Ready to withdraw</p>
            </div>
          </div>
        </Card>

        <Card>
          <div className="flex items-center gap-4">
            <div className="bg-blue-100 rounded-full p-3">
              <Clock className="w-6 h-6 text-blue-600" />
            </div>
            <div>
              <p className="text-sm text-gray-600 mb-1">Pending Balance</p>
              <p className="text-3xl font-bold text-gray-900">
                ${balance.pending.toFixed(2)}
              </p>
              <p className="text-xs text-gray-500 mt-1">Processing</p>
            </div>
          </div>
        </Card>
      </div>

      {/* Withdrawal Section */}
      <Card>
        <h3 className="text-lg font-bold text-gray-900 mb-4">Withdraw Funds</h3>
        
        {balance.available > 0 ? (
          <div className="space-y-4">
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-2">
                Withdrawal Amount
              </label>
              <div className="flex gap-2">
                <input
                  type="number"
                  value={withdrawAmount}
                  onChange={(e) => setWithdrawAmount(e.target.value)}
                  className="flex-1 px-4 py-3 border border-gray-300 rounded-lg focus:ring-2 focus:ring-primary-500 focus:border-transparent"
                  placeholder="0.00"
                  min="0"
                  max={balance.available}
                  step="0.01"
                />
                <Button
                  onClick={() => setWithdrawAmount(balance.available.toString())}
                  variant="secondary"
                >
                  Max
                </Button>
              </div>
              <p className="text-xs text-gray-500 mt-1">
                Maximum: ${balance.available.toFixed(2)}
              </p>
            </div>

            <Button
              onClick={handleWithdraw}
              disabled={isWithdrawing || !withdrawAmount || parseFloat(withdrawAmount) <= 0}
              className="w-full"
            >
              {isWithdrawing ? (
                <>
                  <RefreshCw className="w-4 h-4 mr-2 animate-spin" />
                  Processing...
                </>
              ) : (
                <>
                  <TrendingUp className="w-4 h-4 mr-2" />
                  Withdraw to Bank Account
                </>
              )}
            </Button>

            <p className="text-xs text-center text-gray-500">
              Funds typically arrive in 1-2 business days
            </p>
          </div>
        ) : (
          <div className="text-center py-8">
            <AlertCircle className="w-12 h-12 text-gray-400 mx-auto mb-3" />
            <p className="text-gray-600">No funds available for withdrawal</p>
            <p className="text-sm text-gray-500 mt-1">
              Complete bookings to earn money
            </p>
          </div>
        )}
      </Card>

      {/* Payout History */}
      <Card>
        <div className="flex items-center justify-between mb-4">
          <h3 className="text-lg font-bold text-gray-900">Payout History</h3>
          <Button variant="secondary" onClick={openDashboard}>
            <ExternalLink className="w-4 h-4 mr-2" />
            Stripe Dashboard
          </Button>
        </div>

        {payouts.length > 0 ? (
          <div className="space-y-3">
            {payouts.map((payout) => (
              <div
                key={payout.id}
                className="flex items-center justify-between p-3 bg-gray-50 rounded-lg"
              >
                <div className="flex items-center gap-3">
                  <div className="bg-green-100 rounded-full p-2">
                    <CheckCircle className="w-4 h-4 text-green-600" />
                  </div>
                  <div>
                    <p className="font-medium text-gray-900">
                      ${payout.amount.toFixed(2)}
                    </p>
                    <p className="text-xs text-gray-500">
                      {new Date(payout.created).toLocaleDateString()}
                    </p>
                  </div>
                </div>
                <span className="text-sm px-3 py-1 bg-green-100 text-green-800 rounded-full font-medium">
                  Completed
                </span>
              </div>
            ))}
          </div>
        ) : (
          <div className="text-center py-8">
            <Clock className="w-12 h-12 text-gray-400 mx-auto mb-3" />
            <p className="text-gray-600">No payouts yet</p>
            <p className="text-sm text-gray-500 mt-1">
              Your withdrawal history will appear here
            </p>
          </div>
        )}
      </Card>
    </div>
  );
}

