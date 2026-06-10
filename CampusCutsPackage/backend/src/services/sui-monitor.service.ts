import { logger } from '../utils/logger';

/**
 * Placeholder for Sui transaction polling / indexer feed (admin dashboard).
 */
class SuiMonitorService {
  async start(): Promise<void> {
    logger.info('Sui monitor: start() — wire to Sui RPC or indexer when ready');
  }

  async getRecentTransactions(_limit = 50): Promise<unknown[]> {
    return [];
  }
}

export default new SuiMonitorService();
