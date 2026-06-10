/**
 * Legacy custodial chain signer — disabled; use Sui zkLogin.
 * Identity and signing move to Sui zkLogin + backend salt (salt.service).
 */

import crypto from 'crypto';
import { logger } from '../utils/logger';

interface TransactionPayload {
  function: string;
  type_arguments?: string[];
  arguments: unknown[];
}

class CustodialSignerService {
  getUserAddress(email: string): string {
    const h = crypto.createHash('sha256').update(email.toLowerCase() + '|campus_cuts_legacy').digest('hex');
    return `0x${h.slice(0, 64)}`;
  }

  async createUserAccount(
    _email: string,
    _password: string
  ): Promise<{ address: string; encryptedPrivateKey: string }> {
    throw new Error('Custodial chain signup removed — use Sign in with Google (Sui zkLogin)');
  }

  async loadUserAccount(_email: string, _password: string, _enc: string): Promise<never> {
    throw new Error('Custodial chain login removed — use zkLogin');
  }

  async signAndSubmitTransaction(
    _email: string,
    _password: string,
    _encryptedPrivateKey: string,
    _payload: TransactionPayload
  ): Promise<{ txHash: string }> {
    throw new Error('Custodial signing removed — use zkLogin + sponsored Sui transactions');
  }

  async signAndSubmitOptimistic(
    _email: string,
    _payload: TransactionPayload
  ): Promise<{ txHash: string }> {
    throw new Error('Custodial signing removed — use zkLogin + sponsored Sui transactions');
  }

  logout(_email: string): void {
    logger.debug('custodial-signer.logout noop');
  }
}

export default new CustodialSignerService();
