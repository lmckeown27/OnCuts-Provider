/**
 * Gas wallet admin surface (legacy shape for dashboard).
 *
 * Flows use **Sui sponsored transactions** (`GAS_SPONSOR_SECRET`), not a custodial platform
 * gas hot wallet. This module returns safe stubs unless re-enabled for Sui balance monitoring.
 */

import { logger } from '../utils/logger';
import { ApiError } from '../middleware/errorHandler';

interface GasWalletStatus {
  address: string;
  balance_apt: number;
  balance_usd_estimate: number;
  estimated_transactions_remaining: number;
  needs_refill: boolean;
  last_checked_at: string;
}

class GasWalletService {
  private gasWalletAddress: string = '';
  private isEnabled: boolean = false;
  
  // Thresholds for alerts
  private readonly MIN_BALANCE_APT = 10; // Legacy field name (was APT); unused while service disabled
  private readonly CRITICAL_BALANCE_APT = 2;
  private readonly AVG_GAS_PER_TX_APT = 0.0001; // Placeholder if Sui monitoring is added

  constructor() {
    this.gasWalletAddress =
      process.env.SUI_GAS_WALLET_ADDRESS ||
      process.env.GAS_WALLET_ADDRESS ||
      '';
    this.isEnabled = false;
    logger.warn(
      'Gas Wallet Service: disabled — use Sui sponsored gas (GAS_SPONSOR_SECRET / relayer)'
    );
  }

  /**
   * Check if gas wallet service is enabled
   */
  isConfigured(): boolean {
    return this.isEnabled;
  }

  /**
   * Ensure service is configured, throw if not
   */
  private ensureConfigured(): never {
    throw new Error('Gas Wallet Service is not configured. Use Sui gas sponsorship.');
  }

  /**
   * Get current gas wallet status
   * Called by admin dashboard to display gas meter
   */
  async getGasWalletStatus(): Promise<GasWalletStatus> {
    if (!this.isEnabled) {
      return {
        address: 'Not configured',
        balance_apt: 0,
        balance_usd_estimate: 0,
        estimated_transactions_remaining: 0,
        needs_refill: false,
        last_checked_at: new Date().toISOString(),
      };
    }

    try {
      const balance = await this.getBalance();
      const aptPrice = await this.getAptPrice();
      const balanceUsd = balance * aptPrice;
      const estimatedTxRemaining = Math.floor(balance / this.AVG_GAS_PER_TX_APT);
      const needsRefill = balance < this.MIN_BALANCE_APT;

      return {
        address: this.gasWalletAddress,
        balance_apt: balance,
        balance_usd_estimate: balanceUsd,
        estimated_transactions_remaining: estimatedTxRemaining,
        needs_refill: needsRefill,
        last_checked_at: new Date().toISOString(),
      };
    } catch (error: any) {
      logger.error('❌ Failed to get gas wallet status', { error: error.message });
      throw new ApiError(500, 'Failed to get gas wallet status');
    }
  }

  /**
   * Get gas wallet APT balance
   */
  async getBalance(): Promise<number> {
    return 0;
  }

  /**
   * Check if gas wallet needs refill
   * Returns alert level: 'ok' | 'low' | 'critical'
   */
  async checkBalanceStatus(): Promise<{
    status: 'ok' | 'low' | 'critical';
    balance_apt: number;
    message: string;
  }> {
    const balance = await this.getBalance();

    if (balance < this.CRITICAL_BALANCE_APT) {
      return {
        status: 'critical',
        balance_apt: balance,
        message: `🚨 CRITICAL: Gas wallet has only ${balance.toFixed(4)} APT. Platform may stop processing bookings!`,
      };
    } else if (balance < this.MIN_BALANCE_APT) {
      return {
        status: 'low',
        balance_apt: balance,
        message: `⚠️  LOW: Gas wallet has ${balance.toFixed(4)} APT. Consider refilling soon.`,
      };
    } else {
      return {
        status: 'ok',
        balance_apt: balance,
        message: `✅ OK: Gas wallet has ${balance.toFixed(4)} APT.`,
      };
    }
  }

  /**
   * Estimate gas cost for a transaction
   * Used for budgeting and monitoring
   */
  estimateGasCost(transactionType: 'create_escrow' | 'release_payment' | 'refund'): number {
    // Average gas costs per transaction type
    const gasCosts = {
      create_escrow: 0.00012, // APT
      release_payment: 0.00015, // APT (two coin transfers)
      refund: 0.00010, // APT (single transfer)
    };

    return gasCosts[transactionType] || this.AVG_GAS_PER_TX_APT;
  }

  /**
   * Optional display address (SUI_GAS_WALLET_ADDRESS / GAS_WALLET_ADDRESS); not used for Sui signing.
   */
  getGasWalletAddress(): string {
    return this.gasWalletAddress;
  }

  /**
   * Native token USD price for rough admin estimates (Sui). Legacy name kept for callers.
   */
  async getAptPrice(): Promise<number> {
    try {
      const response = await fetch(
        'https://api.coingecko.com/api/v3/simple/price?ids=sui&vs_currencies=usd'
      );
      const data = (await response.json()) as { sui?: { usd?: number } };

      if (data.sui?.usd) {
        return data.sui.usd;
      }

      return 2.5;
    } catch (error) {
      logger.warn('Failed to fetch SUI price, using fallback', { error });
      return 2.5;
    }
  }

  /**
   * Log gas usage for a transaction
   * Used for analytics and cost tracking
   */
  async logGasUsage(params: {
    transaction_hash: string;
    transaction_type: string;
    gas_used_apt: number;
    booking_id?: string;
  }): Promise<void> {
    const aptPrice = await this.getAptPrice();
    const gasUsd = params.gas_used_apt * aptPrice;

    logger.info('⛽ Gas used for transaction', {
      tx_hash: params.transaction_hash,
      type: params.transaction_type,
      gas_apt: params.gas_used_apt.toFixed(6),
      gas_usd: gasUsd.toFixed(4),
      booking_id: params.booking_id,
    });

    // TODO: Store in database for analytics
    // await prisma.gasLog.create({
    //   data: {
    //     transaction_hash: params.transaction_hash,
    //     transaction_type: params.transaction_type,
    //     gas_used_apt: params.gas_used_apt,
    //     gas_used_usd: gasUsd,
    //     booking_id: params.booking_id,
    //     created_at: new Date(),
    //   },
    // });
  }

  /**
   * Fund gas wallet from faucet (devnet only)
   * Use for testing on devnet
   */
  async fundFromFaucet(): Promise<void> {
    throw new ApiError(
      410,
      'Use Sui testnet faucet or fund the gas sponsor key; see GAS_SPONSOR_SECRET.'
    );
  }

  /**
   * Get refill instructions for admin
   * Shows how to top-up the gas wallet
   */
  getRefillInstructions(): {
    method: string;
    instructions: string[];
    address: string;
    recommended_amount_apt: number;
  } {
    return {
      method: 'sui_gas_sponsor',
      instructions: [
        'Configure GAS_SPONSOR_SECRET (Sui keypair that pays gas for sponsored PTBs).',
        'Fund that address with SUI on your target network (testnet faucet or exchange withdraw).',
        this.gasWalletAddress
          ? `Optional monitoring address: ${this.gasWalletAddress}`
          : 'Set SUI_GAS_WALLET_ADDRESS only if you add balance monitoring later.',
      ],
      address: this.gasWalletAddress || 'Configure GAS_SPONSOR_SECRET',
      recommended_amount_apt: 0,
    };
  }

  /**
   * Legacy hook — use GAS_SPONSOR_SECRET + Sui PTB (relayer).
   */
  getGasWalletAccount(): never {
    this.ensureConfigured();
  }
}

export default new GasWalletService();

