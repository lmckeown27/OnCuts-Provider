import { useState } from 'react';
import { useLocation } from 'react-router-dom';
import {
  GOOGLE_OAUTH_CLIENT_ID,
  getGoogleOAuthRedirectOrigin,
  isZkLoginWalletlessEnabled,
} from '../config/constants';

type Props = {
  disabled?: boolean;
  className?: string;
};

/** OAuth `nonce` sent to Google; must match JWT and survive until backend links the wallet. */
export const NONCE_SESSION_KEY = 'cc_zklogin_google_nonce';
/** Reserved for full zkLogin prover flows (`jwtRandomness`); address-only linking does not set this yet. */
export const JWT_RANDOMNESS_SESSION_KEY = 'cc_zklogin_jwt_randomness';

function randomNonce(): string {
  const a = new Uint8Array(16);
  crypto.getRandomValues(a);
  return Array.from(a, (b) => b.toString(16).padStart(2, '0')).join('');
}

/**
 * Google implicit OAuth (id_token). Callback verifies token server-side and derives Sui address via @mysten/sui/zklogin.
 */
export default function SignInWithGoogleZkLoginButton({ disabled, className }: Props) {
  const location = useLocation();
  const [busy, setBusy] = useState(false);

  if (!isZkLoginWalletlessEnabled()) {
    return null;
  }

  /** Campus web vs PWA: must match Google Cloud “Authorized redirect URIs” exactly (including `/web/` or `/app/`). */
  const platformPrefix: '/web' | '/app' = location.pathname.startsWith('/app') ? '/app' : '/web';

  const handleClick = () => {
    setBusy(true);
    try {
      const redirectUri = `${getGoogleOAuthRedirectOrigin()}${platformPrefix}/zklogin/callback`;
      const nonce = randomNonce();
      sessionStorage.setItem(NONCE_SESSION_KEY, nonce);
      const params = new URLSearchParams({
        client_id: GOOGLE_OAUTH_CLIENT_ID,
        redirect_uri: redirectUri,
        response_type: 'id_token',
        scope: 'openid email',
        nonce,
        prompt: 'select_account',
      });
      window.location.assign(`https://accounts.google.com/o/oauth2/v2/auth?${params.toString()}`);
    } catch (e) {
      console.error(e);
      setBusy(false);
    }
  };

  return (
    <button
      type="button"
      disabled={disabled || busy}
      onClick={handleClick}
      className={
        className ||
        'inline-flex w-full items-center justify-center gap-2 rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-800 shadow-sm hover:bg-gray-50 disabled:opacity-50'
      }
    >
      <svg className="h-5 w-5" viewBox="0 0 24 24" aria-hidden>
        <path
          fill="#4285F4"
          d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z"
        />
        <path
          fill="#34A853"
          d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z"
        />
        <path
          fill="#FBBC05"
          d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z"
        />
        <path
          fill="#EA4335"
          d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z"
        />
      </svg>
      {busy ? 'Redirecting…' : 'Sign in with Google (Sui zkLogin)'}
    </button>
  );
}

