/**
 * Mysten-hosted zkLogin proving service (no Enoki). Use when signing transactions as a zkLogin user.
 * @see https://docs.sui.io/guides/developer/cryptography/zklogin-integration
 */
import { SUI_ZKLOGIN_PROVER_URL } from '../config/constants';

export type ZkLoginProverRequestBody = {
  jwt: string;
  extendedEphemeralPublicKey: string;
  maxEpoch: string;
  jwtRandomness: string;
  salt: string;
  keyClaimName?: string;
};

export async function requestZkLoginProofFromProver(
  body: ZkLoginProverRequestBody
): Promise<unknown> {
  const res = await fetch(SUI_ZKLOGIN_PROVER_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      ...body,
      keyClaimName: body.keyClaimName ?? 'sub',
    }),
  });
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`zkLogin prover error ${res.status}: ${text}`);
  }
  return res.json();
}
