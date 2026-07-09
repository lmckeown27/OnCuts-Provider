/**
 * AWS S3 Upload Service for CampusCuts
 * 
 * Uploads images to S3 for CDN delivery.
 * Uses IAM Role attached to EC2 instance (no credentials needed in code).
 * 
 * Images are served from:
 * https://campuscut-images.s3.us-west-1.amazonaws.com/
 */

import { S3Client, PutObjectCommand, DeleteObjectCommand } from '@aws-sdk/client-s3';
import { logger } from '../utils/logger';

// S3 Configuration
const S3_BUCKET = process.env.S3_BUCKET || 'campuscut-images';
const S3_REGION = process.env.S3_REGION || 'us-west-1';

// Initialize S3 client
// When running on EC2 with an IAM role, credentials are automatically detected
const s3Client = new S3Client({
  region: S3_REGION,
  // No credentials needed - uses EC2 instance role automatically
});

// Public URL for serving images
export const getS3PublicUrl = (key: string): string => {
  return `https://${S3_BUCKET}.s3.${S3_REGION}.amazonaws.com/${key}`;
};

/**
 * Upload a file to S3
 */
export const uploadToS3 = async (
  buffer: Buffer,
  key: string,
  contentType: string = 'image/webp'
): Promise<{ success: boolean; url?: string; error?: string }> => {
  try {
    const command = new PutObjectCommand({
      Bucket: S3_BUCKET,
      Key: key,
      Body: buffer,
      ContentType: contentType,
      CacheControl: 'public, max-age=31536000', // Cache for 1 year
    });

    await s3Client.send(command);
    
    const url = getS3PublicUrl(key);
    logger.info(`Uploaded to S3: ${key}`);
    
    return { success: true, url };
  } catch (error: any) {
    logger.error(`S3 upload failed: ${error.message}`);
    return { success: false, error: error.message };
  }
};

/**
 * Delete a file from S3
 */
export const deleteFromS3 = async (key: string): Promise<boolean> => {
  try {
    const command = new DeleteObjectCommand({
      Bucket: S3_BUCKET,
      Key: key,
    });

    await s3Client.send(command);
    logger.info(`Deleted from S3: ${key}`);
    return true;
  } catch (error: any) {
    logger.error(`S3 delete failed: ${error.message}`);
    return false;
  }
};

/**
 * Upload multiple sizes of an image to S3
 */
export const uploadImageWithSizes = async (
  originalBuffer: Buffer,
  mediumBuffer: Buffer,
  thumbnailBuffer: Buffer,
  baseKey: string
): Promise<{
  success: boolean;
  urls?: { original: string; medium: string; thumbnail: string };
  error?: string;
}> => {
  try {
    const ext = 'webp';
    
    // Upload all sizes in parallel
    const [originalResult, mediumResult, thumbnailResult] = await Promise.all([
      uploadToS3(originalBuffer, `${baseKey}.${ext}`, 'image/webp'),
      uploadToS3(mediumBuffer, `med-${baseKey}.${ext}`, 'image/webp'),
      uploadToS3(thumbnailBuffer, `thumb-${baseKey}.${ext}`, 'image/webp'),
    ]);

    if (!originalResult.success || !mediumResult.success || !thumbnailResult.success) {
      throw new Error('One or more uploads failed');
    }

    return {
      success: true,
      urls: {
        original: originalResult.url!,
        medium: mediumResult.url!,
        thumbnail: thumbnailResult.url!,
      },
    };
  } catch (error: any) {
    logger.error(`S3 multi-upload failed: ${error.message}`);
    return { success: false, error: error.message };
  }
};

/**
 * Check if S3 is enabled and configured
 */
export const isS3Enabled = (): boolean => {
  return process.env.USE_S3 === 'true';
};

export default {
  uploadToS3,
  deleteFromS3,
  uploadImageWithSizes,
  getS3PublicUrl,
  isS3Enabled,
  S3_BUCKET,
  S3_REGION,
};
