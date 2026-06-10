/**
 * Slack Service
 * 
 * Send alerts to Slack via webhooks
 */

import axios from 'axios';
import { logger } from '../utils/logger';

const SLACK_WEBHOOK_URL = process.env.SLACK_WEBHOOK_URL || '';

/**
 * Send alert to Slack
 */
export async function sendSlackAlert(message: any): Promise<void> {
  try {
    if (!SLACK_WEBHOOK_URL) {
      logger.warn('Slack webhook not configured, alert not sent');
      logger.info('Slack message:', JSON.stringify(message, null, 2));
      return;
    }

    await axios.post(SLACK_WEBHOOK_URL, message);
    logger.info('Slack alert sent successfully');
  } catch (error: any) {
    logger.error('Error sending Slack alert:', error.message);
    throw error;
  }
}

/**
 * Send simple text message to Slack
 */
export async function sendSlackMessage(text: string): Promise<void> {
  await sendSlackAlert({ text });
}

