import { useEffect, useState } from 'react';
import { useNavigate, useSearchParams, Link } from 'react-router-dom';
import { getBackendOrigin, STORAGE_KEYS } from '../../config/constants';
import axios from 'axios';
import Loading from '../../components/Loading';

interface SettlementPayload {
  bookingId: string;
  bookingStatus: string;
  stripePaymentStatus: string | null;
  bridgePayoutId: string | null;
  onChainSettlementStatus: string | null;
  paid: boolean;
}

/**
 * Shown after Stripe Checkout success while the booking is finalized.
 */
export default function PaymentProcessingPage() {
  const [searchParams] = useSearchParams();
  const sessionId = searchParams.get('session_id');
  const navigate = useNavigate();
  const [status, setStatus] = useState<'loading' | 'ready' | 'error'>('loading');
  const [data, setData] = useState<SettlementPayload | null>(null);

  useEffect(() => {
    if (!sessionId) {
      setStatus('error');
      return;
    }

    const token = localStorage.getItem(STORAGE_KEYS.ACCESS_TOKEN);
    if (!token) {
      navigate('/web/auth', { replace: true });
      return;
    }

    const origin = getBackendOrigin();
    let cancelled = false;
    const poll = async () => {
      try {
        const res = await axios.get<{ data: SettlementPayload }>(
          `${origin}/api/v2/bookings/checkout-session/${encodeURIComponent(sessionId)}/settlement`,
          { headers: { Authorization: `Bearer ${token}` } }
        );
        if (cancelled) return;
        setData(res.data.data);
        if (res.data.data.paid && res.data.data.onChainSettlementStatus) {
          setStatus('ready');
          return;
        }
        if (res.data.data.paid) {
          setStatus('ready');
          return;
        }
      } catch {
        if (!cancelled) setStatus('error');
      }
    };

    poll();
    const id = window.setInterval(poll, 4000);
    return () => {
      cancelled = true;
      window.clearInterval(id);
    };
  }, [sessionId, navigate]);

  if (!sessionId || status === 'error') {
    return (
      <div className="min-h-screen flex flex-col items-center justify-center px-4">
        <p className="text-gray-700 mb-4">Missing session or could not load payment status.</p>
        <Link to="/web/consumer/booking-status" className="text-primary-600 font-medium">
          Back to bookings
        </Link>
      </div>
    );
  }

  if (status === 'loading' && !data) {
    return (
      <div className="min-h-screen flex items-center justify-center">
        <Loading />
      </div>
    );
  }

  return (
    <div className="min-h-screen flex flex-col items-center justify-center px-4 bg-gray-50">
      <div className="max-w-md w-full bg-white rounded-xl shadow p-8 text-center">
        <h1 className="text-xl font-semibold text-gray-900 mb-2">Processing your payment</h1>
        <p className="text-gray-600 text-sm mb-6">
          Stripe confirmed your checkout. We&apos;re finalizing your booking—this usually takes a few seconds.
        </p>
        {data && (
          <ul className="text-left text-sm text-gray-700 space-y-2 mb-6">
            <li>Stripe: {data.stripePaymentStatus || 'unknown'}</li>
            <li>Settlement: {data.onChainSettlementStatus || 'pending'}</li>
            {data.bridgePayoutId && <li>Bridge ref: {data.bridgePayoutId}</li>}
          </ul>
        )}
        <Link
          to="/web/consumer/booking-status"
          className="inline-block px-4 py-2 bg-primary-500 text-white rounded-lg font-medium"
        >
          View bookings
        </Link>
      </div>
    </div>
  );
}
