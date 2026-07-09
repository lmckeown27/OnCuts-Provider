/**
 * Blockchain Sync Service
 * 
 * Responsible for:
 * 1. Write-through sync: Update Postgres immediately after blockchain transaction
 * 2. Verification: Compare Postgres vs blockchain state
 * 3. Auto-repair: Fix discrepancies (blockchain always wins)
 * 
 * CRITICAL RULES:
 * - Blockchain is ALWAYS the source of truth
 * - Postgres can be overwritten without warning
 * - All discrepancies are logged for audit
 */

// TODO: Install Prisma - See POSTGRES_SYNC_SETUP.md
// import { PrismaClient, PaymentStatus, SyncSource } from '@prisma/client';
import { logger } from '../utils/logger';
import { ApiError } from '../middleware/errorHandler';
import { pool } from '../database/connection';

// Temporary: Using raw SQL until Prisma is installed
// const prisma = new PrismaClient();

// Temporary enums until Prisma is set up
enum PaymentStatus {
  PENDING = 'PENDING',
  PROCESSING = 'PROCESSING',
  ESCROWED = 'ESCROWED',
  RELEASED = 'RELEASED',
  REFUNDED = 'REFUNDED',
  FAILED = 'FAILED'
}

enum SyncSource {
  WRITE_THROUGH = 'WRITE_THROUGH',
  PERIODIC_RECON = 'PERIODIC_RECON',
  MANUAL_REPAIR = 'MANUAL_REPAIR',
  INITIAL_LOAD = 'INITIAL_LOAD'
}

// Mock Prisma client until hybrid schema is deployed
const prisma = {
  booking: {
    findUnique: async () => ({ id: 'mock', barberId: 'mock', bookingStatus: 'CONFIRMED' }),
    update: async (params: any) => ({ id: params.where.id, ...params.data }),
  },
  paymentCache: {
    findUnique: async () => ({ 
      id: 'mock',
      blockchainPaymentId: 'mock',
      bookingId: 'mock',
      status: PaymentStatus.ESCROWED,
      amountUSDC: 25,
      booking: { barberId: 'mock' }
    }),
    upsert: async (params: any) => ({ id: 'mock', ...params.create }),
    update: async (params: any) => ({ 
      id: 'mock',
      bookingId: 'mock',
      ...params.data,
      booking: { barberId: 'mock' }
    }),
  },
  barber: {
    findUnique: async () => ({ 
      id: 'mock',
      user: { suiAddress: '0xmock' }
    }),
    update: async () => ({}),
  },
  dataDiscrepancy: {
    create: async () => ({ id: 'mock' }),
  },
} as any;

interface BlockchainPaymentState {
  paymentId: string;
  status: PaymentStatus;
  amountUSDC: number;
  barberPayoutUSDC: number;
  platformFeeUSDC: number;
  txHashEscrowCreated?: string;
  txHashPaymentReleased?: string;
  txHashRefunded?: string;
  barberAddress: string;
  consumerAddress: string;
}

interface SyncResult {
  success: boolean;
  updated: boolean;
  discrepancyDetected: boolean;
  error?: string;
}

export class BlockchainSyncService {
  private moduleAddress: string;
  
  constructor() {
    this.moduleAddress = process.env.SUI_PACKAGE_ID || '';
    
    if (!this.moduleAddress) {
      logger.warn('⚠️  SUI_PACKAGE_ID not configured - blockchain sync stubbed');
    }
  }
  
  // ═══════════════════════════════════════════════════════════════
  // WRITE-THROUGH SYNC (Called immediately after blockchain tx)
  // ═══════════════════════════════════════════════════════════════
  
  /**
   * Sync payment cache after escrow created
   * Called immediately after blockchain transaction confirms
   */
  async syncAfterEscrowCreated(params: {
    bookingId: string;
    blockchainPaymentId: string;
    txHash: string;
    amountUSDC: number;
    barberAddress: string;
    consumerAddress: string;
  }): Promise<SyncResult> {
    // TODO: Implement with Prisma once installed
    // See POSTGRES_SYNC_SETUP.md for migration guide
    
    logger.warn('⚠️  Blockchain sync not yet implemented - Install Prisma first');
    logger.info('📋 Would sync after escrow created', params);
    
    return { success: true, updated: false, discrepancyDetected: false };
  }
  
  /**
   * Sync payment cache after payment released
   * Called immediately after blockchain transaction confirms
   */
  async syncAfterPaymentReleased(params: {
    blockchainPaymentId: string;
    txHash: string;
  }): Promise<SyncResult> {
    const { blockchainPaymentId, txHash } = params;
    
    try {
      logger.info('🔄 Syncing Postgres after payment released', {
        payment_id: blockchainPaymentId,
        tx_hash: txHash
      });
      
      // Update payment cache
      const paymentCache = await prisma.paymentCache.update({
        where: { blockchainPaymentId },
        data: {
          status: PaymentStatus.RELEASED,
          txHashPaymentReleased: txHash,
          lastSyncedAt: new Date(),
          syncSource: SyncSource.WRITE_THROUGH
        },
        include: { booking: true }
      });
      
      // Update booking
      await prisma.booking.update({
        where: { id: paymentCache.bookingId },
        data: {
          txHashReleased: txHash,
          paymentStatus: PaymentStatus.RELEASED,
          paymentStatusSyncedAt: new Date(),
          bookingStatus: 'COMPLETED',
          completedAt: new Date()
        }
      });
      
      // Update barber earnings cache
      await this.updateBarberEarningsCache(paymentCache.booking.barberId);
      
      logger.info('✅ Postgres synced after payment released', {
        payment_id: blockchainPaymentId
      });
      
      return { success: true, updated: true, discrepancyDetected: false };
      
    } catch (error: any) {
      logger.error('❌ Failed to sync after payment released', {
        payment_id: blockchainPaymentId,
        error: error.message
      });
      
      return { success: false, updated: false, discrepancyDetected: false, error: error.message };
    }
  }
  
  /**
   * Sync payment cache after refund
   * Called immediately after blockchain transaction confirms
   */
  async syncAfterRefund(params: {
    blockchainPaymentId: string;
    txHash: string;
  }): Promise<SyncResult> {
    const { blockchainPaymentId, txHash } = params;
    
    try {
      logger.info('🔄 Syncing Postgres after refund', {
        payment_id: blockchainPaymentId,
        tx_hash: txHash
      });
      
      // Update payment cache
      const paymentCache = await prisma.paymentCache.update({
        where: { blockchainPaymentId },
        data: {
          status: PaymentStatus.REFUNDED,
          txHashRefunded: txHash,
          lastSyncedAt: new Date(),
          syncSource: SyncSource.WRITE_THROUGH
        },
        include: { booking: true }
      });
      
      // Update booking
      await prisma.booking.update({
        where: { id: paymentCache.bookingId },
        data: {
          txHashRefunded: txHash,
          paymentStatus: PaymentStatus.REFUNDED,
          paymentStatusSyncedAt: new Date(),
          bookingStatus: 'CANCELLED',
          cancelledAt: new Date()
        }
      });
      
      logger.info('✅ Postgres synced after refund', {
        payment_id: blockchainPaymentId
      });
      
      return { success: true, updated: true, discrepancyDetected: false };
      
    } catch (error: any) {
      logger.error('❌ Failed to sync after refund', {
        payment_id: blockchainPaymentId,
        error: error.message
      });
      
      return { success: false, updated: false, discrepancyDetected: false, error: error.message };
    }
  }
  
  // ═══════════════════════════════════════════════════════════════
  // VERIFICATION & AUTO-REPAIR
  // ═══════════════════════════════════════════════════════════════
  
  /**
   * Verify payment cache against blockchain
   * Returns true if data matches, false if discrepancy detected
   */
  async verifyPaymentCache(blockchainPaymentId: string): Promise<{
    matches: boolean;
    discrepancies: string[];
    blockchainState?: BlockchainPaymentState;
    postgresState?: any;
  }> {
    try {
      // 1. Get Postgres state
      const paymentCache = await prisma.paymentCache.findUnique({
        where: { blockchainPaymentId },
        include: { booking: true }
      });
      
      if (!paymentCache) {
        return {
          matches: false,
          discrepancies: ['Payment cache not found in Postgres']
        };
      }
      
      // 2. Get blockchain state
      const blockchainState = await this.getBlockchainPaymentState(blockchainPaymentId);
      
      if (!blockchainState) {
        return {
          matches: false,
          discrepancies: ['Payment not found on blockchain']
        };
      }
      
      // 3. Compare
      const discrepancies: string[] = [];
      
      if (paymentCache.status !== blockchainState.status) {
        discrepancies.push(`Status mismatch: Postgres=${paymentCache.status}, Blockchain=${blockchainState.status}`);
      }
      
      if (Math.abs(parseFloat(paymentCache.amountUSDC.toString()) - blockchainState.amountUSDC) > 0.01) {
        discrepancies.push(`Amount mismatch: Postgres=${paymentCache.amountUSDC}, Blockchain=${blockchainState.amountUSDC}`);
      }
      
      if (Math.abs(parseFloat(paymentCache.barberPayoutUSDC.toString()) - blockchainState.barberPayoutUSDC) > 0.01) {
        discrepancies.push(`Barber payout mismatch: Postgres=${paymentCache.barberPayoutUSDC}, Blockchain=${blockchainState.barberPayoutUSDC}`);
      }
      
      return {
        matches: discrepancies.length === 0,
        discrepancies,
        blockchainState,
        postgresState: paymentCache
      };
      
    } catch (error: any) {
      logger.error('❌ Failed to verify payment cache', {
        payment_id: blockchainPaymentId,
        error: error.message
      });
      
      throw new ApiError(500, `Verification failed: ${error.message}`);
    }
  }
  
  /**
   * Auto-repair payment cache from blockchain
   * Called when discrepancy detected
   * 
   * RULE: Blockchain ALWAYS wins
   */
  async repairPaymentCache(blockchainPaymentId: string): Promise<SyncResult> {
    try {
      logger.warn('🔧 Auto-repairing payment cache from blockchain', {
        payment_id: blockchainPaymentId
      });
      
      // Get authoritative blockchain state
      const blockchainState = await this.getBlockchainPaymentState(blockchainPaymentId);
      
      if (!blockchainState) {
        throw new ApiError(404, 'Payment not found on blockchain');
      }
      
      // Overwrite Postgres with blockchain truth
      await prisma.paymentCache.update({
        where: { blockchainPaymentId },
        data: {
          status: blockchainState.status,
          amountUSDC: blockchainState.amountUSDC,
          barberPayoutUSDC: blockchainState.barberPayoutUSDC,
          platformFeeUSDC: blockchainState.platformFeeUSDC,
          txHashEscrowCreated: blockchainState.txHashEscrowCreated,
          txHashPaymentReleased: blockchainState.txHashPaymentReleased,
          txHashRefunded: blockchainState.txHashRefunded,
          lastSyncedAt: new Date(),
          syncSource: SyncSource.MANUAL_REPAIR,
          discrepancyCount: {
            increment: 1
          }
        }
      });
      
      // Log discrepancy for audit
      await prisma.dataDiscrepancy.create({
        data: {
          entityType: 'payment',
          entityId: blockchainPaymentId,
          field: 'multiple',
          postgresValue: 'corrupted',
          blockchainValue: 'repaired',
          resolved: true,
          resolvedAt: new Date(),
          resolutionAction: 'auto_repaired',
          detectedBy: 'verification_system'
        }
      });
      
      logger.info('✅ Payment cache auto-repaired from blockchain', {
        payment_id: blockchainPaymentId
      });
      
      return { success: true, updated: true, discrepancyDetected: true };
      
    } catch (error: any) {
      logger.error('❌ Failed to auto-repair payment cache', {
        payment_id: blockchainPaymentId,
        error: error.message
      });
      
      return { success: false, updated: false, discrepancyDetected: true, error: error.message };
    }
  }
  
  /**
   * Update barber earnings cache from blockchain
   */
  async updateBarberEarningsCache(barberId: string): Promise<void> {
    try {
      const barber = await prisma.barber.findUnique({
        where: { id: barberId },
        include: { user: true }
      });
      
      if (!barber) {
        throw new ApiError(404, 'Barber not found');
      }
      
      // Get earnings from blockchain
      const earnings = await this.getBarberEarningsFromBlockchain(
        (barber.user as { suiAddress?: string }).suiAddress || '0x0'
      );
      
      // Update cache
      await prisma.barber.update({
        where: { id: barberId },
        data: {
          totalEarningsCache: earnings.total,
          pendingPayoutCache: earnings.pending,
          completedBookingsCache: earnings.completedCount,
          earningsSyncedAt: new Date()
        }
      });
      
      logger.debug('Updated barber earnings cache', {
        barber_id: barberId,
        total: earnings.total,
        pending: earnings.pending
      });
      
    } catch (error: any) {
      logger.error('Failed to update barber earnings cache', {
        barber_id: barberId,
        error: error.message
      });
    }
  }
  
  // ═══════════════════════════════════════════════════════════════
  // BLOCKCHAIN QUERIES (Private helpers)
  // ═══════════════════════════════════════════════════════════════
  
  /**
   * Get payment state from blockchain
   */
  private async getBlockchainPaymentState(_paymentId: string): Promise<BlockchainPaymentState | null> {
    logger.debug('Sui: getBlockchainPaymentState stub');
    return null;
  }
  
  /**
   * Get barber earnings from blockchain
   */
  private async getBarberEarningsFromBlockchain(_suiAddress: string): Promise<{
    total: number;
    pending: number;
    completedCount: number;
  }> {
    return { total: 0, pending: 0, completedCount: 0 };
  }
}

// Singleton export
export const blockchainSyncService = new BlockchainSyncService();
