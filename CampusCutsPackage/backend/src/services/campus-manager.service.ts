/**
 * Campus Manager Service
 * 
 * Handles Campus Manager role management and permissions
 * Enforces rule: Only ONE Campus Manager per campus
 */

import { pool } from '../database/connection';
import { logger } from '../utils/logger';

export class CampusManagerService {
  /**
   * Check if a barber is a Campus Manager
   * Checks BOTH barbers.isCampusManager AND users.role = 'CAMPUS_MANAGER'
   */
  async isCampusManager(barberId: string): Promise<boolean> {
    try {
      const result = await pool.query(`
        SELECT 
          b."isCampusManager",
          u.role
        FROM barbers b
        JOIN users u ON b."userId" = u.id
        WHERE b.id = $1
      `, [barberId]);
      
      if (result.rows.length === 0) return false;
      
      const row = result.rows[0];
      return row.isCampusManager === true || row.role === 'CAMPUS_MANAGER';
    } catch (error) {
      logger.error('Error checking Campus Manager status:', error);
      throw error;
    }
  }

  /**
   * Get Campus Manager for a specific campus
   * Checks BOTH barbers.isCampusManager AND users.role = 'CAMPUS_MANAGER'
   */
  async getCampusManager(campusId: string): Promise<{
    barberId: string | null;
    userId: string;
    displayName: string;
    since: Date | null;
  } | null> {
    try {
      // First try to find by barbers.isCampusManager
      const barberResult = await pool.query(`
        SELECT 
          b.id as barber_id,
          b."userId" as user_id,
          COALESCE(u."displayName", u.first_name || ' ' || u.last_name) as display_name,
          b."createdAt" as campus_manager_since
        FROM barbers b
        INNER JOIN users u ON b."userId" = u.id
        WHERE 
          b."campusId" = $1 
          AND b."isCampusManager" = true
          AND b."isActive" = true
      `, [campusId]);

      if (barberResult.rows.length > 0) {
        return {
          barberId: barberResult.rows[0].barber_id,
          userId: barberResult.rows[0].user_id,
          displayName: barberResult.rows[0].display_name,
          since: barberResult.rows[0].campus_manager_since,
        };
      }

      // Fall back to users with role = CAMPUS_MANAGER
      const userResult = await pool.query(`
        SELECT 
          u.id as user_id,
          COALESCE(u."displayName", u.first_name || ' ' || u.last_name) as display_name,
          b.id as barber_id,
          b."createdAt" as campus_manager_since
        FROM users u
        LEFT JOIN barbers b ON b."userId" = u.id
        WHERE 
          u."campusId" = $1 
          AND u.role = 'CAMPUS_MANAGER'
      `, [campusId]);

      if (userResult.rows.length > 0) {
        return {
          barberId: userResult.rows[0].barber_id,
          userId: userResult.rows[0].user_id,
          displayName: userResult.rows[0].display_name,
          since: userResult.rows[0].campus_manager_since,
        };
      }

      return null;
    } catch (error) {
      logger.error('Error fetching Campus Manager:', error);
      throw error;
    }
  }

  /**
   * Promote a barber to Campus Manager
   * Uses PostgreSQL function to enforce uniqueness constraint
   */
  async promoteToCampusManager(
    barberId: string,
    campusId: string
  ): Promise<{ success: boolean; error?: string }> {
    try {
      // Verify barber belongs to this campus and is active
      const barberCheck = await pool.query(`
        SELECT id, campus_id, is_active, is_onboarded
        FROM barbers
        WHERE id = $1 AND campus_id = $2
      `, [barberId, campusId]);

      if (barberCheck.rows.length === 0) {
        return {
          success: false,
          error: 'Barber not found or does not belong to this campus',
        };
      }

      const barber = barberCheck.rows[0];
      if (!barber.is_active || !barber.is_onboarded) {
        return {
          success: false,
          error: 'Barber must be active and onboarded to become Campus Manager',
        };
      }

      // Use PostgreSQL function to safely promote
      const result = await pool.query(
        'SELECT promote_to_campus_manager($1, $2) as success',
        [barberId, campusId]
      );

      logger.info('Barber promoted to Campus Manager', {
        barberId,
        campusId,
      });

      return { success: result.rows[0].success };
    } catch (error: any) {
      logger.error('Error promoting to Campus Manager:', error);
      
      // Handle unique constraint violation
      if (error.message?.includes('already has a Campus Manager')) {
        return {
          success: false,
          error: 'This campus already has a Campus Manager',
        };
      }

      throw error;
    }
  }

  /**
   * Revoke Campus Manager role
   */
  async revokeCampusManager(barberId: string): Promise<boolean> {
    try {
      const result = await pool.query(
        'SELECT revoke_campus_manager($1) as success',
        [barberId]
      );

      logger.info('Campus Manager role revoked', { barberId });
      return result.rows[0].success;
    } catch (error) {
      logger.error('Error revoking Campus Manager:', error);
      throw error;
    }
  }

  /**
   * Get Campus Manager permissions/scopes
   */
  getCampusManagerPermissions(): string[] {
    return [
      'manage_barber_applications',
      'view_campus_metrics',
      'upload_campus_content',
      'flag_incidents',
      'escalate_to_admin',
    ];
  }

  /**
   * Verify Campus Manager has permission for an action on a specific campus
   * Note: Admins have campus manager privileges at ALL campuses
   */
  async verifyPermission(
    barberId: string,
    campusId: string,
    action: string,
    userId?: string
  ): Promise<boolean> {
    try {
      // First check if user is an admin (admins have campus manager permissions at all campuses)
      if (userId) {
        const adminCheck = await pool.query(
          'SELECT role FROM users WHERE id = $1',
          [userId]
        );
        if (adminCheck.rows.length > 0 && adminCheck.rows[0].role === 'ADMIN') {
          // Admins have all campus manager permissions at all campuses
          const allowedPermissions = this.getCampusManagerPermissions();
          return allowedPermissions.includes(action);
        }
      }

      // Check if barber is Campus Manager for this campus
      // Check BOTH barbers.isCampusManager AND users.role = 'CAMPUS_MANAGER'
      const result = await pool.query(`
        SELECT b.id
        FROM barbers b
        JOIN users u ON b."userId" = u.id
        WHERE 
          b.id = $1 
          AND b."campusId" = $2 
          AND (b."isCampusManager" = true OR u.role = 'CAMPUS_MANAGER')
          AND b."isActive" = true
      `, [barberId, campusId]);

      if (result.rows.length === 0) {
        logger.warn('Permission denied: Not Campus Manager', {
          barberId,
          campusId,
          action,
        });
        return false;
      }

      // Verify action is in allowed permissions
      const allowedPermissions = this.getCampusManagerPermissions();
      return allowedPermissions.includes(action);
    } catch (error) {
      logger.error('Error verifying Campus Manager permission:', error);
      return false;
    }
  }
  
  /**
   * Check if a user is an admin (admin has campus manager privileges at all campuses)
   */
  async isAdmin(userId: string): Promise<boolean> {
    try {
      const result = await pool.query(
        'SELECT role FROM users WHERE id = $1',
        [userId]
      );
      return result.rows[0]?.role === 'ADMIN';
    } catch (error) {
      logger.error('Error checking admin status:', error);
      return false;
    }
  }
}

export const campusManagerService = new CampusManagerService();

