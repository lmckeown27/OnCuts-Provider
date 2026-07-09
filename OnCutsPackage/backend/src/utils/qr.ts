// @ts-nocheck — optional native `canvas` dependency for branded QR assets
/**
 * QR Code Generator with Centered Logo
 * 
 * Generates QR codes with the CampusCut logo centered in the middle.
 * Uses high error correction (H) to ensure QR remains scannable with logo overlay.
 */

import QRCode from 'qrcode';
import { createCanvas, loadImage } from 'canvas';
import * as fs from 'fs';
import * as path from 'path';

interface QrOptions {
  /** The URL or data to encode in the QR code */
  url: string;
  /** Path to the logo image file */
  logoPath: string;
  /** Path where the final QR code image will be saved */
  outputPath: string;
  /** QR code size in pixels (default: 500) */
  size?: number;
  /** Logo size as percentage of QR width (default: 0.22 = 22%) */
  logoSizePercent?: number;
  /** White padding around logo in pixels (default: 8) */
  logoPadding?: number;
}

/**
 * Generates a QR code with a centered logo
 * @param options - Configuration options for QR generation
 * @returns Promise that resolves when the QR code is saved
 */
export async function generateQrWithLogo({
  url,
  logoPath,
  outputPath,
  size = 500,
  logoSizePercent = 0.22,
  logoPadding = 8,
}: QrOptions): Promise<string> {
  // Generate QR code as data URL with high error correction
  const qrDataUrl = await QRCode.toDataURL(url, {
    errorCorrectionLevel: 'H',
    width: size,
    margin: 2, // Preserve quiet zone
    color: {
      dark: '#000000',
      light: '#FFFFFF',
    },
  });

  // Create canvas and draw QR code
  const canvas = createCanvas(size, size);
  const ctx = canvas.getContext('2d');

  // Load and draw QR code
  const qrImage = await loadImage(qrDataUrl);
  ctx.drawImage(qrImage, 0, 0, size, size);

  // Load logo
  const logo = await loadImage(logoPath);

  // Calculate logo dimensions
  const logoSize = Math.floor(size * logoSizePercent);
  const logoX = Math.floor((size - logoSize) / 2);
  const logoY = Math.floor((size - logoSize) / 2);

  // Draw white padding background behind logo
  const paddingX = logoX - logoPadding;
  const paddingY = logoY - logoPadding;
  const paddingSize = logoSize + logoPadding * 2;

  ctx.fillStyle = '#FFFFFF';
  ctx.fillRect(paddingX, paddingY, paddingSize, paddingSize);

  // Draw centered logo
  ctx.drawImage(logo, logoX, logoY, logoSize, logoSize);

  // Ensure output directory exists
  const outputDir = path.dirname(outputPath);
  if (!fs.existsSync(outputDir)) {
    fs.mkdirSync(outputDir, { recursive: true });
  }

  // Save to file
  const buffer = canvas.toBuffer('image/png');
  fs.writeFileSync(outputPath, buffer);

  return outputPath;
}

/**
 * Generates a QR code as a base64 data URL (for API responses)
 * @param options - Configuration options for QR generation
 * @returns Promise that resolves to base64 data URL
 */
export async function generateQrWithLogoBase64({
  url,
  logoPath,
  size = 500,
  logoSizePercent = 0.22,
  logoPadding = 8,
}: Omit<QrOptions, 'outputPath'>): Promise<string> {
  // Generate QR code as data URL with high error correction
  const qrDataUrl = await QRCode.toDataURL(url, {
    errorCorrectionLevel: 'H',
    width: size,
    margin: 2,
    color: {
      dark: '#000000',
      light: '#FFFFFF',
    },
  });

  // Create canvas and draw QR code
  const canvas = createCanvas(size, size);
  const ctx = canvas.getContext('2d');

  // Load and draw QR code
  const qrImage = await loadImage(qrDataUrl);
  ctx.drawImage(qrImage, 0, 0, size, size);

  // Load logo
  const logo = await loadImage(logoPath);

  // Calculate logo dimensions
  const logoSize = Math.floor(size * logoSizePercent);
  const logoX = Math.floor((size - logoSize) / 2);
  const logoY = Math.floor((size - logoSize) / 2);

  // Draw white padding background behind logo
  const paddingX = logoX - logoPadding;
  const paddingY = logoY - logoPadding;
  const paddingSize = logoSize + logoPadding * 2;

  ctx.fillStyle = '#FFFFFF';
  ctx.fillRect(paddingX, paddingY, paddingSize, paddingSize);

  // Draw centered logo
  ctx.drawImage(logo, logoX, logoY, logoSize, logoSize);

  // Return as base64 data URL
  return canvas.toDataURL('image/png');
}

// Default logo path for CampusCut
export const CAMPUSCUT_LOGO_PATH = path.resolve(
  __dirname,
  '../../../web-app/src/assets/logos/Mobile_Header_Chair.png'
);

