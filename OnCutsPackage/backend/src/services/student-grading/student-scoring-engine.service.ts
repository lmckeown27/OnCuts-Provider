/**
 * Student Scoring Engine Service
 * 
 * Scores students/consumers based on their behavior in the marketplace.
 * STRICTER than barber scoring to maintain marketplace quality.
 * 
 * Score Components:
 * 1. Review Fairness (40% weight) - Are they fair or overly harsh?
 * 2. Attendance Reliability (40% weight) - Do they show up?
 * 3. Platform Engagement (20% weight) - Are they active, loyal users?
 */

import { logger } from '../../utils/logger';
import { pool } from '../../database/connection';
import Decimal from 'decimal.js';

export interface StudentGradingConfig {
  reviewFairnessWeight: number;
  attendanceWeight: number;
  engagementWeight: number;
  avgRatingWeight: number;
  reviewRateWeight: number;
  showUpWeight: number;
  noCancelWeight: number;
  harshReviewerThreshold: number;
  excessiveNoShowThreshold: number;
  excessiveCancelThreshold: number;
  newStudentBookingThreshold: number;
  autoFlagScoreThreshold: number;
  autoRestrictScoreThreshold: number;
}

export interface StudentMetric {
  studentId: string;
  periodDate: Date;
  numBookings: number;
  numCompletedBookings: number;
  numCanceledBookings: number;
  numNoShows: number;
  attendanceRate: number;
  noShowRate: number;
  cancellationRate: number;
  sameDayCancelRate: number;
  numReviewsGiven: number;
  num5StarReviews: number;
  num4StarReviews: number;
  num3StarReviews: number;
  num2StarReviews: number;
  num1StarReviews: number;
  avgRatingGiven: number | null;
  reviewRate: number;
  numUniqueBarbers: number;
  numRepeatBookings: number;
  loyaltyRate: number;
  avgDaysBetweenBookings: number | null;
  totalSpentCents: number;
  avgTipPct: number;
  numComplaintsFiled: number;
  numComplaintsReceived: number;
}

export interface StudentScore {
  studentId: string;
  periodDate: Date;
  reviewFairnessScore: number;
  attendanceScore: number;
  engagementScore: number;
  customerScore: number;
  isNewStudent: boolean;
  totalLifetimeBookings: number;
  isFlagged: boolean;
  flagReason: string | null;
  breakdown: any;
}

class StudentScoringEngineService {
  /**
   * Calculate all scores for a student
   */
  async calculateStudentScore(
    studentId: string,
    metric: StudentMetric,
    periodDate: Date
  ): Promise<StudentScore> {
    logger.info(`Calculating customer score for student ${studentId}`);

    const config = await this.loadConfig();
    const totalLifetimeBookings = await this.getTotalLifetimeBookings(studentId);
    const isNewStudent = totalLifetimeBookings < config.newStudentBookingThreshold;

    // Calculate component scores
    const reviewFairnessScore = this.calculateReviewFairnessScore(metric, config);
    const attendanceScore = this.calculateAttendanceScore(metric, config);
    const engagementScore = this.calculateEngagementScore(metric, config);

    // Calculate weighted customer score
    const customerScore = this.calculateCustomerScore(
      reviewFairnessScore,
      attendanceScore,
      engagementScore,
      config
    );

    // Check for auto-flagging
    const { isFlagged, flagReason } = this.checkForAutoFlag(metric, customerScore, config);

    const score: StudentScore = {
      studentId,
      periodDate,
      reviewFairnessScore,
      attendanceScore,
      engagementScore,
      customerScore,
      isNewStudent,
      totalLifetimeBookings,
      isFlagged,
      flagReason,
      breakdown: {
        reviewFairnessScore,
        attendanceScore,
        engagementScore,
        customerScore,
        weights: {
          reviewFairness: config.reviewFairnessWeight,
          attendance: config.attendanceWeight,
          engagement: config.engagementWeight,
        },
        isNewStudent,
        isFlagged,
        flags: flagReason ? [flagReason] : [],
      },
    };

    // Save to database
    await this.saveScore(score);

    // Handle auto-restrictions if score is critically low
    if (customerScore < config.autoRestrictScoreThreshold) {
      await this.applyAutoRestrictions(studentId, customerScore);
    }

    return score;
  }

  /**
   * Calculate Review Fairness Score (0-100)
   * HARSH PENALTY for students who are overly critical or don't review
   */
  calculateReviewFairnessScore(metric: StudentMetric, config: StudentGradingConfig): number {
    if (metric.numBookings === 0) {
      return 50.0; // Neutral for new students
    }

    // Calculate average rating they give to barbers
    const avgRatingGiven = metric.avgRatingGiven || 3.0; // Default to neutral if no reviews

    // Normalize avg rating from 1-5 scale to 0-100 scale
    // Optimal is 4.0-4.5 (fair but not too easy)
    // Penalize both harsh (< 3.5) and overly easy (> 4.8) raters
    let ratingFairnessScore: number;

    if (avgRatingGiven >= 3.8 && avgRatingGiven <= 4.6) {
      // Optimal range - give high score
      ratingFairnessScore = 100;
    } else if (avgRatingGiven < config.harshReviewerThreshold) {
      // HARSH REVIEWER - significant penalty
      // < 3.5 average = they're too critical
      const distance = config.harshReviewerThreshold - avgRatingGiven;
      ratingFairnessScore = Math.max(0, 50 - (distance * 30)); // Heavy penalty
    } else if (avgRatingGiven > 4.8) {
      // Too easy - minor penalty (they rate everyone 5 stars = useless)
      ratingFairnessScore = 85;
    } else {
      // Slightly outside optimal range - small penalty
      const distanceFromOptimal = Math.min(
        Math.abs(avgRatingGiven - 3.8),
        Math.abs(avgRatingGiven - 4.6)
      );
      ratingFairnessScore = 100 - (distanceFromOptimal * 20);
    }

    // Calculate review rate score
    // Students should leave reviews (but it's less important than fairness)
    const reviewRateScore = metric.reviewRate * 100;

    // Weighted combination
    const fairnessScore = new Decimal(ratingFairnessScore)
      .times(config.avgRatingWeight)
      .plus(new Decimal(reviewRateScore).times(config.reviewRateWeight))
      .toDecimalPlaces(2)
      .toNumber();

    return Math.max(0, Math.min(100, fairnessScore));
  }

  /**
   * Calculate Attendance Score (0-100)
   * VERY HARSH on no-shows and cancellations
   */
  calculateAttendanceScore(metric: StudentMetric, config: StudentGradingConfig): number {
    if (metric.numBookings === 0) {
      return 50.0; // Neutral for new students
    }

    // Show-up score (inverse of no-show rate)
    // NO-SHOWS ARE HEAVILY PENALIZED
    let showUpScore: number;
    if (metric.noShowRate === 0) {
      showUpScore = 100; // Perfect
    } else if (metric.noShowRate > config.excessiveNoShowThreshold) {
      // > 15% no-shows = CRITICAL PROBLEM
      const excess = metric.noShowRate - config.excessiveNoShowThreshold;
      showUpScore = Math.max(0, 20 - (excess * 100)); // Very harsh penalty
    } else {
      // < 15% but not perfect
      showUpScore = new Decimal(1)
        .minus(metric.noShowRate)
        .times(100)
        .toNumber();
    }

    // Cancellation score
    // Cancellations are bad but less bad than no-shows
    let noCancelScore: number;
    if (metric.cancellationRate === 0) {
      noCancelScore = 100; // Perfect
    } else if (metric.cancellationRate > config.excessiveCancelThreshold) {
      // > 25% cancellations = PROBLEM
      const excess = metric.cancellationRate - config.excessiveCancelThreshold;
      noCancelScore = Math.max(0, 40 - (excess * 100)); // Harsh penalty
    } else {
      noCancelScore = new Decimal(1)
        .minus(metric.cancellationRate)
        .times(100)
        .toNumber();
    }

    // Extra penalty for same-day cancellations
    if (metric.sameDayCancelRate > 0.10) {
      // > 10% same-day cancels = additional penalty
      noCancelScore = Math.max(0, noCancelScore - (metric.sameDayCancelRate * 50));
    }

    // Weighted combination
    const attendanceScore = new Decimal(showUpScore)
      .times(config.showUpWeight)
      .plus(new Decimal(noCancelScore).times(config.noCancelWeight))
      .toDecimalPlaces(2)
      .toNumber();

    return Math.max(0, Math.min(100, attendanceScore));
  }

  /**
   * Calculate Engagement Score (0-100)
   * Rewards active, loyal customers
   */
  calculateEngagementScore(metric: StudentMetric, config: StudentGradingConfig): number {
    if (metric.numBookings === 0) {
      return 50.0; // Neutral
    }

    // Loyalty score (rebooking same barbers)
    const loyaltyScore = metric.loyaltyRate * 100;

    // Variety score (trying different barbers)
    const varietyScore = Math.min(100, (metric.numUniqueBarbers / 3) * 100);

    // Frequency score (how often they book)
    let frequencyScore = 50; // Default
    if (metric.avgDaysBetweenBookings) {
      if (metric.avgDaysBetweenBookings <= 14) {
        frequencyScore = 100; // Books every 2 weeks
      } else if (metric.avgDaysBetweenBookings <= 30) {
        frequencyScore = 80; // Monthly
      } else if (metric.avgDaysBetweenBookings <= 60) {
        frequencyScore = 60; // Every 2 months
      } else {
        frequencyScore = 40; // Infrequent
      }
    }

    // Tip score (generous customers get a small boost)
    const tipScore = Math.min(100, metric.avgTipPct * 5); // 20% tip = 100 score

    // Combined engagement (balanced)
    const engagementScore = new Decimal(loyaltyScore)
      .times(0.30)
      .plus(new Decimal(varietyScore).times(0.20))
      .plus(new Decimal(frequencyScore).times(0.30))
      .plus(new Decimal(tipScore).times(0.20))
      .toDecimalPlaces(2)
      .toNumber();

    return Math.max(0, Math.min(100, engagementScore));
  }

  /**
   * Calculate weighted Customer Score
   */
  calculateCustomerScore(
    reviewFairnessScore: number,
    attendanceScore: number,
    engagementScore: number,
    config: StudentGradingConfig
  ): number {
    const customerScore = new Decimal(reviewFairnessScore)
      .times(config.reviewFairnessWeight)
      .plus(new Decimal(attendanceScore).times(config.attendanceWeight))
      .plus(new Decimal(engagementScore).times(config.engagementWeight))
      .toDecimalPlaces(2)
      .toNumber();

    return Math.max(0, Math.min(100, customerScore));
  }

  /**
   * Check if student should be auto-flagged
   */
  private checkForAutoFlag(
    metric: StudentMetric,
    customerScore: number,
    config: StudentGradingConfig
  ): { isFlagged: boolean; flagReason: string | null } {
    const flags: string[] = [];

    // Low customer score
    if (customerScore < config.autoFlagScoreThreshold) {
      flags.push(`Low customer score: ${customerScore.toFixed(1)}`);
    }

    // Excessive no-shows
    if (metric.noShowRate > config.excessiveNoShowThreshold) {
      flags.push(`Excessive no-shows: ${(metric.noShowRate * 100).toFixed(1)}%`);
    }

    // Harsh reviewer
    if (metric.avgRatingGiven && metric.avgRatingGiven < config.harshReviewerThreshold) {
      flags.push(`Overly critical reviewer: ${metric.avgRatingGiven.toFixed(2)} avg`);
    }

    // Excessive complaints
    if (metric.numComplaintsReceived > 3) {
      flags.push(`Multiple complaints from barbers: ${metric.numComplaintsReceived}`);
    }

    return {
      isFlagged: flags.length > 0,
      flagReason: flags.length > 0 ? flags.join('; ') : null,
    };
  }

  /**
   * Apply automatic restrictions for very low scores
   */
  private async applyAutoRestrictions(studentId: string, customerScore: number): Promise<void> {
    logger.warn(`Auto-restricting student ${studentId} due to critically low score: ${customerScore}`);

    // Check if already restricted
    const existing = await pool.query(
      `SELECT id FROM student_restrictions 
       WHERE student_id = $1 AND restriction_type = 'barber_approval_required' AND is_active = true`,
      [studentId]
    );

    if (existing.rows.length > 0) {
      return; // Already restricted
    }

    // Apply restriction
    await pool.query(
      `INSERT INTO student_restrictions (
        student_id, restriction_type, reason, severity,
        triggered_by_score, triggered_by_metric
      ) VALUES ($1, $2, $3, $4, $5, $6)`,
      [
        studentId,
        'barber_approval_required',
        `Automatically restricted due to critically low customer score: ${customerScore.toFixed(1)}`,
        'high',
        customerScore,
        'customer_score',
      ]
    );

    // Log audit
    await this.logAudit(studentId, 'restricted', null, customerScore, {
      reason: 'auto_restrict_low_score',
      triggered_by: 'system',
    });
  }

  /**
   * Load grading configuration
   */
  private async loadConfig(): Promise<StudentGradingConfig> {
    const result = await pool.query(
      `SELECT * FROM student_grading_config ORDER BY version DESC LIMIT 1`
    );

    if (result.rows.length === 0) {
      throw new Error('Student grading config not found');
    }

    const row = result.rows[0];
    return {
      reviewFairnessWeight: parseFloat(row.review_fairness_weight),
      attendanceWeight: parseFloat(row.attendance_weight),
      engagementWeight: parseFloat(row.engagement_weight),
      avgRatingWeight: parseFloat(row.avg_rating_weight),
      reviewRateWeight: parseFloat(row.review_rate_weight),
      showUpWeight: parseFloat(row.show_up_weight),
      noCancelWeight: parseFloat(row.no_cancel_weight),
      harshReviewerThreshold: parseFloat(row.harsh_reviewer_threshold),
      excessiveNoShowThreshold: parseFloat(row.excessive_no_show_threshold),
      excessiveCancelThreshold: parseFloat(row.excessive_cancel_threshold),
      newStudentBookingThreshold: parseInt(row.new_student_booking_threshold),
      autoFlagScoreThreshold: parseFloat(row.auto_flag_score_threshold),
      autoRestrictScoreThreshold: parseFloat(row.auto_restrict_score_threshold),
    };
  }

  /**
   * Get total lifetime bookings
   */
  private async getTotalLifetimeBookings(studentId: string): Promise<number> {
    const result = await pool.query(
      `SELECT COUNT(*) as total FROM bookings 
       WHERE student_id = $1 AND status = 'completed'`,
      [studentId]
    );

    return parseInt(result.rows[0].total) || 0;
  }

  /**
   * Save score to database
   */
  private async saveScore(score: StudentScore): Promise<void> {
    await pool.query(
      `INSERT INTO student_scores (
        student_id, period_date,
        review_fairness_score, attendance_score, engagement_score,
        customer_score,
        is_new_student, total_lifetime_bookings,
        is_flagged, flag_reason,
        breakdown
      ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
      ON CONFLICT (student_id, period_date)
      DO UPDATE SET
        review_fairness_score = EXCLUDED.review_fairness_score,
        attendance_score = EXCLUDED.attendance_score,
        engagement_score = EXCLUDED.engagement_score,
        customer_score = EXCLUDED.customer_score,
        is_new_student = EXCLUDED.is_new_student,
        total_lifetime_bookings = EXCLUDED.total_lifetime_bookings,
        is_flagged = EXCLUDED.is_flagged,
        flag_reason = EXCLUDED.flag_reason,
        breakdown = EXCLUDED.breakdown,
        computed_at = CURRENT_TIMESTAMP
      `,
      [
        score.studentId,
        score.periodDate,
        score.reviewFairnessScore,
        score.attendanceScore,
        score.engagementScore,
        score.customerScore,
        score.isNewStudent,
        score.totalLifetimeBookings,
        score.isFlagged,
        score.flagReason,
        JSON.stringify(score.breakdown),
      ]
    );
  }

  /**
   * Log audit entry
   */
  private async logAudit(
    studentId: string,
    action: string,
    oldScore: number | null,
    newScore: number | null,
    details: any
  ): Promise<void> {
    await pool.query(
      `INSERT INTO student_grading_audit (
        student_id, action, old_score, new_score, details, triggered_by
      ) VALUES ($1, $2, $3, $4, $5, $6)`,
      [studentId, action, oldScore, newScore, JSON.stringify(details), 'system']
    );
  }

  /**
   * Get student score history
   */
  async getStudentScoreHistory(studentId: string, days: number = 30): Promise<StudentScore[]> {
    const result = await pool.query(
      `SELECT * FROM student_scores
       WHERE student_id = $1 AND period_date >= CURRENT_DATE - $2
       ORDER BY period_date DESC`,
      [studentId, days]
    );

    return result.rows.map(row => ({
      studentId: row.student_id,
      periodDate: new Date(row.period_date),
      reviewFairnessScore: parseFloat(row.review_fairness_score),
      attendanceScore: parseFloat(row.attendance_score),
      engagementScore: parseFloat(row.engagement_score),
      customerScore: parseFloat(row.customer_score),
      isNewStudent: row.is_new_student,
      totalLifetimeBookings: row.total_lifetime_bookings,
      isFlagged: row.is_flagged,
      flagReason: row.flag_reason,
      breakdown: row.breakdown,
    }));
  }

  /**
   * Get student's grade level
   */
  async getStudentGradeLevel(studentId: string): Promise<any> {
    const result = await pool.query(
      `SELECT get_student_grade_level($1) as grade_level`,
      [studentId]
    );

    if (!result.rows[0].grade_level) {
      return {
        level: 'New Customer',
        minScore: 0,
        maxScore: 100,
        badgeColor: 'gray',
        benefits: ['Welcome to CampusCuts!'],
        restrictions: [],
      };
    }

    const levelResult = await pool.query(
      `SELECT * FROM student_grade_levels WHERE level_name = $1`,
      [result.rows[0].grade_level]
    );

    return levelResult.rows[0];
  }
}

export default new StudentScoringEngineService();

