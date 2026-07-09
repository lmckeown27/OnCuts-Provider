/**
 * Blockchain Sync Cron Service
 * 
 * This is a compatibility wrapper for the new blockchain-reconciliation.job.ts
 * 
 * DEPRECATED: This file exists for backward compatibility.
 * New code should use blockchain-reconciliation.job.ts directly.
 * 
 * The new architecture uses:
 * - Periodic reconciliation (every 5 minutes)
 * - Full reindex (nightly at 3am)
 * - Write-through sync (immediate after blockchain tx)
 */

import { logger } from '../utils/logger';
import { blockchainReconciliationJob } from './blockchain-reconciliation.job';

class BlockchainSyncCronService {
  /**
   * Start the reconciliation job
   * 
   * This now delegates to the new blockchain-reconciliation.job
   */
  start() {
    logger.info('Starting blockchain reconciliation job (via compatibility wrapper)');
    blockchainReconciliationJob.start();
  }

  /**
   * Manually trigger reconciliation (for testing/admin)
   */
  async triggerManualSync(): Promise<any> {
    logger.info('Manually triggering blockchain reconciliation...');
    const result = await blockchainReconciliationJob.triggerManual();
    logger.info('Manual blockchain reconciliation complete', {
      scanned: result.recordsScanned,
      updated: result.recordsUpdated,
      discrepancies: result.discrepanciesFound
    });
    return result;
  }

  /**
   * Get sync status
   */
  getStatus() {
    return blockchainReconciliationJob.getStatus();
  }

  /**
   * Stop is no-op (reconciliation job manages its own lifecycle)
   */
  stop() {
    logger.info('Stop called on BlockchainSyncCronService (no-op)');
  }
}

export default new BlockchainSyncCronService();

