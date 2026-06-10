import axios from 'axios';
import { getBackendOrigin, STORAGE_KEYS } from '../config/constants';

/**
 * zkLogin: backend salt + optional Google-complete endpoint.
 */
export async function fetchZkLoginSalt(iss: string, sub: string): Promise<string> {
  const origin = getBackendOrigin();
  const res = await axios.post<{ salt: string }>(`${origin}/api/zklogin/salt`, { iss, sub });
  return res.data.salt;
}

export async function completeZkLoginWithGoogle(idToken: string): Promise<{ suiAddress: string }> {
  const origin = getBackendOrigin();
  const res = await axios.post<{ suiAddress: string }>(
    `${origin}/api/zklogin/google-complete`,
    { idToken },
    {
      headers: {
        Authorization: `Bearer ${localStorage.getItem(STORAGE_KEYS.ACCESS_TOKEN) || ''}`,
      },
    }
  );
  return { suiAddress: res.data.suiAddress };
}

export async function persistUserSuiAddress(suiAddress: string, zkLoginSalt?: string): Promise<void> {
  const origin = getBackendOrigin();
  await axios.put(
    `${origin}/api/zklogin/address`,
    { suiAddress, zkLoginSalt },
    {
      headers: {
        Authorization: `Bearer ${localStorage.getItem(STORAGE_KEYS.ACCESS_TOKEN) || ''}`,
      },
    }
  );
}
