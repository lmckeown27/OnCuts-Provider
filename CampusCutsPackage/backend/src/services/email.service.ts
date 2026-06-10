/**
 * Email Service - SMTP Email Verification for CampusCuts
 * 
 * Handles sending verification emails and password reset emails using SMTP.
 * 
 * ## Environment Variables Required:
 * - SMTP_HOST: SMTP server hostname
 * - SMTP_PORT: SMTP server port (usually 587 for TLS)
 * - SMTP_USER: SMTP authentication username
 * - SMTP_PASS: SMTP authentication password
 * - FRONTEND_URL: Frontend base URL for email links
 * - AUTO_VERIFY_EMAILS: Set to 'true' to skip email sending in development
 * 
 * @module email.service
 */

import nodemailer from 'nodemailer';
import { logger } from '../utils/logger';

/**
 * Email Configuration Interface
 */
interface EmailConfig {
  host: string;
  port: number;
  secure: boolean;
  auth: {
    user: string;
    pass: string;
  };
}

/**
 * Get Email Configuration from Environment
 * 
 * @returns EmailConfig object
 * @throws Error if required environment variables are missing
 */
function getEmailConfig(): EmailConfig {
  const host = process.env.SMTP_HOST;
  const port = parseInt(process.env.SMTP_PORT || '587');
  const user = process.env.SMTP_USER;
  const pass = process.env.SMTP_PASS;

  if (!host || !user || !pass) {
    throw new Error(
      'Email service not configured. Required: SMTP_HOST, SMTP_PORT, SMTP_USER, SMTP_PASS'
    );
  }

  return {
    host,
    port,
    secure: port === 465, // Use SSL for port 465, TLS for 587
    auth: { user, pass }
  };
}

/**
 * Create Nodemailer Transporter
 * 
 * Creates and configures SMTP transporter for sending emails.
 * 
 * @returns Nodemailer transporter instance
 */
function createTransporter() {
  try {
    const config = getEmailConfig();
    
    const transporter = nodemailer.createTransport({
      host: config.host,
      port: config.port,
      secure: config.secure,
      auth: config.auth,
      tls: {
        rejectUnauthorized: process.env.NODE_ENV === 'production'
      }
    });

    return transporter;
  } catch (error) {
    logger.error('Failed to create email transporter:', error);
    throw error;
  }
}

/**
 * Check if Auto-Verify Mode is Enabled
 * 
 * In development, emails can be auto-verified without sending actual emails.
 * 
 * @returns true if AUTO_VERIFY_EMAILS=true
 */
export function isAutoVerifyEnabled(): boolean {
  return process.env.AUTO_VERIFY_EMAILS === 'true';
}

/**
 * Send Generic Email
 * 
 * Sends a generic email with subject and body.
 * 
 * @param to - Recipient email address
 * @param subject - Email subject
 * @param body - Email body (plain text or HTML)
 * @returns Promise<void>
 * 
 * @example
 * await sendEmail('admin@campuscuts.com', 'Alert', 'Gas wallet is low!');
 */
export async function sendEmail(to: string, subject: string, body: string): Promise<void> {
  if (isAutoVerifyEnabled()) {
    logger.info(`[AUTO-VERIFY MODE] Skipping email to ${to}, subject: ${subject}`);
    return;
  }

  try {
    const transporter = createTransporter();

    const mailOptions = {
      from: `CampusCut <${process.env.SMTP_USER}>`,
      to,
      subject,
      text: body,
      html: body.includes('<') ? body : `<p>${body.replace(/\n/g, '<br>')}</p>`
    };

    const info = await transporter.sendMail(mailOptions);
    
    logger.info(`Email sent to ${to}`, { messageId: info.messageId, subject });
  } catch (error: any) {
    logger.error(`Failed to send email to ${to}:`, error.message);
    throw new Error('Failed to send email. Please try again later.');
  }
}

/**
 * Send Verification Email
 * 
 * Sends a 6-digit verification code to the user's email address.
 * Skips sending if AUTO_VERIFY_EMAILS=true.
 * 
 * @param email - User's email address
 * @param code - 6-digit verification code
 * @returns Promise<void>
 * 
 * @example
 * await sendVerificationEmail('student@university.edu', '123456');
 */
export async function sendVerificationEmail(email: string, code: string): Promise<void> {
  // Skip email sending in auto-verify mode
  if (isAutoVerifyEnabled()) {
    logger.info(`[AUTO-VERIFY MODE] Skipping email to ${email}, code: ${code}`);
    return;
  }

  try {
    const transporter = createTransporter();
    const frontendUrl = process.env.FRONTEND_URL || 'http://localhost:5173';

    const mailOptions = {
      from: `CampusCut <${process.env.SMTP_USER}>`,
      to: email,
      subject: 'Verify Your CampusCut Account - Code Inside',
      text: generateVerificationEmailText(code, frontendUrl),
      html: generateVerificationEmailHtml(code, frontendUrl)
    };

    const info = await transporter.sendMail(mailOptions);
    
    logger.info(`Verification email sent to ${email}`, { messageId: info.messageId });
  } catch (error: any) {
    logger.error(`Failed to send verification email to ${email}:`, error.message);
    throw new Error('Failed to send verification email. Please try again later.');
  }
}

/**
 * Send Password Reset Email
 * 
 * Sends a password reset link to the user's email address.
 * Skips sending if AUTO_VERIFY_EMAILS=true.
 * 
 * @param email - User's email address
 * @param resetLink - Password reset URL with token
 * @returns Promise<void>
 * 
 * @example
 * const resetLink = `https://campuscuts.com/reset-password?token=${token}`;
 * await sendPasswordResetEmail('student@university.edu', resetLink);
 */
export async function sendPasswordResetEmail(email: string, resetLink: string): Promise<void> {
  // Skip email sending in auto-verify mode
  if (isAutoVerifyEnabled()) {
    logger.info(`[AUTO-VERIFY MODE] Skipping password reset email to ${email}`);
    logger.info(`[AUTO-VERIFY MODE] Reset link: ${resetLink}`);
    return;
  }

  try {
    const transporter = createTransporter();

    const mailOptions = {
      from: `CampusCut <${process.env.SMTP_USER}>`,
      to: email,
      subject: 'Reset Your CampusCut Password',
      text: generatePasswordResetEmailText(resetLink),
      html: generatePasswordResetEmailHtml(resetLink)
    };

    const info = await transporter.sendMail(mailOptions);
    
    logger.info(`Password reset email sent to ${email}`, { messageId: info.messageId });
  } catch (error: any) {
    logger.error(`Failed to send password reset email to ${email}:`, error.message);
    throw new Error('Failed to send password reset email. Please try again later.');
  }
}

/**
 * Verify SMTP Configuration
 * 
 * Tests SMTP connection to ensure email service is properly configured.
 * 
 * @returns Promise<boolean> - true if connection successful
 */
export async function verifyEmailService(): Promise<boolean> {
  // Skip verification in auto-verify mode
  if (isAutoVerifyEnabled()) {
    logger.info('[AUTO-VERIFY MODE] Email service verification skipped');
    return true;
  }

  try {
    const transporter = createTransporter();
    await transporter.verify();
    logger.info('Email service verified successfully');
    return true;
  } catch (error: any) {
    logger.error('Email service verification failed:', error.message);
    return false;
  }
}

// ============================================
// EMAIL TEMPLATES
// ============================================

/**
 * Generate Verification Email Plain Text
 */
function generateVerificationEmailText(code: string, frontendUrl: string): string {
  return `
Welcome to CampusCut!

Your verification code is: ${code}

This code will expire in 10 minutes.

To verify your account, enter this code on the verification page:
${frontendUrl}/web/verify-email

If you didn't create an account with CampusCut, please ignore this email.

---
CampusCut
`.trim();
}

/**
 * Generate Verification Email HTML
 */
function generateVerificationEmailHtml(code: string, frontendUrl: string): string {
  return `
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <meta name="color-scheme" content="light">
  <meta name="supported-color-schemes" content="light">
</head>
<body style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif; line-height: 1.6; color: #333333; max-width: 600px; margin: 0 auto; padding: 20px; background-color: #f3f4f6;">
  <div style="background: linear-gradient(135deg, #022b19 0%, #034d2e 100%); padding: 30px; text-align: center; border-radius: 12px 12px 0 0;">
    <h1 style="color: white; margin: 0; font-size: 28px;">CampusCut</h1>
    <p style="color: #4ade80; margin: 10px 0 0 0; font-size: 16px;">Account Verification</p>
  </div>
  
  <div style="background-color: #ffffff; padding: 30px; border-radius: 0 0 12px 12px; border: 1px solid #e5e7eb; border-top: none;">
    <h2 style="color: #022b19; margin-bottom: 20px;">Welcome to CampusCut!</h2>
    
    <p style="color: #555555; line-height: 1.6; margin-bottom: 25px;">
      We're excited to have you join our campus community. To complete your registration, 
      please enter the verification code below.
    </p>
    
    <div style="text-align: center; margin: 30px 0; padding: 25px; background-color: #e6ebea; border-radius: 12px; border: 2px dashed #5a7268;">
      <p style="color: #166534; margin: 0 0 10px 0; font-size: 14px; font-weight: 600; text-transform: uppercase; letter-spacing: 1px;">
        Your Verification Code
      </p>
      <div style="font-size: 40px; font-weight: bold; color: #000000; letter-spacing: 10px; font-family: 'Courier New', monospace;">
        ${code}
      </div>
      <p style="color: #374151; margin: 15px 0 0 0; font-size: 13px;">
        This code expires in <strong>10 minutes</strong>
      </p>
    </div>
    
    <p style="text-align: center;">
      <a href="${frontendUrl}/web/verify-email" style="display: inline-block; background-color: #5a7268; color: white; padding: 14px 40px; text-decoration: none; border-radius: 8px; font-weight: 600; font-size: 16px;">
        Verify My Account
      </a>
    </p>
    
    <hr style="border: none; border-top: 1px solid #e5e7eb; margin: 30px 0;">
    
    <p style="color: #6b7280; font-size: 13px; text-align: center;">
      If you didn't create an account with CampusCut, you can safely ignore this email.
    </p>
  </div>
  
  <div style="text-align: center; padding: 20px; color: #9ca3af; font-size: 12px;">
    <p style="margin: 0;">© ${new Date().getFullYear()} CampusCut</p>
    <p style="margin: 5px 0 0 0;">
      <a href="${frontendUrl}/privacy" style="color: #5a7268; text-decoration: none;">Privacy Policy</a>
    </p>
  </div>
</body>
</html>
`.trim();
}

/**
 * Generate Password Reset Email Plain Text
 */
function generatePasswordResetEmailText(resetLink: string): string {
  return `
Reset Your CampusCut Password

You requested to reset your password for your CampusCut account.

Click the link below to reset your password:
${resetLink}

This link will expire in 1 hour.

If you didn't request a password reset, please ignore this email or contact support if you have concerns.

---
CampusCut
`.trim();
}

/**
 * Generate Password Reset Email HTML
 */
function generatePasswordResetEmailHtml(resetLink: string): string {
  return `
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
</head>
<body style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; line-height: 1.6; color: #333; max-width: 600px; margin: 0 auto; padding: 20px; background-color: #f3f4f6;">
  <div style="background: linear-gradient(135deg, #022b19 0%, #034d2e 100%); padding: 30px; text-align: center; border-radius: 12px 12px 0 0;">
    <h1 style="color: white; margin: 0; font-size: 28px;">CampusCut</h1>
    <p style="color: #4ade80; margin: 10px 0 0 0; font-size: 16px;">Password Reset</p>
  </div>
  
  <div style="background-color: #ffffff; padding: 30px; border-radius: 0 0 12px 12px; border: 1px solid #e5e7eb; border-top: none;">
    <h2 style="color: #022b19; margin-bottom: 20px;">Reset Your Password</h2>
    
    <p style="color: #555555; line-height: 1.6; margin-bottom: 25px;">
      You requested to reset your password for your CampusCut account. 
      Click the button below to create a new password.
    </p>
    
    <p style="text-align: center; margin: 30px 0;">
      <a href="${resetLink}" style="display: inline-block; background-color: #5a7268; color: white; padding: 14px 40px; text-decoration: none; border-radius: 8px; font-weight: 600; font-size: 16px;">
        Reset My Password
      </a>
    </p>
    
    <p style="color: #dc2626; font-size: 14px; text-align: center;">
      This link expires in <strong>1 hour</strong>
    </p>
    
    <p style="color: #6b7280; font-size: 13px; margin-top: 20px;">
      If the button doesn't work, copy and paste this link into your browser:
    </p>
    <p style="word-break: break-all; color: #5a7268; font-size: 13px;">${resetLink}</p>
    
    <hr style="border: none; border-top: 1px solid #e5e7eb; margin: 30px 0;">
    
    <p style="color: #6b7280; font-size: 13px; text-align: center;">
      If you didn't request a password reset, you can safely ignore this email.
    </p>
  </div>
  
  <div style="text-align: center; padding: 20px; color: #9ca3af; font-size: 12px;">
    <p style="margin: 0;">© ${new Date().getFullYear()} CampusCut</p>
  </div>
</body>
</html>
`.trim();
}

/**
 * Send Welcome Email (Optional)
 * 
 * Sends a welcome email after successful verification.
 * 
 * @param email - User's email address
 * @param firstName - User's first name
 */
export async function sendWelcomeEmail(email: string, firstName: string): Promise<void> {
  if (isAutoVerifyEnabled()) {
    logger.info(`[AUTO-VERIFY MODE] Skipping welcome email to ${email}`);
    return;
  }

  try {
    const transporter = createTransporter();
    const frontendUrl = process.env.FRONTEND_URL || 'http://localhost:5173';

    const mailOptions = {
      from: `CampusCut <${process.env.SMTP_USER}>`,
      to: email,
      subject: 'Welcome to CampusCut!',
      text: `
Welcome to CampusCut, ${firstName}!

Your account has been successfully verified. You can now:
- Book appointments with talented barbers on your campus
- Browse barber profiles and portfolios
- Manage your bookings and payment methods
- Leave reviews and ratings

Get started: ${frontendUrl}/web/discover

We're excited to help you look your best!

---
CampusCut Team
`.trim(),
      html: `
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
</head>
<body style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; line-height: 1.6; color: #333; max-width: 600px; margin: 0 auto; padding: 20px; background-color: #f3f4f6;">
  <div style="background: linear-gradient(135deg, #022b19 0%, #034d2e 100%); padding: 30px; text-align: center; border-radius: 12px 12px 0 0;">
    <h1 style="color: white; margin: 0; font-size: 28px;">CampusCut</h1>
    <p style="color: #4ade80; margin: 10px 0 0 0; font-size: 16px;">Welcome Aboard!</p>
  </div>
  
  <div style="background-color: #ffffff; padding: 30px; border-radius: 0 0 12px 12px; border: 1px solid #e5e7eb; border-top: none;">
    <h2 style="color: #022b19; margin-bottom: 20px;">Hey ${firstName}!</h2>
    
    <p style="color: #555555; line-height: 1.6; margin-bottom: 20px;">
      Your account has been verified and you're all set! Welcome to the CampusCut community.
    </p>
    
    <div style="background-color: #f2f5f4; border-radius: 8px; padding: 20px; margin: 20px 0;">
      <p style="color: #166534; font-weight: 600; margin: 0 0 10px 0;">Here's what you can do now:</p>
      <ul style="color: #555555; margin: 0; padding-left: 20px;">
        <li>Discover talented barbers on your campus</li>
        <li>Book appointments that fit your schedule</li>
        <li>Pay securely through the website</li>
        <li>Leave reviews and help others find great cuts</li>
      </ul>
    </div>
    
    <p style="text-align: center; margin: 30px 0;">
      <a href="${frontendUrl}/web/discover" style="display: inline-block; background-color: #5a7268; color: white; padding: 14px 40px; text-decoration: none; border-radius: 8px; font-weight: 600; font-size: 16px;">
        Find Your Barber
      </a>
    </p>
    
    <p style="color: #6b7280; font-size: 14px; text-align: center;">
      We're excited to help you look your best!
    </p>
  </div>
  
  <div style="text-align: center; padding: 20px; color: #9ca3af; font-size: 12px;">
    <p style="margin: 0;">© ${new Date().getFullYear()} CampusCut</p>
  </div>
</body>
</html>
`.trim()
    };

    await transporter.sendMail(mailOptions);
    logger.info(`Welcome email sent to ${email}`);
  } catch (error: any) {
    // Don't throw - welcome email is non-critical
    logger.error(`Failed to send welcome email to ${email}:`, error.message);
  }
}

/**
 * Booking Confirmation Details Interface
 */
interface BookingConfirmationDetails {
  bookingId: string;
  serviceName: string;
  price: number; // in dollars
  scheduledDate: string; // formatted date string
  scheduledTime: string; // formatted time string
  location?: string;
  notes?: string;
  consumerName: string;
  consumerEmail: string;
  barberName: string;
  barberEmail: string;
}

/**
 * Send Booking Confirmation Emails
 * 
 * Sends confirmation emails to both the consumer and barber when a booking is accepted.
 * 
 * @param details - Booking confirmation details
 */
export async function sendBookingConfirmationEmails(details: BookingConfirmationDetails): Promise<void> {
  if (isAutoVerifyEnabled()) {
    logger.info(`[AUTO-VERIFY MODE] Skipping booking confirmation emails for booking ${details.bookingId}`);
    return;
  }

  const frontendUrl = process.env.FRONTEND_URL || 'https://campuscut.com';

  // Send to consumer
  try {
    const transporter = createTransporter();
    
    const consumerMailOptions = {
      from: `CampusCut <${process.env.SMTP_USER}>`,
      to: details.consumerEmail,
      subject: `Booking Confirmed! Your ${details.serviceName} with ${details.barberName}`,
      text: generateBookingConfirmationText(details, 'consumer'),
      html: generateBookingConfirmationHtml(details, 'consumer', frontendUrl)
    };

    await transporter.sendMail(consumerMailOptions);
    logger.info(`Booking confirmation email sent to consumer: ${details.consumerEmail}`);
  } catch (error: any) {
    logger.error(`Failed to send booking confirmation to consumer ${details.consumerEmail}:`, error.message);
  }

  // Send to barber
  try {
    const transporter = createTransporter();
    
    const barberMailOptions = {
      from: `CampusCut <${process.env.SMTP_USER}>`,
      to: details.barberEmail,
      subject: `New Booking Confirmed: ${details.serviceName} with ${details.consumerName}`,
      text: generateBookingConfirmationText(details, 'barber'),
      html: generateBookingConfirmationHtml(details, 'barber', frontendUrl)
    };

    await transporter.sendMail(barberMailOptions);
    logger.info(`Booking confirmation email sent to barber: ${details.barberEmail}`);
  } catch (error: any) {
    logger.error(`Failed to send booking confirmation to barber ${details.barberEmail}:`, error.message);
  }
}

/**
 * Generate Booking Confirmation Plain Text
 */
function generateBookingConfirmationText(
  details: BookingConfirmationDetails, 
  recipient: 'consumer' | 'barber'
): string {
  const isConsumer = recipient === 'consumer';
  const greeting = isConsumer 
    ? `Hi ${details.consumerName.split(' ')[0]}!` 
    : `Hi ${details.barberName.split(' ')[0]}!`;
  
  const intro = isConsumer
    ? `Great news! Your booking with ${details.barberName} has been confirmed.`
    : `You have a new confirmed booking with ${details.consumerName}.`;

  return `
${greeting}

${intro}

BOOKING DETAILS
---------------
Service: ${details.serviceName}
Date: ${details.scheduledDate}
Time: ${details.scheduledTime}
Price: $${details.price.toFixed(2)}
${details.location ? `Location: ${details.location}` : ''}
${details.notes ? `Notes: ${details.notes}` : ''}

${isConsumer ? 'Customer' : 'Barber'}: ${isConsumer ? details.barberName : details.consumerName}

Booking Reference: ${details.bookingId.slice(0, 8).toUpperCase()}

${isConsumer 
  ? 'Please arrive on time. You can message your barber through the app if you need to make any changes.'
  : 'Please review the booking details and be ready for your client at the scheduled time.'}

---
CampusCut
`.trim();
}

/**
 * Generate Booking Confirmation HTML Email
 */
function generateBookingConfirmationHtml(
  details: BookingConfirmationDetails, 
  recipient: 'consumer' | 'barber',
  frontendUrl: string
): string {
  const isConsumer = recipient === 'consumer';
  const greeting = isConsumer 
    ? `Hi ${details.consumerName.split(' ')[0]}!` 
    : `Hi ${details.barberName.split(' ')[0]}!`;
  
  const intro = isConsumer
    ? `Great news! Your booking with <strong>${details.barberName}</strong> has been confirmed.`
    : `You have a new confirmed booking with <strong>${details.consumerName}</strong>.`;

  const ctaText = isConsumer ? 'View My Bookings' : 'View Dashboard';
  const ctaLink = `${frontendUrl}/web`; // Links to sign-in page, user redirected after login

  return `
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
</head>
<body style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; line-height: 1.6; color: #333; max-width: 600px; margin: 0 auto; padding: 20px; background-color: #f3f4f6;">
  <div style="background: linear-gradient(135deg, #022b19 0%, #034d2e 100%); padding: 30px; text-align: center; border-radius: 12px 12px 0 0;">
    <h1 style="color: white; margin: 0; font-size: 28px;">CampusCut</h1>
    <p style="color: #4ade80; margin: 10px 0 0 0; font-size: 16px;">Booking Confirmed!</p>
  </div>
  
  <div style="background-color: #ffffff; padding: 30px; border-radius: 0 0 12px 12px; border: 1px solid #e5e7eb; border-top: none;">
    <h2 style="color: #022b19; margin-bottom: 10px;">${greeting}</h2>
    
    <p style="color: #555555; line-height: 1.6; margin-bottom: 25px;">
      ${intro}
    </p>
    
    <div style="background-color: #f2f5f4; border-radius: 12px; padding: 25px; margin: 20px 0; border: 1px solid #bfcdc8;">
      <h3 style="color: #166534; margin: 0 0 15px 0; font-size: 16px; text-transform: uppercase; letter-spacing: 1px;">
        Booking Details
      </h3>
      
      <table style="width: 100%; border-collapse: collapse;">
        <tr>
          <td style="padding: 10px 0; border-bottom: 1px solid #e6ebea; color: #6b7280; width: 40%;">Service</td>
          <td style="padding: 10px 0; border-bottom: 1px solid #e6ebea; color: #1f2937; font-weight: 600;">${details.serviceName}</td>
        </tr>
        <tr>
          <td style="padding: 10px 0; border-bottom: 1px solid #e6ebea; color: #6b7280;">Date</td>
          <td style="padding: 10px 0; border-bottom: 1px solid #e6ebea; color: #1f2937; font-weight: 600;">${details.scheduledDate}</td>
        </tr>
        <tr>
          <td style="padding: 10px 0; border-bottom: 1px solid #e6ebea; color: #6b7280;">Time</td>
          <td style="padding: 10px 0; border-bottom: 1px solid #e6ebea; color: #1f2937; font-weight: 600;">${details.scheduledTime}</td>
        </tr>
        ${details.location ? `
        <tr>
          <td style="padding: 10px 0; border-bottom: 1px solid #e6ebea; color: #6b7280;">Location</td>
          <td style="padding: 10px 0; border-bottom: 1px solid #e6ebea; color: #1f2937; font-weight: 600;">${details.location}</td>
        </tr>
        ` : ''}
        <tr>
          <td style="padding: 10px 0; border-bottom: 1px solid #e6ebea; color: #6b7280;">${isConsumer ? 'Your Barber' : 'Customer'}</td>
          <td style="padding: 10px 0; border-bottom: 1px solid #e6ebea; color: #1f2937; font-weight: 600;">${isConsumer ? details.barberName : details.consumerName}</td>
        </tr>
        <tr>
          <td style="padding: 10px 0; color: #6b7280;">Price</td>
          <td style="padding: 10px 0; color: #5a7268; font-weight: 700; font-size: 20px;">$${details.price.toFixed(2)}</td>
        </tr>
      </table>
      
      ${details.notes ? `
      <div style="margin-top: 15px; padding-top: 15px; border-top: 1px solid #e6ebea;">
        <p style="color: #6b7280; margin: 0 0 5px 0; font-size: 14px;">Notes:</p>
        <p style="color: #1f2937; margin: 0; font-style: italic;">"${details.notes}"</p>
      </div>
      ` : ''}
    </div>
    
    <div style="background-color: #f9fafb; border-radius: 8px; padding: 15px; margin: 20px 0; text-align: center;">
      <p style="color: #6b7280; margin: 0; font-size: 14px;">Booking Reference</p>
      <p style="color: #1f2937; margin: 5px 0 0 0; font-size: 18px; font-weight: 700; letter-spacing: 2px;">${details.bookingId.slice(0, 8).toUpperCase()}</p>
    </div>
    
    <p style="color: #6b7280; font-size: 14px; margin: 20px 0;">
      ${isConsumer 
        ? 'Please arrive on time. You can message your barber through the app if you need to make any changes.'
        : 'Please review the booking details and be ready for your client at the scheduled time.'}
    </p>
    
    <p style="text-align: center; margin: 30px 0 20px 0;">
      <a href="${ctaLink}" style="display: inline-block; background-color: #5a7268; color: white; padding: 14px 40px; text-decoration: none; border-radius: 8px; font-weight: 600; font-size: 16px;">
        ${ctaText}
      </a>
    </p>
  </div>
  
  <div style="text-align: center; padding: 20px; color: #9ca3af; font-size: 12px;">
    <p style="margin: 0;">© ${new Date().getFullYear()} CampusCut</p>
    <p style="margin: 10px 0 0 0;">
      <a href="${frontendUrl}/web" style="color: #9ca3af;">Messages</a>
    </p>
  </div>
</body>
</html>
`.trim();
}

/**
 * Interface for pending booking email details
 */
interface PendingBookingEmailDetails {
  consumerEmail: string;
  consumerName: string;
  barberEmail: string;
  barberName: string;
  serviceName: string;
  scheduledDate: string;
  scheduledTime: string;
  price: number;
  location?: string;
  notes?: string;
  bookingId: string;
}

/**
 * Send Pending Booking Receipt Emails
 * 
 * Sends receipt emails to the consumer when a booking is created (pending status).
 * Also notifies the barber about the new booking request.
 */
export async function sendPendingBookingEmails(details: PendingBookingEmailDetails): Promise<void> {
  if (isAutoVerifyEnabled()) {
    logger.info(`[AUTO-VERIFY MODE] Skipping pending booking emails for booking ${details.bookingId}`);
    return;
  }

  const frontendUrl = process.env.FRONTEND_URL || 'https://campuscut.com';

  // Send receipt to consumer
  try {
    const transporter = createTransporter();
    
    const consumerMailOptions = {
      from: `CampusCut <${process.env.SMTP_USER}>`,
      to: details.consumerEmail,
      subject: `Booking Request Submitted - ${details.serviceName} with ${details.barberName}`,
      text: generatePendingBookingText(details, 'consumer'),
      html: generatePendingBookingHtml(details, 'consumer', frontendUrl)
    };

    await transporter.sendMail(consumerMailOptions);
    logger.info(`Pending booking receipt sent to consumer: ${details.consumerEmail}`);
  } catch (error: any) {
    logger.error(`Failed to send pending booking email to consumer ${details.consumerEmail}:`, error.message);
  }

  // Send notification to barber
  try {
    const transporter = createTransporter();
    
    const barberMailOptions = {
      from: `CampusCut <${process.env.SMTP_USER}>`,
      to: details.barberEmail,
      subject: `New Booking Request from ${details.consumerName}`,
      text: generatePendingBookingText(details, 'barber'),
      html: generatePendingBookingHtml(details, 'barber', frontendUrl)
    };

    await transporter.sendMail(barberMailOptions);
    logger.info(`Pending booking notification sent to barber: ${details.barberEmail}`);
  } catch (error: any) {
    logger.error(`Failed to send pending booking email to barber ${details.barberEmail}:`, error.message);
  }
}

/**
 * Generate Pending Booking Plain Text
 */
function generatePendingBookingText(
  details: PendingBookingEmailDetails, 
  recipient: 'consumer' | 'barber'
): string {
  const isConsumer = recipient === 'consumer';
  const greeting = isConsumer 
    ? `Hi ${details.consumerName.split(' ')[0]}!` 
    : `Hi ${details.barberName.split(' ')[0]}!`;
  
  const intro = isConsumer
    ? `Your booking request with ${details.barberName} has been submitted and is awaiting confirmation.`
    : `You have a new booking request from ${details.consumerName}!`;

  return `
${greeting}

${intro}

BOOKING REQUEST DETAILS
-----------------------
Service: ${details.serviceName}
Requested Date: ${details.scheduledDate}
Requested Time: ${details.scheduledTime}
Price: $${details.price.toFixed(2)}
${details.location ? `Location: ${details.location}` : ''}
${details.notes ? `Notes: ${details.notes}` : ''}

${isConsumer ? 'Barber' : 'Customer'}: ${isConsumer ? details.barberName : details.consumerName}

Booking Reference: ${details.bookingId.slice(0, 8).toUpperCase()}

${isConsumer 
  ? "We'll notify you once the barber confirms your booking. You can track your booking status on the webpage."
  : 'Please review and respond to this booking request in the CampusCut app.'}

---
CampusCut
`.trim();
}

/**
 * Generate Pending Booking HTML Email
 */
function generatePendingBookingHtml(
  details: PendingBookingEmailDetails, 
  recipient: 'consumer' | 'barber',
  frontendUrl: string
): string {
  const isConsumer = recipient === 'consumer';
  
  const title = isConsumer ? 'Booking Request Submitted' : 'New Booking Request';
  const subtitle = isConsumer 
    ? `Awaiting confirmation from ${details.barberName}`
    : `${details.consumerName} wants to book with you`;
  const statusText = 'PENDING CONFIRMATION';
  
  const ctaText = isConsumer ? 'Track Your Booking' : 'View Request';
  const ctaLink = `${frontendUrl}/web`; // Links to sign-in page, user redirected after login

  return `
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
</head>
<body style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; line-height: 1.6; color: #333; max-width: 600px; margin: 0 auto; padding: 20px; background-color: #f3f4f6;">
  <div style="background: linear-gradient(135deg, #5a7268 0%, #4a6258 100%); padding: 30px; text-align: center; border-radius: 12px 12px 0 0;">
    <h1 style="color: white; margin: 0; font-size: 28px;">CampusCut</h1>
    <p style="color: #d1e0d9; margin: 10px 0 0 0; font-size: 16px;">${title}</p>
  </div>
  
  <div style="background-color: #ffffff; padding: 30px; border-radius: 0 0 12px 12px; border: 1px solid #e5e7eb; border-top: none;">
    <h2 style="color: #3d5149; margin: 0 0 10px 0;">${isConsumer ? `Hi ${details.consumerName.split(' ')[0]}!` : `Hi ${details.barberName.split(' ')[0]}!`}</h2>
    <p style="color: #6b7280; margin: 0 0 20px 0;">${subtitle}</p>
    
    <!-- Status Badge -->
    <div style="text-align: center; margin: 20px 0;">
      <span style="display: inline-block; background-color: #f2f5f4; color: #5a7268; padding: 8px 16px; border-radius: 20px; font-size: 12px; font-weight: 600; letter-spacing: 1px;">
        ${statusText}
      </span>
    </div>
    
    <!-- Booking Details Card -->
    <div style="background-color: #f9fafb; border-radius: 12px; padding: 20px; margin: 20px 0;">
      <h3 style="color: #1f2937; margin: 0 0 15px 0; font-size: 16px;">Booking Request Details</h3>
      
      <table style="width: 100%; border-collapse: collapse;">
        <tr>
          <td style="color: #6b7280; padding: 5px 0;">Service</td>
          <td style="color: #1f2937; font-weight: 600; text-align: right; padding: 5px 0;">${details.serviceName}</td>
        </tr>
        <tr>
          <td style="color: #6b7280; padding: 5px 0;">Requested Date</td>
          <td style="color: #1f2937; font-weight: 600; text-align: right; padding: 5px 0;">${details.scheduledDate}</td>
        </tr>
        <tr>
          <td style="color: #6b7280; padding: 5px 0;">Requested Time</td>
          <td style="color: #1f2937; font-weight: 600; text-align: right; padding: 5px 0;">${details.scheduledTime}</td>
        </tr>
        ${details.location ? `
        <tr>
          <td style="color: #6b7280; padding: 5px 0;">Location</td>
          <td style="color: #1f2937; font-weight: 600; text-align: right; padding: 5px 0;">${details.location}</td>
        </tr>
        ` : ''}
      </table>
      
      <div style="border-top: 1px dashed #e5e7eb; margin: 15px 0; padding-top: 15px;">
        <table style="width: 100%; border-collapse: collapse;">
          <tr>
            <td style="color: #6b7280; font-weight: 600;">Total</td>
            <td style="color: #5a7268; font-weight: 700; font-size: 20px; text-align: right;">$${details.price.toFixed(2)}</td>
          </tr>
        </table>
      </div>
    </div>
    
    ${details.notes ? `
    <div style="background-color: #fefce8; border-radius: 8px; padding: 15px; margin: 15px 0;">
      <p style="color: #854d0e; margin: 0; font-size: 14px;"><strong>Notes:</strong> ${details.notes}</p>
    </div>
    ` : ''}
    
    <!-- Person Info -->
    <div style="background-color: #f2f5f4; border-radius: 8px; padding: 15px; margin: 20px 0;">
      <p style="color: #3d5149; margin: 0; font-size: 14px;">
        <strong>${isConsumer ? 'Your Barber:' : 'Customer:'}</strong> ${isConsumer ? details.barberName : details.consumerName}
      </p>
    </div>
    
    <!-- Reference -->
    <div style="text-align: center; margin: 20px 0;">
      <p style="color: #6b7280; margin: 0; font-size: 14px;">Booking Reference</p>
      <p style="color: #1f2937; margin: 5px 0 0 0; font-size: 18px; font-weight: 700; letter-spacing: 2px;">${details.bookingId.slice(0, 8).toUpperCase()}</p>
    </div>
    
    <p style="color: #6b7280; font-size: 14px; margin: 15px 0 20px 0;">
      ${isConsumer 
        ? "We'll notify you once the barber confirms your booking."
        : 'Please review and respond to this booking request.'}
    </p>
    
    <!-- CTA Button -->
    <table width="100%" cellpadding="0" cellspacing="0" border="0" style="margin: 10px 0 15px 0;">
      <tr>
        <td align="center">
          <a href="${ctaLink}" style="display: inline-block; background-color: #5a7268; color: white; padding: 14px 40px; text-decoration: none; border-radius: 8px; font-weight: 600; font-size: 16px;">
            ${ctaText}
          </a>
        </td>
      </tr>
    </table>
  </div>
  
  <div style="text-align: center; padding: 20px; color: #9ca3af; font-size: 12px;">
    <p style="margin: 0;">© ${new Date().getFullYear()} CampusCut</p>
  </div>
</body>
</html>
`.trim();
}

/**
 * Interface for booking edit email details
 */
interface BookingEditEmailDetails {
  consumerEmail: string;
  consumerName: string;
  barberEmail: string;
  barberName: string;
  serviceName: string;
  originalScheduledDate: string;
  originalScheduledTime: string;
  newScheduledDate: string;
  newScheduledTime: string;
  originalLocation?: string;
  newLocation?: string;
  originalNotes?: string;
  newNotes?: string;
  price: number;
  bookingId: string;
}

/**
 * Send Booking Edit Notification Emails
 * Sends notification emails to both consumer and barber when a booking is edited.
 */
export async function sendBookingEditEmails(details: BookingEditEmailDetails): Promise<void> {
  if (isAutoVerifyEnabled()) {
    logger.info(`[AUTO-VERIFY MODE] Skipping booking edit emails for booking ${details.bookingId}`);
    return;
  }

  const frontendUrl = process.env.FRONTEND_URL || 'https://campuscut.com';

  // Send to consumer
  try {
    const transporter = createTransporter();
    
    await transporter.sendMail({
      from: `CampusCut <${process.env.SMTP_USER}>`,
      to: details.consumerEmail,
      subject: `Booking Updated - Your ${details.serviceName} appointment has been rescheduled`,
      text: `Hi ${details.consumerName.split(' ')[0]}!\n\n${details.barberName} has made changes to your upcoming ${details.serviceName} appointment.\n\nWHAT CHANGED:\nOriginal: ${details.originalScheduledDate} at ${details.originalScheduledTime}\nNew: ${details.newScheduledDate} at ${details.newScheduledTime}\n\nBooking Reference: ${details.bookingId.slice(0, 8).toUpperCase()}\n\nIf you have questions, message your barber through the app.\n\n- CampusCut`,
      html: `
<!DOCTYPE html>
<html>
<head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0"></head>
<body style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; line-height: 1.6; color: #333; max-width: 600px; margin: 0 auto; padding: 20px; background-color: #f3f4f6;">
  <div style="background: linear-gradient(135deg, #022b19 0%, #034d2e 100%); padding: 30px; text-align: center; border-radius: 12px 12px 0 0;">
    <h1 style="color: white; margin: 0; font-size: 28px;">CampusCut</h1>
    <p style="color: #fbbf24; margin: 10px 0 0 0; font-size: 16px;">Booking Updated</p>
  </div>
  <div style="background-color: #ffffff; padding: 30px; border-radius: 0 0 12px 12px; border: 1px solid #e5e7eb; border-top: none;">
    <h2 style="color: #022b19; margin: 0 0 10px 0;">Hi ${details.consumerName.split(' ')[0]}!</h2>
    <p style="color: #6b7280; margin: 0 0 20px 0;">${details.barberName} has rescheduled your appointment</p>
    <div style="background-color: #fef3c7; border: 2px solid #f59e0b; border-radius: 12px; padding: 20px; margin: 20px 0;">
      <h3 style="color: #92400e; margin: 0 0 15px 0; font-size: 16px;">What Changed</h3>
      ${(details.originalScheduledDate !== details.newScheduledDate || details.originalScheduledTime !== details.newScheduledTime) ? `
      <div style="margin-bottom: 10px;">
        <p style="color: #6b7280; font-size: 12px; margin: 0 0 2px 0;">Date & Time</p>
        <p style="color: #6b7280; text-decoration: line-through; margin: 2px 0;">${details.originalScheduledDate} at ${details.originalScheduledTime}</p>
        <p style="color: #059669; font-weight: 700; font-size: 16px; margin: 2px 0;">→ ${details.newScheduledDate} at ${details.newScheduledTime}</p>
      </div>` : ''}
      ${(details.originalLocation && details.newLocation && details.originalLocation !== details.newLocation) ? `
      <div style="margin-bottom: 10px;">
        <p style="color: #6b7280; font-size: 12px; margin: 0 0 2px 0;">Location</p>
        <p style="color: #6b7280; text-decoration: line-through; margin: 2px 0;">${details.originalLocation}</p>
        <p style="color: #059669; font-weight: 700; font-size: 16px; margin: 2px 0;">→ ${details.newLocation}</p>
      </div>` : ''}
      ${(details.originalNotes !== details.newNotes) ? `
      <div style="margin-bottom: 10px;">
        <p style="color: #6b7280; font-size: 12px; margin: 0 0 2px 0;">Notes</p>
        ${details.originalNotes ? `<p style="color: #6b7280; text-decoration: line-through; margin: 2px 0;">${details.originalNotes}</p>` : '<p style="color: #6b7280; margin: 2px 0;">(no notes)</p>'}
        <p style="color: #059669; font-weight: 700; font-size: 16px; margin: 2px 0;">→ ${details.newNotes || '(removed)'}</p>
      </div>` : ''}
    </div>
    <div style="background-color: #f9fafb; border-radius: 12px; padding: 20px; margin: 20px 0;">
      <p><strong>Service:</strong> ${details.serviceName}</p>
      <p><strong>Price:</strong> <span style="color: #5a7268; font-weight: 700;">$${details.price.toFixed(2)}</span></p>
      ${details.newLocation ? `<p><strong>Location:</strong> ${details.newLocation}</p>` : ''}
    </div>
    <div style="text-align: center; margin: 20px 0;">
      <p style="color: #6b7280; margin: 0; font-size: 14px;">Booking Reference</p>
      <p style="color: #1f2937; margin: 5px 0 0 0; font-size: 18px; font-weight: 700;">${details.bookingId.slice(0, 8).toUpperCase()}</p>
    </div>
    <p style="text-align: center; margin: 30px 0;">
      <a href="${frontendUrl}/web" style="display: inline-block; background-color: #f59e0b; color: white; padding: 14px 40px; text-decoration: none; border-radius: 8px; font-weight: 600;">View Updated Booking</a>
    </p>
  </div>
  <div style="text-align: center; padding: 20px; color: #9ca3af; font-size: 12px;">© ${new Date().getFullYear()} CampusCut</div>
</body>
</html>`.trim()
    });
    logger.info(`Booking edit email sent to consumer: ${details.consumerEmail}`);
  } catch (error: any) {
    logger.error(`Failed to send booking edit email to consumer:`, error.message);
  }

  // Send to barber
  try {
    const transporter = createTransporter();
    
    await transporter.sendMail({
      from: `CampusCut <${process.env.SMTP_USER}>`,
      to: details.barberEmail,
      subject: `Booking Updated - Confirmation of changes to ${details.consumerName}'s appointment`,
      text: `Hi ${details.barberName.split(' ')[0]}!\n\nThis confirms your changes to the ${details.serviceName} appointment with ${details.consumerName}.\n\nWHAT CHANGED:\nOriginal: ${details.originalScheduledDate} at ${details.originalScheduledTime}\nNew: ${details.newScheduledDate} at ${details.newScheduledTime}\n\nBooking Reference: ${details.bookingId.slice(0, 8).toUpperCase()}\n\nThe customer has been notified of this change.\n\n- CampusCut`,
      html: `
<!DOCTYPE html>
<html>
<head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0"></head>
<body style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; line-height: 1.6; color: #333; max-width: 600px; margin: 0 auto; padding: 20px; background-color: #f3f4f6;">
  <div style="background: linear-gradient(135deg, #022b19 0%, #034d2e 100%); padding: 30px; text-align: center; border-radius: 12px 12px 0 0;">
    <h1 style="color: white; margin: 0; font-size: 28px;">CampusCut</h1>
    <p style="color: #fbbf24; margin: 10px 0 0 0; font-size: 16px;">Booking Updated</p>
  </div>
  <div style="background-color: #ffffff; padding: 30px; border-radius: 0 0 12px 12px; border: 1px solid #e5e7eb; border-top: none;">
    <h2 style="color: #022b19; margin: 0 0 10px 0;">Hi ${details.barberName.split(' ')[0]}!</h2>
    <p style="color: #6b7280; margin: 0 0 20px 0;">Confirmation of your changes</p>
    <div style="background-color: #fef3c7; border: 2px solid #f59e0b; border-radius: 12px; padding: 20px; margin: 20px 0;">
      <h3 style="color: #92400e; margin: 0 0 15px 0; font-size: 16px;">What Changed</h3>
      ${(details.originalScheduledDate !== details.newScheduledDate || details.originalScheduledTime !== details.newScheduledTime) ? `
      <div style="margin-bottom: 10px;">
        <p style="color: #6b7280; font-size: 12px; margin: 0 0 2px 0;">Date & Time</p>
        <p style="color: #6b7280; text-decoration: line-through; margin: 2px 0;">${details.originalScheduledDate} at ${details.originalScheduledTime}</p>
        <p style="color: #059669; font-weight: 700; font-size: 16px; margin: 2px 0;">→ ${details.newScheduledDate} at ${details.newScheduledTime}</p>
      </div>` : ''}
      ${(details.originalLocation && details.newLocation && details.originalLocation !== details.newLocation) ? `
      <div style="margin-bottom: 10px;">
        <p style="color: #6b7280; font-size: 12px; margin: 0 0 2px 0;">Location</p>
        <p style="color: #6b7280; text-decoration: line-through; margin: 2px 0;">${details.originalLocation}</p>
        <p style="color: #059669; font-weight: 700; font-size: 16px; margin: 2px 0;">→ ${details.newLocation}</p>
      </div>` : ''}
      ${(details.originalNotes !== details.newNotes) ? `
      <div style="margin-bottom: 10px;">
        <p style="color: #6b7280; font-size: 12px; margin: 0 0 2px 0;">Notes</p>
        ${details.originalNotes ? `<p style="color: #6b7280; text-decoration: line-through; margin: 2px 0;">${details.originalNotes}</p>` : '<p style="color: #6b7280; margin: 2px 0;">(no notes)</p>'}
        <p style="color: #059669; font-weight: 700; font-size: 16px; margin: 2px 0;">→ ${details.newNotes || '(removed)'}</p>
      </div>` : ''}
    </div>
    <div style="background-color: #f9fafb; border-radius: 12px; padding: 20px; margin: 20px 0;">
      <p><strong>Customer:</strong> ${details.consumerName}</p>
      <p><strong>Service:</strong> ${details.serviceName}</p>
      <p><strong>Price:</strong> <span style="color: #5a7268; font-weight: 700;">$${details.price.toFixed(2)}</span></p>
      ${details.newLocation ? `<p><strong>Location:</strong> ${details.newLocation}</p>` : ''}
    </div>
    <div style="text-align: center; margin: 20px 0;">
      <p style="color: #6b7280; margin: 0; font-size: 14px;">Booking Reference</p>
      <p style="color: #1f2937; margin: 5px 0 0 0; font-size: 18px; font-weight: 700;">${details.bookingId.slice(0, 8).toUpperCase()}</p>
    </div>
    <p style="color: #166534; text-align: center; font-size: 14px;">The customer has been notified of this change.</p>
    <p style="text-align: center; margin: 30px 0;">
      <a href="${frontendUrl}/web" style="display: inline-block; background-color: #f59e0b; color: white; padding: 14px 40px; text-decoration: none; border-radius: 8px; font-weight: 600;">View Booking</a>
    </p>
  </div>
  <div style="text-align: center; padding: 20px; color: #9ca3af; font-size: 12px;">© ${new Date().getFullYear()} CampusCut</div>
</body>
</html>`.trim()
    });
    logger.info(`Booking edit email sent to barber: ${details.barberEmail}`);
  } catch (error: any) {
    logger.error(`Failed to send booking edit email to barber:`, error.message);
  }
}

/**
 * Booking Completed Email Details Interface
 */
interface BookingCompletedEmailDetails {
  bookingId: string;
  serviceName: string;
  price: number; // in dollars
  scheduledDate: string;
  scheduledTime: string;
  location?: string;
  consumerName: string;
  consumerEmail: string;
  barberName: string;
  barberEmail: string;
  paymentUrl: string;
}

/**
 * Send Booking Completed Emails
 * 
 * Sends emails to both consumer and barber when a booking is marked as complete.
 * Consumer email includes a link to the payment page.
 * 
 * @param details - Booking completed details
 */
export async function sendBookingCompletedEmails(details: BookingCompletedEmailDetails): Promise<void> {
  logger.info(`[BOOKING COMPLETE EMAIL] Starting email send for booking ${details.bookingId}`);
  logger.info(`[BOOKING COMPLETE EMAIL] Consumer: ${details.consumerName} <${details.consumerEmail}>`);
  logger.info(`[BOOKING COMPLETE EMAIL] Barber: ${details.barberName} <${details.barberEmail}>`);
  logger.info(`[BOOKING COMPLETE EMAIL] Service: ${details.serviceName}, Price: $${details.price}`);
  logger.info(`[BOOKING COMPLETE EMAIL] Payment URL: ${details.paymentUrl}`);
  
  if (isAutoVerifyEnabled()) {
    logger.info(`[AUTO-VERIFY MODE] Skipping booking completed emails for booking ${details.bookingId}`);
    return;
  }

  // Validate required fields
  if (!details.consumerEmail) {
    logger.error(`[BOOKING COMPLETE EMAIL] Missing consumer email for booking ${details.bookingId}`);
    return;
  }

  const frontendUrl = process.env.FRONTEND_URL || 'https://campuscut.com';

  // Send to consumer - Payment Request
  try {
    logger.info(`[BOOKING COMPLETE EMAIL] Creating transporter for consumer email...`);
    const transporter = createTransporter();
    
    const consumerMailOptions = {
      from: `CampusCut <${process.env.SMTP_USER}>`,
      to: details.consumerEmail,
      subject: `Payment Required: Your ${details.serviceName} is Complete!`,
      text: generateBookingCompletedText(details, 'consumer'),
      html: generateBookingCompletedHtml(details, 'consumer', frontendUrl)
    };

    logger.info(`[BOOKING COMPLETE EMAIL] Sending consumer email to ${details.consumerEmail}...`);
    await transporter.sendMail(consumerMailOptions);
    logger.info(`[BOOKING COMPLETE EMAIL] ✅ Consumer email sent successfully to: ${details.consumerEmail}`);
  } catch (error: any) {
    logger.error(`[BOOKING COMPLETE EMAIL] ❌ Failed to send consumer email to ${details.consumerEmail}:`, error.message);
    logger.error(`[BOOKING COMPLETE EMAIL] Full error:`, error);
  }

  // Send to barber - Service Complete Confirmation
  try {
    if (!details.barberEmail) {
      logger.warn(`[BOOKING COMPLETE EMAIL] Missing barber email for booking ${details.bookingId}, skipping barber notification`);
    } else {
      logger.info(`[BOOKING COMPLETE EMAIL] Sending barber confirmation email to ${details.barberEmail}...`);
      const transporter = createTransporter();
      
      const barberMailOptions = {
        from: `CampusCut <${process.env.SMTP_USER}>`,
        to: details.barberEmail,
        subject: `Service Complete: ${details.serviceName} with ${details.consumerName}`,
        text: generateBookingCompletedText(details, 'barber'),
        html: generateBookingCompletedHtml(details, 'barber', frontendUrl)
      };

      await transporter.sendMail(barberMailOptions);
      logger.info(`[BOOKING COMPLETE EMAIL] ✅ Barber email sent successfully to: ${details.barberEmail}`);
    }
  } catch (error: any) {
    logger.error(`[BOOKING COMPLETE EMAIL] ❌ Failed to send barber email to ${details.barberEmail}:`, error.message);
    logger.error(`[BOOKING COMPLETE EMAIL] Full error:`, error);
  }
  
  logger.info(`[BOOKING COMPLETE EMAIL] Finished processing emails for booking ${details.bookingId}`);
}

/**
 * Generate Booking Completed Plain Text
 */
function generateBookingCompletedText(
  details: BookingCompletedEmailDetails, 
  recipient: 'consumer' | 'barber'
): string {
  const isConsumer = recipient === 'consumer';
  const firstName = isConsumer 
    ? details.consumerName.split(' ')[0] 
    : details.barberName.split(' ')[0];

  if (isConsumer) {
    return `
Hi ${firstName}!

Your ${details.serviceName} with ${details.barberName} is complete!

BOOKING DETAILS
---------------
Service: ${details.serviceName}
Date: ${details.scheduledDate}
Time: ${details.scheduledTime}
${details.location ? `Location: ${details.location}` : ''}
Barber: ${details.barberName}

PAYMENT REQUIRED
----------------
Amount Due: $${details.price.toFixed(2)}

Please complete your payment by visiting:
${details.paymentUrl}

Thank you for choosing CampusCut!

Booking Reference: ${details.bookingId.slice(0, 8).toUpperCase()}

---
CampusCut
`.trim();
  } else {
    return `
Hi ${firstName}!

Great job! You've completed a service.

SERVICE DETAILS
---------------
Service: ${details.serviceName}
Customer: ${details.consumerName}
Date: ${details.scheduledDate}
Time: ${details.scheduledTime}
${details.location ? `Location: ${details.location}` : ''}
Amount: $${details.price.toFixed(2)}

A payment request has been sent to ${details.consumerName}. You'll be notified when payment is received.

Booking Reference: ${details.bookingId.slice(0, 8).toUpperCase()}

---
CampusCut
`.trim();
  }
}

/**
 * Generate Booking Completed HTML Email
 */
function generateBookingCompletedHtml(
  details: BookingCompletedEmailDetails, 
  recipient: 'consumer' | 'barber',
  frontendUrl: string
): string {
  const isConsumer = recipient === 'consumer';
  const firstName = isConsumer 
    ? details.consumerName.split(' ')[0] 
    : details.barberName.split(' ')[0];

  const headerColor = isConsumer ? '#5a7268' : '#3b82f6'; // Primary green for consumer (pay), Blue for barber
  const headerText = isConsumer ? 'Payment Required' : 'Service Complete';
  const headerEmoji = isConsumer ? '' : '✅'; // No emoji for consumer, show CampusCut text instead

  const ctaButton = isConsumer
    ? `<a href="${details.paymentUrl}" style="display: inline-block; background-color: #5a7268; color: white; padding: 16px 48px; text-decoration: none; border-radius: 12px; font-weight: 700; font-size: 18px;">Pay $${details.price.toFixed(2)} Now</a>`
    : `<a href="${frontendUrl}/web/barber" style="display: inline-block; background-color: #3b82f6; color: white; padding: 14px 40px; text-decoration: none; border-radius: 8px; font-weight: 600;">View Dashboard</a>`;

  const introText = isConsumer
    ? `Your <strong>${details.serviceName}</strong> with <strong>${details.barberName}</strong> is complete! Please complete your payment to finish the booking.`
    : `Great job! You've completed a <strong>${details.serviceName}</strong> with <strong>${details.consumerName}</strong>. A payment request has been sent.`;

  return `
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
</head>
<body style="margin: 0; padding: 0; background-color: #f3f4f6; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;">
  <div style="max-width: 500px; margin: 40px auto; background-color: white; border-radius: 16px; overflow: hidden; box-shadow: 0 4px 6px rgba(0,0,0,0.1);">
    <div style="background-color: ${headerColor}; padding: 30px 20px; text-align: center;">
      ${isConsumer 
        ? `<span style="font-size: 28px; font-weight: 700; color: white; letter-spacing: -1px;">CampusCut</span>`
        : `<span style="font-size: 48px;">${headerEmoji}</span>`
      }
      <h1 style="color: white; margin: 10px 0 0 0; font-size: 24px;">${headerText}</h1>
    </div>
    <div style="padding: 30px;">
      <p style="color: #1f2937; font-size: 16px; margin: 0 0 20px 0;">Hi ${firstName}!</p>
      <p style="color: #4b5563; font-size: 15px; line-height: 1.6; margin: 0 0 25px 0;">${introText}</p>
      
      <div style="background-color: #f9fafb; border-radius: 12px; padding: 20px; margin: 20px 0;">
        <h3 style="color: #1f2937; margin: 0 0 15px 0; font-size: 14px; text-transform: uppercase; letter-spacing: 0.5px;">Booking Details</h3>
        <table style="width: 100%; border-collapse: collapse;">
          <tr>
            <td style="padding: 8px 0; color: #6b7280; font-size: 14px;">Service</td>
            <td style="padding: 8px 0; color: #1f2937; font-weight: 600; text-align: right;">${details.serviceName}</td>
          </tr>
          <tr>
            <td style="padding: 8px 0; color: #6b7280; font-size: 14px;">Date</td>
            <td style="padding: 8px 0; color: #1f2937; font-weight: 600; text-align: right;">${details.scheduledDate}</td>
          </tr>
          <tr>
            <td style="padding: 8px 0; color: #6b7280; font-size: 14px;">Time</td>
            <td style="padding: 8px 0; color: #1f2937; font-weight: 600; text-align: right;">${details.scheduledTime}</td>
          </tr>
          ${details.location ? `
          <tr>
            <td style="padding: 8px 0; color: #6b7280; font-size: 14px;">Location</td>
            <td style="padding: 8px 0; color: #1f2937; font-weight: 600; text-align: right;">${details.location}</td>
          </tr>` : ''}
          <tr>
            <td style="padding: 8px 0; color: #6b7280; font-size: 14px;">${isConsumer ? 'Barber' : 'Customer'}</td>
            <td style="padding: 8px 0; color: #1f2937; font-weight: 600; text-align: right;">${isConsumer ? details.barberName : details.consumerName}</td>
          </tr>
        </table>
        <div style="border-top: 2px solid #e5e7eb; margin-top: 15px; padding-top: 15px;">
          <table style="width: 100%;">
            <tr>
              <td style="color: #1f2937; font-size: 18px; font-weight: 700;">${isConsumer ? 'Amount Due' : 'Amount'}</td>
              <td style="color: #5a7268; font-size: 24px; font-weight: 700; text-align: right;">$${details.price.toFixed(2)}</td>
            </tr>
          </table>
        </div>
      </div>

      <div style="text-align: center; margin: 30px 0;">
        ${ctaButton}
      </div>

      ${isConsumer ? `
      <p style="color: #6b7280; font-size: 13px; text-align: center; margin: 20px 0 0 0;">
        You can also pay by opening the CampusCut app and navigating to your booking.
      </p>` : `
      <p style="color: #6b7280; font-size: 13px; text-align: center; margin: 20px 0 0 0;">
        You'll receive a notification when ${details.consumerName.split(' ')[0]} completes their payment.
      </p>`}

      <div style="text-align: center; margin: 25px 0 0 0;">
        <p style="color: #9ca3af; font-size: 12px; margin: 0;">Booking Reference</p>
        <p style="color: #1f2937; font-size: 16px; font-weight: 700; margin: 5px 0 0 0;">${details.bookingId.slice(0, 8).toUpperCase()}</p>
      </div>
    </div>
    <div style="background-color: #f9fafb; padding: 20px; text-align: center;">
      <p style="color: #9ca3af; font-size: 12px; margin: 0;">© ${new Date().getFullYear()} CampusCut</p>
    </div>
  </div>
</body>
</html>`.trim();
}

/**
 * Barber Application Email Details Interface
 */
interface BarberApplicationEmailDetails {
  applicantName: string;
  applicantEmail: string;
  applicantPhone?: string;
  campusName: string;
  yearsExperience: string;
  hasLicense: boolean;
  licenseNumber?: string;
  specialties: string[];
  hasOwnTools: boolean;
  availableHours: string;
  whyBeBarber: string;
  portfolioDescription?: string;
  socialMedia?: string;
  additionalNotes?: string;
  applicationId: string;
  submittedAt: string;
}

/**
 * Send Barber Application Notification to Campus Manager
 * 
 * Sends an email to the campus manager when a new barber application is submitted.
 * Includes the full application details and incentive to schedule an interview.
 * 
 * @param campusManagerEmail - Campus manager's email address
 * @param campusManagerName - Campus manager's name
 * @param details - Full barber application details
 */
export async function sendBarberApplicationNotification(
  campusManagerEmail: string,
  campusManagerName: string,
  details: BarberApplicationEmailDetails
): Promise<void> {
  if (isAutoVerifyEnabled()) {
    logger.info(`[AUTO-VERIFY MODE] Skipping barber application notification for ${details.applicantName}`);
    return;
  }

  try {
    const transporter = createTransporter();
    const frontendUrl = process.env.FRONTEND_URL || 'https://campuscut.com';

    const mailOptions = {
      from: `CampusCut <${process.env.SMTP_USER}>`,
      to: campusManagerEmail,
      subject: `New Barber Application: ${details.applicantName} wants to join ${details.campusName}`,
      text: generateBarberApplicationText(campusManagerName, details),
      html: generateBarberApplicationHtml(campusManagerName, details, frontendUrl)
    };

    await transporter.sendMail(mailOptions);
    logger.info(`Barber application notification sent to campus manager: ${campusManagerEmail}`);
  } catch (error: any) {
    logger.error(`Failed to send barber application notification to ${campusManagerEmail}:`, error.message);
    // Don't throw - application notification is non-critical
  }
}

/**
 * Generate Barber Application Plain Text Email
 */
function generateBarberApplicationText(
  campusManagerName: string,
  details: BarberApplicationEmailDetails
): string {
  const firstName = campusManagerName.split(' ')[0];
  
  return `
Hi ${firstName}!

Great news! You have a new barber application on CampusCut.

APPLICANT INFORMATION
---------------------
Name: ${details.applicantName}
Email: ${details.applicantEmail}
Phone: ${details.applicantPhone || 'Not provided'}
Campus: ${details.campusName}
Submitted: ${details.submittedAt}

APPLICATION DETAILS
-------------------
Years of Experience: ${details.yearsExperience}
Licensed: ${details.hasLicense ? 'Yes' : 'No'}${details.licenseNumber ? ` (License #: ${details.licenseNumber})` : ''}
Has Own Tools: ${details.hasOwnTools ? 'Yes' : 'No'}
Available Hours: ${details.availableHours}

Services/Specialties: ${details.specialties.join(', ')}

Why They Want to Be a Barber:
"${details.whyBeBarber}"

${details.portfolioDescription ? `Portfolio/Experience:\n"${details.portfolioDescription}"\n` : ''}
${details.socialMedia ? `Social Media: ${details.socialMedia}\n` : ''}
${details.additionalNotes ? `Additional Notes:\n"${details.additionalNotes}"\n` : ''}

ACTION REQUIRED
---------------
Review this application and consider scheduling an interview with ${details.applicantName.split(' ')[0]}.

To schedule an interview, simply reply to this email or send an email to:
${details.applicantEmail}

Suggested interview topics:
- Verify their experience and skills
- Discuss availability and commitment
- Review any portfolio or previous work
- Explain CampusCut policies and expectations

Application Reference: ${details.applicationId.slice(0, 8).toUpperCase()}

---
CampusCut
`.trim();
}

/**
 * Generate Barber Application HTML Email
 */
function generateBarberApplicationHtml(
  campusManagerName: string,
  details: BarberApplicationEmailDetails,
  frontendUrl: string
): string {
  const firstName = campusManagerName.split(' ')[0];
  const applicantFirstName = details.applicantName.split(' ')[0];
  
  return `
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
</head>
<body style="margin: 0; padding: 0; background-color: #f3f4f6; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;">
  <div style="max-width: 600px; margin: 40px auto; background-color: white; border-radius: 16px; overflow: hidden; box-shadow: 0 4px 6px rgba(0,0,0,0.1);">
    <!-- Header -->
    <div style="background: linear-gradient(135deg, #022b19 0%, #034d2e 100%); padding: 30px 20px; text-align: center;">
      <h1 style="color: white; margin: 10px 0 5px 0; font-size: 24px;">New Barber Application</h1>
      <p style="color: #4ade80; margin: 0; font-size: 14px;">Someone wants to join your campus</p>
    </div>
    
    <div style="padding: 30px;">
      <p style="color: #1f2937; font-size: 16px; margin: 0 0 20px 0;">Hi ${firstName}!</p>
      <p style="color: #4b5563; font-size: 15px; line-height: 1.6; margin: 0 0 25px 0;">
        Great news! <strong>${details.applicantName}</strong> has submitted an application to become a barber at <strong>${details.campusName}</strong>.
      </p>
      
      <!-- Applicant Card -->
      <div style="background-color: #f2f5f4; border: 2px solid #5a7268; border-radius: 12px; padding: 20px; margin: 20px 0;">
        <div style="margin-bottom: 15px;">
          <h3 style="color: #2e3c38; margin: 0; font-size: 18px;">${details.applicantName}</h3>
          <p style="color: #445750; margin: 5px 0 0 0; font-size: 14px;">
            <a href="mailto:${details.applicantEmail}" style="color: #5a7268;">${details.applicantEmail}</a>
          </p>
          ${details.applicantPhone ? `
          <p style="color: #445750; margin: 5px 0 0 0; font-size: 14px;">
            <a href="tel:${details.applicantPhone}" style="color: #5a7268;">${details.applicantPhone}</a>
          </p>
          ` : ''}
        </div>
        <p style="color: #6b7280; font-size: 12px; margin: 0;">Submitted ${details.submittedAt}</p>
      </div>
      
      <!-- Application Details -->
      <div style="background-color: #f9fafb; border-radius: 12px; padding: 25px; margin: 20px 0;">
        <h3 style="color: #1f2937; margin: 0 0 20px 0; font-size: 16px; text-transform: uppercase; letter-spacing: 0.5px;">Application Details</h3>
        
        <table style="width: 100%; border-collapse: collapse;">
          <tr>
            <td style="padding: 10px 0; border-bottom: 1px solid #e5e7eb; color: #6b7280; width: 40%;">Years of Experience</td>
            <td style="padding: 10px 0; border-bottom: 1px solid #e5e7eb; color: #1f2937; font-weight: 600;">${details.yearsExperience}</td>
          </tr>
          <tr>
            <td style="padding: 10px 0; border-bottom: 1px solid #e5e7eb; color: #6b7280;">Has Own Tools</td>
            <td style="padding: 10px 0; border-bottom: 1px solid #e5e7eb; color: ${details.hasOwnTools ? '#5a7268' : '#6b7280'}; font-weight: 600;">
              ${details.hasOwnTools ? '✓ Yes' : 'No'}
            </td>
          </tr>
          <tr>
            <td style="padding: 10px 0; border-bottom: 1px solid #e5e7eb; color: #6b7280;">Available Hours</td>
            <td style="padding: 10px 0; border-bottom: 1px solid #e5e7eb; color: #1f2937; font-weight: 600;">${details.availableHours}</td>
          </tr>
        </table>
      </div>
      
      <!-- Specialties -->
      <div style="margin: 20px 0;">
        <h4 style="color: #1f2937; margin: 0 0 10px 0; font-size: 14px;">Services/Specialties:</h4>
        <div style="display: flex; flex-wrap: wrap; gap: 8px;">
          ${details.specialties.map(s => `<span style="display: inline-block; background-color: #e6ebea; color: #2e3c38; padding: 6px 12px; border-radius: 20px; font-size: 13px; font-weight: 500;">${s}</span>`).join('')}
        </div>
      </div>
      
      <!-- Why They Want to Be a Barber -->
      <div style="background-color: #f2f5f4; border: 1px solid #bfcdc8; border-radius: 12px; padding: 20px; margin: 20px 0;">
        <h4 style="color: #445750; margin: 0 0 10px 0; font-size: 14px;">Why They Want to Be a CampusCut Barber:</h4>
        <p style="color: #2e3c38; margin: 0; font-style: italic; line-height: 1.6;">"${details.whyBeBarber}"</p>
      </div>
      
      ${details.portfolioDescription ? `
      <div style="background-color: #f3f4f6; border-radius: 12px; padding: 20px; margin: 20px 0;">
        <h4 style="color: #1f2937; margin: 0 0 10px 0; font-size: 14px;">Portfolio/Experience:</h4>
        <p style="color: #4b5563; margin: 0; line-height: 1.6;">"${details.portfolioDescription}"</p>
      </div>
      ` : ''}
      
      ${details.socialMedia ? `
      <div style="margin: 15px 0;">
        <p style="color: #6b7280; margin: 0; font-size: 14px;">
          <strong>Social Media:</strong> 
          <a href="${details.socialMedia.startsWith('http') ? details.socialMedia : 'https://' + details.socialMedia}" style="color: #2563eb;">${details.socialMedia}</a>
        </p>
      </div>
      ` : ''}
      
      ${details.additionalNotes ? `
      <div style="background-color: #f3f4f6; border-radius: 12px; padding: 20px; margin: 20px 0;">
        <h4 style="color: #1f2937; margin: 0 0 10px 0; font-size: 14px;">Additional Notes:</h4>
        <p style="color: #4b5563; margin: 0; line-height: 1.6;">"${details.additionalNotes}"</p>
      </div>
      ` : ''}
      
      <!-- Action Required -->
      <div style="background-color: #f2f5f4; border: 2px solid #5a7268; border-radius: 12px; padding: 25px; margin: 25px 0; text-align: center;">
        <h3 style="color: #2e3c38; margin: 0 0 15px 0;">Ready to Schedule an Interview?</h3>
        <p style="color: #445750; margin: 0 0 20px 0; font-size: 14px; line-height: 1.6;">
          ${applicantFirstName} is excited to join your campus! Consider reaching out to schedule a quick interview to verify their skills and discuss expectations.
        </p>
        <a href="mailto:${details.applicantEmail}?subject=CampusCut%20Barber%20Application%20-%20Interview%20Request&body=Hi%20${encodeURIComponent(applicantFirstName)}%2C%0A%0AThank%20you%20for%20applying%20to%20become%20a%20barber%20on%20CampusCut!%20I'd%20like%20to%20schedule%20a%20brief%20interview%20to%20learn%20more%20about%20your%20experience.%0A%0AAre%20you%20available%20for%20a%2015-minute%20call%20this%20week%3F%0A%0ABest%2C%0A${encodeURIComponent(firstName)}" 
           style="display: inline-block; background-color: #5a7268; color: white; padding: 14px 32px; text-decoration: none; border-radius: 8px; font-weight: 600; font-size: 16px;">
          Email ${applicantFirstName} for Interview
        </a>
      </div>
      
      <!-- Interview Tips -->
      <div style="background-color: #f9fafb; border-radius: 8px; padding: 20px; margin: 20px 0;">
        <h4 style="color: #1f2937; margin: 0 0 15px 0; font-size: 14px;">Interview Tips:</h4>
        <ul style="color: #4b5563; margin: 0; padding-left: 20px; font-size: 14px; line-height: 1.8;">
          <li>Ask about specific haircut styles they're comfortable with</li>
          <li>Discuss their availability and commitment level</li>
          <li>Request to see any portfolio photos or previous work</li>
          <li>Explain CampusCut policies, pricing, and expectations</li>
          <li>Gauge their professionalism and communication skills</li>
        </ul>
      </div>
      
      <!-- Reference -->
      <div style="text-align: center; margin: 25px 0;">
        <p style="color: #9ca3af; margin: 0; font-size: 12px;">Application Reference</p>
        <p style="color: #1f2937; margin: 5px 0 0 0; font-size: 16px; font-weight: 700; letter-spacing: 2px;">${details.applicationId.slice(0, 8).toUpperCase()}</p>
      </div>
      
      <!-- Dashboard Link -->
      <p style="text-align: center; margin: 25px 0;">
        <a href="${frontendUrl}/web" style="display: inline-block; background-color: #5a7268; color: white; padding: 12px 30px; text-decoration: none; border-radius: 8px; font-weight: 600; font-size: 14px;">
          View in Dashboard
        </a>
      </p>
    </div>
    
    <div style="background-color: #f9fafb; padding: 20px; text-align: center;">
      <p style="color: #9ca3af; font-size: 12px; margin: 0;">© ${new Date().getFullYear()} CampusCut</p>
    </div>
  </div>
</body>
</html>`.trim();
}

/**
 * Booking Cancellation Email Details Interface
 */
interface AlternativeBarberInfo {
  id: string;
  name: string;
  avatar?: string;
  avgRating?: number;
  totalReviews?: number;
}

interface BookingCancellationEmailDetails {
  bookingId: string;
  serviceName: string;
  serviceType: string;
  price: number; // in dollars
  scheduledDate: string;
  scheduledTime: string;
  scheduledDateTime?: string; // ISO string for alternative barbers link
  location?: string;
  consumerName: string;
  consumerEmail: string;
  barberName: string;
  barberEmail: string;
  cancelledBy: 'consumer' | 'barber';
  reason?: string;
  alternativeBarbers?: AlternativeBarberInfo[];
}

/**
 * Send Booking Cancellation Emails
 * 
 * Sends cancellation receipt emails to both consumer and barber when a booking is cancelled.
 * 
 * @param details - Booking cancellation details
 */
export async function sendBookingCancellationEmails(details: BookingCancellationEmailDetails): Promise<void> {
  if (isAutoVerifyEnabled()) {
    logger.info(`[AUTO-VERIFY MODE] Skipping booking cancellation emails for booking ${details.bookingId}`);
    return;
  }

  const frontendUrl = process.env.FRONTEND_URL || 'https://campuscut.com';

  // Send to consumer
  try {
    const transporter = createTransporter();
    
    const consumerSubject = details.cancelledBy === 'consumer'
      ? `Booking Cancelled: Your ${details.serviceName} appointment`
      : `Booking Cancelled: ${details.barberName} cancelled your appointment`;
    
    const consumerMailOptions = {
      from: `CampusCut <${process.env.SMTP_USER}>`,
      to: details.consumerEmail,
      subject: consumerSubject,
      text: generateBookingCancellationText(details, 'consumer'),
      html: generateBookingCancellationHtml(details, 'consumer', frontendUrl)
    };

    await transporter.sendMail(consumerMailOptions);
    logger.info(`Booking cancellation email sent to consumer: ${details.consumerEmail}`);
  } catch (error: any) {
    logger.error(`Failed to send booking cancellation email to consumer ${details.consumerEmail}:`, error.message);
  }

  // Send to barber
  try {
    const transporter = createTransporter();
    
    const barberSubject = details.cancelledBy === 'barber'
      ? `Booking Cancelled: Your ${details.serviceName} with ${details.consumerName}`
      : `Booking Cancelled: ${details.consumerName} cancelled their appointment`;
    
    const barberMailOptions = {
      from: `CampusCut <${process.env.SMTP_USER}>`,
      to: details.barberEmail,
      subject: barberSubject,
      text: generateBookingCancellationText(details, 'barber'),
      html: generateBookingCancellationHtml(details, 'barber', frontendUrl)
    };

    await transporter.sendMail(barberMailOptions);
    logger.info(`Booking cancellation email sent to barber: ${details.barberEmail}`);
  } catch (error: any) {
    logger.error(`Failed to send booking cancellation email to barber ${details.barberEmail}:`, error.message);
  }
}

/**
 * Generate Booking Cancellation Plain Text
 */
function generateBookingCancellationText(
  details: BookingCancellationEmailDetails, 
  recipient: 'consumer' | 'barber'
): string {
  const isConsumer = recipient === 'consumer';
  const firstName = isConsumer 
    ? details.consumerName.split(' ')[0] 
    : details.barberName.split(' ')[0];
  
  const cancelledByYou = (isConsumer && details.cancelledBy === 'consumer') || 
                         (!isConsumer && details.cancelledBy === 'barber');
  
  const otherPartyName = isConsumer ? details.barberName : details.consumerName;

  const intro = cancelledByYou
    ? `This confirms that you have cancelled your ${details.serviceName} appointment.`
    : `${otherPartyName} has cancelled the ${details.serviceName} appointment.`;

  return `
Hi ${firstName},

${intro}

CANCELLED BOOKING DETAILS
-------------------------
Service: ${details.serviceName}
Originally Scheduled: ${details.scheduledDate} at ${details.scheduledTime}
${details.location ? `Location: ${details.location}` : ''}
${isConsumer ? 'Barber' : 'Customer'}: ${otherPartyName}
Price: $${details.price.toFixed(2)}
${details.reason ? `\nReason: ${details.reason}` : ''}

Booking Reference: ${details.bookingId.slice(0, 8).toUpperCase()}

${isConsumer 
  ? 'We hope to see you again soon! You can book a new appointment anytime.'
  : cancelledByYou 
    ? 'The customer has been notified of this cancellation.'
    : 'This time slot is now available for other bookings.'}

---
CampusCut
`.trim();
}

/**
 * Generate Booking Cancellation HTML Email
 */
function generateBookingCancellationHtml(
  details: BookingCancellationEmailDetails, 
  recipient: 'consumer' | 'barber',
  frontendUrl: string
): string {
  const isConsumer = recipient === 'consumer';
  const firstName = isConsumer 
    ? details.consumerName.split(' ')[0] 
    : details.barberName.split(' ')[0];
  
  const cancelledByYou = (isConsumer && details.cancelledBy === 'consumer') || 
                         (!isConsumer && details.cancelledBy === 'barber');
  
  const otherPartyName = isConsumer ? details.barberName : details.consumerName;

  const introText = cancelledByYou
    ? `This confirms that you have cancelled your <strong>${details.serviceName}</strong> appointment.`
    : `<strong>${otherPartyName}</strong> has cancelled the <strong>${details.serviceName}</strong> appointment.`;

  const ctaText = isConsumer ? 'Book New Appointment' : 'View Dashboard';
  const ctaLink = isConsumer ? `${frontendUrl}/web/auth` : `${frontendUrl}/web/barber`;

  return `
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
</head>
<body style="margin: 0; padding: 0; background-color: #f3f4f6; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;">
  <div style="max-width: 500px; margin: 40px auto; background-color: white; border-radius: 16px; overflow: hidden; box-shadow: 0 4px 6px rgba(0,0,0,0.1);">
    <div style="background-color: #ef4444; padding: 30px 20px; text-align: center;">
      <span style="font-size: 48px;">❌</span>
      <h1 style="color: white; margin: 10px 0 0 0; font-size: 24px;">Booking Cancelled</h1>
    </div>
    <div style="padding: 30px;">
      <p style="color: #1f2937; font-size: 16px; margin: 0 0 20px 0;">Hi ${firstName},</p>
      <p style="color: #4b5563; font-size: 15px; line-height: 1.6; margin: 0 0 25px 0;">${introText}</p>
      
      ${details.reason ? `
      <div style="background-color: #fef2f2; border-left: 4px solid #ef4444; padding: 15px; margin: 20px 0; border-radius: 0 8px 8px 0;">
        <p style="color: #991b1b; margin: 0; font-size: 14px;"><strong>Reason:</strong> ${details.reason}</p>
      </div>` : ''}
      
      <div style="background-color: #f9fafb; border-radius: 12px; padding: 20px; margin: 20px 0;">
        <h3 style="color: #6b7280; margin: 0 0 15px 0; font-size: 14px; text-transform: uppercase; letter-spacing: 0.5px;">Cancelled Booking Details</h3>
        <table style="width: 100%; border-collapse: collapse;">
          <tr>
            <td style="padding: 8px 0; color: #6b7280; font-size: 14px;">Service</td>
            <td style="padding: 8px 0; color: #1f2937; font-weight: 600; text-align: right;">${details.serviceName}</td>
          </tr>
          <tr>
            <td style="padding: 8px 0; color: #6b7280; font-size: 14px;">Was Scheduled For</td>
            <td style="padding: 8px 0; color: #9ca3af; font-weight: 600; text-align: right; text-decoration: line-through;">${details.scheduledDate}</td>
          </tr>
          <tr>
            <td style="padding: 8px 0; color: #6b7280; font-size: 14px;">Time</td>
            <td style="padding: 8px 0; color: #9ca3af; font-weight: 600; text-align: right; text-decoration: line-through;">${details.scheduledTime}</td>
          </tr>
          ${details.location ? `
          <tr>
            <td style="padding: 8px 0; color: #6b7280; font-size: 14px;">Location</td>
            <td style="padding: 8px 0; color: #1f2937; font-weight: 600; text-align: right;">${details.location}</td>
          </tr>` : ''}
          <tr>
            <td style="padding: 8px 0; color: #6b7280; font-size: 14px;">${isConsumer ? 'Barber' : 'Customer'}</td>
            <td style="padding: 8px 0; color: #1f2937; font-weight: 600; text-align: right;">${otherPartyName}</td>
          </tr>
          <tr>
            <td style="padding: 8px 0; color: #6b7280; font-size: 14px;">Price</td>
            <td style="padding: 8px 0; color: #9ca3af; font-weight: 600; text-align: right; text-decoration: line-through;">$${details.price.toFixed(2)}</td>
          </tr>
        </table>
      </div>

      <div style="text-align: center; margin: 25px 0 0 0;">
        <p style="color: #9ca3af; font-size: 12px; margin: 0;">Booking Reference</p>
        <p style="color: #1f2937; font-size: 16px; font-weight: 700; margin: 5px 0 0 0;">${details.bookingId.slice(0, 8).toUpperCase()}</p>
      </div>

      ${isConsumer && details.cancelledBy === 'barber' && details.alternativeBarbers && details.alternativeBarbers.length > 0 ? `
      <div style="background-color: #f0fdf4; border: 2px solid #5a7268; border-radius: 12px; padding: 20px; margin: 25px 0;">
        <h3 style="color: #445750; margin: 0 0 15px 0; font-size: 16px; text-align: center;">
          ${details.alternativeBarbers.length} Barber${details.alternativeBarbers.length !== 1 ? 's' : ''} Available at This Time
        </h3>
        <p style="color: #5a7268; font-size: 13px; text-align: center; margin: 0 0 15px 0;">
          These barbers offer ${details.serviceName} and are available at ${details.scheduledTime}:
        </p>
        <table style="width: 100%; border-collapse: separate; border-spacing: 0 8px;">
          ${details.alternativeBarbers.map(barber => `
          <tr>
            <td style="background-color: white; border-radius: 8px; padding: 12px;">
              <table style="width: 100%;">
                <tr>
                  <td style="width: 48px; vertical-align: middle;">
                    <div style="width: 40px; height: 40px; border-radius: 50%; background-color: #e5e7eb; overflow: hidden;">
                      ${barber.avatar 
                        ? `<img src="${barber.avatar}" alt="${barber.name}" style="width: 40px; height: 40px; border-radius: 50%; object-fit: cover;" />`
                        : `<div style="width: 40px; height: 40px; border-radius: 50%; background-color: #dcfce7; color: #5a7268; font-weight: 600; font-size: 16px; text-align: center; line-height: 40px;">${barber.name.charAt(0)}</div>`
                      }
                    </div>
                  </td>
                  <td style="vertical-align: middle; padding-left: 12px;">
                    <p style="margin: 0; color: #1f2937; font-weight: 600; font-size: 14px;">${barber.name}</p>
                    ${barber.avgRating ? `<p style="margin: 2px 0 0 0; color: #6b7280; font-size: 12px;">⭐ ${barber.avgRating.toFixed(1)}${barber.totalReviews ? ` (${barber.totalReviews} reviews)` : ''}</p>` : ''}
                  </td>
                </tr>
              </table>
            </td>
          </tr>
          `).join('')}
        </table>
      </div>
      ` : ''}

      <div style="text-align: center; margin: 30px 0;">
        <a href="${ctaLink}" style="display: inline-block; background-color: #5a7268; color: white; padding: 14px 40px; text-decoration: none; border-radius: 8px; font-weight: 600; font-size: 16px;">${ctaText}</a>
      </div>

      <p style="color: #6b7280; font-size: 13px; text-align: center; margin: 20px 0 0 0;">
        ${isConsumer 
          ? 'We hope to see you again soon! You can book a new appointment anytime.'
          : cancelledByYou 
            ? 'The customer has been notified of this cancellation.'
            : 'This time slot is now available for other bookings.'}
      </p>
    </div>
    <div style="background-color: #f9fafb; padding: 20px; text-align: center;">
      <p style="color: #9ca3af; font-size: 12px; margin: 0;">© ${new Date().getFullYear()} CampusCut</p>
    </div>
  </div>
</body>
</html>`.trim();
}

// ============================================
// BOOKING DECLINE EMAIL
// ============================================

/**
 * Booking Decline Email Details Interface
 */
interface BookingDeclineEmailDetails {
  consumerEmail: string;
  consumerName: string;
  barberName: string;
  barberId?: string;
  serviceName: string;
  scheduledDate: string;
  scheduledTime: string;
  price: number;
  location?: string;
  reason?: string;
  bookingId: string;
  campusId?: string;
  originalScheduledTime?: string; // ISO timestamp for availability checking
  alternativeBarbers?: {
    id: string;
    name: string;
    avatar?: string;
    average_rating?: number;
    total_reviews?: number;
  }[];
}

/**
 * Send Booking Decline Email to Consumer
 * 
 * Sends an email to the consumer when a barber declines their booking request.
 * Includes the reason for decline and contact information for support.
 */
export async function sendBookingDeclineEmail(details: BookingDeclineEmailDetails): Promise<void> {
  if (isAutoVerifyEnabled()) {
    logger.info(`[AUTO-VERIFY MODE] Skipping booking decline email for booking ${details.bookingId}`);
    return;
  }

  const frontendUrl = process.env.FRONTEND_URL || 'https://campuscut.com';

  try {
    const transporter = createTransporter();
    
    const mailOptions = {
      from: `CampusCut <${process.env.SMTP_USER}>`,
      to: details.consumerEmail,
      subject: `Booking Request Declined - ${details.serviceName} with ${details.barberName}`,
      text: generateBookingDeclineText(details),
      html: generateBookingDeclineHtml(details, frontendUrl)
    };

    await transporter.sendMail(mailOptions);
    logger.info(`Booking decline email sent to consumer: ${details.consumerEmail}`);
  } catch (error: any) {
    logger.error(`Failed to send booking decline email to ${details.consumerEmail}:`, error.message);
  }
}

/**
 * Generate Booking Decline Plain Text
 */
function generateBookingDeclineText(details: BookingDeclineEmailDetails): string {
  const firstName = details.consumerName.split(' ')[0];
  
  return `
Hi ${firstName},

Unfortunately, ${details.barberName} was unable to accept your booking request.

BOOKING DETAILS
---------------
Service: ${details.serviceName}
Requested Date: ${details.scheduledDate}
Requested Time: ${details.scheduledTime}
${details.location ? `Location: ${details.location}` : ''}
Price: $${details.price.toFixed(2)}

${details.reason ? `REASON PROVIDED\n---------------\n${details.reason}\n` : ''}
Booking Reference: ${details.bookingId.slice(0, 8).toUpperCase()}

---
If you believe a mistake has been made, please contact us at:
campuscuthelp@gmail.com

We're here to help!

---
CampusCut
`.trim();
}

/**
 * Generate Booking Decline HTML Email
 */
function generateBookingDeclineHtml(details: BookingDeclineEmailDetails, frontendUrl: string): string {
  const firstName = details.consumerName.split(' ')[0];
  
  // Generate alternative barbers HTML if available
  const alternativeBarbersHtml = details.alternativeBarbers && details.alternativeBarbers.length > 0 ? `
    <!-- Alternative Barbers -->
    <div style="background-color: #f2f5f4; border-radius: 12px; padding: 20px; margin: 25px 0;">
      <h3 style="color: #3d5149; margin: 0 0 15px 0; font-size: 16px; text-align: center;">Other Barbers Available at ${details.scheduledTime}</h3>
      <div style="display: flex; flex-direction: column; gap: 10px;">
        ${details.alternativeBarbers.map(barber => `
          <a href="${frontendUrl}/web/barber/${barber.id}?date=${encodeURIComponent(details.originalScheduledTime?.split('T')[0] || '')}&time=${encodeURIComponent(details.scheduledTime)}&service=${encodeURIComponent(details.serviceName)}" 
             style="display: flex; align-items: center; gap: 12px; padding: 10px; background-color: #ffffff; border-radius: 8px; text-decoration: none; color: #1f2937; box-shadow: 0 1px 2px rgba(0,0,0,0.05);">
            <div style="width: 40px; height: 40px; border-radius: 50%; overflow: hidden; background-color: #d1e0d9; display: flex; align-items: center; justify-content: center; flex-shrink: 0;">
              ${barber.avatar ? `<img src="${barber.avatar}" alt="${barber.name}" style="width: 100%; height: 100%; object-fit: cover;">` : `<span style="color: #5a7268; font-weight: 600; font-size: 16px;">${barber.name?.charAt(0) || 'B'}</span>`}
            </div>
            <div style="flex: 1; min-width: 0;">
              <p style="margin: 0; font-weight: 600; font-size: 15px; line-height: 1.4;">${barber.name}</p>
              ${barber.average_rating ? `
                <p style="margin: 2px 0 0 0; font-size: 13px; color: #6b7280;">⭐ ${barber.average_rating.toFixed(1)} (${barber.total_reviews || 0} reviews)</p>
              ` : `<p style="margin: 2px 0 0 0; font-size: 13px; color: #6b7280;">No reviews yet</p>`}
            </div>
            <span style="color: #5a7268; font-size: 14px; font-weight: 500;">Book Now →</span>
          </a>
        `).join('')}
      </div>
    </div>
  ` : '';
  
  return `
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
</head>
<body style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; line-height: 1.6; color: #333; max-width: 600px; margin: 0 auto; padding: 20px; background-color: #f3f4f6;">
  <div style="background: linear-gradient(135deg, #5a7268 0%, #4a6258 100%); padding: 30px; text-align: center; border-radius: 12px 12px 0 0;">
    <h1 style="color: white; margin: 0; font-size: 28px;">CampusCut</h1>
    <p style="color: #fca5a5; margin: 10px 0 0 0; font-size: 16px;">Booking Request Declined</p>
  </div>
  
  <div style="background-color: #ffffff; padding: 30px; border-radius: 0 0 12px 12px; border: 1px solid #e5e7eb; border-top: none;">
    <h2 style="color: #3d5149; margin: 0 0 10px 0;">Hi ${firstName},</h2>
    <p style="color: #6b7280; margin: 0 0 20px 0;">Unfortunately, ${details.barberName} was unable to accept your booking request.</p>
    
    <!-- Status Badge -->
    <div style="text-align: center; margin: 20px 0;">
      <span style="display: inline-block; background-color: #fee2e2; color: #dc2626; padding: 8px 16px; border-radius: 20px; font-size: 12px; font-weight: 600; letter-spacing: 1px;">
        DECLINED
      </span>
    </div>
    
    <!-- Booking Details -->
    <div style="background-color: #f9fafb; border-radius: 12px; padding: 20px; margin: 20px 0;">
      <h3 style="color: #1f2937; margin: 0 0 15px 0; font-size: 16px;">Original Booking Request</h3>
      
      <table style="width: 100%; border-collapse: collapse;">
        <tr>
          <td style="color: #6b7280; padding: 5px 0;">Service</td>
          <td style="color: #1f2937; font-weight: 600; text-align: right; padding: 5px 0;">${details.serviceName}</td>
        </tr>
        <tr>
          <td style="color: #6b7280; padding: 5px 0;">Requested Date</td>
          <td style="color: #1f2937; font-weight: 600; text-align: right; padding: 5px 0;">${details.scheduledDate}</td>
        </tr>
        <tr>
          <td style="color: #6b7280; padding: 5px 0;">Requested Time</td>
          <td style="color: #1f2937; font-weight: 600; text-align: right; padding: 5px 0;">${details.scheduledTime}</td>
        </tr>
        ${details.location ? `
        <tr>
          <td style="color: #6b7280; padding: 5px 0;">Location</td>
          <td style="color: #1f2937; font-weight: 600; text-align: right; padding: 5px 0;">${details.location}</td>
        </tr>
        ` : ''}
      </table>
      
      <div style="border-top: 1px dashed #e5e7eb; margin: 15px 0; padding-top: 15px;">
        <table style="width: 100%; border-collapse: collapse;">
          <tr>
            <td style="color: #6b7280; font-weight: 600;">Price</td>
            <td style="color: #9ca3af; font-weight: 700; font-size: 18px; text-align: right; text-decoration: line-through;">$${details.price.toFixed(2)}</td>
          </tr>
        </table>
      </div>
    </div>
    
    ${details.reason ? `
    <!-- Reason Box -->
    <div style="background-color: #fef2f2; border: 1px solid #fecaca; border-radius: 8px; padding: 15px; margin: 15px 0;">
      <p style="color: #991b1b; margin: 0; font-size: 14px;"><strong>Reason provided:</strong></p>
      <p style="color: #7f1d1d; margin: 8px 0 0 0; font-size: 14px;">${details.reason}</p>
    </div>
    ` : ''}
    
    ${alternativeBarbersHtml}
    
    <!-- Booking Reference -->
    <div style="text-align: center; margin: 20px 0;">
      <p style="color: #6b7280; margin: 0; font-size: 14px;">Booking Reference</p>
      <p style="color: #1f2937; margin: 5px 0 0 0; font-size: 18px; font-weight: 700; letter-spacing: 2px;">${details.bookingId.slice(0, 8).toUpperCase()}</p>
    </div>
    
    <!-- CTA Button -->
    <p style="text-align: center; margin: 30px 0 20px 0;">
      <a href="${frontendUrl}/web/discover" style="display: inline-block; background-color: #5a7268; color: white; padding: 14px 40px; text-decoration: none; border-radius: 8px; font-weight: 600; font-size: 16px;">
        Find Another Barber
      </a>
    </p>
    
    <!-- Support Box -->
    <div style="background-color: #f2f5f4; border: 1px solid #bfcdc8; border-radius: 8px; padding: 15px; margin: 20px 0;">
      <p style="color: #3d5149; margin: 0; font-size: 14px;">
        <strong>Think a mistake was made?</strong><br>
        Contact us at <a href="mailto:campuscuthelp@gmail.com" style="color: #5a7268; font-weight: 600;">campuscuthelp@gmail.com</a> and we'll be happy to help.
      </p>
    </div>
  </div>
  
  <div style="text-align: center; padding: 20px; color: #9ca3af; font-size: 12px;">
    <p style="margin: 0;">© ${new Date().getFullYear()} CampusCut</p>
  </div>
</body>
</html>`.trim();
}

// ============================================
// BOOKING REMINDER EMAIL
// ============================================

/**
 * Booking Reminder Email Details Interface
 */
interface BookingReminderEmailDetails {
  bookingId: string;
  serviceName: string;
  price: number; // in dollars
  scheduledDate: string; // formatted date string
  scheduledTime: string; // formatted time string
  location?: string;
  notes?: string;
  consumerName: string;
  consumerEmail: string;
  barberName: string;
  barberEmail: string;
}

/**
 * Send Booking Reminder Email
 * 
 * Sends a reminder email to the consumer 1 hour before their scheduled appointment.
 * 
 * @param details - Booking reminder details
 */
export async function sendBookingReminderEmail(details: BookingReminderEmailDetails): Promise<void> {
  if (isAutoVerifyEnabled()) {
    logger.info(`[AUTO-VERIFY MODE] Skipping booking reminder email for booking ${details.bookingId}`);
    return;
  }

  const frontendUrl = process.env.FRONTEND_URL || 'https://campuscut.com';

  try {
    const transporter = createTransporter();
    
    const mailOptions = {
      from: `CampusCut <${process.env.SMTP_USER}>`,
      to: details.consumerEmail,
      subject: `Reminder: Your ${details.serviceName} with ${details.barberName} is in 1 hour!`,
      text: generateBookingReminderText(details),
      html: generateBookingReminderHtml(details, frontendUrl)
    };

    await transporter.sendMail(mailOptions);
    logger.info(`Booking reminder email sent to consumer: ${details.consumerEmail} for booking ${details.bookingId}`);
  } catch (error: any) {
    logger.error(`Failed to send booking reminder email to ${details.consumerEmail}:`, error.message);
    throw error; // Re-throw so the cron job knows the email failed
  }
}

/**
 * Generate Booking Reminder Plain Text
 */
function generateBookingReminderText(details: BookingReminderEmailDetails): string {
  const firstName = details.consumerName.split(' ')[0];
  
  return `
Hi ${firstName}!

This is a friendly reminder that your ${details.serviceName} appointment with ${details.barberName} is coming up in 1 hour!

APPOINTMENT DETAILS
-------------------
Service: ${details.serviceName}
Date: ${details.scheduledDate}
Time: ${details.scheduledTime}
${details.location ? `Location: ${details.location}` : ''}
Barber: ${details.barberName}
Price: $${details.price.toFixed(2)}
${details.notes ? `\nNotes: ${details.notes}` : ''}

Booking Reference: ${details.bookingId.slice(0, 8).toUpperCase()}

TIPS FOR YOUR APPOINTMENT
-------------------------
- Please arrive on time
- If you need to cancel or reschedule, contact your barber ASAP
- Bring any reference photos if you have a specific style in mind

See you soon!

---
CampusCut
`.trim();
}

/**
 * Generate Booking Reminder HTML Email
 */
function generateBookingReminderHtml(details: BookingReminderEmailDetails, frontendUrl: string): string {
  const firstName = details.consumerName.split(' ')[0];
  
  return `
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
</head>
<body style="margin: 0; padding: 0; background-color: #f3f4f6; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;">
  <div style="max-width: 500px; margin: 40px auto; background-color: white; border-radius: 16px; overflow: hidden; box-shadow: 0 4px 6px rgba(0,0,0,0.1);">
    <!-- Header -->
    <div style="background: linear-gradient(135deg, #5a7268 0%, #4a6258 100%); padding: 30px 20px; text-align: center;">
      <h1 style="color: white; margin: 0; font-size: 24px;">Appointment Reminder</h1>
      <p style="color: #d1e0d9; margin: 5px 0 0 0; font-size: 14px;">Starting in 1 hour!</p>
    </div>
    
    <div style="padding: 30px;">
      <p style="color: #1f2937; font-size: 16px; margin: 0 0 20px 0;">Hi ${firstName}!</p>
      <p style="color: #4b5563; font-size: 15px; line-height: 1.6; margin: 0 0 25px 0;">
        Your <strong>${details.serviceName}</strong> appointment with <strong>${details.barberName}</strong> is coming up soon!
      </p>
      
      <!-- Countdown Badge -->
      <div style="text-align: center; margin: 20px 0;">
        <span style="display: inline-block; background-color: #f2f5f4; color: #3d5149; padding: 12px 24px; border-radius: 30px; font-size: 16px; font-weight: 700;">
          Starts in approximately 1 hour
        </span>
      </div>
      
      <!-- Booking Details Card -->
      <div style="background-color: #f9fafb; border-radius: 12px; padding: 20px; margin: 20px 0; border: 2px solid #e5e7eb;">
        <h3 style="color: #1f2937; margin: 0 0 15px 0; font-size: 14px; text-transform: uppercase; letter-spacing: 0.5px;">Appointment Details</h3>
        <table style="width: 100%; border-collapse: collapse;">
          <tr>
            <td style="padding: 8px 0; color: #6b7280; font-size: 14px;">Service</td>
            <td style="padding: 8px 0; color: #1f2937; font-weight: 600; text-align: right;">${details.serviceName}</td>
          </tr>
          <tr>
            <td style="padding: 8px 0; color: #6b7280; font-size: 14px;">Date</td>
            <td style="padding: 8px 0; color: #1f2937; font-weight: 600; text-align: right;">${details.scheduledDate}</td>
          </tr>
          <tr>
            <td style="padding: 8px 0; color: #6b7280; font-size: 14px;">Time</td>
            <td style="padding: 8px 0; color: #5a7268; font-weight: 700; text-align: right; font-size: 16px;">${details.scheduledTime}</td>
          </tr>
          ${details.location ? `
          <tr>
            <td style="padding: 8px 0; color: #6b7280; font-size: 14px;">Location</td>
            <td style="padding: 8px 0; color: #1f2937; font-weight: 600; text-align: right;">${details.location}</td>
          </tr>` : ''}
          <tr>
            <td style="padding: 8px 0; color: #6b7280; font-size: 14px;">Barber</td>
            <td style="padding: 8px 0; color: #1f2937; font-weight: 600; text-align: right;">${details.barberName}</td>
          </tr>
          <tr>
            <td style="padding: 8px 0; color: #6b7280; font-size: 14px;">Price</td>
            <td style="padding: 8px 0; color: #5a7268; font-weight: 700; text-align: right; font-size: 18px;">$${details.price.toFixed(2)}</td>
          </tr>
        </table>
        
        ${details.notes ? `
        <div style="border-top: 1px solid #e5e7eb; margin-top: 15px; padding-top: 15px;">
          <p style="color: #6b7280; margin: 0 0 5px 0; font-size: 12px;">Notes:</p>
          <p style="color: #1f2937; margin: 0; font-style: italic;">"${details.notes}"</p>
        </div>` : ''}
      </div>
      
      <!-- Tips Section -->
      <div style="background-color: #f2f5f4; border-radius: 12px; padding: 20px; margin: 20px 0;">
        <h4 style="color: #3d5149; margin: 0 0 10px 0; font-size: 14px;">Tips for your appointment:</h4>
        <ul style="color: #4a6258; margin: 0; padding-left: 20px; font-size: 14px; line-height: 1.8;">
          <li>Please arrive on time</li>
          <li>If you need to cancel, contact your barber ASAP</li>
          <li>Bring any reference photos if you have a specific style in mind</li>
        </ul>
      </div>
      
      <!-- Booking Reference -->
      <div style="text-align: center; margin: 25px 0;">
        <p style="color: #9ca3af; margin: 0; font-size: 12px;">Booking Reference</p>
        <p style="color: #1f2937; margin: 5px 0 0 0; font-size: 16px; font-weight: 700; letter-spacing: 2px;">${details.bookingId.slice(0, 8).toUpperCase()}</p>
      </div>
      
      <!-- CTA Button -->
      <div style="text-align: center; margin: 25px 0;">
        <a href="${frontendUrl}/web" style="display: inline-block; background-color: #5a7268; color: white; padding: 14px 40px; text-decoration: none; border-radius: 8px; font-weight: 600; font-size: 16px;">
          View Booking Details
        </a>
      </div>
      
      <p style="color: #6b7280; font-size: 13px; text-align: center; margin: 20px 0 0 0;">
        See you soon!
      </p>
    </div>
    
    <div style="background-color: #f9fafb; padding: 20px; text-align: center;">
      <p style="color: #9ca3af; font-size: 12px; margin: 0;">© ${new Date().getFullYear()} CampusCut</p>
    </div>
  </div>
</body>
</html>`.trim();
}

/**
 * Send Booking Reminder Email to Barber
 * 
 * Sends a reminder email to the barber 1 hour before their scheduled appointment.
 * 
 * @param details - Booking reminder details
 */
export async function sendBarberReminderEmail(details: BookingReminderEmailDetails): Promise<void> {
  if (isAutoVerifyEnabled()) {
    logger.info(`[AUTO-VERIFY MODE] Skipping barber reminder email for booking ${details.bookingId}`);
    return;
  }

  if (!details.barberEmail) {
    logger.warn(`No barber email for booking ${details.bookingId}, skipping barber reminder`);
    return;
  }

  const frontendUrl = process.env.FRONTEND_URL || 'https://campuscut.com';

  try {
    const transporter = createTransporter();
    
    const mailOptions = {
      from: `CampusCut <${process.env.SMTP_USER}>`,
      to: details.barberEmail,
      subject: `Reminder: ${details.consumerName}'s ${details.serviceName} is in 1 hour!`,
      text: generateBarberReminderText(details),
      html: generateBarberReminderHtml(details, frontendUrl)
    };

    await transporter.sendMail(mailOptions);
    logger.info(`Booking reminder email sent to barber: ${details.barberEmail} for booking ${details.bookingId}`);
  } catch (error: any) {
    logger.error(`Failed to send barber reminder email to ${details.barberEmail}:`, error.message);
    throw error;
  }
}

/**
 * Generate Barber Reminder Plain Text
 */
function generateBarberReminderText(details: BookingReminderEmailDetails): string {
  const barberFirstName = details.barberName.split(' ')[0];
  
  return `
Hi ${barberFirstName}!

This is a reminder that you have an upcoming ${details.serviceName} appointment in 1 hour!

APPOINTMENT DETAILS
-------------------
Customer: ${details.consumerName}
Service: ${details.serviceName}
Date: ${details.scheduledDate}
Time: ${details.scheduledTime}
${details.location ? `Location: ${details.location}` : ''}
Price: $${details.price.toFixed(2)}
${details.notes ? `\nCustomer Notes: ${details.notes}` : ''}

Booking Reference: ${details.bookingId.slice(0, 8).toUpperCase()}

CHECKLIST
---------
✓ Make sure your equipment is ready
✓ Review any style preferences the customer mentioned
✓ Be ready to greet ${details.consumerName.split(' ')[0]} on time

Time to deliver another great cut!

---
CampusCut
`.trim();
}

/**
 * Generate Barber Reminder HTML Email
 */
function generateBarberReminderHtml(details: BookingReminderEmailDetails, frontendUrl: string): string {
  const barberFirstName = details.barberName.split(' ')[0];
  const consumerFirstName = details.consumerName.split(' ')[0];
  
  return `
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
</head>
<body style="margin: 0; padding: 0; background-color: #f3f4f6; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;">
  <div style="max-width: 500px; margin: 40px auto; background-color: white; border-radius: 16px; overflow: hidden; box-shadow: 0 4px 6px rgba(0,0,0,0.1);">
    <!-- Header -->
    <div style="background: linear-gradient(135deg, #5a7268 0%, #4a6258 100%); padding: 30px 20px; text-align: center;">
      <h1 style="color: white; margin: 0; font-size: 24px;">Upcoming Appointment</h1>
      <p style="color: #d1e0d9; margin: 5px 0 0 0; font-size: 14px;">Starting in 1 hour!</p>
    </div>
    
    <div style="padding: 30px;">
      <p style="color: #1f2937; font-size: 16px; margin: 0 0 20px 0;">Hi ${barberFirstName}!</p>
      <p style="color: #4b5563; font-size: 15px; line-height: 1.6; margin: 0 0 25px 0;">
        You have a <strong>${details.serviceName}</strong> appointment with <strong>${details.consumerName}</strong> coming up soon!
      </p>
      
      <!-- Countdown Badge -->
      <div style="text-align: center; margin: 20px 0;">
        <span style="display: inline-block; background-color: #f2f5f4; color: #3d5149; padding: 12px 24px; border-radius: 30px; font-size: 16px; font-weight: 700;">
          Starts in approximately 1 hour
        </span>
      </div>
      
      <!-- Customer Info Card -->
      <div style="background-color: #f2f5f4; border-radius: 12px; padding: 20px; margin: 20px 0; border: 2px solid #bfcdc8;">
        <h3 style="color: #3d5149; margin: 0 0 10px 0; font-size: 14px; text-transform: uppercase; letter-spacing: 0.5px;">Customer</h3>
        <p style="color: #1f2937; margin: 0; font-size: 18px; font-weight: 600;">${details.consumerName}</p>
      </div>
      
      <!-- Booking Details Card -->
      <div style="background-color: #f9fafb; border-radius: 12px; padding: 20px; margin: 20px 0; border: 2px solid #e5e7eb;">
        <h3 style="color: #1f2937; margin: 0 0 15px 0; font-size: 14px; text-transform: uppercase; letter-spacing: 0.5px;">Appointment Details</h3>
        <table style="width: 100%; border-collapse: collapse;">
          <tr>
            <td style="padding: 8px 0; color: #6b7280; font-size: 14px;">Service</td>
            <td style="padding: 8px 0; color: #1f2937; font-weight: 600; text-align: right;">${details.serviceName}</td>
          </tr>
          <tr>
            <td style="padding: 8px 0; color: #6b7280; font-size: 14px;">Date</td>
            <td style="padding: 8px 0; color: #1f2937; font-weight: 600; text-align: right;">${details.scheduledDate}</td>
          </tr>
          <tr>
            <td style="padding: 8px 0; color: #6b7280; font-size: 14px;">Time</td>
            <td style="padding: 8px 0; color: #5a7268; font-weight: 700; text-align: right; font-size: 16px;">${details.scheduledTime}</td>
          </tr>
          ${details.location ? `
          <tr>
            <td style="padding: 8px 0; color: #6b7280; font-size: 14px;">Location</td>
            <td style="padding: 8px 0; color: #1f2937; font-weight: 600; text-align: right;">${details.location}</td>
          </tr>` : ''}
          <tr>
            <td style="padding: 8px 0; color: #6b7280; font-size: 14px;">You'll Earn</td>
            <td style="padding: 8px 0; color: #5a7268; font-weight: 700; text-align: right; font-size: 18px;">$${details.price.toFixed(2)}</td>
          </tr>
        </table>
        
        ${details.notes ? `
        <div style="border-top: 1px solid #e5e7eb; margin-top: 15px; padding-top: 15px;">
          <p style="color: #6b7280; margin: 0 0 5px 0; font-size: 12px;">Customer Notes:</p>
          <p style="color: #1f2937; margin: 0; font-style: italic;">"${details.notes}"</p>
        </div>` : ''}
      </div>
      
      <!-- Checklist Section -->
      <div style="background-color: #f2f5f4; border-radius: 12px; padding: 20px; margin: 20px 0;">
        <h4 style="color: #3d5149; margin: 0 0 10px 0; font-size: 14px;">Quick Checklist:</h4>
        <ul style="color: #4a6258; margin: 0; padding-left: 20px; font-size: 14px; line-height: 1.8;">
          <li>Equipment ready and clean</li>
          <li>Review customer's style preferences</li>
          <li>Be ready to greet ${consumerFirstName} on time</li>
        </ul>
      </div>
      
      <!-- Booking Reference -->
      <div style="text-align: center; margin: 25px 0;">
        <p style="color: #9ca3af; margin: 0; font-size: 12px;">Booking Reference</p>
        <p style="color: #1f2937; margin: 5px 0 0 0; font-size: 16px; font-weight: 700; letter-spacing: 2px;">${details.bookingId.slice(0, 8).toUpperCase()}</p>
      </div>
      
      <!-- CTA Button -->
      <div style="text-align: center; margin: 25px 0;">
        <a href="${frontendUrl}/web" style="display: inline-block; background-color: #5a7268; color: white; padding: 14px 40px; text-decoration: none; border-radius: 8px; font-weight: 600; font-size: 16px;">
          View Appointment
        </a>
      </div>
      
      <p style="color: #6b7280; font-size: 13px; text-align: center; margin: 20px 0 0 0;">
        Time to deliver another great cut!
      </p>
    </div>
    
    <div style="background-color: #f9fafb; padding: 20px; text-align: center;">
      <p style="color: #9ca3af; font-size: 12px; margin: 0;">© ${new Date().getFullYear()} CampusCut</p>
    </div>
  </div>
</body>
</html>`.trim();
}

/**
 * Send Guest Application Approved Email
 * 
 * Notifies a guest applicant that their barber application has been approved
 * and prompts them to create an account to complete onboarding.
 * 
 * @param email - Guest applicant's email
 * @param firstName - Guest applicant's first name
 * @param campusName - Name of the campus they applied to
 */
export async function sendGuestApplicationApprovedEmail(
  email: string,
  firstName: string,
  campusName: string
): Promise<void> {
  const frontendUrl = process.env.FRONTEND_URL || 'https://campuscut.com';
  const signUpLink = `${frontendUrl}/web/auth`;

  const subject = 'Your CampusCut Barber Application Has Been Approved!';

  const text = `
Hi ${firstName}!

Great news! Your barber application for ${campusName} has been approved! 

To complete your onboarding and start receiving bookings, you need to create your CampusCut account.

Create your account here: ${signUpLink}

IMPORTANT: Use the same email address (${email}) when signing up, and you'll be automatically set up as a barber.

Once you create your account, you can:
- Set up your barber profile and services
- Configure your availability
- Start receiving booking requests from students

Welcome to CampusCut!

Best,
The CampusCut Team
`.trim();

  const html = `
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
</head>
<body style="margin: 0; padding: 0; background-color: #f3f4f6; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;">
  <div style="max-width: 600px; margin: 0 auto; background-color: white; border-radius: 16px; overflow: hidden; margin-top: 20px; margin-bottom: 20px; box-shadow: 0 4px 6px rgba(0, 0, 0, 0.1);">
    <!-- Header -->
    <div style="background: linear-gradient(135deg, #5a7268 0%, #445750 100%); padding: 40px 30px; text-align: center;">
      <h1 style="color: white; margin: 0; font-size: 28px; font-weight: 700;">Application Approved!</h1>
      <p style="color: rgba(255, 255, 255, 0.9); margin: 10px 0 0 0; font-size: 16px;">Welcome to the CampusCut barber team</p>
    </div>
    
    <!-- Content -->
    <div style="padding: 30px;">
      <p style="color: #374151; font-size: 16px; line-height: 1.6; margin: 0 0 20px 0;">
        Hi <strong>${firstName}</strong>,
      </p>
      
      <p style="color: #374151; font-size: 16px; line-height: 1.6; margin: 0 0 20px 0;">
        Great news! Your barber application for <strong>${campusName}</strong> has been approved! 
      </p>
      
      <div style="background-color: #fef3c7; border-radius: 12px; padding: 20px; margin: 20px 0; border-left: 4px solid #f59e0b;">
        <h4 style="color: #92400e; margin: 0 0 10px 0; font-size: 14px;">One More Step</h4>
        <p style="color: #78350f; margin: 0; font-size: 14px; line-height: 1.6;">
          To complete your onboarding and start receiving bookings, you need to create your CampusCut account.
        </p>
      </div>
      
      <div style="background-color: #f2f5f4; border-radius: 12px; padding: 15px; margin: 20px 0;">
        <p style="color: #166534; margin: 0; font-size: 14px;">
          <strong>Important:</strong> Use the same email address (<strong>${email}</strong>) when signing up, and you'll be automatically set up as a barber.
        </p>
      </div>
      
      <!-- CTA Button -->
      <div style="text-align: center; margin: 30px 0;">
        <a href="${signUpLink}" style="display: inline-block; background-color: #5a7268; color: white; padding: 16px 50px; text-decoration: none; border-radius: 10px; font-weight: 600; font-size: 18px;">
          Create Your Account
        </a>
      </div>
      
      <p style="color: #374151; font-size: 16px; line-height: 1.6; margin: 20px 0;">
        Once you create your account, you can:
      </p>
      <ul style="color: #374151; font-size: 14px; line-height: 1.8; padding-left: 20px; margin: 0 0 20px 0;">
        <li>Set up your barber profile and services</li>
        <li>Configure your availability and schedule</li>
        <li>Start receiving booking requests from students</li>
        <li>Build your reputation with reviews</li>
      </ul>
      
      <p style="color: #6b7280; font-size: 14px; text-align: center; margin: 20px 0 0 0;">
        Welcome to the team!
      </p>
    </div>
    
    <div style="background-color: #f9fafb; padding: 20px; text-align: center;">
      <p style="color: #9ca3af; font-size: 12px; margin: 0;">© ${new Date().getFullYear()} CampusCut</p>
    </div>
  </div>
</body>
</html>`.trim();

  if (isAutoVerifyEnabled()) {
    logger.info(`[AUTO-VERIFY MODE] Skipping guest approval email to ${email}`);
    return;
  }

  try {
    const transporter = createTransporter();

    const mailOptions = {
      from: `CampusCut <${process.env.SMTP_USER}>`,
      to: email,
      subject,
      text,
      html
    };

    await transporter.sendMail(mailOptions);
    logger.info(`Guest application approved email sent to: ${email}`);
  } catch (error: any) {
    logger.error(`Failed to send guest approval email to ${email}:`, error.message);
    throw error;
  }
}

// ============================================
// NEW MESSAGE EMAIL NOTIFICATIONS
// ============================================

/**
 * New Message Email Details Interface
 */
interface NewMessageEmailDetails {
  recipientEmail: string;
  recipientName: string;
  senderName: string;
  messageContent: string;
  conversationId: number | string;
  // Booking details (optional, for consumer-barber messages)
  booking?: {
    serviceName?: string;
    scheduledDate?: string;
    scheduledTime?: string;
    price?: number;
    status?: string;
  };
}

/**
 * Send New Message Email - Consumer receiving message from Barber
 * 
 * Notifies a consumer when their barber sends them a message.
 * Includes booking details if the conversation is about a booking.
 */
export async function sendConsumerNewMessageEmail(details: NewMessageEmailDetails): Promise<void> {
  if (isAutoVerifyEnabled()) {
    logger.info(`[AUTO-VERIFY MODE] Skipping new message email to consumer ${details.recipientEmail}`);
    return;
  }

  const frontendUrl = process.env.FRONTEND_URL || 'https://campuscut.com';
  // Link to auth page with redirect to consumer messages after login
  const conversationLink = `${frontendUrl}/web/auth?redirect=/web/consumer/messages/${details.conversationId}`;

  const firstName = details.recipientName.split(' ')[0];
  const subject = `New message from ${details.senderName}`;

  const text = `
Hi ${firstName},

You have a new message from your barber, ${details.senderName}.

MESSAGE
-------
"${details.messageContent}"

${details.booking ? `
BOOKING DETAILS
---------------
Service: ${details.booking.serviceName || 'Haircut'}
${details.booking.scheduledDate ? `Date: ${details.booking.scheduledDate}` : ''}
${details.booking.scheduledTime ? `Time: ${details.booking.scheduledTime}` : ''}
${details.booking.price ? `Price: $${details.booking.price.toFixed(2)}` : ''}
Status: ${details.booking.status || 'Pending'}
` : ''}

Reply to this message by visiting:
${conversationLink}

---
CampusCut
`.trim();

  const html = `
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
</head>
<body style="margin: 0; padding: 0; background-color: #f3f4f6; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;">
  <div style="max-width: 500px; margin: 40px auto; background-color: white; border-radius: 16px; overflow: hidden; box-shadow: 0 4px 6px rgba(0,0,0,0.1);">
    <div style="background: linear-gradient(135deg, #022b19 0%, #034d2e 100%); padding: 30px 20px; text-align: center;">
      <h1 style="color: white; margin: 0; font-size: 24px;">CampusCut</h1>
      <p style="color: #4ade80; margin: 10px 0 0 0; font-size: 14px;">New Message</p>
    </div>
    
    <div style="padding: 30px;">
      <p style="color: #1f2937; font-size: 16px; margin: 0 0 20px 0;">Hi ${firstName},</p>
      <p style="color: #4b5563; font-size: 15px; line-height: 1.6; margin: 0 0 20px 0;">
        You have a new message from your barber, <strong>${details.senderName}</strong>.
      </p>
      
      <!-- Message Content -->
      <div style="background-color: #f2f5f4; border-left: 4px solid #5a7268; border-radius: 0 12px 12px 0; padding: 20px; margin: 20px 0;">
        <p style="color: #166534; margin: 0; font-size: 15px; line-height: 1.6; font-style: italic;">
          "${details.messageContent.length > 200 ? details.messageContent.substring(0, 200) + '...' : details.messageContent}"
        </p>
        <p style="color: #6b7280; margin: 10px 0 0 0; font-size: 12px;">- ${details.senderName}</p>
      </div>
      
      ${details.booking ? `
      <!-- Booking Details -->
      <div style="background-color: #f9fafb; border-radius: 12px; padding: 20px; margin: 20px 0;">
        <h3 style="color: #1f2937; margin: 0 0 15px 0; font-size: 14px; text-transform: uppercase; letter-spacing: 0.5px;">Booking Details</h3>
        <table style="width: 100%; border-collapse: collapse;">
          <tr>
            <td style="padding: 8px 0; color: #6b7280; font-size: 14px;">Service</td>
            <td style="padding: 8px 0; color: #1f2937; font-weight: 600; text-align: right;">${details.booking.serviceName || 'Haircut'}</td>
          </tr>
          ${details.booking.scheduledDate ? `
          <tr>
            <td style="padding: 8px 0; color: #6b7280; font-size: 14px;">Date</td>
            <td style="padding: 8px 0; color: #1f2937; font-weight: 600; text-align: right;">${details.booking.scheduledDate}</td>
          </tr>` : ''}
          ${details.booking.scheduledTime ? `
          <tr>
            <td style="padding: 8px 0; color: #6b7280; font-size: 14px;">Time</td>
            <td style="padding: 8px 0; color: #1f2937; font-weight: 600; text-align: right;">${details.booking.scheduledTime}</td>
          </tr>` : ''}
          ${details.booking.price ? `
          <tr>
            <td style="padding: 8px 0; color: #6b7280; font-size: 14px;">Price</td>
            <td style="padding: 8px 0; color: #5a7268; font-weight: 700; text-align: right;">$${details.booking.price.toFixed(2)}</td>
          </tr>` : ''}
          <tr>
            <td style="padding: 8px 0; color: #6b7280; font-size: 14px;">Status</td>
            <td style="padding: 8px 0; color: #1f2937; font-weight: 600; text-align: right;">${(details.booking.status || 'Pending').charAt(0).toUpperCase() + (details.booking.status || 'Pending').slice(1)}</td>
          </tr>
        </table>
      </div>
      ` : ''}
      
      <!-- CTA Button -->
      <div style="text-align: center; margin: 30px 0;">
        <a href="${conversationLink}" style="display: inline-block; background-color: #5a7268; color: white; padding: 14px 40px; text-decoration: none; border-radius: 8px; font-weight: 600; font-size: 16px;">
          Reply to Message
        </a>
      </div>
      
      <p style="color: #6b7280; font-size: 13px; text-align: center; margin: 20px 0 0 0;">
        Open the CampusCut app to continue the conversation.
      </p>
    </div>
    
    <div style="background-color: #f9fafb; padding: 20px; text-align: center;">
      <p style="color: #9ca3af; font-size: 12px; margin: 0;">${new Date().getFullYear()} CampusCut</p>
    </div>
  </div>
</body>
</html>`.trim();

  try {
    const transporter = createTransporter();

    const mailOptions = {
      from: `CampusCut <${process.env.SMTP_USER}>`,
      to: details.recipientEmail,
      subject,
      text,
      html
    };

    await transporter.sendMail(mailOptions);
    logger.info(`New message email sent to consumer: ${details.recipientEmail}`);
  } catch (error: any) {
    logger.error(`Failed to send new message email to consumer ${details.recipientEmail}:`, error.message);
    // Don't throw - email notification is non-critical
  }
}

/**
 * Send New Message Email - Barber receiving message from Consumer
 * 
 * Notifies a barber when a customer sends them a message.
 * Includes booking details if the conversation is about a booking.
 */
export async function sendBarberNewMessageFromConsumerEmail(details: NewMessageEmailDetails): Promise<void> {
  if (isAutoVerifyEnabled()) {
    logger.info(`[AUTO-VERIFY MODE] Skipping new message email to barber ${details.recipientEmail}`);
    return;
  }

  const frontendUrl = process.env.FRONTEND_URL || 'https://campuscut.com';
  // Link to auth page with redirect to barber messages after login
  const conversationLink = `${frontendUrl}/web/auth?redirect=/web/barber/messages/${details.conversationId}`;

  const firstName = details.recipientName.split(' ')[0];
  const subject = `New message from ${details.senderName}`;

  const text = `
Hi ${firstName},

You have a new message from your customer, ${details.senderName}.

MESSAGE
-------
"${details.messageContent}"

${details.booking ? `
BOOKING DETAILS
---------------
Service: ${details.booking.serviceName || 'Haircut'}
${details.booking.scheduledDate ? `Date: ${details.booking.scheduledDate}` : ''}
${details.booking.scheduledTime ? `Time: ${details.booking.scheduledTime}` : ''}
${details.booking.price ? `Price: $${details.booking.price.toFixed(2)}` : ''}
Status: ${details.booking.status || 'Pending'}
` : ''}

Reply to this message by visiting:
${conversationLink}

---
CampusCut
`.trim();

  const html = `
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
</head>
<body style="margin: 0; padding: 0; background-color: #f3f4f6; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;">
  <div style="max-width: 500px; margin: 40px auto; background-color: white; border-radius: 16px; overflow: hidden; box-shadow: 0 4px 6px rgba(0,0,0,0.1);">
    <div style="background: linear-gradient(135deg, #5a7268 0%, #4a6258 100%); padding: 30px 20px; text-align: center;">
      <h1 style="color: white; margin: 0; font-size: 24px;">CampusCut</h1>
      <p style="color: #d1e0d9; margin: 10px 0 0 0; font-size: 14px;">New Message from Customer</p>
    </div>
    
    <div style="padding: 30px;">
      <p style="color: #1f2937; font-size: 16px; margin: 0 0 20px 0;">Hi ${firstName},</p>
      <p style="color: #4b5563; font-size: 15px; line-height: 1.6; margin: 0 0 20px 0;">
        You have a new message from your customer, <strong>${details.senderName}</strong>.
      </p>
      
      <!-- Message Content -->
      <div style="background-color: #f2f5f4; border-left: 4px solid #5a7268; border-radius: 0 12px 12px 0; padding: 20px; margin: 20px 0;">
        <p style="color: #3d5149; margin: 0; font-size: 15px; line-height: 1.6; font-style: italic;">
          "${details.messageContent.length > 200 ? details.messageContent.substring(0, 200) + '...' : details.messageContent}"
        </p>
        <p style="color: #6b7280; margin: 10px 0 0 0; font-size: 12px;">- ${details.senderName}</p>
      </div>
      
      ${details.booking ? `
      <!-- Booking Details -->
      <div style="background-color: #f9fafb; border-radius: 12px; padding: 20px; margin: 20px 0;">
        <h3 style="color: #1f2937; margin: 0 0 15px 0; font-size: 14px; text-transform: uppercase; letter-spacing: 0.5px;">Booking Details</h3>
        <table style="width: 100%; border-collapse: collapse;">
          <tr>
            <td style="padding: 8px 0; color: #6b7280; font-size: 14px;">Service</td>
            <td style="padding: 8px 0; color: #1f2937; font-weight: 600; text-align: right;">${details.booking.serviceName || 'Haircut'}</td>
          </tr>
          ${details.booking.scheduledDate ? `
          <tr>
            <td style="padding: 8px 0; color: #6b7280; font-size: 14px;">Date</td>
            <td style="padding: 8px 0; color: #1f2937; font-weight: 600; text-align: right;">${details.booking.scheduledDate}</td>
          </tr>` : ''}
          ${details.booking.scheduledTime ? `
          <tr>
            <td style="padding: 8px 0; color: #6b7280; font-size: 14px;">Time</td>
            <td style="padding: 8px 0; color: #1f2937; font-weight: 600; text-align: right;">${details.booking.scheduledTime}</td>
          </tr>` : ''}
          ${details.booking.price ? `
          <tr>
            <td style="padding: 8px 0; color: #6b7280; font-size: 14px;">Price</td>
            <td style="padding: 8px 0; color: #5a7268; font-weight: 700; text-align: right;">$${details.booking.price.toFixed(2)}</td>
          </tr>` : ''}
          <tr>
            <td style="padding: 8px 0; color: #6b7280; font-size: 14px;">Status</td>
            <td style="padding: 8px 0; color: #1f2937; font-weight: 600; text-align: right;">${(details.booking.status || 'Pending').charAt(0).toUpperCase() + (details.booking.status || 'Pending').slice(1)}</td>
          </tr>
        </table>
      </div>
      ` : ''}
      
      <!-- CTA Button -->
      <div style="text-align: center; margin: 30px 0;">
        <a href="${conversationLink}" style="display: inline-block; background-color: #5a7268; color: white; padding: 14px 40px; text-decoration: none; border-radius: 8px; font-weight: 600; font-size: 16px;">
          Reply to Message
        </a>
      </div>
      
      <p style="color: #6b7280; font-size: 13px; text-align: center; margin: 20px 0 0 0;">
        Open the CampusCut app to continue the conversation.
      </p>
    </div>
    
    <div style="background-color: #f9fafb; padding: 20px; text-align: center;">
      <p style="color: #9ca3af; font-size: 12px; margin: 0;">${new Date().getFullYear()} CampusCut</p>
    </div>
  </div>
</body>
</html>`.trim();

  try {
    const transporter = createTransporter();

    const mailOptions = {
      from: `CampusCut <${process.env.SMTP_USER}>`,
      to: details.recipientEmail,
      subject,
      text,
      html
    };

    await transporter.sendMail(mailOptions);
    logger.info(`New message email sent to barber: ${details.recipientEmail}`);
  } catch (error: any) {
    logger.error(`Failed to send new message email to barber ${details.recipientEmail}:`, error.message);
    // Don't throw - email notification is non-critical
  }
}

/**
 * Barber-to-Barber Message Email Details Interface
 */
interface BarberToBarberMessageEmailDetails {
  recipientEmail: string;
  recipientName: string;
  senderName: string;
  messageContent: string;
  conversationId: number | string;
}

/**
 * Send New Message Email - Barber receiving message from another Barber
 * 
 * Notifies a barber when another barber on the same campus sends them a message.
 * No booking details included - this is for direct barber communication.
 */
export async function sendBarberToBarberMessageEmail(details: BarberToBarberMessageEmailDetails): Promise<void> {
  if (isAutoVerifyEnabled()) {
    logger.info(`[AUTO-VERIFY MODE] Skipping barber-to-barber message email to ${details.recipientEmail}`);
    return;
  }

  const frontendUrl = process.env.FRONTEND_URL || 'https://campuscut.com';
  // Link to auth page with redirect to barber messages after login
  const conversationLink = `${frontendUrl}/web/auth?redirect=/web/barber/messages/${details.conversationId}`;

  const firstName = details.recipientName.split(' ')[0];
  const subject = `New message from ${details.senderName}`;

  const text = `
Hi ${firstName},

You have a new message from your fellow barber, ${details.senderName}.

MESSAGE
-------
"${details.messageContent}"

Reply to this message by visiting:
${conversationLink}

---
CampusCut
`.trim();

  const html = `
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
</head>
<body style="margin: 0; padding: 0; background-color: #f3f4f6; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;">
  <div style="max-width: 500px; margin: 40px auto; background-color: white; border-radius: 16px; overflow: hidden; box-shadow: 0 4px 6px rgba(0,0,0,0.1);">
    <div style="background: linear-gradient(135deg, #022b19 0%, #034d2e 100%); padding: 30px 20px; text-align: center;">
      <h1 style="color: white; margin: 0; font-size: 24px;">CampusCut</h1>
      <p style="color: #fbbf24; margin: 10px 0 0 0; font-size: 14px;">Message from Fellow Barber</p>
    </div>
    
    <div style="padding: 30px;">
      <p style="color: #1f2937; font-size: 16px; margin: 0 0 20px 0;">Hi ${firstName},</p>
      <p style="color: #4b5563; font-size: 15px; line-height: 1.6; margin: 0 0 20px 0;">
        You have a new message from your fellow barber, <strong>${details.senderName}</strong>.
      </p>
      
      <!-- Message Content -->
      <div style="background-color: #fef3c7; border-left: 4px solid #f59e0b; border-radius: 0 12px 12px 0; padding: 20px; margin: 20px 0;">
        <p style="color: #92400e; margin: 0; font-size: 15px; line-height: 1.6; font-style: italic;">
          "${details.messageContent.length > 200 ? details.messageContent.substring(0, 200) + '...' : details.messageContent}"
        </p>
        <p style="color: #6b7280; margin: 10px 0 0 0; font-size: 12px;">- ${details.senderName}</p>
      </div>
      
      <!-- CTA Button -->
      <div style="text-align: center; margin: 30px 0;">
        <a href="${conversationLink}" style="display: inline-block; background-color: #5a7268; color: white; padding: 14px 40px; text-decoration: none; border-radius: 8px; font-weight: 600; font-size: 16px;">
          Reply to Message
        </a>
      </div>
      
      <p style="color: #6b7280; font-size: 13px; text-align: center; margin: 20px 0 0 0;">
        Open the CampusCut app to continue the conversation.
      </p>
    </div>
    
    <div style="background-color: #f9fafb; padding: 20px; text-align: center;">
      <p style="color: #9ca3af; font-size: 12px; margin: 0;">${new Date().getFullYear()} CampusCut</p>
    </div>
  </div>
</body>
</html>`.trim();

  try {
    const transporter = createTransporter();

    const mailOptions = {
      from: `CampusCut <${process.env.SMTP_USER}>`,
      to: details.recipientEmail,
      subject,
      text,
      html
    };

    await transporter.sendMail(mailOptions);
    logger.info(`Barber-to-barber message email sent to: ${details.recipientEmail}`);
  } catch (error: any) {
    logger.error(`Failed to send barber-to-barber message email to ${details.recipientEmail}:`, error.message);
    // Don't throw - email notification is non-critical
  }
}

// ============================================
// BARBER CHECK-IN EMAIL (1 Hour Past Scheduled Time)
// ============================================

/**
 * Barber Check-In Email Details Interface
 */
export interface BarberCheckInEmailDetails {
  bookingId: string;
  serviceName: string;
  price: number; // in dollars
  scheduledDate: string;
  scheduledTime: string;
  location?: string;
  consumerName: string;
  barberName: string;
  barberEmail: string;
}

/**
 * Consumer Check-In Email Details Interface
 */
export interface ConsumerCheckInEmailDetails {
  bookingId: string;
  serviceName: string;
  price: number; // in dollars
  scheduledDate: string;
  scheduledTime: string;
  location?: string;
  consumerName: string;
  consumerEmail: string;
  barberName: string;
}

/**
 * Send Consumer Check-In Email
 * 
 * Sends a check-in email to the consumer when 1 hour has passed since their
 * scheduled booking time and the booking hasn't been updated.
 * 
 * This email prompts the consumer to:
 * - Message the barber if they need to follow up
 * - Wait for the barber to mark the booking complete
 * - Cancel if the appointment didn't happen
 * 
 * @param details - Consumer check-in email details
 */
export async function sendConsumerCheckInEmail(details: ConsumerCheckInEmailDetails): Promise<void> {
  if (isAutoVerifyEnabled()) {
    logger.info(`[AUTO-VERIFY MODE] Skipping consumer check-in email for booking ${details.bookingId}`);
    return;
  }

  const frontendUrl = process.env.FRONTEND_URL || 'https://campuscut.com';
  const consumerDashboardUrl = `${frontendUrl}/consumer/booking-status`;

  const firstName = details.consumerName.split(' ')[0];
  const subject = `Booking Update: ${details.serviceName} with ${details.barberName}`;

  const text = `
Hi ${firstName},

This is a friendly check-in regarding your ${details.serviceName} appointment with ${details.barberName}.

The scheduled time was ${details.scheduledDate} at ${details.scheduledTime}, and we noticed the booking hasn't been updated yet.

BOOKING DETAILS
---------------
Service: ${details.serviceName}
Barber: ${details.barberName}
Date: ${details.scheduledDate}
Time: ${details.scheduledTime}
${details.location ? `Location: ${details.location}` : ''}
Price: $${details.price.toFixed(2)}

WHAT'S NEXT?
------------

If your haircut was completed:
→ Your barber will mark the booking as complete and you'll receive a payment request

If you haven't heard from your barber:
→ Send them a message to follow up on your appointment

If the appointment didn't happen:
→ You can cancel the booking and book with another barber

Check your booking: ${consumerDashboardUrl}

Booking Reference: ${details.bookingId.slice(0, 8).toUpperCase()}

---
CampusCut
`.trim();

  const html = `
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
</head>
<body style="margin: 0; padding: 0; background-color: #f3f4f6; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;">
  <div style="max-width: 500px; margin: 40px auto; background-color: white; border-radius: 16px; overflow: hidden; box-shadow: 0 4px 6px rgba(0,0,0,0.1);">
    <!-- Header -->
    <div style="background: linear-gradient(135deg, #5a7268 0%, #4a6258 100%); padding: 30px 20px; text-align: center;">
      <h1 style="color: white; margin: 0; font-size: 24px;">Booking Update</h1>
      <p style="color: #d1e0d9; margin: 8px 0 0 0; font-size: 14px;">Checking in on your appointment</p>
    </div>
    
    <div style="padding: 30px;">
      <p style="color: #1f2937; font-size: 16px; margin: 0 0 20px 0;">Hi ${firstName}!</p>
      <p style="color: #4b5563; font-size: 15px; line-height: 1.6; margin: 0 0 20px 0;">
        This is a friendly check-in regarding your <strong>${details.serviceName}</strong> appointment with <strong>${details.barberName}</strong>.
      </p>
      
      <p style="color: #4b5563; font-size: 15px; line-height: 1.6; margin: 0 0 25px 0;">
        The scheduled time was <strong>${details.scheduledDate}</strong> at <strong>${details.scheduledTime}</strong>, and we noticed the booking hasn't been updated yet.
      </p>
      
      <!-- Booking Details Card -->
      <div style="background-color: #f9fafb; border-radius: 12px; padding: 20px; margin: 20px 0; border: 2px solid #e5e7eb;">
        <h3 style="color: #1f2937; margin: 0 0 15px 0; font-size: 14px; text-transform: uppercase; letter-spacing: 0.5px;">Booking Details</h3>
        <table style="width: 100%; border-collapse: collapse;">
          <tr>
            <td style="padding: 8px 0; color: #6b7280; font-size: 14px;">Service</td>
            <td style="padding: 8px 0; color: #1f2937; font-weight: 600; text-align: right;">${details.serviceName}</td>
          </tr>
          <tr>
            <td style="padding: 8px 0; color: #6b7280; font-size: 14px;">Barber</td>
            <td style="padding: 8px 0; color: #1f2937; font-weight: 600; text-align: right;">${details.barberName}</td>
          </tr>
          <tr>
            <td style="padding: 8px 0; color: #6b7280; font-size: 14px;">Scheduled Date</td>
            <td style="padding: 8px 0; color: #1f2937; font-weight: 600; text-align: right;">${details.scheduledDate}</td>
          </tr>
          <tr>
            <td style="padding: 8px 0; color: #6b7280; font-size: 14px;">Scheduled Time</td>
            <td style="padding: 8px 0; color: #5a7268; font-weight: 700; text-align: right;">${details.scheduledTime}</td>
          </tr>
          ${details.location ? `
          <tr>
            <td style="padding: 8px 0; color: #6b7280; font-size: 14px;">Location</td>
            <td style="padding: 8px 0; color: #1f2937; font-weight: 600; text-align: right;">${details.location}</td>
          </tr>` : ''}
          <tr>
            <td style="padding: 8px 0; color: #6b7280; font-size: 14px;">Price</td>
            <td style="padding: 8px 0; color: #5a7268; font-weight: 700; text-align: right; font-size: 18px;">$${details.price.toFixed(2)}</td>
          </tr>
        </table>
      </div>
      
      <!-- What's Next Section -->
      <div style="margin: 25px 0;">
        <h3 style="color: #1f2937; margin: 0 0 15px 0; font-size: 14px; text-transform: uppercase; letter-spacing: 0.5px;">What's Next?</h3>
        
        <!-- Option 1: Completed -->
        <div style="background-color: #f0fdf4; border-radius: 10px; padding: 15px; margin-bottom: 12px; border-left: 4px solid #22c55e;">
          <p style="color: #166534; margin: 0; font-weight: 600; font-size: 14px;">If your haircut was completed:</p>
          <p style="color: #15803d; margin: 8px 0 0 0; font-size: 13px;">Your barber will mark the booking as complete and you'll receive a payment request</p>
        </div>
        
        <!-- Option 2: Follow up -->
        <div style="background-color: #fef3c7; border-radius: 10px; padding: 15px; margin-bottom: 12px; border-left: 4px solid #f59e0b;">
          <p style="color: #92400e; margin: 0; font-weight: 600; font-size: 14px;">If you haven't heard from your barber:</p>
          <p style="color: #b45309; margin: 8px 0 0 0; font-size: 13px;">Send them a message to follow up on your appointment</p>
        </div>
        
        <!-- Option 3: Cancel -->
        <div style="background-color: #fef2f2; border-radius: 10px; padding: 15px; border-left: 4px solid #ef4444;">
          <p style="color: #991b1b; margin: 0; font-weight: 600; font-size: 14px;">If the appointment didn't happen:</p>
          <p style="color: #b91c1c; margin: 8px 0 0 0; font-size: 13px;">You can cancel the booking and book with another barber</p>
        </div>
      </div>
      
      <!-- CTA Button -->
      <div style="text-align: center; margin: 30px 0;">
        <a href="${consumerDashboardUrl}" style="display: inline-block; background-color: #5a7268; color: white; padding: 16px 40px; text-decoration: none; border-radius: 10px; font-weight: 700; font-size: 16px;">
          View My Booking
        </a>
      </div>
      
      <!-- Booking Reference -->
      <div style="text-align: center; margin: 25px 0;">
        <p style="color: #9ca3af; margin: 0; font-size: 12px;">Booking Reference</p>
        <p style="color: #1f2937; margin: 5px 0 0 0; font-size: 16px; font-weight: 700; letter-spacing: 2px;">${details.bookingId.slice(0, 8).toUpperCase()}</p>
      </div>
    </div>
    
    <div style="background-color: #f9fafb; padding: 20px; text-align: center;">
      <p style="color: #9ca3af; font-size: 12px; margin: 0;">© ${new Date().getFullYear()} CampusCut</p>
    </div>
  </div>
</body>
</html>`.trim();

  try {
    const transporter = createTransporter();

    const mailOptions = {
      from: `CampusCut <${process.env.SMTP_USER}>`,
      to: details.consumerEmail,
      subject,
      text,
      html
    };

    await transporter.sendMail(mailOptions);
    logger.info(`Consumer check-in email sent to: ${details.consumerEmail} for booking ${details.bookingId}`);
  } catch (error: any) {
    logger.error(`Failed to send consumer check-in email to ${details.consumerEmail}:`, error.message);
    throw error;
  }
}

/**
 * Send Barber Check-In Email
 * 
 * Sends a check-in email to the barber when 1 hour has passed since their
 * scheduled booking time and they have not marked the booking as complete.
 * 
 * This email prompts the barber to either:
 * - Request payment (mark complete) if the service was done
 * - Edit the booking if they need to reschedule
 * - Cancel the booking if they cannot complete it
 * 
 * @param details - Barber check-in email details
 */
export async function sendBarberCheckInEmail(details: BarberCheckInEmailDetails): Promise<void> {
  if (isAutoVerifyEnabled()) {
    logger.info(`[AUTO-VERIFY MODE] Skipping barber check-in email for booking ${details.bookingId}`);
    return;
  }

  const frontendUrl = process.env.FRONTEND_URL || 'https://campuscut.com';
  const barberDashboardUrl = `${frontendUrl}/web/barber`;

  const firstName = details.barberName.split(' ')[0];
  const subject = `Action Needed: ${details.serviceName} with ${details.consumerName} - Status Update Required`;

  const text = `
Hi ${firstName},

This is a friendly check-in regarding your ${details.serviceName} appointment with ${details.consumerName}.

The scheduled time was ${details.scheduledDate} at ${details.scheduledTime}, and we noticed the booking hasn't been updated yet.

BOOKING DETAILS
---------------
Service: ${details.serviceName}
Customer: ${details.consumerName}
Date: ${details.scheduledDate}
Time: ${details.scheduledTime}
${details.location ? `Location: ${details.location}` : ''}
Price: $${details.price.toFixed(2)}

PLEASE UPDATE THE BOOKING STATUS
---------------------------------

If the haircut was completed:
→ Mark the booking as "Complete" to request payment from ${details.consumerName}

If you need to reschedule:
→ Edit the booking to set a new date/time

If you cannot complete this booking:
→ Cancel the booking so ${details.consumerName} can book with another barber

Visit your dashboard: ${barberDashboardUrl}

Booking Reference: ${details.bookingId.slice(0, 8).toUpperCase()}

---
CampusCut
`.trim();

  const html = `
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
</head>
<body style="margin: 0; padding: 0; background-color: #f3f4f6; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;">
  <div style="max-width: 500px; margin: 40px auto; background-color: white; border-radius: 16px; overflow: hidden; box-shadow: 0 4px 6px rgba(0,0,0,0.1);">
    <!-- Header -->
    <div style="background: linear-gradient(135deg, #5a7268 0%, #4a6258 100%); padding: 30px 20px; text-align: center;">
      <h1 style="color: white; margin: 0; font-size: 24px;">Action Needed</h1>
      <p style="color: #d1e0d9; margin: 8px 0 0 0; font-size: 14px;">Booking Status Update Required</p>
    </div>
    
    <div style="padding: 30px;">
      <p style="color: #1f2937; font-size: 16px; margin: 0 0 20px 0;">Hi ${firstName}!</p>
      <p style="color: #4b5563; font-size: 15px; line-height: 1.6; margin: 0 0 20px 0;">
        This is a friendly check-in regarding your <strong>${details.serviceName}</strong> appointment with <strong>${details.consumerName}</strong>.
      </p>
      
      <p style="color: #4b5563; font-size: 15px; line-height: 1.6; margin: 0 0 25px 0;">
        The scheduled time was <strong>${details.scheduledDate}</strong> at <strong>${details.scheduledTime}</strong>, and we noticed the booking hasn't been updated yet.
      </p>
      
      <!-- Booking Details Card -->
      <div style="background-color: #f9fafb; border-radius: 12px; padding: 20px; margin: 20px 0; border: 2px solid #e5e7eb;">
        <h3 style="color: #1f2937; margin: 0 0 15px 0; font-size: 14px; text-transform: uppercase; letter-spacing: 0.5px;">Booking Details</h3>
        <table style="width: 100%; border-collapse: collapse;">
          <tr>
            <td style="padding: 8px 0; color: #6b7280; font-size: 14px;">Service</td>
            <td style="padding: 8px 0; color: #1f2937; font-weight: 600; text-align: right;">${details.serviceName}</td>
          </tr>
          <tr>
            <td style="padding: 8px 0; color: #6b7280; font-size: 14px;">Customer</td>
            <td style="padding: 8px 0; color: #1f2937; font-weight: 600; text-align: right;">${details.consumerName}</td>
          </tr>
          <tr>
            <td style="padding: 8px 0; color: #6b7280; font-size: 14px;">Scheduled Date</td>
            <td style="padding: 8px 0; color: #1f2937; font-weight: 600; text-align: right;">${details.scheduledDate}</td>
          </tr>
          <tr>
            <td style="padding: 8px 0; color: #6b7280; font-size: 14px;">Scheduled Time</td>
            <td style="padding: 8px 0; color: #5a7268; font-weight: 700; text-align: right;">${details.scheduledTime}</td>
          </tr>
          ${details.location ? `
          <tr>
            <td style="padding: 8px 0; color: #6b7280; font-size: 14px;">Location</td>
            <td style="padding: 8px 0; color: #1f2937; font-weight: 600; text-align: right;">${details.location}</td>
          </tr>` : ''}
          <tr>
            <td style="padding: 8px 0; color: #6b7280; font-size: 14px;">Price</td>
            <td style="padding: 8px 0; color: #5a7268; font-weight: 700; text-align: right; font-size: 18px;">$${details.price.toFixed(2)}</td>
          </tr>
        </table>
      </div>
      
      <!-- Action Options -->
      <div style="margin: 25px 0;">
        <h3 style="color: #1f2937; margin: 0 0 15px 0; font-size: 14px; text-transform: uppercase; letter-spacing: 0.5px;">Please Update the Booking</h3>
        
        <!-- Option 1: Complete -->
        <div style="background-color: #f2f5f4; border-radius: 10px; padding: 15px; margin-bottom: 12px; border-left: 4px solid #5a7268;">
          <p style="color: #3d5149; margin: 0; font-weight: 600; font-size: 14px;">If the haircut was completed:</p>
          <p style="color: #4a6258; margin: 8px 0 0 0; font-size: 13px;">Mark the booking as "Complete" to request payment from ${details.consumerName}</p>
        </div>
        
        <!-- Option 2: Edit -->
        <div style="background-color: #f2f5f4; border-radius: 10px; padding: 15px; margin-bottom: 12px; border-left: 4px solid #5a7268;">
          <p style="color: #3d5149; margin: 0; font-weight: 600; font-size: 14px;">If you need to reschedule:</p>
          <p style="color: #4a6258; margin: 8px 0 0 0; font-size: 13px;">Edit the booking to set a new date/time</p>
        </div>
        
        <!-- Option 3: Cancel -->
        <div style="background-color: #f2f5f4; border-radius: 10px; padding: 15px; border-left: 4px solid #5a7268;">
          <p style="color: #3d5149; margin: 0; font-weight: 600; font-size: 14px;">If you cannot complete this booking:</p>
          <p style="color: #4a6258; margin: 8px 0 0 0; font-size: 13px;">Cancel the booking so ${details.consumerName} can book with another barber</p>
        </div>
      </div>
      
      <!-- CTA Button -->
      <div style="text-align: center; margin: 30px 0;">
        <a href="${barberDashboardUrl}" style="display: inline-block; background-color: #5a7268; color: white; padding: 16px 40px; text-decoration: none; border-radius: 10px; font-weight: 700; font-size: 16px;">
          Update Booking Status
        </a>
      </div>
      
      <!-- Booking Reference -->
      <div style="text-align: center; margin: 25px 0;">
        <p style="color: #9ca3af; margin: 0; font-size: 12px;">Booking Reference</p>
        <p style="color: #1f2937; margin: 5px 0 0 0; font-size: 16px; font-weight: 700; letter-spacing: 2px;">${details.bookingId.slice(0, 8).toUpperCase()}</p>
      </div>
    </div>
    
    <div style="background-color: #f9fafb; padding: 20px; text-align: center;">
      <p style="color: #9ca3af; font-size: 12px; margin: 0;">© ${new Date().getFullYear()} CampusCut</p>
    </div>
  </div>
</body>
</html>`.trim();

  try {
    const transporter = createTransporter();

    const mailOptions = {
      from: `CampusCut <${process.env.SMTP_USER}>`,
      to: details.barberEmail,
      subject,
      text,
      html
    };

    await transporter.sendMail(mailOptions);
    logger.info(`Barber check-in email sent to: ${details.barberEmail} for booking ${details.bookingId}`);
  } catch (error: any) {
    logger.error(`Failed to send barber check-in email to ${details.barberEmail}:`, error.message);
    throw error; // Re-throw so the cron job knows the email failed
  }
}

// ============================================
// 24-HOUR OVERDUE BOOKING EMAIL
// ============================================

/**
 * Send Barber 24-Hour Follow-up Email
 * 
 * Sends an urgent follow-up email to the barber when 24 hours (1 day) has passed 
 * since their scheduled booking time and they still have not updated the booking status.
 * 
 * This is a more urgent reminder than the 1-hour check-in.
 * 
 * @param details - Barber check-in email details (same interface)
 */
export async function sendBarber24HFollowupEmail(details: BarberCheckInEmailDetails): Promise<void> {
  if (isAutoVerifyEnabled()) {
    logger.info(`[AUTO-VERIFY MODE] Skipping barber 24h follow-up email for booking ${details.bookingId}`);
    return;
  }

  const frontendUrl = process.env.FRONTEND_URL || 'https://campuscut.com';
  const barberDashboardUrl = `${frontendUrl}/web/barber`;

  const firstName = details.barberName.split(' ')[0];
  const subject = `⚠️ Urgent: Booking with ${details.consumerName} is 24 Hours Overdue`;

  const text = `
Hi ${firstName},

URGENT: Your booking with ${details.consumerName} is now more than 24 hours past the scheduled time and still hasn't been updated.

BOOKING DETAILS
---------------
Service: ${details.serviceName}
Customer: ${details.consumerName}
Date: ${details.scheduledDate}
Time: ${details.scheduledTime}
${details.location ? `Location: ${details.location}` : ''}
Price: $${details.price.toFixed(2)}

THIS BOOKING REQUIRES YOUR IMMEDIATE ATTENTION
----------------------------------------------

If the haircut was completed:
→ Mark the booking as "Complete" to request payment from ${details.consumerName}

If you need to reschedule:
→ Edit the booking to set a new date/time

If you cannot complete this booking:
→ Cancel the booking so ${details.consumerName} can book with another barber

Visit your dashboard: ${barberDashboardUrl}

Booking Reference: ${details.bookingId.slice(0, 8).toUpperCase()}

---
CampusCut
`.trim();

  const html = `
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
</head>
<body style="margin: 0; padding: 0; background-color: #f3f4f6; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;">
  <div style="max-width: 500px; margin: 40px auto; background-color: white; border-radius: 16px; overflow: hidden; box-shadow: 0 4px 6px rgba(0,0,0,0.1);">
    <!-- Header with Urgent Warning -->
    <div style="background: linear-gradient(135deg, #dc2626 0%, #b91c1c 100%); padding: 30px 20px; text-align: center;">
      <span style="font-size: 48px;">🚨</span>
      <h1 style="color: white; margin: 10px 0 0 0; font-size: 24px;">24 Hours Overdue</h1>
      <p style="color: #fecaca; margin: 5px 0 0 0; font-size: 14px;">Urgent Action Required</p>
    </div>
    
    <div style="padding: 30px;">
      <p style="color: #1f2937; font-size: 16px; margin: 0 0 20px 0;">Hi ${firstName},</p>
      
      <div style="background-color: #fef2f2; border-radius: 12px; padding: 15px; margin: 0 0 20px 0; border-left: 4px solid #dc2626;">
        <p style="color: #991b1b; font-size: 15px; line-height: 1.6; margin: 0; font-weight: 600;">
          Your booking with <strong>${details.consumerName}</strong> is now more than <strong>24 hours</strong> past the scheduled time and still hasn't been updated.
        </p>
      </div>
      
      <!-- Booking Details Card -->
      <div style="background-color: #f9fafb; border-radius: 12px; padding: 20px; margin: 20px 0; border: 2px solid #dc2626;">
        <h3 style="color: #dc2626; margin: 0 0 15px 0; font-size: 14px; text-transform: uppercase; letter-spacing: 0.5px;">Overdue Booking</h3>
        <table style="width: 100%; border-collapse: collapse;">
          <tr>
            <td style="padding: 8px 0; color: #6b7280; font-size: 14px;">Service</td>
            <td style="padding: 8px 0; color: #1f2937; font-weight: 600; text-align: right;">${details.serviceName}</td>
          </tr>
          <tr>
            <td style="padding: 8px 0; color: #6b7280; font-size: 14px;">Customer</td>
            <td style="padding: 8px 0; color: #1f2937; font-weight: 600; text-align: right;">${details.consumerName}</td>
          </tr>
          <tr>
            <td style="padding: 8px 0; color: #6b7280; font-size: 14px;">Scheduled Date</td>
            <td style="padding: 8px 0; color: #1f2937; font-weight: 600; text-align: right;">${details.scheduledDate}</td>
          </tr>
          <tr>
            <td style="padding: 8px 0; color: #6b7280; font-size: 14px;">Scheduled Time</td>
            <td style="padding: 8px 0; color: #dc2626; font-weight: 700; text-align: right;">${details.scheduledTime}</td>
          </tr>
          ${details.location ? `
          <tr>
            <td style="padding: 8px 0; color: #6b7280; font-size: 14px;">Location</td>
            <td style="padding: 8px 0; color: #1f2937; font-weight: 600; text-align: right;">${details.location}</td>
          </tr>` : ''}
          <tr>
            <td style="padding: 8px 0; color: #6b7280; font-size: 14px;">Price</td>
            <td style="padding: 8px 0; color: #5a7268; font-weight: 700; text-align: right; font-size: 18px;">$${details.price.toFixed(2)}</td>
          </tr>
        </table>
      </div>
      
      <!-- Action Options -->
      <div style="margin: 25px 0;">
        <h3 style="color: #dc2626; margin: 0 0 15px 0; font-size: 14px; text-transform: uppercase; letter-spacing: 0.5px;">Immediate Action Required</h3>
        
        <!-- Option 1: Complete -->
        <div style="background-color: #f2f5f4; border-radius: 10px; padding: 15px; margin-bottom: 12px; border-left: 4px solid #5a7268;">
          <p style="color: #166534; margin: 0; font-weight: 600; font-size: 14px;">Haircut was completed?</p>
          <p style="color: #15803d; margin: 8px 0 0 0; font-size: 13px;">Mark as "Complete" to request payment</p>
        </div>
        
        <!-- Option 2: Edit -->
        <div style="background-color: #eff6ff; border-radius: 10px; padding: 15px; margin-bottom: 12px; border-left: 4px solid #3b82f6;">
          <p style="color: #1e40af; margin: 0; font-weight: 600; font-size: 14px;">Need to reschedule?</p>
          <p style="color: #1d4ed8; margin: 8px 0 0 0; font-size: 13px;">Edit the booking for a new date/time</p>
        </div>
        
        <!-- Option 3: Cancel -->
        <div style="background-color: #fef2f2; border-radius: 10px; padding: 15px; border-left: 4px solid #ef4444;">
          <p style="color: #991b1b; margin: 0; font-weight: 600; font-size: 14px;">Cannot complete?</p>
          <p style="color: #b91c1c; margin: 8px 0 0 0; font-size: 13px;">Cancel so ${details.consumerName} can rebook</p>
        </div>
      </div>
      
      <!-- CTA Button -->
      <div style="text-align: center; margin: 30px 0;">
        <a href="${barberDashboardUrl}" style="display: inline-block; background-color: #dc2626; color: white; padding: 16px 40px; text-decoration: none; border-radius: 10px; font-weight: 700; font-size: 16px;">
          Update Booking Now
        </a>
      </div>
      
      <!-- Booking Reference -->
      <div style="text-align: center; margin: 25px 0;">
        <p style="color: #9ca3af; margin: 0; font-size: 12px;">Booking Reference</p>
        <p style="color: #1f2937; margin: 5px 0 0 0; font-size: 16px; font-weight: 700; letter-spacing: 2px;">${details.bookingId.slice(0, 8).toUpperCase()}</p>
      </div>
    </div>
    
    <div style="background-color: #fef2f2; padding: 20px; text-align: center;">
      <p style="color: #991b1b; font-size: 12px; margin: 0;">© ${new Date().getFullYear()} CampusCut</p>
      <p style="color: #b91c1c; font-size: 11px; margin: 8px 0 0 0;">Please update this booking as soon as possible</p>
    </div>
  </div>
</body>
</html>`.trim();

  try {
    const transporter = createTransporter();

    const mailOptions = {
      from: `CampusCut <${process.env.SMTP_USER}>`,
      to: details.barberEmail,
      subject,
      text,
      html
    };

    await transporter.sendMail(mailOptions);
    logger.info(`Barber 24h follow-up email sent to: ${details.barberEmail} for booking ${details.bookingId}`);
  } catch (error: any) {
    logger.error(`Failed to send barber 24h follow-up email to ${details.barberEmail}:`, error.message);
    throw error;
  }
}

// ============================================
// PAYMENT REMINDER EMAIL
// ============================================

/**
 * Payment Reminder Email Details Interface
 */
interface PaymentReminderEmailDetails {
  bookingId: string;
  consumerEmail: string;
  consumerName: string;
  barberName: string;
  serviceName: string;
  price: number; // in dollars
  completedDate: string; // formatted date string
  completedTime: string; // formatted time string
  location?: string;
  hoursAwaiting: number;
}

/**
 * Send Payment Reminder Email to Consumer
 * 
 * Sends a reminder email to the consumer when their completed booking
 * has been awaiting payment for a specified period.
 */
export async function sendPaymentReminderEmail(details: PaymentReminderEmailDetails): Promise<void> {
  if (isAutoVerifyEnabled()) {
    logger.info(`[AUTO-VERIFY MODE] Skipping payment reminder email for booking ${details.bookingId}`);
    return;
  }

  const frontendUrl = process.env.FRONTEND_URL || 'https://campuscut.com';
  const paymentUrl = `${frontendUrl}/web/booking/${details.bookingId}`;

  const firstName = details.consumerName.split(' ')[0];
  const subject = `Payment Pending - Complete your ${details.serviceName} payment`;

  const text = `
Hi ${firstName},

Your ${details.serviceName} with ${details.barberName} has been completed and is awaiting payment.

BOOKING DETAILS
---------------
Service: ${details.serviceName}
Barber: ${details.barberName}
Completed: ${details.completedDate} at ${details.completedTime}
${details.location ? `Location: ${details.location}` : ''}
Amount Due: $${details.price.toFixed(2)}

Please complete your payment to support your barber.

Pay Now: ${paymentUrl}

Booking Reference: ${details.bookingId.slice(0, 8).toUpperCase()}

---
CampusCut
`.trim();

  const html = `
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
</head>
<body style="margin: 0; padding: 0; background-color: #f3f4f6; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;">
  <div style="max-width: 500px; margin: 40px auto; background-color: white; border-radius: 16px; overflow: hidden; box-shadow: 0 4px 6px rgba(0,0,0,0.1);">
    <!-- Header -->
    <div style="background: linear-gradient(135deg, #5a7268 0%, #4a6258 100%); padding: 30px 20px; text-align: center;">
      <h1 style="color: white; margin: 0; font-size: 24px;">Payment Reminder</h1>
      <p style="color: #d1e0d9; margin: 8px 0 0 0; font-size: 14px;">Complete your transaction</p>
    </div>
    
    <div style="padding: 30px;">
      <p style="color: #1f2937; font-size: 16px; margin: 0 0 20px 0;">Hi ${firstName}!</p>
      <p style="color: #4b5563; font-size: 15px; line-height: 1.6; margin: 0 0 25px 0;">
        Your <strong>${details.serviceName}</strong> with <strong>${details.barberName}</strong> has been completed and is awaiting payment.
      </p>
      
      <!-- Status Badge -->
      <div style="text-align: center; margin: 20px 0;">
        <span style="display: inline-block; background-color: #fef3c7; color: #92400e; padding: 10px 20px; border-radius: 25px; font-size: 14px; font-weight: 600;">
          Awaiting Payment
        </span>
      </div>
      
      <!-- Booking Details Card -->
      <div style="background-color: #f9fafb; border-radius: 12px; padding: 20px; margin: 20px 0; border: 2px solid #e5e7eb;">
        <h3 style="color: #1f2937; margin: 0 0 15px 0; font-size: 14px; text-transform: uppercase; letter-spacing: 0.5px;">Completed Service</h3>
        <table style="width: 100%; border-collapse: collapse;">
          <tr>
            <td style="padding: 8px 0; color: #6b7280; font-size: 14px;">Service</td>
            <td style="padding: 8px 0; color: #1f2937; font-weight: 600; text-align: right;">${details.serviceName}</td>
          </tr>
          <tr>
            <td style="padding: 8px 0; color: #6b7280; font-size: 14px;">Barber</td>
            <td style="padding: 8px 0; color: #1f2937; font-weight: 600; text-align: right;">${details.barberName}</td>
          </tr>
          <tr>
            <td style="padding: 8px 0; color: #6b7280; font-size: 14px;">Date</td>
            <td style="padding: 8px 0; color: #1f2937; font-weight: 600; text-align: right;">${details.completedDate}</td>
          </tr>
          <tr>
            <td style="padding: 8px 0; color: #6b7280; font-size: 14px;">Time</td>
            <td style="padding: 8px 0; color: #1f2937; font-weight: 600; text-align: right;">${details.completedTime}</td>
          </tr>
          ${details.location ? `
          <tr>
            <td style="padding: 8px 0; color: #6b7280; font-size: 14px;">Location</td>
            <td style="padding: 8px 0; color: #1f2937; font-weight: 600; text-align: right;">${details.location}</td>
          </tr>` : ''}
        </table>
        
        <div style="border-top: 2px solid #e5e7eb; margin: 15px 0; padding-top: 15px;">
          <table style="width: 100%; border-collapse: collapse;">
            <tr>
              <td style="color: #1f2937; font-weight: 700; font-size: 16px;">Amount Due</td>
              <td style="color: #5a7268; font-weight: 700; text-align: right; font-size: 24px;">$${details.price.toFixed(2)}</td>
            </tr>
          </table>
        </div>
      </div>
      
      <!-- Support Message -->
      <div style="background-color: #f2f5f4; border-radius: 12px; padding: 20px; margin: 20px 0;">
        <p style="color: #3d5149; margin: 0; font-size: 14px; line-height: 1.6;">
          <strong>Support your barber!</strong><br>
          ${details.barberName} has completed your service and is waiting for payment. Please complete your transaction to help support campus barbers.
        </p>
      </div>
      
      <!-- CTA Button -->
      <div style="text-align: center; margin: 30px 0;">
        <a href="${paymentUrl}" style="display: inline-block; background-color: #5a7268; color: white; padding: 16px 50px; text-decoration: none; border-radius: 10px; font-weight: 700; font-size: 16px;">
          Complete Payment
        </a>
      </div>
      
      <!-- Booking Reference -->
      <div style="text-align: center; margin: 25px 0;">
        <p style="color: #9ca3af; margin: 0; font-size: 12px;">Booking Reference</p>
        <p style="color: #1f2937; margin: 5px 0 0 0; font-size: 16px; font-weight: 700; letter-spacing: 2px;">${details.bookingId.slice(0, 8).toUpperCase()}</p>
      </div>
      
      <p style="color: #6b7280; font-size: 13px; text-align: center; margin: 20px 0 0 0;">
        Thank you for using CampusCut!
      </p>
    </div>
    
    <div style="background-color: #f9fafb; padding: 20px; text-align: center;">
      <p style="color: #9ca3af; font-size: 12px; margin: 0;">© ${new Date().getFullYear()} CampusCut</p>
    </div>
  </div>
</body>
</html>`.trim();

  try {
    const transporter = createTransporter();

    const mailOptions = {
      from: `CampusCut <${process.env.SMTP_USER}>`,
      to: details.consumerEmail,
      subject,
      text,
      html
    };

    await transporter.sendMail(mailOptions);
    logger.info(`Payment reminder email sent to consumer: ${details.consumerEmail} for booking ${details.bookingId}`);
  } catch (error: any) {
    logger.error(`Failed to send payment reminder email to ${details.consumerEmail}:`, error.message);
    throw error;
  }
}

// ============================================
// PENDING BOOKING WARNING EMAIL (3h, 2h, 1h Before)
// ============================================

/**
 * Pending Booking Warning Email Details Interface
 */
export interface PendingBookingWarningDetails {
  bookingId: string;
  serviceName: string;
  price: number;
  scheduledDate: string;
  scheduledTime: string;
  location?: string;
  consumerName: string;
  barberName: string;
  barberEmail: string;
  hoursRemaining?: number; // 3, 2, or 1
  timeDescription?: string; // "in 3 hours", "in 2 hours", "in 1 hour"
}

/**
 * Send Pending Booking Warning Email to Barber
 * 
 * Sent at 3h, 2h, and 1h before the scheduled time when the booking is still PENDING.
 * Reminds the barber to accept or decline the booking.
 */
export async function sendPendingBookingWarningEmail(details: PendingBookingWarningDetails): Promise<void> {
  if (isAutoVerifyEnabled()) {
    logger.info(`[AUTO-VERIFY MODE] Skipping pending booking warning email for booking ${details.bookingId}`);
    return;
  }

  const frontendUrl = process.env.FRONTEND_URL || 'https://campuscut.com';
  const barberDashboardUrl = `${frontendUrl}/web/barber`;

  const firstName = details.barberName.split(' ')[0];
  const hoursRemaining = details.hoursRemaining || 3;
  const timeDescription = details.timeDescription || `in ${hoursRemaining} hour${hoursRemaining > 1 ? 's' : ''}`;
  
  const subject = `Action Required: Accept Booking from ${details.consumerName} - Appointment ${timeDescription}`;

  const text = `
Hi ${firstName},

You have a pending booking request that requires your attention!

${details.consumerName} has requested a ${details.serviceName} appointment scheduled for ${details.scheduledDate} at ${details.scheduledTime}.

The appointment is ${timeDescription}. Please accept or decline this booking as soon as possible.

BOOKING DETAILS
---------------
Service: ${details.serviceName}
Customer: ${details.consumerName}
Date: ${details.scheduledDate}
Time: ${details.scheduledTime}
${details.location ? `Location: ${details.location}` : ''}
Price: $${details.price.toFixed(2)}

Please visit your dashboard to accept or decline this booking: ${barberDashboardUrl}

Booking Reference: ${details.bookingId.slice(0, 8).toUpperCase()}

---
CampusCut
`.trim();

  const html = `
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
</head>
<body style="margin: 0; padding: 0; background-color: #f3f4f6; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;">
  <div style="max-width: 500px; margin: 40px auto; background-color: white; border-radius: 16px; overflow: hidden; box-shadow: 0 4px 6px rgba(0,0,0,0.1);">
    <!-- Header -->
    <div style="background: linear-gradient(135deg, #5a7268 0%, #445750 100%); padding: 30px 20px; text-align: center;">
      <h1 style="color: white; margin: 0; font-size: 24px;">Action Required</h1>
      <p style="color: #c8d6cf; margin: 8px 0 0 0; font-size: 14px;">Appointment ${timeDescription}</p>
    </div>
    
    <div style="padding: 30px;">
      <p style="color: #1f2937; font-size: 16px; margin: 0 0 20px 0;">Hi ${firstName}!</p>
      
      <!-- Time Warning -->
      <div style="background-color: #f0fdf4; border: 2px solid #5a7268; border-radius: 12px; padding: 15px; margin: 0 0 25px 0;">
        <p style="color: #445750; margin: 0; font-weight: 600; font-size: 15px; text-align: center;">
          Appointment is ${timeDescription} - please respond now
        </p>
      </div>
      
      <p style="color: #4b5563; font-size: 15px; line-height: 1.6; margin: 0 0 25px 0;">
        <strong>${details.consumerName}</strong> has requested a <strong>${details.serviceName}</strong> appointment and is waiting for your confirmation.
      </p>
      
      <!-- Booking Details Card -->
      <div style="background-color: #f9fafb; border-radius: 12px; padding: 20px; margin: 20px 0; border: 2px solid #e5e7eb;">
        <h3 style="color: #1f2937; margin: 0 0 15px 0; font-size: 14px; text-transform: uppercase; letter-spacing: 0.5px;">Booking Details</h3>
        <table style="width: 100%; border-collapse: collapse;">
          <tr>
            <td style="padding: 8px 0; color: #6b7280; font-size: 14px;">Service</td>
            <td style="padding: 8px 0; color: #1f2937; font-weight: 600; text-align: right;">${details.serviceName}</td>
          </tr>
          <tr>
            <td style="padding: 8px 0; color: #6b7280; font-size: 14px;">Customer</td>
            <td style="padding: 8px 0; color: #1f2937; font-weight: 600; text-align: right;">${details.consumerName}</td>
          </tr>
          <tr>
            <td style="padding: 8px 0; color: #6b7280; font-size: 14px;">Scheduled Date</td>
            <td style="padding: 8px 0; color: #1f2937; font-weight: 600; text-align: right;">${details.scheduledDate}</td>
          </tr>
          <tr>
            <td style="padding: 8px 0; color: #6b7280; font-size: 14px;">Scheduled Time</td>
            <td style="padding: 8px 0; color: #5a7268; font-weight: 700; text-align: right;">${details.scheduledTime}</td>
          </tr>
          ${details.location ? `
          <tr>
            <td style="padding: 8px 0; color: #6b7280; font-size: 14px;">Location</td>
            <td style="padding: 8px 0; color: #1f2937; font-weight: 600; text-align: right;">${details.location}</td>
          </tr>` : ''}
          <tr>
            <td style="padding: 8px 0; color: #6b7280; font-size: 14px;">Price</td>
            <td style="padding: 8px 0; color: #5a7268; font-weight: 700; text-align: right; font-size: 18px;">$${details.price.toFixed(2)}</td>
          </tr>
        </table>
      </div>
      
      <!-- CTA Button -->
      <div style="text-align: center; margin: 30px 0;">
        <a href="${barberDashboardUrl}" style="display: inline-block; background-color: #5a7268; color: white; padding: 16px 40px; text-decoration: none; border-radius: 10px; font-weight: 700; font-size: 16px;">
          Accept or Decline Booking
        </a>
      </div>
      
      <!-- Booking Reference -->
      <div style="text-align: center; margin: 25px 0;">
        <p style="color: #9ca3af; margin: 0; font-size: 12px;">Booking Reference</p>
        <p style="color: #1f2937; margin: 5px 0 0 0; font-size: 16px; font-weight: 700; letter-spacing: 2px;">${details.bookingId.slice(0, 8).toUpperCase()}</p>
      </div>
    </div>
    
    <div style="background-color: #f9fafb; padding: 20px; text-align: center;">
      <p style="color: #9ca3af; font-size: 12px; margin: 0;">© ${new Date().getFullYear()} CampusCut</p>
    </div>
  </div>
</body>
</html>`.trim();

  try {
    const transporter = createTransporter();

    const mailOptions = {
      from: `CampusCut <${process.env.SMTP_USER}>`,
      to: details.barberEmail,
      subject,
      text,
      html
    };

    await transporter.sendMail(mailOptions);
    logger.info(`Pending booking warning email sent to barber: ${details.barberEmail} for booking ${details.bookingId}`);
  } catch (error: any) {
    logger.error(`Failed to send pending booking warning email to ${details.barberEmail}:`, error.message);
    throw error;
  }
}

// ============================================
// AUTO-CANCELLATION EMAILS (2 Hours Before)
// ============================================

/**
 * Auto-Cancellation Email Details Interface
 */
export interface AutoCancellationEmailDetails {
  bookingId: string;
  serviceName: string;
  serviceType: string;
  price: number;
  scheduledDate: string;
  scheduledTime: string;
  scheduledDateTime: string; // ISO timestamp for alternative barber lookup
  location?: string;
  consumerName: string;
  consumerEmail: string;
  barberName: string;
  barberEmail: string;
  campusId?: string;
  campusTimezone?: string;
  alternativeBarbers?: { id: string; name: string; avatar?: string; avgRating?: number; totalReviews?: number }[];
}

/**
 * Send Auto-Cancellation Email to Barber
 * 
 * Sent when a pending booking is auto-cancelled 2 hours before scheduled time
 * because the barber didn't accept it.
 */
export async function sendBarberAutoCancellationEmail(details: AutoCancellationEmailDetails): Promise<void> {
  if (isAutoVerifyEnabled()) {
    logger.info(`[AUTO-VERIFY MODE] Skipping barber auto-cancellation email for booking ${details.bookingId}`);
    return;
  }

  const frontendUrl = process.env.FRONTEND_URL || 'https://campuscut.com';
  const barberDashboardUrl = `${frontendUrl}/web/barber`;

  const firstName = details.barberName.split(' ')[0];
  const subject = `Booking Auto-Cancelled: ${details.serviceName} with ${details.consumerName}`;

  const text = `
Hi ${firstName},

The pending booking request from ${details.consumerName} has been automatically cancelled.

This booking was cancelled because it was not accepted before the 2-hour deadline prior to the scheduled appointment time.

CANCELLED BOOKING DETAILS
-------------------------
Service: ${details.serviceName}
Customer: ${details.consumerName}
Scheduled Date: ${details.scheduledDate}
Scheduled Time: ${details.scheduledTime}
${details.location ? `Location: ${details.location}` : ''}
Price: $${details.price.toFixed(2)}

To avoid auto-cancellations in the future, please respond to booking requests promptly.

Visit your dashboard: ${barberDashboardUrl}

Booking Reference: ${details.bookingId.slice(0, 8).toUpperCase()}

---
CampusCut
`.trim();

  const html = `
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
</head>
<body style="margin: 0; padding: 0; background-color: #f3f4f6; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;">
  <div style="max-width: 500px; margin: 40px auto; background-color: white; border-radius: 16px; overflow: hidden; box-shadow: 0 4px 6px rgba(0,0,0,0.1);">
    <!-- Header -->
    <div style="background-color: #ef4444; padding: 30px 20px; text-align: center;">
      <span style="font-size: 48px;">❌</span>
      <h1 style="color: white; margin: 10px 0 0 0; font-size: 24px;">Booking Auto-Cancelled</h1>
    </div>
    
    <div style="padding: 30px;">
      <p style="color: #1f2937; font-size: 16px; margin: 0 0 20px 0;">Hi ${firstName},</p>
      
      <p style="color: #4b5563; font-size: 15px; line-height: 1.6; margin: 0 0 20px 0;">
        The pending booking request from <strong>${details.consumerName}</strong> has been <strong>automatically cancelled</strong>.
      </p>
      
      <!-- Reason Box -->
      <div style="background-color: #fef2f2; border-left: 4px solid #ef4444; padding: 15px; margin: 20px 0; border-radius: 0 8px 8px 0;">
        <p style="color: #991b1b; margin: 0; font-size: 14px;">
          <strong>Reason:</strong> Booking was not accepted before the 2-hour deadline prior to the scheduled appointment time.
        </p>
      </div>
      
      <!-- Booking Details Card -->
      <div style="background-color: #f9fafb; border-radius: 12px; padding: 20px; margin: 20px 0; border: 2px solid #e5e7eb;">
        <h3 style="color: #1f2937; margin: 0 0 15px 0; font-size: 14px; text-transform: uppercase; letter-spacing: 0.5px;">Cancelled Booking Details</h3>
        <table style="width: 100%; border-collapse: collapse;">
          <tr>
            <td style="padding: 8px 0; color: #6b7280; font-size: 14px;">Service</td>
            <td style="padding: 8px 0; color: #1f2937; font-weight: 600; text-align: right;">${details.serviceName}</td>
          </tr>
          <tr>
            <td style="padding: 8px 0; color: #6b7280; font-size: 14px;">Customer</td>
            <td style="padding: 8px 0; color: #1f2937; font-weight: 600; text-align: right;">${details.consumerName}</td>
          </tr>
          <tr>
            <td style="padding: 8px 0; color: #6b7280; font-size: 14px;">Scheduled Date</td>
            <td style="padding: 8px 0; color: #1f2937; font-weight: 600; text-align: right;">${details.scheduledDate}</td>
          </tr>
          <tr>
            <td style="padding: 8px 0; color: #6b7280; font-size: 14px;">Scheduled Time</td>
            <td style="padding: 8px 0; color: #ef4444; font-weight: 700; text-align: right;">${details.scheduledTime}</td>
          </tr>
          <tr>
            <td style="padding: 8px 0; color: #6b7280; font-size: 14px;">Price</td>
            <td style="padding: 8px 0; color: #6b7280; font-weight: 600; text-align: right; text-decoration: line-through;">$${details.price.toFixed(2)}</td>
          </tr>
        </table>
      </div>
      
      <!-- Tip -->
      <div style="background-color: #f0fdf4; border-radius: 10px; padding: 15px; margin: 20px 0;">
        <p style="color: #166534; margin: 0; font-size: 13px;">
          💡 <strong>Tip:</strong> To avoid auto-cancellations, please respond to booking requests promptly. Customers are waiting for your confirmation!
        </p>
      </div>
      
      <!-- CTA Button -->
      <div style="text-align: center; margin: 30px 0;">
        <a href="${barberDashboardUrl}" style="display: inline-block; background-color: #5a7268; color: white; padding: 14px 40px; text-decoration: none; border-radius: 8px; font-weight: 600; font-size: 16px;">
          View Dashboard
        </a>
      </div>
      
      <!-- Booking Reference -->
      <div style="text-align: center; margin: 25px 0;">
        <p style="color: #9ca3af; margin: 0; font-size: 12px;">Booking Reference</p>
        <p style="color: #1f2937; margin: 5px 0 0 0; font-size: 16px; font-weight: 700; letter-spacing: 2px;">${details.bookingId.slice(0, 8).toUpperCase()}</p>
      </div>
    </div>
    
    <div style="background-color: #f9fafb; padding: 20px; text-align: center;">
      <p style="color: #9ca3af; font-size: 12px; margin: 0;">© ${new Date().getFullYear()} CampusCut</p>
    </div>
  </div>
</body>
</html>`.trim();

  try {
    const transporter = createTransporter();

    const mailOptions = {
      from: `CampusCut <${process.env.SMTP_USER}>`,
      to: details.barberEmail,
      subject,
      text,
      html
    };

    await transporter.sendMail(mailOptions);
    logger.info(`Barber auto-cancellation email sent to: ${details.barberEmail} for booking ${details.bookingId}`);
  } catch (error: any) {
    logger.error(`Failed to send barber auto-cancellation email to ${details.barberEmail}:`, error.message);
    throw error;
  }
}

/**
 * Send Auto-Cancellation Email to Consumer
 * 
 * Sent when a pending booking is auto-cancelled 2 hours before scheduled time
 * because the barber didn't accept it. Includes alternative barbers if available.
 */
export async function sendConsumerAutoCancellationEmail(details: AutoCancellationEmailDetails): Promise<void> {
  if (isAutoVerifyEnabled()) {
    logger.info(`[AUTO-VERIFY MODE] Skipping consumer auto-cancellation email for booking ${details.bookingId}`);
    return;
  }

  const frontendUrl = process.env.FRONTEND_URL || 'https://campuscut.com';

  const firstName = details.consumerName.split(' ')[0];
  const subject = `Booking Cancelled: ${details.serviceName} with ${details.barberName}`;

  // Build alternative barbers text
  let alternativeBarbersText = '';
  if (details.alternativeBarbers && details.alternativeBarbers.length > 0) {
    alternativeBarbersText = `
ALTERNATIVE BARBERS AVAILABLE
-----------------------------
These barbers offer ${details.serviceName} and are available at ${details.scheduledTime}:
${details.alternativeBarbers.map(b => `- ${b.name}${b.avgRating ? ` (★ ${b.avgRating.toFixed(1)})` : ''}`).join('\n')}

Book with one of these barbers: ${frontendUrl}/web/auth
`;
  }

  const text = `
Hi ${firstName},

We're sorry to inform you that your ${details.serviceName} booking has been automatically cancelled.

Unfortunately, ${details.barberName} was unable to confirm the booking before the deadline.

CANCELLED BOOKING DETAILS
-------------------------
Service: ${details.serviceName}
Barber: ${details.barberName}
Scheduled Date: ${details.scheduledDate}
Scheduled Time: ${details.scheduledTime}
${details.location ? `Location: ${details.location}` : ''}
Price: $${details.price.toFixed(2)}
${alternativeBarbersText}
We apologize for any inconvenience. You can book a new appointment with another barber anytime.

Booking Reference: ${details.bookingId.slice(0, 8).toUpperCase()}

---
CampusCut
`.trim();

  // Build alternative barbers HTML
  let alternativeBarbersHtml = '';
  if (details.alternativeBarbers && details.alternativeBarbers.length > 0) {
    alternativeBarbersHtml = `
      <div style="background-color: #f0fdf4; border: 2px solid #5a7268; border-radius: 12px; padding: 20px; margin: 25px 0;">
        <h3 style="color: #445750; margin: 0 0 15px 0; font-size: 16px; text-align: center;">
          ${details.alternativeBarbers.length} Barber${details.alternativeBarbers.length > 1 ? 's' : ''} Available at This Time
        </h3>
        <p style="color: #5a7268; font-size: 13px; text-align: center; margin: 0 0 15px 0;">
          These barbers offer ${details.serviceName} and are available at ${details.scheduledTime}:
        </p>
        <table style="width: 100%; border-collapse: separate; border-spacing: 0 8px;">
          ${details.alternativeBarbers.map(barber => `
          <tr>
            <td style="background-color: white; border-radius: 8px; padding: 12px;">
              <table style="width: 100%;">
                <tr>
                  <td style="width: 48px; vertical-align: middle;">
                    <div style="width: 40px; height: 40px; border-radius: 50%; background-color: #e5e7eb; overflow: hidden;">
                      ${barber.avatar 
                        ? `<img src="${barber.avatar}" alt="${barber.name}" style="width: 40px; height: 40px; border-radius: 50%; object-fit: cover;">`
                        : `<div style="width: 40px; height: 40px; display: flex; align-items: center; justify-content: center; font-weight: bold; color: #6b7280;">${barber.name.charAt(0)}</div>`
                      }
                    </div>
                  </td>
                  <td style="vertical-align: middle; padding-left: 12px;">
                    <p style="margin: 0; color: #1f2937; font-weight: 600; font-size: 14px;">${barber.name}</p>
                    ${barber.avgRating ? `<p style="margin: 2px 0 0 0; color: #6b7280; font-size: 12px;">⭐ ${barber.avgRating.toFixed(1)}${barber.totalReviews ? ` (${barber.totalReviews} reviews)` : ''}</p>` : ''}
                  </td>
                </tr>
              </table>
            </td>
          </tr>
          `).join('')}
        </table>
      </div>
    `;
  }

  const html = `
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
</head>
<body style="margin: 0; padding: 0; background-color: #f3f4f6; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;">
  <div style="max-width: 500px; margin: 40px auto; background-color: white; border-radius: 16px; overflow: hidden; box-shadow: 0 4px 6px rgba(0,0,0,0.1);">
    <!-- Header -->
    <div style="background-color: #ef4444; padding: 30px 20px; text-align: center;">
      <span style="font-size: 48px;">❌</span>
      <h1 style="color: white; margin: 10px 0 0 0; font-size: 24px;">Booking Cancelled</h1>
    </div>
    
    <div style="padding: 30px;">
      <p style="color: #1f2937; font-size: 16px; margin: 0 0 20px 0;">Hi ${firstName},</p>
      
      <p style="color: #4b5563; font-size: 15px; line-height: 1.6; margin: 0 0 20px 0;">
        We're sorry to inform you that your <strong>${details.serviceName}</strong> booking has been <strong>automatically cancelled</strong>.
      </p>
      
      <!-- Reason Box -->
      <div style="background-color: #fef2f2; border-left: 4px solid #ef4444; padding: 15px; margin: 20px 0; border-radius: 0 8px 8px 0;">
        <p style="color: #991b1b; margin: 0; font-size: 14px;">
          <strong>Reason:</strong> ${details.barberName} was unable to confirm the booking before the deadline.
        </p>
      </div>
      
      <!-- Booking Details Card -->
      <div style="background-color: #f9fafb; border-radius: 12px; padding: 20px; margin: 20px 0; border: 2px solid #e5e7eb;">
        <h3 style="color: #1f2937; margin: 0 0 15px 0; font-size: 14px; text-transform: uppercase; letter-spacing: 0.5px;">Cancelled Booking Details</h3>
        <table style="width: 100%; border-collapse: collapse;">
          <tr>
            <td style="padding: 8px 0; color: #6b7280; font-size: 14px;">Service</td>
            <td style="padding: 8px 0; color: #1f2937; font-weight: 600; text-align: right;">${details.serviceName}</td>
          </tr>
          <tr>
            <td style="padding: 8px 0; color: #6b7280; font-size: 14px;">Barber</td>
            <td style="padding: 8px 0; color: #1f2937; font-weight: 600; text-align: right;">${details.barberName}</td>
          </tr>
          <tr>
            <td style="padding: 8px 0; color: #6b7280; font-size: 14px;">Scheduled Date</td>
            <td style="padding: 8px 0; color: #1f2937; font-weight: 600; text-align: right;">${details.scheduledDate}</td>
          </tr>
          <tr>
            <td style="padding: 8px 0; color: #6b7280; font-size: 14px;">Scheduled Time</td>
            <td style="padding: 8px 0; color: #ef4444; font-weight: 700; text-align: right;">${details.scheduledTime}</td>
          </tr>
          <tr>
            <td style="padding: 8px 0; color: #6b7280; font-size: 14px;">Price</td>
            <td style="padding: 8px 0; color: #6b7280; font-weight: 600; text-align: right; text-decoration: line-through;">$${details.price.toFixed(2)}</td>
          </tr>
        </table>
      </div>
      
      ${alternativeBarbersHtml}
      
      <!-- CTA Button -->
      <div style="text-align: center; margin: 30px 0;">
        <a href="${frontendUrl}/web/auth" style="display: inline-block; background-color: #5a7268; color: white; padding: 14px 40px; text-decoration: none; border-radius: 8px; font-weight: 600; font-size: 16px;">
          Book New Appointment
        </a>
      </div>
      
      <p style="color: #6b7280; font-size: 13px; text-align: center; margin: 20px 0 0 0;">
        We apologize for any inconvenience. You can book a new appointment anytime.
      </p>
      
      <!-- Booking Reference -->
      <div style="text-align: center; margin: 25px 0;">
        <p style="color: #9ca3af; margin: 0; font-size: 12px;">Booking Reference</p>
        <p style="color: #1f2937; margin: 5px 0 0 0; font-size: 16px; font-weight: 700; letter-spacing: 2px;">${details.bookingId.slice(0, 8).toUpperCase()}</p>
      </div>
    </div>
    
    <div style="background-color: #f9fafb; padding: 20px; text-align: center;">
      <p style="color: #9ca3af; font-size: 12px; margin: 0;">© ${new Date().getFullYear()} CampusCut</p>
    </div>
  </div>
</body>
</html>`.trim();

  try {
    const transporter = createTransporter();

    const mailOptions = {
      from: `CampusCut <${process.env.SMTP_USER}>`,
      to: details.consumerEmail,
      subject,
      text,
      html
    };

    await transporter.sendMail(mailOptions);
    logger.info(`Consumer auto-cancellation email sent to: ${details.consumerEmail} for booking ${details.bookingId}`);
  } catch (error: any) {
    logger.error(`Failed to send consumer auto-cancellation email to ${details.consumerEmail}:`, error.message);
    throw error;
  }
}
