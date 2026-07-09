/**
 * Audit Service
 * 
 * Immutable audit logging for all critical operations.
 * Required for compliance, debugging, and dispute resolution.
 */

import { pool } from '../database/connection';
import { logger } from '../utils/logger';

export interface AuditLogInput {
  actor_user_id?: string;  // NULL for system actions
  action: string;
  object_type?: string;
  object_id?: string;
  details?: Record<string, any>;
  ip_address?: string;
  user_agent?: string;
}

export interface AuditLog {
  id: number;
  actor_user_id?: string;
  action: string;
  object_type?: string;
  object_id?: string;
  details?: Record<string, any>;
  ip_address?: string;
  user_agent?: string;
  created_at: Date;
}

class AuditService {
  /**
   * Create an audit log entry
   */
  async log(input: AuditLogInput): Promise<AuditLog> {
    try {
      const result = await pool.query(
        `INSERT INTO audit_logs (
          actor_user_id, action, object_type, object_id,
          details, ip_address, user_agent
        )
        VALUES ($1, $2, $3, $4, $5, $6, $7)
        RETURNING *`,
        [
          input.actor_user_id || null,
          input.action,
          input.object_type || null,
          input.object_id || null,
          JSON.stringify(input.details || {}),
          input.ip_address || null,
          input.user_agent || null,
        ]
      );

      return result.rows[0];
    } catch (error) {
      // Don't throw on audit failure - log it instead
      logger.error('Failed to create audit log', {
        input,
        error,
      });
      // Return a mock audit log to prevent breaking the main flow
      return {
        id: -1,
        created_at: new Date(),
        ...input,
      };
    }
  }

  /**
   * Get audit logs for a user
   */
  async getUserAuditLogs(
    userId: string,
    limit: number = 50,
    offset: number = 0
  ): Promise<{ logs: AuditLog[]; total: number }> {
    const [logsResult, countResult] = await Promise.all([
      pool.query(
        `SELECT * FROM audit_logs
         WHERE actor_user_id = $1
         ORDER BY created_at DESC
         LIMIT $2 OFFSET $3`,
        [userId, limit, offset]
      ),
      pool.query(
        `SELECT COUNT(*) as total FROM audit_logs WHERE actor_user_id = $1`,
        [userId]
      ),
    ]);

    return {
      logs: logsResult.rows,
      total: parseInt(countResult.rows[0].total),
    };
  }

  /**
   * Get audit logs for a specific object
   */
  async getObjectAuditLogs(
    objectType: string,
    objectId: string
  ): Promise<AuditLog[]> {
    const result = await pool.query(
      `SELECT * FROM audit_logs
       WHERE object_type = $1 AND object_id = $2
       ORDER BY created_at DESC`,
      [objectType, objectId]
    );

    return result.rows;
  }

  /**
   * Get recent audit logs (admin)
   */
  async getRecentLogs(
    limit: number = 100,
    offset: number = 0
  ): Promise<{ logs: AuditLog[]; total: number }> {
    const [logsResult, countResult] = await Promise.all([
      pool.query(
        `SELECT * FROM audit_logs
         ORDER BY created_at DESC
         LIMIT $1 OFFSET $2`,
        [limit, offset]
      ),
      pool.query(`SELECT COUNT(*) as total FROM audit_logs`),
    ]);

    return {
      logs: logsResult.rows,
      total: parseInt(countResult.rows[0].total),
    };
  }

  /**
   * Search audit logs by action
   */
  async searchByAction(
    action: string,
    limit: number = 50
  ): Promise<AuditLog[]> {
    const result = await pool.query(
      `SELECT * FROM audit_logs
       WHERE action = $1
       ORDER BY created_at DESC
       LIMIT $2`,
      [action, limit]
    );

    return result.rows;
  }
}

export default new AuditService();

