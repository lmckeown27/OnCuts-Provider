/**
 * Barber payout setup — Stripe Connect (legacy URL /web/barber/connect).
 * Sends barbers to Payout Settings on the dashboard.
 */

import { useNavigate } from 'react-router-dom';
import { Landmark, ArrowRight } from 'lucide-react';
import Button from '../components/Button';
import Card from '../components/Card';

export const BarberConnectOnboarding = () => {
  const navigate = useNavigate();

  return (
    <div className="min-h-screen bg-gray-50 flex items-center justify-center p-4">
      <Card className="max-w-lg w-full p-8 shadow-lg">
        <div className="flex items-center gap-3 text-primary-600 mb-4">
          <Landmark className="w-8 h-8" />
          <h1 className="text-2xl font-bold text-gray-900">Payout setup (Stripe Connect)</h1>
        </div>
        <p className="text-gray-600 mb-4">
          Customer payments run through <strong>Stripe</strong>. Your earnings are paid out with{' '}
          <strong>Stripe Connect</strong>—CampusCuts does <strong>not</strong> hold barber money in a platform balance.
          Complete Connect onboarding (bank account) when prompted from your barber dashboard or Stripe.
        </p>
        <ul className="text-sm text-gray-600 list-disc pl-5 space-y-2 mb-6">
          <li>Open Payout Settings from your barber dashboard for booking estimates.</li>
          <li>Use your Stripe Express / Connect dashboard for payouts to your bank.</li>
        </ul>
        <Button
          variant="primary"
          size="lg"
          className="w-full"
          onClick={() => navigate('/web/barber?showPayoutSettings=true')}
        >
          Open Payout Settings
          <ArrowRight className="w-4 h-4 ml-2 inline" />
        </Button>
      </Card>
    </div>
  );
};

export default BarberConnectOnboarding;
