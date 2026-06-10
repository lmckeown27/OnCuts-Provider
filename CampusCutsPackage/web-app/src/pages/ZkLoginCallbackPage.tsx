import { useEffect, useRef, useState } from 'react';
import { useNavigate, useLocation, Navigate } from 'react-router-dom';
import toast from 'react-hot-toast';
import { useAuthStore } from '../store/useAuthStore';
import { completeZkLoginWithGoogle } from '../services/zkLogin.service';
import Loading from '../components/Loading';
import { isZkLoginWalletlessEnabled } from '../config/constants';
import {
  JWT_RANDOMNESS_SESSION_KEY,
  NONCE_SESSION_KEY,
} from '../components/SignInWithGoogleZkLoginButton';

function parseHashParams(hash: string): Record<string, string> {
  const h = hash.startsWith('#') ? hash.slice(1) : hash;
  const out: Record<string, string> = {};
  new URLSearchParams(h).forEach((v, k) => {
    out[k] = v;
  });
  return out;
}

function decodeJwtPayload(jwt: string): { nonce?: string; sub?: string } {
  const part = jwt.split('.')[1];
  if (!part) {
    throw new Error('Invalid id_token');
  }
  const b64 = part.replace(/-/g, '+').replace(/_/g, '/');
  const pad = b64.length % 4 === 0 ? '' : '='.repeat(4 - (b64.length % 4));
  const json = atob(b64 + pad);
  return JSON.parse(json) as { nonce?: string; sub?: string };
}

/**
 * Google OAuth redirect: fragment contains `id_token`. Server verifies JWT and persists zkLogin Sui address.
 * Nonce / optional jwt randomness in sessionStorage are cleared only after the backend confirms the link.
 */
export default function ZkLoginCallbackPage() {
  if (!isZkLoginWalletlessEnabled()) {
    return <Navigate to="/web" replace />;
  }
  return <ZkLoginCallbackInner />;
}

function ZkLoginCallbackInner() {
  const navigate = useNavigate();
  const location = useLocation();
  const { isAuthenticated, loadUser } = useAuthStore();
  const [error, setError] = useState<string | null>(null);
  /** Prevents duplicate submissions (e.g. React Strict Mode or re-renders); reset on API failure so user can retry. */
  const flowStartedRef = useRef(false);

  const platformPrefix = location.pathname.startsWith('/app') ? '/app' : '/web';

  useEffect(() => {
    if (flowStartedRef.current) {
      return;
    }

    if (!isAuthenticated) {
      toast.error('Log in to CampusCuts first, then link your Sui zkLogin wallet.');
      navigate(`${platformPrefix}/auth`, { replace: true });
      return;
    }

    const hash = window.location.hash || '';
    const params = parseHashParams(hash);

    if (params.error) {
      const desc = params.error_description
        ? decodeURIComponent(params.error_description.replace(/\+/g, ' '))
        : params.error;
      setError(desc);
      toast.error(desc);
      return;
    }

    const idToken = params.id_token;
    if (!idToken) {
      const msg = 'Missing Google id_token. Try Sign in with Google again.';
      setError(msg);
      toast.error(msg);
      return;
    }

    let payload: { nonce?: string };
    try {
      payload = decodeJwtPayload(idToken);
    } catch {
      const msg = 'Could not read Google token.';
      setError(msg);
      toast.error(msg);
      return;
    }

    const expectedNonce = sessionStorage.getItem(NONCE_SESSION_KEY);
    if (!expectedNonce || payload.nonce !== expectedNonce) {
      const msg = 'Sign-in session expired or invalid. Please try again.';
      setError(msg);
      toast.error(msg);
      return;
    }

    flowStartedRef.current = true;

    void (async () => {
      try {
        await completeZkLoginWithGoogle(idToken);
        await loadUser();
        sessionStorage.removeItem(NONCE_SESSION_KEY);
        sessionStorage.removeItem(JWT_RANDOMNESS_SESSION_KEY);
        window.history.replaceState(null, '', window.location.pathname + window.location.search);
        toast.success('zkLogin wallet linked — your Sui address is saved.');
        navigate(`${platformPrefix}/barber`, { replace: true });
      } catch (e: unknown) {
        flowStartedRef.current = false;
        const ax =
          e && typeof e === 'object' && 'response' in e
            ? (e as { response?: { data?: unknown } }).response
            : undefined;
        const data = ax?.data as { error?: { message?: string }; message?: string } | undefined;
        const msg =
          data?.error?.message ||
          data?.message ||
          (e instanceof Error ? e.message : null) ||
          'Could not save Sui address';
        setError(msg || 'Could not save Sui address');
        toast.error(msg || 'Could not save Sui address');
      }
    })();
  }, [isAuthenticated, navigate, platformPrefix, loadUser]);

  return (
    <div className="min-h-[50vh] flex flex-col items-center justify-center p-8">
      <Loading />
      <p className="mt-4 text-sm text-gray-600 text-center max-w-md">
        Finishing Google sign-in and linking your Sui zkLogin address…
      </p>
      {error && <p className="mt-2 text-sm text-red-600 text-center max-w-md">{error}</p>}
    </div>
  );
}
