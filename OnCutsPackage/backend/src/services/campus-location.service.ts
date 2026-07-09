/**
 * Campus Location Service
 * 
 * Purpose: Core business logic for campus location management
 * Responsibilities:
 * - Location submission and deduplication
 * - Usage tracking and confidence scoring
 * - Automatic promotion to verified status
 * - Location retrieval for barber scheduling
 */

import { Pool } from 'pg';
import { TextNormalizationService } from './text-normalization.service';
import { LocationFuzzyMatchingService } from './location-fuzzy-matching.service';
import { logger } from '../utils/logger';

interface SubmitLocationParams {
  universityId: string;
  locationName: string;
  category: 'ON_CAMPUS' | 'OFF_CAMPUS' | 'DORM' | 'APARTMENT' | 'COMMON_AREA' | 'OTHER';
  userId?: string;
}

interface CampusLocation {
  id: string;
  universityId: string;
  name: string;
  normalizedName: string;
  category: string;
  cohort: string;
  usageCount: number;
  confidence: number;
  isVerified: boolean;
  createdAt: Date;
  updatedAt: Date;
}

interface LocationSelectionOption extends CampusLocation {
  aliases?: string[];
  matchedVia?: string;
}

export class CampusLocationService {
  private pool: Pool;
  private fuzzyMatcher: LocationFuzzyMatchingService;

  // Promotion thresholds
  private readonly VERIFICATION_USAGE_THRESHOLD = 5;
  private readonly VERIFICATION_CONFIDENCE_THRESHOLD = 0.8;

  // Confidence adjustments
  private readonly USAGE_CONFIDENCE_BOOST = 0.05;
  private readonly MAX_CONFIDENCE = 1.0;

  constructor(pool: Pool) {
    this.pool = pool;
    this.fuzzyMatcher = new LocationFuzzyMatchingService(pool);
  }

  /**
   * Submit a location from a barber
   * 
   * Flow:
   * 1. Normalize input
   * 2. Check for duplicates via fuzzy matching
   * 3. If match found → increment usage
   * 4. If no match → create new location
   * 5. Check for auto-promotion to verified
   * 6. Queue for AI enrichment if needed
   */
  async submitLocation(params: SubmitLocationParams): Promise<CampusLocation> {
    const { universityId, locationName, category, userId } = params;

    // Step 1: Normalize
    const cleanName = TextNormalizationService.cleanLocationName(locationName);
    const normalizedName = TextNormalizationService.normalizeForMatching(cleanName);

    logger.info('Processing location submission', {
      universityId,
      originalName: locationName,
      cleanName,
      normalizedName,
      category,
    });

    // Step 2: Check for duplicates
    const matches = await this.fuzzyMatcher.findMatches(universityId, cleanName, category);

    if (matches.length > 0) {
      const bestMatch = matches[0];
      logger.info('Found existing location match', {
        matchedLocationId: bestMatch.location.id,
        similarity: bestMatch.similarity,
        matchReason: bestMatch.matchReason,
      });

      // Increment usage
      const updated = await this.incrementUsage(bestMatch.location.id);

      // Check for promotion
      await this.checkAndPromoteLocation(updated);

      return this.mapToLocationDTO(updated);
    }

    // Step 3: No match found, create new location
    logger.info('Creating new location', { universityId, cleanName, category });

    const newLocation = await this.createLocation({
      universityId,
      name: cleanName,
      normalizedName,
      category,
      userId,
    });

    // Step 4: Queue for AI enrichment
    await this.queueForAIEnrichment(newLocation.id);

    return this.mapToLocationDTO(newLocation);
  }

  /**
   * Create a new campus location
   */
  private async createLocation(data: {
    universityId: string;
    name: string;
    normalizedName: string;
    category: string;
    userId?: string;
  }) {
    const result = await this.pool.query(
      `INSERT INTO campus_locations (
        university_id,
        name,
        normalized_name,
        category,
        created_by_user_id
      ) VALUES ($1, $2, $3, $4, $5)
      RETURNING *`,
      [data.universityId, data.name, data.normalizedName, data.category, data.userId || null]
    );

    return result.rows[0];
  }

  /**
   * Increment usage count and boost confidence
   */
  private async incrementUsage(locationId: string) {
    const result = await this.pool.query(
      `UPDATE campus_locations
       SET 
         usage_count = usage_count + 1,
         confidence = LEAST($1, confidence + $2),
         updated_at = NOW()
       WHERE id = $3
       RETURNING *`,
      [this.MAX_CONFIDENCE, this.USAGE_CONFIDENCE_BOOST, locationId]
    );

    logger.info('Incremented location usage', {
      locationId,
      newUsageCount: result.rows[0].usage_count,
      newConfidence: result.rows[0].confidence,
    });

    return result.rows[0];
  }

  /**
   * Check if location meets verification criteria and promote if eligible
   */
  private async checkAndPromoteLocation(location: any): Promise<void> {
    if (location.is_verified) {
      return; // Already verified
    }

    const meetsUsageThreshold = location.usage_count >= this.VERIFICATION_USAGE_THRESHOLD;
    const meetsConfidenceThreshold = location.confidence >= this.VERIFICATION_CONFIDENCE_THRESHOLD;
    const hasCohort = location.cohort && location.cohort !== 'UNKNOWN';

    if (meetsUsageThreshold && meetsConfidenceThreshold && hasCohort) {
      await this.pool.query(
        `UPDATE campus_locations
         SET is_verified = TRUE, updated_at = NOW()
         WHERE id = $1`,
        [location.id]
      );

      logger.info('Location promoted to verified', {
        locationId: location.id,
        name: location.name,
        usageCount: location.usage_count,
        confidence: location.confidence,
        cohort: location.cohort,
      });
    }
  }

  /**
   * Get locations for selection UI (for barbers scheduling)
   * 
   * Returns:
   * - Verified locations first
   * - High-confidence locations next
   * - All locations sorted by usage
   */
  async getLocationsForSelection(universityId: string, category?: string): Promise<LocationSelectionOption[]> {
    let query = `
      SELECT cl.*, 
        ARRAY_AGG(DISTINCT cla.alias) FILTER (WHERE cla.alias IS NOT NULL) as aliases
      FROM campus_locations cl
      LEFT JOIN campus_location_aliases cla ON cla.campus_location_id = cl.id
      WHERE cl.university_id = $1
    `;
    const params: any[] = [universityId];

    if (category) {
      query += ` AND cl.category = $2`;
      params.push(category);
    }

    query += `
      GROUP BY cl.id
      ORDER BY 
        cl.is_verified DESC,
        cl.confidence DESC,
        cl.usage_count DESC
      LIMIT 100
    `;

    const result = await this.pool.query(query, params);
    return result.rows.map(row => this.mapToLocationDTO(row));
  }

  /**
   * Search locations by name (for autocomplete)
   */
  async searchLocations(universityId: string, query: string, limit: number = 10): Promise<LocationSelectionOption[]> {
    const normalized = TextNormalizationService.normalizeForMatching(query);
    const searchPattern = `%${normalized}%`;

    const result = await this.pool.query(
      `SELECT cl.*,
        ARRAY_AGG(DISTINCT cla.alias) FILTER (WHERE cla.alias IS NOT NULL) as aliases
       FROM campus_locations cl
       LEFT JOIN campus_location_aliases cla ON cla.campus_location_id = cl.id
       WHERE cl.university_id = $1
       AND (
         cl.normalized_name LIKE $2
         OR EXISTS (
           SELECT 1 FROM campus_location_aliases cla2
           WHERE cla2.campus_location_id = cl.id
           AND cla2.normalized_alias LIKE $2
         )
       )
       GROUP BY cl.id
       ORDER BY cl.is_verified DESC, cl.confidence DESC, cl.usage_count DESC
       LIMIT $3`,
      [universityId, searchPattern, limit]
    );

    return result.rows.map(row => this.mapToLocationDTO(row));
  }

  /**
   * Get a single location by ID
   */
  async getLocationById(locationId: string): Promise<CampusLocation | null> {
    const result = await this.pool.query(
      `SELECT * FROM campus_locations WHERE id = $1`,
      [locationId]
    );

    if (result.rows.length === 0) return null;
    return this.mapToLocationDTO(result.rows[0]);
  }

  /**
   * Add an alias to a location
   * 
   * Called by AI enrichment worker
   */
  async addAlias(locationId: string, alias: string): Promise<void> {
    const cleanAlias = TextNormalizationService.cleanLocationName(alias);
    const normalizedAlias = TextNormalizationService.normalizeForMatching(cleanAlias);

    try {
      await this.pool.query(
        `INSERT INTO campus_location_aliases (campus_location_id, alias, normalized_alias)
         VALUES ($1, $2, $3)
         ON CONFLICT (campus_location_id, normalized_alias) DO NOTHING`,
        [locationId, cleanAlias, normalizedAlias]
      );

      logger.info('Added alias to location', { locationId, alias: cleanAlias });
    } catch (error) {
      logger.error('Failed to add alias', { locationId, alias, error });
    }
  }

  /**
   * Update location category and cohort
   * 
   * Called by AI enrichment worker
   */
  async updateLocationClassification(
    locationId: string,
    category?: string,
    cohort?: string,
    confidenceBoost?: number
  ): Promise<void> {
    const updates: string[] = [];
    const params: any[] = [];
    let paramIndex = 1;

    if (category) {
      updates.push(`category = $${paramIndex++}`);
      params.push(category);
    }

    if (cohort) {
      updates.push(`cohort = $${paramIndex++}`);
      params.push(cohort);
    }

    if (confidenceBoost !== undefined) {
      updates.push(`confidence = LEAST(${this.MAX_CONFIDENCE}, confidence + $${paramIndex++})`);
      params.push(confidenceBoost);
    }

    if (updates.length === 0) return;

    updates.push(`updated_at = NOW()`);
    params.push(locationId);

    await this.pool.query(
      `UPDATE campus_locations SET ${updates.join(', ')} WHERE id = $${paramIndex}`,
      params
    );

    logger.info('Updated location classification', { locationId, category, cohort, confidenceBoost });

    // Check for promotion after classification update
    const updated = await this.getLocationById(locationId);
    if (updated) {
      await this.checkAndPromoteLocation(updated);
    }
  }

  /**
   * Merge two locations (deduplication)
   * 
   * Called by admin or automatic deduplication
   */
  async mergeLocations(sourceId: string, targetId: string, reason: string, adminId?: string): Promise<void> {
    const client = await this.pool.connect();

    try {
      await client.query('BEGIN');

      // Transfer usage count
      await client.query(
        `UPDATE campus_locations
         SET usage_count = usage_count + (SELECT usage_count FROM campus_locations WHERE id = $1),
             updated_at = NOW()
         WHERE id = $2`,
        [sourceId, targetId]
      );

      // Transfer aliases
      await client.query(
        `UPDATE campus_location_aliases
         SET campus_location_id = $2
         WHERE campus_location_id = $1
         ON CONFLICT (campus_location_id, normalized_alias) DO NOTHING`,
        [sourceId, targetId]
      );

      // Log the merge
      await client.query(
        `INSERT INTO location_merge_log (source_location_id, target_location_id, merged_by_user_id, merge_reason)
         VALUES ($1, $2, $3, $4)`,
        [sourceId, targetId, adminId || null, reason]
      );

      // Delete source location
      await client.query(`DELETE FROM campus_locations WHERE id = $1`, [sourceId]);

      await client.query('COMMIT');

      logger.info('Merged locations', { sourceId, targetId, reason });
    } catch (error) {
      await client.query('ROLLBACK');
      logger.error('Failed to merge locations', { sourceId, targetId, error });
      throw error;
    } finally {
      client.release();
    }
  }

  /**
   * Queue location for AI enrichment
   * 
   * Triggers BullMQ job for async processing
   */
  private async queueForAIEnrichment(locationId: string): Promise<void> {
    // TODO: Integrate with BullMQ when AI enrichment worker is built
    logger.info('Location queued for AI enrichment', { locationId });
  }

  /**
   * Map database row to DTO
   */
  private mapToLocationDTO(row: any): any {
    return {
      id: row.id,
      universityId: row.university_id,
      name: row.name,
      normalizedName: row.normalized_name,
      category: row.category,
      cohort: row.cohort,
      usageCount: row.usage_count,
      confidence: parseFloat(row.confidence),
      isVerified: row.is_verified,
      createdAt: row.created_at,
      updatedAt: row.updated_at,
      aliases: row.aliases || [],
    };
  }
}

