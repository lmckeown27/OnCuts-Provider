/**
 * Metrics Aggregation Service
 * 
 * Aggregates raw booking data into structured barber metrics for pricing calculations.
 * Runs daily to compute:
 * - Booking counts (total, completed, canceled, no-shows)
 * - Quality metrics (ratings, repeat customers)
 * - Reliability metrics (on-time %, no-show %, cancel %)
 */

import { logger } from '../../utils/logger';
import { pool } from '../../database/connection';
import { startOfDay, endOfDay, subDays, format } from 'date-fns';

export interface BarberMetric {
  barberId: string;
  periodDate: Date;
  numBookings: number;
  numCompletedBookings: number;
  numCanceledBookings: number;
  numNoShows: number;
  avgRating: number | null;
  totalRatings: number;
  numRepeatCustomers: number;
  numUniqueCustomers: number;
  repeatRate: number;
  numOnTime: number;
  onTimePct: number;
  noShowPct: number;
  canceledPct: number;
}

export interface DateRange {
  start: Date;
  end: Date;
}

class MetricsAggregatorService {
  /**
   * Aggregate metrics for a single barber for a specific date
   */
  async aggregateBarberMetrics(
    barberId: string,
    periodDate: Date
  ): Promise<BarberMetric> {
    const windowStart = startOfDay(periodDate);
    const windowEnd = endOfDay(periodDate);

    logger.info(`Aggregating metrics for barber ${barberId} on ${format(periodDate, 'yyyy-MM-dd')}`);

    // Aggregate booking counts
    const bookingCounts = await this.getBookingCounts(barberId, windowStart, windowEnd);
    
    // Calculate quality metrics
    const qualityMetrics = await this.getQualityMetrics(barberId, windowStart, windowEnd);
    
    // Calculate reliability metrics
    const reliabilityMetrics = await this.getReliabilityMetrics(barberId, windowStart, windowEnd);

    const metric: BarberMetric = {
      barberId,
      periodDate,
      ...bookingCounts,
      ...qualityMetrics,
      ...reliabilityMetrics,
    };

    // Persist to database
    await this.saveMetric(metric);

    return metric;
  }

  /**
   * Aggregate metrics for all active barbers for a specific date
   */
  async aggregateDailyMetricsForAllBarbers(periodDate: Date = new Date()): Promise<void> {
    logger.info(`Starting daily metrics aggregation for ${format(periodDate, 'yyyy-MM-dd')}`);

    try {
      // Get all active barbers
      const barbers = await this.getActiveBarbers();
      logger.info(`Found ${barbers.length} active barbers to process`);

      let processed = 0;
      let errors = 0;

      for (const barber of barbers) {
        try {
          await this.aggregateBarberMetrics(barber.id, periodDate);
          processed++;
        } catch (error) {
          logger.error(`Failed to aggregate metrics for barber ${barber.id}:`, error);
          errors++;
        }
      }

      logger.info(`Daily metrics aggregation complete. Processed: ${processed}, Errors: ${errors}`);
    } catch (error) {
      logger.error('Daily metrics aggregation failed:', error);
      throw error;
    }
  }

  /**
   * Get booking counts for a barber in a time window
   */
  private async getBookingCounts(
    barberId: string,
    windowStart: Date,
    windowEnd: Date
  ): Promise<{
    numBookings: number;
    numCompletedBookings: number;
    numCanceledBookings: number;
    numNoShows: number;
  }> {
    const result = await pool.query(
      `
      SELECT
        COUNT(*) FILTER (WHERE status IN ('completed', 'canceled', 'no_show')) as num_bookings,
        COUNT(*) FILTER (WHERE status = 'completed') as num_completed_bookings,
        COUNT(*) FILTER (WHERE status = 'canceled') as num_canceled_bookings,
        COUNT(*) FILTER (WHERE status = 'no_show') as num_no_shows
      FROM bookings
      WHERE barber_id = $1
        AND created_at >= $2
        AND created_at < $3
      `,
      [barberId, windowStart, windowEnd]
    );

    return {
      numBookings: parseInt(result.rows[0].num_bookings) || 0,
      numCompletedBookings: parseInt(result.rows[0].num_completed_bookings) || 0,
      numCanceledBookings: parseInt(result.rows[0].num_canceled_bookings) || 0,
      numNoShows: parseInt(result.rows[0].num_no_shows) || 0,
    };
  }

  /**
   * Calculate quality metrics (ratings, repeat rate)
   */
  private async getQualityMetrics(
    barberId: string,
    windowStart: Date,
    windowEnd: Date
  ): Promise<{
    avgRating: number | null;
    totalRatings: number;
    numRepeatCustomers: number;
    numUniqueCustomers: number;
    repeatRate: number;
  }> {
    // Get average rating
    const ratingResult = await pool.query(
      `
      SELECT
        AVG(rating) as avg_rating,
        COUNT(*) as total_ratings
      FROM reviews
      WHERE barber_id = $1
        AND created_at >= $2
        AND created_at < $3
      `,
      [barberId, windowStart, windowEnd]
    );

    const avgRating = ratingResult.rows[0].avg_rating
      ? parseFloat(parseFloat(ratingResult.rows[0].avg_rating).toFixed(2))
      : null;
    const totalRatings = parseInt(ratingResult.rows[0].total_ratings) || 0;

    // Get repeat customer rate
    const repeatResult = await pool.query(
      `
      WITH customer_booking_counts AS (
        SELECT
          student_id,
          COUNT(*) as booking_count
        FROM bookings
        WHERE barber_id = $1
          AND status = 'completed'
          AND created_at >= $2
          AND created_at < $3
        GROUP BY student_id
      )
      SELECT
        COUNT(*) FILTER (WHERE booking_count > 1) as num_repeat_customers,
        COUNT(*) as num_unique_customers
      FROM customer_booking_counts
      `,
      [barberId, windowStart, windowEnd]
    );

    const numRepeatCustomers = parseInt(repeatResult.rows[0].num_repeat_customers) || 0;
    const numUniqueCustomers = parseInt(repeatResult.rows[0].num_unique_customers) || 0;
    const repeatRate = numUniqueCustomers > 0
      ? parseFloat((numRepeatCustomers / numUniqueCustomers).toFixed(4))
      : 0;

    return {
      avgRating,
      totalRatings,
      numRepeatCustomers,
      numUniqueCustomers,
      repeatRate,
    };
  }

  /**
   * Calculate reliability metrics (on-time %, no-show %, canceled %)
   */
  private async getReliabilityMetrics(
    barberId: string,
    windowStart: Date,
    windowEnd: Date
  ): Promise<{
    numOnTime: number;
    onTimePct: number;
    noShowPct: number;
    canceledPct: number;
  }> {
    // Note: In a real implementation, we'd check actual checkin times vs scheduled times
    // For now, we'll use a simplified calculation based on completed vs total bookings
    
    const result = await pool.query(
      `
      WITH booking_stats AS (
        SELECT
          COUNT(*) FILTER (WHERE status = 'completed') as completed,
          COUNT(*) FILTER (WHERE status = 'no_show') as no_shows,
          COUNT(*) FILTER (WHERE status = 'canceled') as canceled,
          COUNT(*) FILTER (WHERE status IN ('completed', 'no_show', 'canceled')) as total
        FROM bookings
        WHERE barber_id = $1
          AND scheduled_time >= $2
          AND scheduled_time < $3
      )
      SELECT
        completed as num_on_time,
        CASE WHEN total > 0 THEN completed::decimal / total ELSE 0 END as on_time_pct,
        CASE WHEN total > 0 THEN no_shows::decimal / total ELSE 0 END as no_show_pct,
        CASE WHEN total > 0 THEN canceled::decimal / total ELSE 0 END as canceled_pct
      FROM booking_stats
      `,
      [barberId, windowStart, windowEnd]
    );

    if (result.rows.length === 0) {
      return {
        numOnTime: 0,
        onTimePct: 0,
        noShowPct: 0,
        canceledPct: 0,
      };
    }

    return {
      numOnTime: parseInt(result.rows[0].num_on_time) || 0,
      onTimePct: parseFloat(parseFloat(result.rows[0].on_time_pct).toFixed(4)),
      noShowPct: parseFloat(parseFloat(result.rows[0].no_show_pct).toFixed(4)),
      canceledPct: parseFloat(parseFloat(result.rows[0].canceled_pct).toFixed(4)),
    };
  }

  /**
   * Save metric to database
   */
  private async saveMetric(metric: BarberMetric): Promise<void> {
    await pool.query(
      `
      INSERT INTO barber_metrics (
        barber_id,
        window_start,
        window_end,
        period_date,
        num_bookings,
        num_completed_bookings,
        num_canceled_bookings,
        num_no_shows,
        avg_rating,
        total_ratings,
        num_repeat_customers,
        num_unique_customers,
        repeat_rate,
        num_on_time,
        on_time_pct,
        no_show_pct,
        canceled_pct
      ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17)
      ON CONFLICT (barber_id, period_date)
      DO UPDATE SET
        window_start = EXCLUDED.window_start,
        window_end = EXCLUDED.window_end,
        num_bookings = EXCLUDED.num_bookings,
        num_completed_bookings = EXCLUDED.num_completed_bookings,
        num_canceled_bookings = EXCLUDED.num_canceled_bookings,
        num_no_shows = EXCLUDED.num_no_shows,
        avg_rating = EXCLUDED.avg_rating,
        total_ratings = EXCLUDED.total_ratings,
        num_repeat_customers = EXCLUDED.num_repeat_customers,
        num_unique_customers = EXCLUDED.num_unique_customers,
        repeat_rate = EXCLUDED.repeat_rate,
        num_on_time = EXCLUDED.num_on_time,
        on_time_pct = EXCLUDED.on_time_pct,
        no_show_pct = EXCLUDED.no_show_pct,
        canceled_pct = EXCLUDED.canceled_pct
      `,
      [
        metric.barberId,
        startOfDay(metric.periodDate),
        endOfDay(metric.periodDate),
        format(metric.periodDate, 'yyyy-MM-dd'),
        metric.numBookings,
        metric.numCompletedBookings,
        metric.numCanceledBookings,
        metric.numNoShows,
        metric.avgRating,
        metric.totalRatings,
        metric.numRepeatCustomers,
        metric.numUniqueCustomers,
        metric.repeatRate,
        metric.numOnTime,
        metric.onTimePct,
        metric.noShowPct,
        metric.canceledPct,
      ]
    );
  }

  /**
   * Get all active barbers
   */
  private async getActiveBarbers(): Promise<Array<{ id: string }>> {
    const result = await pool.query(
      `
      SELECT id
      FROM barbers
      WHERE is_active = true
      `
    );

    return result.rows;
  }

  /**
   * Get metrics for a barber over a date range (for historical analysis)
   */
  async getBarberMetricsHistory(
    barberId: string,
    startDate: Date,
    endDate: Date
  ): Promise<BarberMetric[]> {
    const result = await pool.query(
      `
      SELECT
        barber_id,
        period_date,
        num_bookings,
        num_completed_bookings,
        num_canceled_bookings,
        num_no_shows,
        avg_rating,
        total_ratings,
        num_repeat_customers,
        num_unique_customers,
        repeat_rate,
        num_on_time,
        on_time_pct,
        no_show_pct,
        canceled_pct
      FROM barber_metrics
      WHERE barber_id = $1
        AND period_date >= $2
        AND period_date <= $3
      ORDER BY period_date ASC
      `,
      [barberId, format(startDate, 'yyyy-MM-dd'), format(endDate, 'yyyy-MM-dd')]
    );

    return result.rows.map(row => ({
      barberId: row.barber_id,
      periodDate: new Date(row.period_date),
      numBookings: row.num_bookings,
      numCompletedBookings: row.num_completed_bookings,
      numCanceledBookings: row.num_canceled_bookings,
      numNoShows: row.num_no_shows,
      avgRating: row.avg_rating ? parseFloat(row.avg_rating) : null,
      totalRatings: row.total_ratings,
      numRepeatCustomers: row.num_repeat_customers,
      numUniqueCustomers: row.num_unique_customers,
      repeatRate: parseFloat(row.repeat_rate),
      numOnTime: row.num_on_time,
      onTimePct: parseFloat(row.on_time_pct),
      noShowPct: parseFloat(row.no_show_pct),
      canceledPct: parseFloat(row.canceled_pct),
    }));
  }
}

export default new MetricsAggregatorService();

