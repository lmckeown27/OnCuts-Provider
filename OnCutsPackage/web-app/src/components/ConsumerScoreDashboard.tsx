import React, { useState, useEffect } from 'react';
import { TrendingUp, TrendingDown, Award, AlertCircle, Calendar, DollarSign, Target } from 'lucide-react';
import Card from './Card';
import Button from './Button';

interface ConsumerScore {
  overall_score: number;
  grade_level: string;
  grade_badge: string;
  review_fairness_score: number;
  attendance_score: number;
  engagement_score: number;
  metrics: {
    total_bookings: number;
    completed_bookings: number;
    no_shows: number;
    cancellations: number;
    no_show_rate: number;
    cancel_rate: number;
    avg_rating_given: number;
    total_reviews_left: number;
    review_rate: number;
    total_spent_dollars: number;
    avg_tip_percentage: number;
    favorite_barbers_count: number;
  };
  restrictions: string[];
  benefits: string[];
  improvement_tips: string[];
}

interface ConsumerScoreDashboardProps {
  userId: string;
}

export const ConsumerScoreDashboard: React.FC<ConsumerScoreDashboardProps> = ({ userId }) => {
  const [score, setScore] = useState<ConsumerScore | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    loadConsumerScore();
  }, [userId]);

  const loadConsumerScore = async () => {
    setLoading(true);
    try {
      // TODO: Replace with actual API call
      // const response = await api.get(`/student-scoring/${userId}`);
      // setScore(response.data);
      
      // Mock data for now
      setScore({
        overall_score: 87,
        grade_level: 'Excellent Customer',
        grade_badge: '🥇',
        review_fairness_score: 92,
        attendance_score: 95,
        engagement_score: 68,
        metrics: {
          total_bookings: 24,
          completed_bookings: 23,
          no_shows: 1,
          cancellations: 2,
          no_show_rate: 4.2,
          cancel_rate: 8.3,
          avg_rating_given: 4.3,
          total_reviews_left: 20,
          review_rate: 83.3,
          total_spent_dollars: 720,
          avg_tip_percentage: 15,
          favorite_barbers_count: 3,
        },
        restrictions: [],
        benefits: [
          '5% loyalty discount',
          'Priority scheduling',
          'Preferred customer status'
        ],
        improvement_tips: [
          'Increase engagement score by trying new barbers',
          'Keep attending appointments to maintain excellent score',
          'Leave more reviews to help the community'
        ],
      });
    } catch (error) {
      console.error('Failed to load consumer score:', error);
    } finally {
      setLoading(false);
    }
  };

  if (loading) {
    return (
      <div className="flex items-center justify-center py-12">
        <div className="text-gray-500">Loading your customer score...</div>
      </div>
    );
  }

  if (!score) {
    return (
      <div className="text-center py-12 text-gray-500">
        Unable to load your customer score. Please try again.
      </div>
    );
  }

  const getScoreColor = (score: number) => {
    if (score >= 95) return 'text-primary-400';
    if (score >= 85) return 'text-yellow-600';
    if (score >= 70) return 'text-green-600';
    if (score >= 50) return 'text-blue-600';
    if (score >= 30) return 'text-orange-600';
    return 'text-red-600';
  };

  const getScoreBgColor = (score: number) => {
    if (score >= 95) return 'bg-primary-50';
    if (score >= 85) return 'bg-yellow-50';
    if (score >= 70) return 'bg-green-50';
    if (score >= 50) return 'bg-blue-50';
    if (score >= 30) return 'bg-orange-50';
    return 'bg-red-50';
  };

  const getGradeBadgeEmoji = (score: number) => {
    if (score >= 95) return 'A+';
    if (score >= 85) return 'A';
    if (score >= 70) return 'B';
    if (score >= 50) return 'C';
    if (score >= 30) return 'D';
    return 'F';
  };

  return (
    <div className="space-y-6">
      {/* Overall Score Card */}
      <Card className={`${getScoreBgColor(score.overall_score)} border-2`}>
        <div className="text-center py-8">
          <div className="text-6xl mb-4">{getGradeBadgeEmoji(score.overall_score)}</div>
          <div className={`text-5xl font-bold mb-2 ${getScoreColor(score.overall_score)}`}>
            {score.overall_score}/100
          </div>
          <div className="text-xl font-semibold text-gray-800 mb-2">
            {score.grade_level}
          </div>
          <div className="text-sm text-gray-600">
            Your Customer Score
          </div>
        </div>
      </Card>

      {/* Score Breakdown */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
        {/* Review Activity Score */}
        <Card>
          <div className="flex items-center justify-between mb-4">
            <div className="flex items-center gap-2">
              <Target className="w-5 h-5 text-yellow-500" />
              <span className="font-semibold">Review Activity</span>
            </div>
            <span className="text-2xl font-bold text-yellow-600">
              {score.review_fairness_score}
            </span>
          </div>
          <div className="text-sm text-gray-600 space-y-1">
            <div>Reviews Left: {score.metrics.total_reviews_left}</div>
            <div>Review Rate: {score.metrics.review_rate.toFixed(0)}%</div>
          </div>
          <div className="mt-3 text-xs text-gray-500">
            40% of your overall score
          </div>
        </Card>

        {/* Attendance Score */}
        <Card>
          <div className="flex items-center justify-between mb-4">
            <div className="flex items-center gap-2">
              <Calendar className="w-5 h-5 text-green-500" />
              <span className="font-semibold">Attendance</span>
            </div>
            <span className="text-2xl font-bold text-green-600">
              {score.attendance_score}
            </span>
          </div>
          <div className="text-sm text-gray-600 space-y-1">
            <div>Completed: {score.metrics.completed_bookings}/{score.metrics.total_bookings}</div>
            <div>No-Shows: {score.metrics.no_shows} ({score.metrics.no_show_rate.toFixed(1)}%)</div>
            <div>Cancellations: {score.metrics.cancellations} ({score.metrics.cancel_rate.toFixed(1)}%)</div>
          </div>
          <div className="mt-3 text-xs text-gray-500">
            40% of your overall score
          </div>
        </Card>

        {/* Engagement Score */}
        <Card>
          <div className="flex items-center justify-between mb-4">
            <div className="flex items-center gap-2">
              <Target className="w-5 h-5 text-blue-500" />
              <span className="font-semibold">Engagement</span>
            </div>
            <span className="text-2xl font-bold text-blue-600">
              {score.engagement_score}
            </span>
          </div>
          <div className="text-sm text-gray-600 space-y-1">
            <div>Total Spent: ${score.metrics.total_spent_dollars}</div>
            <div>Avg Tip: {score.metrics.avg_tip_percentage}%</div>
            <div>Favorite Barbers: {score.metrics.favorite_barbers_count}</div>
          </div>
          <div className="mt-3 text-xs text-gray-500">
            20% of your overall score
          </div>
        </Card>
      </div>

      {/* Benefits */}
      {score.benefits.length > 0 && (
        <Card className="bg-green-50 border-green-200">
          <h3 className="text-lg font-semibold mb-3 flex items-center gap-2">
            <Award className="w-5 h-5 text-green-600" />
            Your Benefits
          </h3>
          <ul className="space-y-2">
            {score.benefits.map((benefit, index) => (
              <li key={index} className="flex items-start gap-2 text-sm text-gray-700">
                <span className="text-green-600">✓</span>
                <span>{benefit}</span>
              </li>
            ))}
          </ul>
        </Card>
      )}

      {/* Restrictions */}
      {score.restrictions.length > 0 && (
        <Card className="bg-red-50 border-red-200">
          <h3 className="text-lg font-semibold mb-3 flex items-center gap-2 text-red-700">
            <AlertCircle className="w-5 h-5" />
            Account Restrictions
          </h3>
          <ul className="space-y-2">
            {score.restrictions.map((restriction, index) => (
              <li key={index} className="flex items-start gap-2 text-sm text-red-700">
                <span className="text-red-600 font-bold">!</span>
                <span>{restriction}</span>
              </li>
            ))}
          </ul>
          <div className="mt-4 p-3 bg-red-100 rounded-lg text-xs text-red-800">
            <strong>How to lift restrictions:</strong> Improve your attendance and review fairness scores by showing up to appointments and leaving fair reviews.
          </div>
        </Card>
      )}

      {/* Improvement Tips */}
      <Card>
        <h3 className="text-lg font-semibold mb-3 flex items-center gap-2">
          <TrendingUp className="w-5 h-5 text-blue-600" />
          How to Improve Your Score
        </h3>
        <ul className="space-y-3">
          {score.improvement_tips.map((tip, index) => (
            <li key={index} className="flex items-start gap-3 text-sm text-gray-700">
              <div className="w-6 h-6 rounded-full bg-blue-100 text-blue-600 flex items-center justify-center flex-shrink-0 font-semibold">
                {index + 1}
              </div>
              <span>{tip}</span>
            </li>
          ))}
        </ul>
      </Card>

      {/* Path to Next Level */}
      {score.overall_score < 95 && (
        <Card className="bg-gradient-to-r from-primary-50 to-blue-50 border-primary-200">
          <h3 className="text-lg font-semibold mb-3 flex items-center gap-2">
            <Target className="w-5 h-5 text-primary-400" />
            Path to {score.overall_score >= 85 ? 'VIP Status' : 'Next Level'}
          </h3>
          <div className="space-y-4">
            <div>
              <div className="flex justify-between text-sm mb-2">
                <span>Current Score</span>
                <span className="font-semibold">{score.overall_score}/100</span>
              </div>
              <div className="w-full bg-gray-200 rounded-full h-3">
                <div
                  className="bg-gradient-to-r from-primary-500 to-blue-500 h-3 rounded-full transition-all"
                  style={{ width: `${score.overall_score}%` }}
                />
              </div>
            </div>

            {score.overall_score >= 85 ? (
              <div className="text-sm text-gray-700">
                <p className="font-semibold mb-2">To reach VIP Status (95+):</p>
                <ul className="space-y-1 ml-4">
                  <li>• Maintain 0% no-shows</li>
                  <li>• Leave fair reviews (4.0-4.5 avg)</li>
                  <li>• Book regularly (2x/month)</li>
                  <li>• Tip 15%+ on average</li>
                </ul>
                <div className="mt-3 p-3 bg-primary-100 rounded-lg">
                  <strong>VIP Benefits:</strong> 10% discount, priority scheduling, exclusive perks
                </div>
              </div>
            ) : score.overall_score >= 70 ? (
              <div className="text-sm text-gray-700">
                <p className="font-semibold mb-2">To reach Excellent Customer (85+):</p>
                <ul className="space-y-1 ml-4">
                  <li>• Reduce no-shows to 0%</li>
                  <li>• Leave more balanced reviews</li>
                  <li>• Increase booking frequency</li>
                </ul>
              </div>
            ) : (
              <div className="text-sm text-gray-700">
                <p className="font-semibold mb-2">To reach Good Customer (70+):</p>
                <ul className="space-y-1 ml-4">
                  <li>• Show up to ALL appointments</li>
                  <li>• Leave fair, constructive reviews</li>
                  <li>• Avoid last-minute cancellations</li>
                </ul>
              </div>
            )}
          </div>
        </Card>
      )}

      {/* Review Weight Info */}
      <Card className="bg-blue-50 border-blue-200">
        <h3 className="text-lg font-semibold mb-3 flex items-center gap-2">
          <Target className="w-5 h-5 text-blue-600" />
          Your Review Impact
        </h3>
        <div className="space-y-3">
          <div>
            <div className="flex justify-between items-center mb-2">
              <span className="text-sm text-gray-700">Review Weight:</span>
              <span className="text-2xl font-bold text-blue-600">
                {score.overall_score >= 95 ? '1.2x' : 
                 score.overall_score >= 85 ? '1.0x' :
                 score.overall_score >= 70 ? '0.8x' :
                 score.overall_score >= 50 ? '0.5x' :
                 score.overall_score >= 30 ? '0.2x' : '0.0x'}
              </span>
            </div>
            <div className="text-xs text-gray-600">
              {score.overall_score >= 95 ? 
                'Your reviews count 20% MORE than normal (trusted reviewer)' :
               score.overall_score >= 85 ?
                'Your reviews have full impact (fair reviewer)' :
               score.overall_score >= 70 ?
                'Your reviews count 20% less (improve fairness)' :
               score.overall_score >= 50 ?
                'Your reviews count 50% less (improve behavior)' :
               score.overall_score >= 30 ?
                'Your reviews have minimal impact (80% reduced)' :
                'Your reviews are IGNORED (improve score to 30+ first)'}
            </div>
          </div>

          {score.overall_score < 85 && (
            <div className="p-3 bg-blue-100 rounded-lg text-xs text-blue-800">
              <strong>Why review weight matters:</strong> To protect barbers from unfair reviews, we weight reviews based on customer reliability and fairness. Improve your score to make your reviews count more!
            </div>
          )}
        </div>
      </Card>

      {/* Detailed Metrics */}
      <Card>
        <h3 className="text-lg font-semibold mb-4">Your Statistics</h3>
        <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
          <div className="text-center">
            <div className="text-2xl font-bold text-gray-800">{score.metrics.total_bookings}</div>
            <div className="text-xs text-gray-600">Total Bookings</div>
          </div>
          <div className="text-center">
            <div className="text-2xl font-bold text-green-600">{score.metrics.completed_bookings}</div>
            <div className="text-xs text-gray-600">Completed</div>
          </div>
          <div className="text-center">
            <div className="text-2xl font-bold text-red-600">{score.metrics.no_shows}</div>
            <div className="text-xs text-gray-600">No-Shows</div>
          </div>
          <div className="text-center">
            <div className="text-2xl font-bold text-orange-600">{score.metrics.cancellations}</div>
            <div className="text-xs text-gray-600">Cancellations</div>
          </div>
          <div className="text-center">
            <div className="text-2xl font-bold text-yellow-600">{score.metrics.avg_rating_given.toFixed(1)}</div>
            <div className="text-xs text-gray-600">Avg Rating Given</div>
          </div>
          <div className="text-center">
            <div className="text-2xl font-bold text-blue-600">{score.metrics.total_reviews_left}</div>
            <div className="text-xs text-gray-600">Reviews Written</div>
          </div>
          <div className="text-center">
            <div className="text-2xl font-bold text-green-600">${score.metrics.total_spent_dollars}</div>
            <div className="text-xs text-gray-600">Total Spent</div>
          </div>
          <div className="text-center">
            <div className="text-2xl font-bold text-primary-400">{score.metrics.avg_tip_percentage}%</div>
            <div className="text-xs text-gray-600">Avg Tip</div>
          </div>
        </div>
      </Card>

      {/* Grade Level Explanation */}
      <Card className="bg-gray-50">
        <h3 className="text-lg font-semibold mb-3">Customer Grade Levels</h3>
        <div className="space-y-2 text-sm">
          <div className="flex items-center justify-between p-2 rounded bg-primary-100">
            <span>VIP Customer (95-100)</span>
            <span className="text-xs text-primary-500">10% discount, priority scheduling</span>
          </div>
          <div className="flex items-center justify-between p-2 rounded bg-yellow-100">
            <span>🥇 Excellent (85-94)</span>
            <span className="text-xs text-yellow-700">5% discount, priority access</span>
          </div>
          <div className="flex items-center justify-between p-2 rounded bg-green-100">
            <span>🥈 Good (70-84)</span>
            <span className="text-xs text-green-700">Standard access</span>
          </div>
          <div className="flex items-center justify-between p-2 rounded bg-blue-100">
            <span>🥉 Average (50-69)</span>
            <span className="text-xs text-blue-700">Standard access</span>
          </div>
          <div className="flex items-center justify-between p-2 rounded bg-orange-100">
            <span>⚪ Below Average (30-49)</span>
            <span className="text-xs text-orange-700">Standard access</span>
          </div>
          <div className="flex items-center justify-between p-2 rounded bg-red-100">
            <span>Poor (0-29)</span>
            <span className="text-xs text-red-700">Severe restrictions</span>
          </div>
        </div>
      </Card>

      {/* Warning for Low Scores */}
      {score.overall_score < 50 && (
        <Card className="bg-red-50 border-red-300 border-2">
          <div className="flex items-start gap-3">
            <AlertCircle className="w-6 h-6 text-red-600 flex-shrink-0 mt-1" />
            <div>
              <h3 className="text-lg font-semibold text-red-800 mb-2">
                Action Required
              </h3>
              <p className="text-sm text-red-700 mb-3">
                Your customer score is below 50. This affects your ability to book appointments and your review impact.
              </p>
              <div className="space-y-2">
                <p className="text-sm font-semibold text-red-800">To improve:</p>
                <ul className="text-sm text-red-700 space-y-1 ml-4">
                  <li>• Show up to ALL scheduled appointments</li>
                  <li>• Leave fair, balanced reviews (not overly harsh)</li>
                  <li>• Avoid last-minute cancellations</li>
                  <li>• Be respectful to barbers</li>
                </ul>
              </div>
            </div>
          </div>
        </Card>
      )}
    </div>
  );
};

