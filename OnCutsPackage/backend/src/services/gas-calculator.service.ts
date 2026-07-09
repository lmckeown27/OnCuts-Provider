/**
 * Gas Calculator Service
 * 
 * Gas cost hints (legacy shape; Sui uses gas / sponsorship)
 * Based on real transaction data from production systems
 * 
 * Extracted and adapted from typescript_cash_bot
 * https://github.com/lmckeown27/typescript_cash_bot
 */

import { logger } from '../utils/logger';

export interface GasEstimate {
  gasUnits: number;
  gasPriceOctas: number;
  totalCostOctas: number;
  totalCostAPT: number;
  safetyBufferAPT: number;
  totalWithBufferAPT: number;
}

export class GasCalculatorService {
  // Placeholder gas unit estimates (tune for Sui when monitoring is wired)
  private readonly GAS_UNITS = {
    SIMPLE_TRANSFER: 500,       // APT/token transfer
    BATCH_WITHDRAWAL: 1200,     // Batch withdrawal to multiple addresses
    TOKEN_REGISTRATION: 1000,   // Register new token
    SMART_CONTRACT_CALL: 2000,  // Generic contract interaction
  };

  // Conservative gas price (100 octas per unit)
  // Rough USD conversion for dashboards only
  private readonly GAS_PRICE_OCTAS = 100;

  // Safety buffer (0.001 APT = 100,000 octas)
  // Prevents edge cases and gas price spikes
  private readonly SAFETY_BUFFER_APT = 0.001;

  /**
   * Calculate gas cost for a simple transfer (APT or other token)
   */
  calculateTransferGas(): GasEstimate {
    const gasUnits = this.GAS_UNITS.SIMPLE_TRANSFER;
    const gasPriceOctas = this.GAS_PRICE_OCTAS;
    const totalCostOctas = gasUnits * gasPriceOctas;
    const totalCostAPT = totalCostOctas / 100_000_000;

    const estimate: GasEstimate = {
      gasUnits,
      gasPriceOctas,
      totalCostOctas,
      totalCostAPT,
      safetyBufferAPT: this.SAFETY_BUFFER_APT,
      totalWithBufferAPT: totalCostAPT + this.SAFETY_BUFFER_APT,
    };

    logger.debug('Transfer gas estimate:', estimate);
    return estimate;
  }

  /**
   * Calculate gas cost for batch withdrawal
   * More expensive than simple transfer due to multiple recipients
   */
  calculateBatchWithdrawalGas(recipientCount: number): GasEstimate {
    // Base cost + marginal cost per recipient
    const baseGasUnits = this.GAS_UNITS.BATCH_WITHDRAWAL;
    const additionalUnitsPerRecipient = 100;
    const totalGasUnits = baseGasUnits + (recipientCount * additionalUnitsPerRecipient);

    const gasPriceOctas = this.GAS_PRICE_OCTAS;
    const totalCostOctas = totalGasUnits * gasPriceOctas;
    const totalCostAPT = totalCostOctas / 100_000_000;

    const estimate: GasEstimate = {
      gasUnits: totalGasUnits,
      gasPriceOctas,
      totalCostOctas,
      totalCostAPT,
      safetyBufferAPT: this.SAFETY_BUFFER_APT,
      totalWithBufferAPT: totalCostAPT + this.SAFETY_BUFFER_APT,
    };

    logger.info('Batch withdrawal gas estimate:', {
      recipientCount,
      ...estimate,
    });

    return estimate;
  }

  /**
   * Calculate gas cost for smart contract call
   */
  calculateContractCallGas(): GasEstimate {
    const gasUnits = this.GAS_UNITS.SMART_CONTRACT_CALL;
    const gasPriceOctas = this.GAS_PRICE_OCTAS;
    const totalCostOctas = gasUnits * gasPriceOctas;
    const totalCostAPT = totalCostOctas / 100_000_000;

    const estimate: GasEstimate = {
      gasUnits,
      gasPriceOctas,
      totalCostOctas,
      totalCostAPT,
      safetyBufferAPT: this.SAFETY_BUFFER_APT,
      totalWithBufferAPT: totalCostAPT + this.SAFETY_BUFFER_APT,
    };

    logger.debug('Contract call gas estimate:', estimate);
    return estimate;
  }

  /**
   * Validate that an account has sufficient balance for transaction + gas
   * 
   * @param accountBalance Current account balance in APT
   * @param transferAmount Amount to transfer in APT
   * @param transactionType Type of transaction
   * @returns true if sufficient, false otherwise
   */
  validateSufficientBalance(
    accountBalance: number,
    transferAmount: number,
    transactionType: 'transfer' | 'batch' = 'transfer',
    recipientCount: number = 1
  ): {
    sufficient: boolean;
    required: number;
    available: number;
    shortfall: number;
    estimate: GasEstimate;
  } {
    const estimate = transactionType === 'transfer'
      ? this.calculateTransferGas()
      : this.calculateBatchWithdrawalGas(recipientCount);

    const totalRequired = transferAmount + estimate.totalWithBufferAPT;
    const sufficient = accountBalance >= totalRequired;
    const shortfall = sufficient ? 0 : totalRequired - accountBalance;

    const result = {
      sufficient,
      required: totalRequired,
      available: accountBalance,
      shortfall,
      estimate,
    };

    if (!sufficient) {
      logger.warn('⚠️ Insufficient balance for transaction:', {
        accountBalance: accountBalance.toFixed(8),
        transferAmount: transferAmount.toFixed(8),
        gasCost: estimate.totalWithBufferAPT.toFixed(8),
        totalRequired: totalRequired.toFixed(8),
        shortfall: shortfall.toFixed(8),
      });
    }

    return result;
  }

  /**
   * Calculate safe transfer amount
   * Returns the maximum amount that can be transferred while reserving gas
   * 
   * @param accountBalance Current account balance in APT
   * @param transactionType Type of transaction
   * @returns Safe transfer amount (balance minus gas + buffer)
   */
  calculateSafeTransferAmount(
    accountBalance: number,
    transactionType: 'transfer' | 'batch' = 'transfer',
    recipientCount: number = 1
  ): number {
    const estimate = transactionType === 'transfer'
      ? this.calculateTransferGas()
      : this.calculateBatchWithdrawalGas(recipientCount);

    const safeAmount = Math.max(0, accountBalance - estimate.totalWithBufferAPT);

    logger.info('Safe transfer amount calculated:', {
      accountBalance: accountBalance.toFixed(8),
      gasReserved: estimate.totalWithBufferAPT.toFixed(8),
      safeTransferAmount: safeAmount.toFixed(8),
    });

    return safeAmount;
  }

  /**
   * Estimate total gas cost for multiple operations
   * Useful for planning multi-step operations
   */
  estimateMultiOperationGas(operations: {
    transfers?: number;
    batches?: Array<{ recipientCount: number }>;
    contractCalls?: number;
  }): {
    totalGasAPT: number;
    breakdown: {
      transfers: number;
      batches: number;
      contractCalls: number;
    };
  } {
    let totalGasAPT = 0;
    const breakdown = {
      transfers: 0,
      batches: 0,
      contractCalls: 0,
    };

    // Calculate transfer gas
    if (operations.transfers) {
      const transferGas = this.calculateTransferGas();
      breakdown.transfers = transferGas.totalWithBufferAPT * operations.transfers;
      totalGasAPT += breakdown.transfers;
    }

    // Calculate batch gas
    if (operations.batches) {
      for (const batch of operations.batches) {
        const batchGas = this.calculateBatchWithdrawalGas(batch.recipientCount);
        breakdown.batches += batchGas.totalWithBufferAPT;
      }
      totalGasAPT += breakdown.batches;
    }

    // Calculate contract call gas
    if (operations.contractCalls) {
      const contractGas = this.calculateContractCallGas();
      breakdown.contractCalls = contractGas.totalWithBufferAPT * operations.contractCalls;
      totalGasAPT += breakdown.contractCalls;
    }

    logger.info('Multi-operation gas estimate:', {
      totalGasAPT: totalGasAPT.toFixed(8),
      breakdown: {
        transfers: breakdown.transfers.toFixed(8),
        batches: breakdown.batches.toFixed(8),
        contractCalls: breakdown.contractCalls.toFixed(8),
      },
    });

    return {
      totalGasAPT,
      breakdown,
    };
  }
}

export default new GasCalculatorService();

