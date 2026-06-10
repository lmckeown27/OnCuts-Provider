/**
 * Image Processing Service for CampusCuts
 * Transferred from CampusKinect with CampusCuts adaptations
 * 
 * Handles:
 * - Barber portfolio image processing
 * - Profile picture processing
 * - Image optimization and compression
 * - Thumbnail generation
 * - Image validation
 */

import multer from 'multer';
import sharp from 'sharp';
import path from 'path';
import fs from 'fs/promises';
import { v4 as uuidv4 } from 'uuid';
import s3Service from './s3.service';

// Get uploads directory - use absolute path for production
const getUploadsDir = (): string => {
  if (process.env.UPLOAD_PATH) {
    return process.env.UPLOAD_PATH;
  }
  // Default to uploads folder in backend root (one level up from dist/src)
  return path.join(__dirname, '..', '..', 'uploads');
};

// Configure multer for file uploads
const storage = multer.memoryStorage();

const fileFilter = (
  req: any,
  file: Express.Multer.File,
  cb: multer.FileFilterCallback
) => {
  console.log('[Image Service] fileFilter called:', {
    originalname: file.originalname,
    mimetype: file.mimetype,
    encoding: file.encoding,
    size: file.size,
  });
  
  // Check file type - be lenient for mobile uploads
  // iOS Photo Library may send empty mimetype or application/octet-stream
  const isImage = file.mimetype.startsWith('image/');
  const isEmptyMime = file.mimetype === '' || file.mimetype === 'application/octet-stream';
  
  // Also check file extension as fallback
  const ext = file.originalname.toLowerCase().split('.').pop() || '';
  const imageExtensions = ['jpg', 'jpeg', 'png', 'gif', 'webp', 'heic', 'heif', 'bmp'];
  const hasImageExtension = imageExtensions.includes(ext);
  
  console.log('[Image Service] File validation:', { isImage, isEmptyMime, ext, hasImageExtension });
  
  if (isImage || isEmptyMime || hasImageExtension) {
    console.log('[Image Service] File accepted');
    cb(null, true);
  } else {
    console.error('[Image Service] File rejected - invalid type');
    cb(new Error('Only image files are allowed'));
  }
};

export const upload = multer({
  storage: storage,
  fileFilter: fileFilter,
  limits: {
    fileSize: parseInt(process.env.MAX_FILE_SIZE || '10485760'), // 10MB default
    files: 8, // Maximum 8 files for barber portfolio
  },
});

// Process and save image options
interface ProcessImageOptions {
  width?: number;
  height?: number;
  quality?: number;
  format?: 'jpeg' | 'png' | 'webp';
}

interface ProcessedImageResult {
  original: string;
  thumbnail: string;
  medium?: string;
  path: string;
  thumbnailPath: string;
  mediumPath?: string;
}

// Image size presets
const IMAGE_SIZES = {
  thumbnail: { width: 150, height: 150, quality: 70 },
  small: { width: 300, height: 300, quality: 75 },
  medium: { width: 600, height: 600, quality: 80 },
  large: { width: 1200, height: 1200, quality: 85 },
};

/**
 * Process and save image with optimization
 * Now defaults to WebP format for 70-80% smaller files
 */
export const processAndSaveImage = async (
  buffer: Buffer,
  filename: string,
  options: ProcessImageOptions = {}
): Promise<ProcessedImageResult> => {
  try {
    // Default to WebP for best compression
    const { width = 1200, height = 1200, quality = 85, format = 'webp' } = options;

    const uploadPath = getUploadsDir();
    await fs.mkdir(uploadPath, { recursive: true });

    // Generate unique base filename
    const baseId = `${uuidv4()}-${Date.now()}`;
    const ext = format === 'webp' ? 'webp' : format;

    // Process and save the main image (large size)
    const uniqueFilename = `${baseId}.${ext}`;
    const fullPath = path.join(uploadPath, uniqueFilename);

    await sharp(buffer)
      .resize(width, height, {
        fit: 'inside',
        withoutEnlargement: true,
      })
      .webp({ quality, effort: 4 }) // effort 4 = good balance of speed/compression
      .toFile(fullPath);

    console.log(`[Image Service] Saved original: ${uniqueFilename}`);

    // Generate medium size (for cards/lists)
    const mediumFilename = `med-${baseId}.${ext}`;
    const mediumPath = path.join(uploadPath, mediumFilename);

    await sharp(buffer)
      .resize(IMAGE_SIZES.medium.width, IMAGE_SIZES.medium.height, {
        fit: 'inside',
        withoutEnlargement: true,
      })
      .webp({ quality: IMAGE_SIZES.medium.quality, effort: 4 })
      .toFile(mediumPath);

    console.log(`[Image Service] Saved medium: ${mediumFilename}`);

    // Generate thumbnail (for avatars/small displays)
    const thumbnailFilename = `thumb-${baseId}.${ext}`;
    const thumbnailPath = path.join(uploadPath, thumbnailFilename);

    await sharp(buffer)
      .resize(IMAGE_SIZES.thumbnail.width, IMAGE_SIZES.thumbnail.height, {
        fit: 'cover', // Cover for thumbnails to ensure square
        withoutEnlargement: true,
      })
      .webp({ quality: IMAGE_SIZES.thumbnail.quality, effort: 4 })
      .toFile(thumbnailPath);

    console.log(`[Image Service] Saved thumbnail: ${thumbnailFilename}`);

    // Log file sizes for monitoring
    const [origStats, medStats, thumbStats] = await Promise.all([
      fs.stat(fullPath),
      fs.stat(mediumPath),
      fs.stat(thumbnailPath),
    ]);
    console.log(`[Image Service] Sizes - Original: ${(origStats.size / 1024).toFixed(1)}KB, Medium: ${(medStats.size / 1024).toFixed(1)}KB, Thumb: ${(thumbStats.size / 1024).toFixed(1)}KB`);

    // Upload to S3 if enabled
    if (s3Service.isS3Enabled()) {
      try {
        // Read the processed files
        const [origBuffer, medBuffer, thumbBuffer] = await Promise.all([
          fs.readFile(fullPath),
          fs.readFile(mediumPath),
          fs.readFile(thumbnailPath),
        ]);

        const s3Result = await s3Service.uploadImageWithSizes(
          origBuffer,
          medBuffer,
          thumbBuffer,
          baseId
        );

        if (s3Result.success && s3Result.urls) {
          console.log(`[Image Service] Uploaded to S3: ${baseId}`);
          
          // Optionally delete local files after S3 upload
          if (process.env.S3_DELETE_LOCAL === 'true') {
            await Promise.all([
              fs.unlink(fullPath).catch(() => {}),
              fs.unlink(mediumPath).catch(() => {}),
              fs.unlink(thumbnailPath).catch(() => {}),
            ]);
            console.log(`[Image Service] Deleted local files after S3 upload`);
          }

          // Return S3 URLs instead of local paths
          return {
            original: uniqueFilename,
            medium: mediumFilename,
            thumbnail: thumbnailFilename,
            path: s3Result.urls.original,
            mediumPath: s3Result.urls.medium,
            thumbnailPath: s3Result.urls.thumbnail,
            // Store S3 URLs for generateImageUrl to use
            s3Urls: s3Result.urls,
          } as ProcessedImageResult & { s3Urls?: { original: string; medium: string; thumbnail: string } };
        }
      } catch (s3Error) {
        console.error('[Image Service] S3 upload failed, using local storage:', s3Error);
        // Continue with local storage as fallback
      }
    }

    return {
      original: uniqueFilename,
      medium: mediumFilename,
      thumbnail: thumbnailFilename,
      path: fullPath,
      mediumPath: mediumPath,
      thumbnailPath: thumbnailPath,
    };
  } catch (error) {
    console.error('Image processing error:', error);
    throw new Error('Failed to process image');
  }
};

/**
 * Process barber portfolio image (larger dimensions)
 * Uses WebP for ~70% smaller files than JPEG
 */
export const processPortfolioImage = async (
  buffer: Buffer
): Promise<ProcessedImageResult> => {
  return processAndSaveImage(buffer, 'portfolio', {
    width: 1200,
    height: 1200,
    quality: 85,
    format: 'webp',
  });
};

/**
 * Process profile picture
 * Generates multiple sizes for different UI contexts:
 * - Original (up to 800px) for full profile view
 * - Medium (400px) for barber cards
 * - Thumbnail (150px) for avatars in dropdowns/lists
 */
export const processProfilePicture = async (
  buffer: Buffer
): Promise<ProcessedImageResult> => {
  return processAndSaveImage(buffer, 'profile', {
    width: 800,
    height: 800,
    quality: 85,
    format: 'webp',
  });
};

/**
 * Upload single image middleware
 */
export const uploadSingleImage = upload.single('image');

/**
 * Upload multiple images middleware (for portfolio)
 */
export const uploadMultipleImages = upload.array('images', 8);

/**
 * Delete image file
 */
export const deleteImageFile = async (filename: string): Promise<boolean> => {
  try {
    const uploadPath = getUploadsDir();
    const imagePath = path.join(uploadPath, filename);
    const thumbnailPath = path.join(uploadPath, `thumb-${filename}`);

    // Delete original image
    try {
      await fs.unlink(imagePath);
    } catch (error: any) {
      if (error.code !== 'ENOENT') {
        console.error('Error deleting original image:', error);
      }
    }

    // Delete thumbnail
    try {
      await fs.unlink(thumbnailPath);
    } catch (error: any) {
      if (error.code !== 'ENOENT') {
        console.error('Error deleting thumbnail:', error);
      }
    }

    return true;
  } catch (error) {
    console.error('Error deleting image files:', error);
    return false;
  }
};

/**
 * Get image metadata
 */
export const getImageInfo = async (
  buffer: Buffer
): Promise<{
  width: number;
  height: number;
  format: string;
  size: number;
  hasAlpha: boolean;
} | null> => {
  try {
    const metadata = await sharp(buffer).metadata();
    return {
      width: metadata.width || 0,
      height: metadata.height || 0,
      format: metadata.format || 'unknown',
      size: buffer.length,
      hasAlpha: metadata.hasAlpha || false,
    };
  } catch (error) {
    console.error('Error getting image info:', error);
    return null;
  }
};

/**
 * Validate image dimensions
 */
export const validateImageDimensions = (
  width: number,
  height: number,
  minWidth: number = 200,
  minHeight: number = 200,
  maxWidth: number = 4000,
  maxHeight: number = 4000
): boolean => {
  if (width < minWidth || height < minHeight) {
    throw new Error(`Image too small. Minimum: ${minWidth}x${minHeight}px`);
  }

  if (width > maxWidth || height > maxHeight) {
    throw new Error(`Image too large. Maximum: ${maxWidth}x${maxHeight}px`);
  }

  return true;
};

/**
 * Generate image URL for a specific size
 * Uses /api/uploads/ path so it goes through Nginx API proxy
 */
export const generateImageUrl = (filename: string, type: 'original' | 'medium' | 'thumbnail' = 'original'): string => {
  if (!filename) return '';
  
  // Determine prefix based on type
  let prefix = '';
  if (type === 'thumbnail') prefix = 'thumb-';
  else if (type === 'medium') prefix = 'med-';
  
  // If S3 is enabled, generate S3 URL
  if (s3Service.isS3Enabled()) {
    return s3Service.getS3PublicUrl(`${prefix}${filename}`);
  }
  
  // If BASE_URL is explicitly set (for CDN), use it
  if (process.env.BASE_URL) {
    return `${process.env.BASE_URL}/uploads/${prefix}${filename}`;
  }
  
  // Use /api/uploads/ path - this goes through Nginx's /api/ proxy
  return `/api/uploads/${prefix}${filename}`;
};

/**
 * Generate all image URLs from a base filename
 * Useful for returning complete image data to frontend
 */
export const generateAllImageUrls = (filename: string): { original: string; medium: string; thumbnail: string } => {
  return {
    original: generateImageUrl(filename, 'original'),
    medium: generateImageUrl(filename, 'medium'),
    thumbnail: generateImageUrl(filename, 'thumbnail'),
  };
};

/**
 * Clean up orphaned images (older than 24 hours)
 */
export const cleanupOrphanedImages = async (): Promise<void> => {
  try {
    const uploadPath = getUploadsDir();
    const files = await fs.readdir(uploadPath);

    for (const file of files) {
      if (file.startsWith('thumb-')) continue; // Skip thumbnails

      const filePath = path.join(uploadPath, file);
      const stats = await fs.stat(filePath);

      // Delete files older than 24 hours
      const hoursSinceModified = (Date.now() - stats.mtime.getTime()) / (1000 * 60 * 60);
      if (hoursSinceModified > 24) {
        await deleteImageFile(file);
        console.log(`Deleted orphaned image: ${file}`);
      }
    }

    console.log('Image cleanup completed');
  } catch (error) {
    console.error('Image cleanup error:', error);
  }
};

export default {
  upload,
  uploadSingleImage,
  uploadMultipleImages,
  processAndSaveImage,
  processPortfolioImage,
  processProfilePicture,
  deleteImageFile,
  getImageInfo,
  validateImageDimensions,
  generateImageUrl,
  generateAllImageUrls,
  cleanupOrphanedImages,
  IMAGE_SIZES,
};

