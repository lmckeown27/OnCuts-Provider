import AWS from 'aws-sdk';
import { logger } from '../utils/logger';

/**
 * Sends a transactional SMS via AWS SNS.
 * Requires IAM permission `sns:Publish` (and SNS SMS / origination set up for the account).
 * If AWS SMS is not configured, logs the code (similar to email dev mode).
 */
export async function sendVerificationSms(phoneE164: string, code: string): Promise<void> {
  const region = process.env.AWS_REGION || process.env.AWS_DEFAULT_REGION || 'us-east-1';
  const skipAws = process.env.SKIP_AWS_SMS === 'true' || process.env.NODE_ENV === 'test';

  if (skipAws) {
    logger.warn(`[SMS] SKIP_AWS_SMS / test — code for ${phoneE164}: ${code}`);
    return;
  }

  const hasKeys =
    process.env.AWS_ACCESS_KEY_ID &&
    process.env.AWS_SECRET_ACCESS_KEY &&
    process.env.AWS_ACCESS_KEY_ID !== '' &&
    process.env.AWS_SECRET_ACCESS_KEY !== '';

  if (!hasKeys) {
    logger.warn(`[SMS] AWS credentials not set — verification code for ${phoneE164}: ${code}`);
    return;
  }

  const message = `Your CampusCuts verification code is: ${code}. It expires in 10 minutes.`;

  try {
    const sns = new AWS.SNS({ region });
    await sns
      .publish({
        PhoneNumber: phoneE164,
        Message: message,
        MessageAttributes: {
          'AWS.SNS.SMS.SMSType': {
            DataType: 'String',
            StringValue: 'Transactional',
          },
        },
      })
      .promise();
    logger.info(`SMS verification sent to ${phoneE164}`);
  } catch (err: unknown) {
    logger.error('Failed to send verification SMS:', err);
    throw err;
  }
}
