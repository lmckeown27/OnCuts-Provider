/**
 * Upload Routes for CampusCuts
 * Handles image uploads for barber portfolios and profile pictures
 * 
 * ## IPFS Integration:
 * - Files are uploaded to local IPFS node first (fast)
 * - Then pinned to Pinata for permanent storage (reliable)
 * - Falls back to local storage if IPFS is disabled
 * 
 * Set USE_IPFS=true in .env to enable IPFS uploads
 */

import express from 'express';
import imageService from '../services/image.service';
import { authenticate } from '../middleware/auth';
import { uploadToIPFS, IPFSUploadResult } from '../services/ipfs.service';
import { logger } from '../utils/logger';
import { pool } from '../database/connection';

const router = express.Router();

/**
 * POST /api/upload/portfolio
 * Upload barber portfolio images (multiple)
 * 
 * ## IPFS Integration:
 * If USE_IPFS=true, each image is:
 * 1. Processed and saved locally
 * 2. Uploaded to local IPFS node
 * 3. Pinned to Pinata for permanent storage
 * 
 * Response includes both local URLs and IPFS CIDs
 */
router.post(
  '/portfolio',
  authenticate,
  imageService.uploadMultipleImages,
  async (req, res, next) => {
    try {
      const userId = (req as any).user.id;
      const files = (req as any).files;

      if (!files || files.length === 0) {
        return res.status(400).json({
          success: false,
          error: { message: 'No images provided' },
        });
      }

      const processedImages = [];

      for (const file of files) {
        // Process image locally
        const result = await imageService.processPortfolioImage(file.buffer);
        
        const imageData: any = {
          url: imageService.generateImageUrl(result.original),
          thumbnailUrl: imageService.generateImageUrl(result.thumbnail),  // thumbnail filename already has thumb- prefix
          filename: result.original,
        };

        // Upload to IPFS (if enabled)
        if (process.env.USE_IPFS === 'true') {
          try {
            const ipfsResult = await uploadToIPFS(
              file.buffer,
              file.originalname,
              {
                name: `Portfolio Image - ${userId}`,
                keyvalues: {
                  userId,
                  type: 'portfolio',
                  timestamp: Date.now()
                }
              }
            );

            if (ipfsResult.success) {
              imageData.ipfs = {
                localCID: ipfsResult.localCID,
                pinataCID: ipfsResult.pinataCID,
                gatewayUrl: ipfsResult.gatewayUrl,
                ipfsUrl: ipfsResult.ipfsUrl
              };
              
              logger.info(`Portfolio image uploaded to IPFS: ${ipfsResult.pinataCID}`);
            } else {
              logger.warn(`IPFS upload failed for portfolio image: ${ipfsResult.error}`);
            }
          } catch (ipfsError: any) {
            logger.error(`IPFS upload error:`, ipfsError.message);
            // Continue without IPFS - local storage is fallback
          }
        }

        processedImages.push(imageData);
      }

      res.json({
        success: true,
        message: 'Portfolio images uploaded successfully',
        data: { 
          images: processedImages,
          ipfsEnabled: process.env.USE_IPFS === 'true'
        },
      });
    } catch (error) {
      next(error);
    }
  }
);

/**
 * POST /api/upload/profile-picture
 * Upload profile picture (single)
 * 
 * ## IPFS Integration:
 * Profile pictures are uploaded to both local storage and IPFS (if enabled).
 * IPFS ensures the profile picture is permanently available.
 */
router.post(
  '/profile-picture',
  authenticate,
  imageService.uploadSingleImage,
  async (req, res, next) => {
    try {
      const userId = (req as any).user.id;
      const file = (req as any).file;

      if (!file) {
        return res.status(400).json({
          success: false,
          error: { message: 'No image provided' },
        });
      }

      // Process image locally
      const result = await imageService.processProfilePicture(file.buffer);

      const responseData: any = {
        url: imageService.generateImageUrl(result.original),
        thumbnailUrl: imageService.generateImageUrl(result.thumbnail),  // thumbnail filename already has thumb- prefix
        filename: result.original,
      };

      // Upload to IPFS (if enabled)
      if (process.env.USE_IPFS === 'true') {
        try {
          const ipfsResult = await uploadToIPFS(
            file.buffer,
            file.originalname,
            {
              name: `Profile Picture - ${userId}`,
              keyvalues: {
                userId,
                type: 'profile',
                timestamp: Date.now()
              }
            }
          );

          if (ipfsResult.success) {
            responseData.ipfs = {
              localCID: ipfsResult.localCID,
              pinataCID: ipfsResult.pinataCID,
              gatewayUrl: ipfsResult.gatewayUrl,
              ipfsUrl: ipfsResult.ipfsUrl
            };
            
            logger.info(`Profile picture uploaded to IPFS: ${ipfsResult.pinataCID}`);
          } else {
            logger.warn(`IPFS upload failed for profile picture: ${ipfsResult.error}`);
          }
        } catch (ipfsError: any) {
          logger.error(`IPFS upload error:`, ipfsError.message);
          // Continue without IPFS - local storage is fallback
        }
      }

      res.json({
        success: true,
        message: 'Profile picture uploaded successfully',
        data: responseData,
      });
    } catch (error) {
      next(error);
    }
  }
);

// Alias route for profile-photo (frontend compatibility)
router.post(
  '/profile-photo',
  authenticate,
  imageService.uploadSingleImage,
  async (req, res, next) => {
    try {
      const userId = (req as any).user.userId;
      const file = (req as any).file;

      logger.info(`[Upload] Profile photo upload started for user: ${userId}`);
      logger.info(`[Upload] File received: ${file ? `${file.originalname} (${file.size} bytes, ${file.mimetype})` : 'No file'}`);

      if (!userId) {
        logger.error('[Upload] No userId found in JWT token');
        return res.status(401).json({
          success: false,
          error: { message: 'User ID not found in token' },
        });
      }

      if (!file) {
        return res.status(400).json({
          success: false,
          error: { message: 'No image provided' },
        });
      }

      // Validate file type on server side as well
      // Note: HEIC/HEIF are iOS native formats - sharp can convert them if libheif is installed
      // Also accept empty mimetype as iOS Photo Library sometimes doesn't set it
      const allowedMimeTypes = ['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif'];
      const isValidMime = allowedMimeTypes.includes(file.mimetype) || 
                          file.mimetype === '' || 
                          file.mimetype === 'application/octet-stream';
      
      if (!isValidMime) {
        logger.warn(`[Upload] Rejected file with unsupported type: ${file.mimetype}`);
        return res.status(400).json({
          success: false,
          error: { message: `Unsupported image format: ${file.mimetype}. Only JPG, PNG, WebP, and HEIC are allowed.` },
        });
      }
      
      logger.info(`[Upload] File type validated: ${file.mimetype || 'empty (likely iOS Photo Library)'}`)

      // Process image locally - now generates original, medium, and thumbnail
      logger.info(`[Upload] Processing image...`);
      const result = await imageService.processProfilePicture(file.buffer);
      const imageUrl = imageService.generateImageUrl(result.original);
      logger.info(`[Upload] Image processed successfully: ${result.original}`);
      logger.info(`[Upload] Generated URL: ${imageUrl}`);

      // Update user's avatarUrl in database
      const updateResult = await pool.query(
        'UPDATE users SET "avatarUrl" = $1, "updatedAt" = NOW() WHERE id = $2 RETURNING id',
        [imageUrl, userId]
      );

      if (updateResult.rowCount === 0) {
        logger.error(`[Upload] Database update failed - no user found with id: ${userId}`);
        return res.status(404).json({
          success: false,
          error: { message: 'User not found' },
        });
      }

      logger.info(`[Upload] Database updated successfully for user: ${userId}`);

      // Return all sizes for frontend flexibility
      const responseData: any = {
        url: imageUrl,
        mediumUrl: result.medium ? imageService.generateImageUrl(result.medium, 'original') : imageUrl,
        thumbnailUrl: imageService.generateImageUrl(result.thumbnail, 'original'),
        filename: result.original,
      };

      res.json({
        success: true,
        message: 'Profile photo uploaded successfully',
        data: responseData,
      });
    } catch (error: any) {
      logger.error(`[Upload] Profile photo upload failed:`, error.message);
      next(error);
    }
  }
);

/**
 * POST /api/upload/chat-image
 * Upload image in chat conversation
 * 
 * ## IPFS Integration:
 * Chat images can be uploaded to IPFS for permanent, decentralized storage.
 */
router.post(
  '/chat-image',
  authenticate,
  imageService.uploadSingleImage,
  async (req, res, next) => {
    try {
      const userId = (req as any).user.id;
      const file = (req as any).file;

      if (!file) {
        return res.status(400).json({
          success: false,
          error: { message: 'No image provided' },
        });
      }

      // Process image locally
      const result = await imageService.processAndSaveImage(file.buffer, 'chat', {
        width: 800,
        height: 800,
        quality: 80,
      });

      const responseData: any = {
        url: imageService.generateImageUrl(result.original),
        filename: result.original,
      };

      // Upload to IPFS (if enabled)
      if (process.env.USE_IPFS === 'true') {
        try {
          const ipfsResult = await uploadToIPFS(
            file.buffer,
            file.originalname,
            {
              name: `Chat Image - ${userId}`,
              keyvalues: {
                userId,
                type: 'chat',
                timestamp: Date.now()
              }
            }
          );

          if (ipfsResult.success) {
            responseData.ipfs = {
              localCID: ipfsResult.localCID,
              pinataCID: ipfsResult.pinataCID,
              gatewayUrl: ipfsResult.gatewayUrl,
              ipfsUrl: ipfsResult.ipfsUrl
            };
            
            logger.info(`Chat image uploaded to IPFS: ${ipfsResult.pinataCID}`);
          }
        } catch (ipfsError: any) {
          logger.error(`IPFS upload error:`, ipfsError.message);
          // Continue without IPFS
        }
      }

      res.json({
        success: true,
        message: 'Chat image uploaded successfully',
        data: responseData,
      });
    } catch (error) {
      next(error);
    }
  }
);

export default router;

