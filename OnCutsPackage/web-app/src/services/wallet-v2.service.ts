/**
 * Wallet Service V2
 * 
 * Integrates with the production V2 custodial wallet system
 */

import api from './api.service';

export interface WalletBalance {
  available_dollars: number;
  pending_dollars: number;
  total_dollars: number;
  available_cents: number;
  pending_cents: number;
  total_cents: number;
  active_escrows: number;
}

export interface Transaction {
  id: number;
  tx_ref: string;
  user_id: string;
  type: string;
  amount: number;
  amount_dollars: number;
  currency: string;
  status: string;
  related_booking_id?: string;
  metadata?: any;
  created_at: string;
  completed_at?: string;
}

export interface Escrow {
  id: string;
  booking_id: string;
  consumer_id: string;
  barber_id: string;
  amount: number;
  amount_dollars: number;
  currency: string;
  status: 'held' | 'released' | 'refunded' | 'expired';
  created_at: string;
  expires_at: string;
  released_at?: string;
  refunded_at?: string;
}

export interface WithdrawalRequest {
  id: number;
  user_id: string;
  transaction_id: number;
  amount: number;
  amount_dollars: number;
  destination_type: 'bank' | 'onchain';
  destination_address?: string;
  chain?: string;
  status: 'queued' | 'batched' | 'processing' | 'completed' | 'failed';
  batch_id?: string;
  queued_at: string;
  processed_at?: string;
  failure_reason?: string;
}

class WalletV2Service {
  /**
   * Get wallet balance (available + pending + escrow count)
   */
  async getBalance(): Promise<WalletBalance> {
    const response = await api.get('/v2/wallet/balance');
    return response.data;
  }

  /**
   * Create deposit intent (for Stripe Elements)
   */
  async createDepositIntent(amountDollars: number): Promise<{
    clientSecret: string;
    paymentIntentId: string;
  }> {
    const response = await api.post('/v2/wallet/deposit/intent', {
      amount: amountDollars,
    });
    return response.data;
  }

  /**
   * Get transaction history
   */
  async getTransactionHistory(limit: number = 50, offset: number = 0): Promise<{
    transactions: Transaction[];
    total: number;
    limit: number;
    offset: number;
  }> {
    const response = await api.get('/v2/wallet/transactions', {
      params: { limit, offset },
    });
    return response.data;
  }

  /**
   * Withdraw to bank (legacy; prefer Stripe Connect — see Payout Settings)
   */
  async withdrawToBank(amountDollars: number): Promise<{
    payout_id: string;
    amount_dollars: number;
  }> {
    const response = await api.post('/v2/wallet/withdraw/bank', {
      amount: amountDollars,
    });
    return response.data;
  }

  /**
   * Withdraw on-chain (queued for batching)
   */
  async withdrawOnChain(
    amountDollars: number,
    destinationAddress: string,
    chain: string = 'sui'
  ): Promise<{
    queue_id: number;
    status: string;
    amount_dollars: number;
  }> {
    const response = await api.post('/v2/wallet/withdraw/onchain', {
      amount: amountDollars,
      destinationAddress,
      chain,
    });
    return response.data;
  }

  /**
   * Get withdrawal history
   */
  async getWithdrawalHistory(): Promise<WithdrawalRequest[]> {
    const response = await api.get('/v2/wallet/withdrawals');
    return response.data;
  }

  /**
   * Send tip to barber
   */
  async sendTip(
    toUserId: string,
    amountDollars: number,
    bookingId?: string
  ): Promise<void> {
    await api.post('/v2/wallet/tip', {
      toUserId,
      amount: amountDollars,
      bookingId,
    });
  }

  /**
   * Get active escrows
   */
  async getEscrows(status?: 'held' | 'released' | 'refunded' | 'expired'): Promise<Escrow[]> {
    const response = await api.get('/v2/wallet/escrows', {
      params: status ? { status } : {},
    });
    return response.data;
  }
}

export default new WalletV2Service();

