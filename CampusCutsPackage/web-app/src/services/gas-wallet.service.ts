// @ts-nocheck
/**
 * Gas Wallet Service
 * 
 * Frontend service for gas wallet estimation and top-up requests
 */

import apiService from './api.service';

export interface GasEstimate {
  gasWalletAddress: string;
  currentBalanceAPT: number;
  estimatedNeededAPT: number;
  amountNeededAPT: number;
  estimatedCoverageDays: number;
  timestamp: string;
  metadata: {
    pendingWrites: number;
    avgGasPerWrite: number;
    safetyBufferPct: number;
    estimationHorizon: string;
  };
}

export interface TopUpRequest {
  id: string;
  gas_wallet_address: string;
  requested_amount_apt: number;
  requested_amount_octas: number;
  status: 'pending' | 'approved' | 'completed' | 'failed' | 'cancelled';
  verification_status?: 'pending' | 'verified' | 'amount_mismatch' | 'tx_not_found' | 'timeout';
  admin_address_requested_from?: string;
  approved_tx_hash?: string;
  verified_amount_octas?: number;
  reason?: string;
  estimated_coverage_days?: number;
  created_at: string;
  approved_at?: string;
  completed_at?: string;
  failed_at?: string;
  error_message?: string;
  wallet_name?: string;
  admin_email?: string;
}

export interface GasWalletHealth {
  id: string;
  address: string;
  descriptive_name: string;
  current_balance_apt: number;
  min_balance_threshold_apt: number;
  last_checked_at: string;
  health_status: 'critical' | 'low' | 'healthy';
  pending_top_ups: number;
  total_topped_up_apt: number;
}

class GasWalletService {
  /**
   * Get current gas estimate
   */
  async getEstimate(): Promise<GasEstimate> {
    const response = await apiService.get<GasEstimate>('/gas/estimate');
    return response.data;
  }

  /**
   * Create a top-up request
   */
  async createTopUpRequest(
    requestedAmountAPT?: number,
    idempotencyKey?: string
  ): Promise<TopUpRequest> {
    const response = await apiService.post<TopUpRequest>('/gas/topup-request', {
      requestedAmountAPT,
      idempotencyKey,
    });
    return response.data;
  }

  /**
   * List top-up requests
   */
  async listTopUpRequests(
    status?: string,
    limit: number = 50,
    offset: number = 0
  ): Promise<{ data: TopUpRequest[]; pagination: any }> {
    const params: any = { limit, offset };
    if (status) params.status = status;

    const response = await apiService.get<{ data: TopUpRequest[]; pagination: any }>(
      '/gas/topup-requests',
      { params }
    );
    return response;
  }

  /**
   * Get single top-up request
   */
  async getTopUpRequest(id: string): Promise<TopUpRequest> {
    const response = await apiService.get<TopUpRequest>(`/gas/topup-request/${id}`);
    return response.data;
  }

  /**
   * Confirm top-up request with transaction hash
   */
  async confirmTopUpRequest(
    id: string,
    txHash: string,
    fromAddress: string
  ): Promise<{ requestId: string; txHash: string; status: string; verificationStatus: string }> {
    const response = await apiService.post<{
      requestId: string;
      txHash: string;
      status: string;
      verificationStatus: string;
    }>(`/gas/topup-request/${id}/confirm`, {
      txHash,
      fromAddress,
    });
    return response.data;
  }

  /**
   * Get gas wallet health status
   */
  async getHealth(): Promise<GasWalletHealth[]> {
    const response = await apiService.get<GasWalletHealth[]>('/gas/health');
    return response.data;
  }

  /**
   * Manually mark request as completed (admin override)
   */
  async manualMarkCompleted(
    id: string,
    verifiedAmountOctas: number,
    note: string
  ): Promise<{ message: string }> {
    const response = await apiService.post<{ message: string }>(
      `/gas/topup-request/${id}/mark-completed`,
      {
        verifiedAmountOctas,
        note,
      }
    );
    return response;
  }
}

const gasWalletService = new GasWalletService();

export default gasWalletService;

