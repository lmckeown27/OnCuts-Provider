/**
 * Return URL handler (legacy `/web/barber/connect/return` bookmarks).
 * Sends barbers to the dashboard payout modal.
 */

import { useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import Loading from '../components/Loading';

export default function BarberConnectReturn() {
  const navigate = useNavigate();

  useEffect(() => {
    // Redirect to barber page with showPayoutSettings param
    navigate('/web/barber?showPayoutSettings=true', { replace: true });
  }, [navigate]);

  return <Loading />;
}

