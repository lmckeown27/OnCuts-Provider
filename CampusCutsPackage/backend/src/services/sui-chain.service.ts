/**
 * Sui chain orchestration.
 * On-chain program integration lands here (Sui).
 */

import { logger } from '../utils/logger';

const STUB_TX = '0x0000000000000000000000000000000000000000000000000000000000000000';

class SuiChainService {
  isEnabled(): boolean {
    return Boolean(process.env.SUI_RPC_URL);
  }

  getPlatformAddress(): string {
    return process.env.SUI_PLATFORM_ADDRESS || process.env.SUI_TREASURY_ADDRESS || '0x0';
  }

  async lockFundsInEscrow(_bookingId: string, _amountUsd: number): Promise<void> {
    logger.debug('SuiChain: lockFundsInEscrow (no-op until Move package wired)', { _bookingId });
  }

  async releaseEscrowToStudent(_bookingId: string, _amountUsd: number): Promise<void> {
    logger.debug('SuiChain: releaseEscrowToStudent (no-op until Move package wired)', { _bookingId });
  }

  async createBooking(params: Record<string, unknown>): Promise<string> {
    logger.info('SuiChain: createBooking stub', { params });
    return STUB_TX;
  }

  async confirmBooking(_barberAddress: string, _bookingId: number): Promise<string> {
    return STUB_TX;
  }

  async completeBooking(_bookingId: number): Promise<string> {
    return STUB_TX;
  }

  async cancelBooking(_bookingId: number): Promise<string> {
    return STUB_TX;
  }

  async registerBarber(params: Record<string, unknown>): Promise<string> {
    logger.info('SuiChain: registerBarber stub', { params });
    return STUB_TX;
  }

  async submitReview(params: Record<string, unknown>): Promise<string> {
    logger.info('SuiChain: submitReview stub', { params });
    return STUB_TX;
  }

  async createPayment(params: Record<string, unknown>): Promise<string> {
    logger.info('SuiChain: createPayment stub', { params });
    return STUB_TX;
  }

  async releasePayment(_paymentId: number): Promise<string> {
    return STUB_TX;
  }

  async getBooking(_bookingId: number): Promise<Record<string, unknown> | null> {
    return { id: _bookingId, status: 'stub' };
  }

  async getBarberRating(
    _barberAddress: string
  ): Promise<{ average: number; total: number }> {
    return { average: 0, total: 0 };
  }

  /** Native / SUI balance for an address (MIST). Stub returns 0. */
  async getAccountBalance(_address: string): Promise<number> {
    return 0;
  }

  async createUsdcEscrow(params: Record<string, unknown>): Promise<string> {
    logger.info('SuiChain: createUsdcEscrow stub', { params });
    return STUB_TX;
  }

  async releaseUsdcEscrow(_bookingId: string): Promise<string> {
    return STUB_TX;
  }

  async refundUsdcEscrow(_bookingId: string): Promise<string> {
    return STUB_TX;
  }

  async getEscrowDetails(_bookingId: string): Promise<{ status: string } | null> {
    return null;
  }

  generateAccount(): { address: string; privateKey: string } {
    return {
      address: STUB_TX,
      privateKey: '',
    };
  }

  async fundAccount(_address: string, _amount = 0): Promise<void> {
    logger.warn('SuiChain: fundAccount not implemented');
  }

  async submitBatchWithdrawal(
    recipients: (string | undefined)[],
    amounts: number[]
  ): Promise<string> {
    logger.info('SuiChain: submitBatchWithdrawal stub', {
      count: recipients.filter(Boolean).length,
      amounts: amounts.length,
    });
    return STUB_TX;
  }

  async submitHashProof(
    recordType: string,
    subjectId: string,
    dataHash: string
  ): Promise<string> {
    logger.info('SuiChain: submitHashProof stub', { recordType, subjectId, dataHash });
    return STUB_TX;
  }
}

export default new SuiChainService();
