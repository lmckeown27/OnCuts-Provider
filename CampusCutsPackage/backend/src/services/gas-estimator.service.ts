/**
 * Gas Estimator Service (Blockchain-First Version)
 * 
 * Estimates required APT gas for upcoming platform operations
 * Monitors gas wallet balance and triggers top-up alerts
 * 
 * Note: Simplified version without PostgreSQL - uses hardcoded config
 */

import { logger } from '../utils/logger';
import suiChainService from './sui-chain.service';
import Decimal from 'decimal.js';
import { redisGet, redisSet } from '../config/redis';

interface GasEstimate {
  gasWalletAddress: string;
  currentBalanceAPT: number;
  estimatedNeededAPT: number;
  amountNeededAPT: number;
  estimatedCoverageDays: number;
  timestamp: Date;
  metadata: {
    pendingWrites: number;
    avgGasPerWrite: number;
    safetyBufferPct: number;
    estimationHorizon: string;
  };
}

interface GasWallet {
  address: string;
  descriptive_name: string;
}

interface GasEstimationConfig {
  default_avg_gas_apt_per_write: number;
  estimation_horizon_hours: number;
  safety_buffer_percentage: number;
  min_balance_alert_threshold_apt: number;
  critical_balance_threshold_apt: number;
  auto_create_topup_threshold_apt: number;
}

class GasEstimatorService {
  // Hardcoded configuration (no database needed)
  private config: GasEstimationConfig = {
    default_avg_gas_apt_per_write: 0.001, // 0.001 APT per transaction
    estimation_horizon_hours: 24, // Look ahead 24 hours
    safety_buffer_percentage: 50, // 50% safety buffer
    min_balance_alert_threshold_apt: 1.0, // Alert below 1 APT
    critical_balance_threshold_apt: 0.5, // Critical below 0.5 APT
    auto_create_topup_threshold_apt: 2.0, // Auto top-up below 2 APT
  };

  /**
   * Get gas wallet from environment
   */
  private getActiveGasWallet(): GasWallet {
    const address =
      process.env.SUI_GAS_WALLET_ADDRESS ||
      process.env.GAS_WALLET_ADDRESS ||
      process.env.SUI_TREASURY_ADDRESS ||
      '';
    if (!address) {
      throw new Error('SUI_GAS_WALLET_ADDRESS or SUI_TREASURY_ADDRESS not configured');
    }

    return {
      address,
      descriptive_name: 'Platform Gas Wallet',
    };
  }

  /**
   * Estimate pending writes for next N hours
   * Simplified version - uses conservative estimate without database
   */
  private async estimatePendingWrites(horizonHours: number): Promise<number> {
    // Conservative estimate: assume 10 transactions per hour
    const estimatedTxPerHour = 10;
    const totalEstimatedWrites = estimatedTxPerHour * horizonHours;

    logger.debug('Estimated pending writes (conservative):', {
      horizonHours,
      estimatedTxPerHour,
      total: totalEstimatedWrites,
    });

    return Math.max(totalEstimatedWrites, 50); // Minimum 50 writes
  }

  /**
   * Get current gas wallet balance from blockchain
   */
  private async getCurrentBalance(address: string): Promise<number> {
    try {
      return suiChainService.getAccountBalance(address);
    } catch (error) {
      logger.error(`Failed to get balance for ${address}:`, error);
      return 0;
    }
  }

  /**
   * Calculate gas estimate with safety buffer
   */
  async estimateGas(): Promise<GasEstimate> {
    const config = this.config;
    const wallet = this.getActiveGasWallet();

    // Get current balance from blockchain
    const currentBalanceAPT = await this.getCurrentBalance(wallet.address);

    // Cache balance in Redis
    await redisSet(
      `gas:balance:${wallet.address}`,
      currentBalanceAPT.toString(),
      60 * 60 // 1 hour TTL
    );

    // Estimate pending writes
    const pendingWrites = await this.estimatePendingWrites(config.estimation_horizon_hours);

    // Calculate estimated needed APT
    const baseEstimate = new Decimal(pendingWrites)
      .times(config.default_avg_gas_apt_per_write);

    const safetyMultiplier = new Decimal(1).plus(
      new Decimal(config.safety_buffer_percentage).div(100)
    );

    const estimatedNeededAPT = baseEstimate
      .times(safetyMultiplier)
      .toDecimalPlaces(6, Decimal.ROUND_UP)
      .toNumber();

    // Calculate amount needed (max of 0 or difference)
    const amountNeededAPT = Math.max(
      0,
      new Decimal(estimatedNeededAPT)
        .minus(currentBalanceAPT)
        .toDecimalPlaces(6, Decimal.ROUND_UP)
        .toNumber()
    );

    // Estimate coverage days
    const estimatedDailyConsumption = new Decimal(pendingWrites)
      .div(config.estimation_horizon_hours)
      .times(24)
      .times(config.default_avg_gas_apt_per_write)
      .toNumber();

    const estimatedCoverageDays = estimatedDailyConsumption > 0
      ? new Decimal(currentBalanceAPT)
          .div(estimatedDailyConsumption)
          .toDecimalPlaces(2, Decimal.ROUND_DOWN)
          .toNumber()
      : 999;

    const estimate: GasEstimate = {
      gasWalletAddress: wallet.address,
      currentBalanceAPT,
      estimatedNeededAPT,
      amountNeededAPT,
      estimatedCoverageDays,
      timestamp: new Date(),
      metadata: {
        pendingWrites,
        avgGasPerWrite: config.default_avg_gas_apt_per_write,
        safetyBufferPct: config.safety_buffer_percentage,
        estimationHorizon: `${config.estimation_horizon_hours}h`,
      },
    };

    logger.info('Gas estimate calculated:', {
      current: currentBalanceAPT,
      needed: estimatedNeededAPT,
      amount_needed: amountNeededAPT,
      coverage_days: estimatedCoverageDays,
    });

    return estimate;
  }

  /**
   * Check if top-up is needed and send alert
   */
  async checkAndCreateTopUpIfNeeded(): Promise<string | null> {
    const config = this.config;
    const estimate = await this.estimateGas();

    // Check if amount needed exceeds threshold
    if (estimate.amountNeededAPT < config.auto_create_topup_threshold_apt) {
      logger.debug('No top-up needed', {
        amountNeeded: estimate.amountNeededAPT,
        threshold: config.auto_create_topup_threshold_apt,
      });
      return null;
    }

    // Check Redis for recent alert (prevent spam)
    const alertKey = `gas:alert:${estimate.gasWalletAddress}`;
    const recentAlert = await redisGet(alertKey);

    if (recentAlert) {
      logger.debug('Top-up alert recently sent, skipping');
      return recentAlert;
    }

    // Generate alert ID and cache it
    const alertId = `alert_${Date.now()}`;
    await redisSet(alertKey, alertId, 60 * 60); // 1 hour cooldown

    const requestedAmountAPT = new Decimal(estimate.amountNeededAPT)
      .toDecimalPlaces(6, Decimal.ROUND_UP)
      .toNumber();

    const reason = `Auto-generated: Balance (${estimate.currentBalanceAPT.toFixed(4)} APT) below threshold. Estimated need: ${estimate.estimatedNeededAPT.toFixed(4)} APT for next ${config.estimation_horizon_hours}h.`;

    logger.info('Gas top-up alert generated:', {
      alertId,
      requestedAmountAPT,
      reason,
    });

    // Send alert
    await this.sendTopUpAlert(alertId, requestedAmountAPT, reason);

    return alertId;
  }

  /**
   * Send top-up alert
   */
  private async sendTopUpAlert(
    alertId: string,
    amount: number,
    reason: string
  ): Promise<void> {
    logger.warn('🚨 GAS TOP-UP NEEDED:', {
      alertId,
      amount: `${amount.toFixed(6)} APT`,
      reason,
      action: 'Admin action required - manually top up gas wallet',
    });

    // TODO: Implement email/Slack notification
    // await emailService.send({
    //   to: process.env.ADMIN_EMAIL,
    //   subject: `CampusCuts: Gas Top-Up Required (${amount.toFixed(4)} APT)`,
    //   body: `Alert ID: ${alertId}\nAmount: ${amount.toFixed(6)} APT\nReason: ${reason}`,
    // });
  }
}

// Singleton instance
const gasEstimatorService = new GasEstimatorService();

export default gasEstimatorService;

