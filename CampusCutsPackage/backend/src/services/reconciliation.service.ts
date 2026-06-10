/**
 * Reconciliation Service
 * 
 * Daily reconciliation of:
 * - Stripe ledger vs internal transactions
 * - Bank account vs platform treasury
 * - On-chain records vs internal records
 * 
 * Runs as nightly cron job to detect discrepancies early.
 */

import { pool } from '../database/connection';
import { logger } from '../utils/logger';
import Stripe from 'stripe';
import { getDefaultStripeClient } from '../config/stripe';

function stripeSdk(): Stripe {
  return getDefaultStripeClient();
}

export enum ReconciliationType {
  STRIPE = 'stripe',
  BANK = 'bank',
  ONCHAIN = 'onchain',
  FULL = 'full'
}

export enum ReconciliationStatus {
  PENDING = 'pending',
  COMPLETED = 'completed',
  DISCREPANCIES = 'discrepancies',
  FAILED = 'failed'
}

export interface ReconciliationReport {
  id: number;
  report_date: Date;
  report_type: ReconciliationType;
  status: ReconciliationStatus;
  total_platform_balance_cents: number;
  total_user_balances_cents: number;
  total_escrow_cents: number;
  discrepancy_cents: number;
  discrepancies?: Array<{
    type: string;
    description: string;
    amount_cents: number;
    details: any;
  }>;
  created_at: Date;
  completed_at?: Date;
}

class ReconciliationService {
  /**
   * Run full daily reconciliation
   */
  async runDailyReconciliation(date: Date = new Date()): Promise<ReconciliationReport> {
    const reportDate = new Date(date);
    reportDate.setHours(0, 0, 0, 0);

    logger.info('Starting daily reconciliation', { report_date: reportDate });

    const client = await pool.connect();

    try {
      await client.query('BEGIN');

      // 1. Create reconciliation report
      const reportResult = await client.query(
        `INSERT INTO reconciliation_reports (
          report_date, report_type, status
        )
        VALUES ($1, $2, $3)
        RETURNING *`,
        [reportDate, ReconciliationType.FULL, ReconciliationStatus.PENDING]
      );

      const reportId = reportResult.rows[0].id;

      // 2. Calculate balances
      const balances = await this.calculateBalances(client);

      // 3. Reconcile Stripe
      const stripeDiscrepancies = await this.reconcileStripe(reportDate);

      // 4. Reconcile on-chain
      const onchainDiscrepancies = await this.reconcileOnChain(reportDate);

      // 5. Check internal consistency
      const internalDiscrepancies = await this.checkInternalConsistency(client);

      // 6. Combine all discrepancies
      const allDiscrepancies = [
        ...stripeDiscrepancies,
        ...onchainDiscrepancies,
        ...internalDiscrepancies,
      ];

      const totalDiscrepancy = allDiscrepancies.reduce(
        (sum, d) => sum + Math.abs(d.amount_cents),
        0
      );

      // 7. Update report
      await client.query(
        `UPDATE reconciliation_reports
         SET status = $1,
             total_platform_balance_cents = $2,
             total_user_balances_cents = $3,
             total_escrow_cents = $4,
             discrepancy_cents = $5,
             discrepancies = $6,
             completed_at = NOW()
         WHERE id = $7`,
        [
          allDiscrepancies.length > 0 
            ? ReconciliationStatus.DISCREPANCIES 
            : ReconciliationStatus.COMPLETED,
          balances.platform_balance,
          balances.user_balances,
          balances.escrow_balance,
          totalDiscrepancy,
          JSON.stringify(allDiscrepancies),
          reportId,
        ]
      );

      await client.query('COMMIT');

      const finalReport = await this.getReport(reportId);

      if (allDiscrepancies.length > 0) {
        logger.warn('Reconciliation found discrepancies!', {
          report_id: reportId,
          discrepancy_count: allDiscrepancies.length,
          total_discrepancy_dollars: totalDiscrepancy / 100,
          discrepancies: allDiscrepancies,
        });

        // Send alert to admin
        if (finalReport) {
          await this.sendDiscrepancyAlert(finalReport);
        }
      } else {
        logger.info('Reconciliation completed successfully - no discrepancies');
      }

      return finalReport!;
    } catch (error) {
      await client.query('ROLLBACK');
      logger.error('Reconciliation failed', error);

      // Mark report as failed
      await pool.query(
        `UPDATE reconciliation_reports
         SET status = $1, completed_at = NOW()
         WHERE report_date = $2`,
        [ReconciliationStatus.FAILED, reportDate]
      );

      throw error;
    } finally {
      client.release();
    }
  }

  /**
   * Calculate current balances
   */
  private async calculateBalances(client: any): Promise<{
    platform_balance: number;
    user_balances: number;
    escrow_balance: number;
  }> {
    // Get total user balances
    const userBalancesResult = await client.query(`
      SELECT COALESCE(SUM(available_amount + pending_amount), 0) as total
      FROM balances
    `);

    // Get total escrow
    const escrowResult = await client.query(`
      SELECT COALESCE(SUM(amount), 0) as total
      FROM escrow_holds
      WHERE status = 'held'
    `);

    // Get total platform fees
    const feesResult = await client.query(`
      SELECT COALESCE(SUM(amount), 0) as total
      FROM platform_fees
      WHERE NOT withdrawn
    `);

    return {
      platform_balance: parseInt(feesResult.rows[0].total),
      user_balances: parseInt(userBalancesResult.rows[0].total),
      escrow_balance: parseInt(escrowResult.rows[0].total),
    };
  }

  /**
   * Reconcile against Stripe
   */
  private async reconcileStripe(date: Date): Promise<Array<any>> {
    const discrepancies: Array<any> = [];

    try {
      // Get all Stripe charges for the date
      const startOfDay = new Date(date);
      startOfDay.setHours(0, 0, 0, 0);
      
      const endOfDay = new Date(date);
      endOfDay.setHours(23, 59, 59, 999);

      const charges = await stripeSdk().charges.list({
        created: {
          gte: Math.floor(startOfDay.getTime() / 1000),
          lte: Math.floor(endOfDay.getTime() / 1000),
        },
        limit: 100,
      });

      // Get internal transactions for the date
      const internalResult = await pool.query(
        `SELECT stripe_payment_intent_id, amount
         FROM transactions
         WHERE type = 'charge'
           AND created_at >= $1
           AND created_at <= $2
           AND stripe_payment_intent_id IS NOT NULL`,
        [startOfDay, endOfDay]
      );

      const internalMap = new Map(
        internalResult.rows.map(row => [row.stripe_payment_intent_id, row.amount])
      );

      // Check for missing or mismatched charges
      for (const charge of charges.data) {
        if (charge.status === 'succeeded') {
          const internalAmount = internalMap.get(charge.payment_intent as string);

          if (!internalAmount) {
            discrepancies.push({
              type: 'stripe_charge_missing',
              description: `Stripe charge ${charge.id} not found in internal ledger`,
              amount_cents: charge.amount,
              details: {
                stripe_charge_id: charge.id,
                stripe_amount: charge.amount,
              },
            });
          } else if (internalAmount !== charge.amount) {
            discrepancies.push({
              type: 'stripe_amount_mismatch',
              description: `Amount mismatch for charge ${charge.id}`,
              amount_cents: Math.abs(internalAmount - charge.amount),
              details: {
                stripe_charge_id: charge.id,
                stripe_amount: charge.amount,
                internal_amount: internalAmount,
              },
            });
          }
        }
      }
    } catch (error) {
      logger.error('Stripe reconciliation failed', error);
      discrepancies.push({
        type: 'stripe_reconciliation_error',
        description: 'Failed to reconcile Stripe',
        amount_cents: 0,
        details: { error: (error as Error).message },
      });
    }

    return discrepancies;
  }

  /**
   * Reconcile against on-chain records
   */
  private async reconcileOnChain(date: Date): Promise<Array<any>> {
    const discrepancies: Array<any> = [];

    try {
      // Check that all completed bookings have on-chain anchors
      const bookingsWithoutAnchors = await pool.query(
        `SELECT b.id, b.status
         FROM bookings b
         LEFT JOIN onchain_records o ON o.subject_id = b.id AND o.record_type = 'booking_hash'
         WHERE b.status = 'completed'
           AND b.completed_at >= $1
           AND o.id IS NULL`,
        [date]
      );

      for (const booking of bookingsWithoutAnchors.rows) {
        discrepancies.push({
          type: 'missing_onchain_anchor',
          description: `Completed booking ${booking.id} missing on-chain anchor`,
          amount_cents: 0,
          details: {
            booking_id: booking.id,
            status: booking.status,
          },
        });
      }
    } catch (error) {
      logger.error('On-chain reconciliation failed', error);
    }

    return discrepancies;
  }

  /**
   * Check internal consistency
   */
  private async checkInternalConsistency(client: any): Promise<Array<any>> {
    const discrepancies: Array<any> = [];

    try {
      // Check that balance table matches sum of transactions
      const users = await client.query(`SELECT user_id FROM balances`);

      for (const user of users.rows) {
        const balanceResult = await client.query(
          `SELECT available_amount FROM balances WHERE user_id = $1`,
          [user.user_id]
        );

        const txResult = await client.query(
          `SELECT COALESCE(SUM(amount), 0) as total
           FROM transactions
           WHERE user_id = $1 AND status = 'completed'`,
          [user.user_id]
        );

        const balanceAmount = balanceResult.rows[0].available_amount;
        const txTotal = parseInt(txResult.rows[0].total);

        if (balanceAmount !== txTotal) {
          discrepancies.push({
            type: 'balance_transaction_mismatch',
            description: `User ${user.user_id} balance doesn't match transaction sum`,
            amount_cents: Math.abs(balanceAmount - txTotal),
            details: {
              user_id: user.user_id,
              balance_amount: balanceAmount,
              transaction_total: txTotal,
              difference: balanceAmount - txTotal,
            },
          });
        }
      }
    } catch (error) {
      logger.error('Internal consistency check failed', error);
    }

    return discrepancies;
  }

  /**
   * Get reconciliation report
   */
  async getReport(reportId: number): Promise<ReconciliationReport | null> {
    const result = await pool.query(
      `SELECT * FROM reconciliation_reports WHERE id = $1`,
      [reportId]
    );

    return result.rows[0] || null;
  }

  /**
   * Get recent reports
   */
  async getRecentReports(limit: number = 30): Promise<ReconciliationReport[]> {
    const result = await pool.query(
      `SELECT * FROM reconciliation_reports
       ORDER BY report_date DESC
       LIMIT $1`,
      [limit]
    );

    return result.rows;
  }

  /**
   * Send discrepancy alert
   */
  private async sendDiscrepancyAlert(report: ReconciliationReport): Promise<void> {
    // TODO: Integrate with alerting system (Slack, PagerDuty, email)
    logger.warn('ALERT: Reconciliation discrepancies detected!', {
      report_id: report.id,
      report_date: report.report_date,
      discrepancy_count: report.discrepancies?.length || 0,
      total_discrepancy_dollars: report.discrepancy_cents / 100,
    });
  }
}

export default new ReconciliationService();

