/**
 * Data Source Decision Layer
 * 
 * This service decides which database to query based on request type:
 * - Critical financial queries → Blockchain
 * - Display/UX queries → Postgres cache
 * 
 * RULE: If it involves money or needs cryptographic proof → Blockchain
 *       If it needs speed or searchability → Postgres
 */

import { logger } from '../utils/logger';

export enum DataSource {
  BLOCKCHAIN = 'blockchain',
  POSTGRES = 'postgres',
  BOTH = 'both'  // Query both, blockchain wins if mismatch
}

export enum QueryType {
  // Financial (MUST use blockchain)
  PAYMENT_STATUS = 'payment_status',
  PAYMENT_AMOUNT = 'payment_amount',
  BARBER_EARNINGS_VERIFY = 'barber_earnings_verify',
  ESCROW_BALANCE = 'escrow_balance',
  SETTLEMENT_PROOF = 'settlement_proof',
  
  // Display (CAN use Postgres cache)
  BARBER_LIST = 'barber_list',
  BARBER_SEARCH = 'barber_search',
  BOOKING_LIST = 'booking_list',
  DASHBOARD_STATS = 'dashboard_stats',
  USER_PROFILE = 'user_profile',
  AVAILABILITY_CHECK = 'availability_check',
  
  // Hybrid (Postgres primary, blockchain for verification)
  BARBER_EARNINGS_DISPLAY = 'barber_earnings_display',
  PAYMENT_HISTORY = 'payment_history',
  PLATFORM_REVENUE = 'platform_revenue'
}

interface QueryContext {
  type: QueryType;
  userId?: string;
  isAdminRequest?: boolean;
  requiresProof?: boolean;
  cacheAge?: number; // Max age in seconds
}

interface DataSourceDecision {
  source: DataSource;
  reason: string;
  fallback?: DataSource;
  cacheMaxAge?: number;
}

export class DataSourceDecisionService {
  
  /**
   * Decide which database to query
   */
  decide(context: QueryContext): DataSourceDecision {
    const { type, isAdminRequest, requiresProof, cacheAge } = context;
    
    // RULE 1: Explicit proof requirement always uses blockchain
    if (requiresProof) {
      return {
        source: DataSource.BLOCKCHAIN,
        reason: 'Proof explicitly requested by user/admin'
      };
    }
    
    // RULE 2: Admin verification queries use blockchain
    if (isAdminRequest && this.isCriticalFinancialQuery(type)) {
      return {
        source: DataSource.BLOCKCHAIN,
        reason: 'Admin verification requires blockchain truth'
      };
    }
    
    // RULE 3: Critical financial queries use blockchain
    if (this.isCriticalFinancialQuery(type)) {
      return {
        source: DataSource.BLOCKCHAIN,
        reason: 'Critical financial data requires blockchain source of truth',
        fallback: DataSource.POSTGRES // Fallback if blockchain unavailable
      };
    }
    
    // RULE 4: Display queries use Postgres cache
    if (this.isDisplayQuery(type)) {
      return {
        source: DataSource.POSTGRES,
        reason: 'Display query optimized for speed',
        cacheMaxAge: 300 // 5 minutes
      };
    }
    
    // RULE 5: Hybrid queries use Postgres with verification option
    if (this.isHybridQuery(type)) {
      // Check if cache is fresh enough
      const maxAge = cacheAge || 300; // Default 5 minutes
      
      return {
        source: DataSource.POSTGRES,
        reason: `Hybrid query: Postgres cache (max age: ${maxAge}s), blockchain verification available`,
        fallback: DataSource.BLOCKCHAIN,
        cacheMaxAge: maxAge
      };
    }
    
    // Default: Use Postgres for performance
    return {
      source: DataSource.POSTGRES,
      reason: 'Default to Postgres for performance'
    };
  }
  
  /**
   * Check if query is critical financial (MUST use blockchain)
   */
  private isCriticalFinancialQuery(type: QueryType): boolean {
    return [
      QueryType.PAYMENT_STATUS,
      QueryType.PAYMENT_AMOUNT,
      QueryType.BARBER_EARNINGS_VERIFY,
      QueryType.ESCROW_BALANCE,
      QueryType.SETTLEMENT_PROOF
    ].includes(type);
  }
  
  /**
   * Check if query is display-only (CAN use Postgres cache)
   */
  private isDisplayQuery(type: QueryType): boolean {
    return [
      QueryType.BARBER_LIST,
      QueryType.BARBER_SEARCH,
      QueryType.BOOKING_LIST,
      QueryType.USER_PROFILE,
      QueryType.AVAILABILITY_CHECK
    ].includes(type);
  }
  
  /**
   * Check if query is hybrid (Postgres primary, blockchain for verification)
   */
  private isHybridQuery(type: QueryType): boolean {
    return [
      QueryType.BARBER_EARNINGS_DISPLAY,
      QueryType.PAYMENT_HISTORY,
      QueryType.DASHBOARD_STATS,
      QueryType.PLATFORM_REVENUE
    ].includes(type);
  }
  
  /**
   * Log decision for audit
   */
  logDecision(context: QueryContext, decision: DataSourceDecision): void {
    logger.debug('Data source decision', {
      query_type: context.type,
      source: decision.source,
      reason: decision.reason,
      user_id: context.userId,
      is_admin: context.isAdminRequest,
      requires_proof: context.requiresProof
    });
  }
  
  /**
   * Verify if cached data is fresh enough
   */
  isCacheFresh(lastSyncedAt: Date | null, maxAgeSeconds: number): boolean {
    if (!lastSyncedAt) {
      return false; // Never synced
    }
    
    const ageSeconds = (Date.now() - lastSyncedAt.getTime()) / 1000;
    return ageSeconds <= maxAgeSeconds;
  }
  
  /**
   * Get recommended cache age for query type
   */
  getRecommendedCacheAge(type: QueryType): number {
    const cacheAges: Record<QueryType, number> = {
      // Critical (sync immediately)
      [QueryType.PAYMENT_STATUS]: 0,
      [QueryType.PAYMENT_AMOUNT]: 0,
      [QueryType.BARBER_EARNINGS_VERIFY]: 0,
      [QueryType.ESCROW_BALANCE]: 0,
      [QueryType.SETTLEMENT_PROOF]: 0,
      
      // Display (5 minute cache)
      [QueryType.BARBER_LIST]: 300,
      [QueryType.BARBER_SEARCH]: 300,
      [QueryType.BOOKING_LIST]: 300,
      [QueryType.USER_PROFILE]: 300,
      [QueryType.AVAILABILITY_CHECK]: 60,
      
      // Hybrid (2 minute cache)
      [QueryType.BARBER_EARNINGS_DISPLAY]: 120,
      [QueryType.PAYMENT_HISTORY]: 120,
      [QueryType.DASHBOARD_STATS]: 120,
      [QueryType.PLATFORM_REVENUE]: 120
    };
    
    return cacheAges[type] || 300; // Default 5 minutes
  }
}

// Singleton export
export const dataSourceDecisionService = new DataSourceDecisionService();

// ═══════════════════════════════════════════════════════════════════
// USAGE EXAMPLES
// ═══════════════════════════════════════════════════════════════════

/**
 * Example 1: Get payment status (critical)
 */
export async function getPaymentStatusExample(paymentId: string) {
  const decision = dataSourceDecisionService.decide({
    type: QueryType.PAYMENT_STATUS,
    requiresProof: false
  });
  
  // decision.source === DataSource.BLOCKCHAIN
  // Query blockchain directly for authoritative status
}

/**
 * Example 2: List barbers (display)
 */
export async function listBarbersExample(campusId: string) {
  const decision = dataSourceDecisionService.decide({
    type: QueryType.BARBER_LIST
  });
  
  // decision.source === DataSource.POSTGRES
  // Query Postgres cache for fast results
}

/**
 * Example 3: Show barber earnings (hybrid)
 */
export async function getBarberEarningsExample(barberId: string, userId: string) {
  const decision = dataSourceDecisionService.decide({
    type: QueryType.BARBER_EARNINGS_DISPLAY,
    userId
  });
  
  // decision.source === DataSource.POSTGRES (with verification option)
  // 1. Query Postgres cache for fast display
  // 2. Show cache age to user
  // 3. Offer "Verify on Blockchain" button
}

/**
 * Example 4: Admin verifies payment (requires proof)
 */
export async function adminVerifyPaymentExample(paymentId: string, adminId: string) {
  const decision = dataSourceDecisionService.decide({
    type: QueryType.PAYMENT_STATUS,
    userId: adminId,
    isAdminRequest: true,
    requiresProof: true
  });
  
  // decision.source === DataSource.BLOCKCHAIN
  // Admin verification always uses blockchain
}



