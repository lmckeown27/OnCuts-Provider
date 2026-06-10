/**
 * IPFS Service - Decentralized File Storage
 * 
 * Integrates both local IPFS node and Pinata pinning service.
 * 
 * ## Workflow:
 * 1. Upload to local IPFS node (fast, local)
 * 2. Pin to Pinata (permanent, distributed)
 * 3. Return both CIDs for verification
 * 
 * ## Environment Variables Required:
 * - PINATA_API_KEY: Pinata API key
 * - PINATA_API_SECRET: Pinata secret key
 * - IPFS_NODE_URL: Local IPFS node URL (default: http://localhost:5001)
 * - USE_IPFS: Enable/disable IPFS (true/false)
 * 
 * @module ipfs.service
 */

import axios from 'axios';
import FormData from 'form-data';
// import { create as createIPFSClient } from 'ipfs-http-client'; // Optional - install if using IPFS
import { logger } from '../utils/logger';
import fs from 'fs';
import path from 'path';

// Placeholder for IPFS client type
type IPFSHTTPClient = any;

/**
 * IPFS Upload Result
 */
export interface IPFSUploadResult {
  success: boolean;
  localCID?: string;
  pinataCID?: string;
  ipfsUrl?: string;
  pinataUrl?: string;
  gatewayUrl?: string;
  error?: string;
  // Backward compatibility properties
  cid?: string;  // Alias for pinataCID (primary CID)
  url?: string;  // Alias for gatewayUrl
}

/**
 * Check if IPFS is enabled
 */
function isIPFSEnabled(): boolean {
  return process.env.USE_IPFS === 'true';
}

/**
 * Get IPFS HTTP Client
 * 
 * Connects to local IPFS node or Pinata IPFS gateway.
 * Uses ipfs-http-client v56 (CommonJS compatible).
 * 
 * @returns IPFS HTTP client instance
 */
function getIPFSClient(): IPFSHTTPClient {
  const ipfsNodeUrl = process.env.IPFS_NODE_URL || 'http://localhost:5001';
  
  try {
    // Check if IPFS client is available
    // If ipfs-http-client is not installed, this will fail
    // Install it with: npm install ipfs-http-client@56.0.3
    throw new Error('IPFS client not available. Please install ipfs-http-client@56.0.3');
    
    // Uncomment when ipfs-http-client is installed:
    // const { create } = require('ipfs-http-client');
    // const url = new URL(ipfsNodeUrl);
    // const client = create({
    //   host: url.hostname,
    //   port: url.port ? parseInt(url.port) : (url.protocol === 'https:' ? 443 : 5001),
    //   protocol: url.protocol.replace(':', ''),
    //   timeout: 60000
    // });
    // return client;
  } catch (error: any) {
    logger.error('Failed to create IPFS client:', error.message);
    throw new Error(`IPFS client connection failed: ${error.message}`);
  }
}

/**
 * Upload to Local IPFS Node
 * 
 * Adds file to local IPFS node and returns CID.
 * This is fast but not guaranteed to be permanently available.
 * 
 * @param buffer - File buffer to upload
 * @param filename - Original filename
 * @returns Local IPFS CID
 * 
 * @example
 * const cid = await uploadToLocalIPFS(fileBuffer, 'profile.jpg');
 * console.log('IPFS CID:', cid); // QmX123...
 */
export async function uploadToLocalIPFS(
  buffer: Buffer,
  filename: string
): Promise<string> {
  if (!isIPFSEnabled()) {
    throw new Error('IPFS is disabled. Set USE_IPFS=true in .env');
  }

  try {
    const client = getIPFSClient();
    
    logger.info(`Uploading ${filename} to local IPFS node...`);
    
    // Add file to IPFS
    const result = await client.add({
      path: filename,
      content: buffer
    }, {
      pin: true, // Pin locally
      wrapWithDirectory: false,
      cidVersion: 1 // Use CIDv1 for better compatibility
    });
    
    const cid = result.cid.toString();
    
    logger.info(`✅ Uploaded to local IPFS: ${cid}`);
    
    return cid;
  } catch (error: any) {
    logger.error(`Failed to upload to local IPFS:`, error.message);
    throw new Error(`Local IPFS upload failed: ${error.message}`);
  }
}

/**
 * Upload File Path to Local IPFS
 * 
 * Reads file from disk and uploads to local IPFS node.
 * 
 * @param filePath - Path to file on disk
 * @returns Local IPFS CID
 * 
 * @example
 * const cid = await uploadFileToLocalIPFS('/tmp/profile.jpg');
 */
export async function uploadFileToLocalIPFS(filePath: string): Promise<string> {
  if (!isIPFSEnabled()) {
    throw new Error('IPFS is disabled. Set USE_IPFS=true in .env');
  }

  try {
    const buffer = fs.readFileSync(filePath);
    const filename = path.basename(filePath);
    
    return await uploadToLocalIPFS(buffer, filename);
  } catch (error: any) {
    logger.error(`Failed to upload file to local IPFS:`, error.message);
    throw new Error(`File upload to IPFS failed: ${error.message}`);
  }
}

/**
 * Pin to Pinata
 * 
 * Uploads file to Pinata for permanent pinning.
 * Pinata ensures the file is always available on IPFS.
 * 
 * @param buffer - File buffer to upload
 * @param filename - Original filename
 * @param metadata - Optional metadata for Pinata
 * @returns Pinata CID
 * 
 * @example
 * const cid = await uploadToPinata(fileBuffer, 'profile.jpg', {
 *   name: 'User Profile Picture',
 *   keyvalues: { userId: '123', type: 'profile' }
 * });
 */
export async function uploadToPinata(
  buffer: Buffer,
  filename: string,
  metadata?: {
    name?: string;
    keyvalues?: Record<string, string | number>;
  }
): Promise<string> {
  if (!isIPFSEnabled()) {
    throw new Error('IPFS is disabled. Set USE_IPFS=true in .env');
  }

  const apiKey = process.env.PINATA_API_KEY;
  const apiSecret = process.env.PINATA_API_SECRET;

  if (!apiKey || !apiSecret) {
    throw new Error(
      'Pinata credentials not configured. Set PINATA_API_KEY and PINATA_API_SECRET in .env'
    );
  }

  try {
    logger.info(`Pinning ${filename} to Pinata...`);
    
    // Create form data
    const formData = new FormData();
    formData.append('file', buffer, {
      filename,
      contentType: 'application/octet-stream'
    });

    // Add metadata if provided
    if (metadata) {
      const pinataMetadata = {
        name: metadata.name || filename,
        keyvalues: metadata.keyvalues || {}
      };
      
      formData.append('pinataMetadata', JSON.stringify(pinataMetadata));
    }

    // Pin options
    const pinataOptions = {
      cidVersion: 1 // Use CIDv1
    };
    
    formData.append('pinataOptions', JSON.stringify(pinataOptions));

    // Upload to Pinata
    const response = await axios.post(
      'https://api.pinata.cloud/pinning/pinFileToIPFS',
      formData,
      {
        headers: {
          'Content-Type': `multipart/form-data; boundary=${(formData as any)._boundary}`,
          'pinata_api_key': apiKey,
          'pinata_secret_api_key': apiSecret
        },
        maxContentLength: Infinity,
        maxBodyLength: Infinity,
        timeout: 120000 // 2 minutes
      }
    );

    const cid = response.data.IpfsHash;
    
    logger.info(`✅ Pinned to Pinata: ${cid}`);
    
    return cid;
  } catch (error: any) {
    const errorMsg = error.response?.data?.error || error.message;
    logger.error(`Failed to pin to Pinata:`, errorMsg);
    throw new Error(`Pinata upload failed: ${errorMsg}`);
  }
}

/**
 * Pin File Path to Pinata
 * 
 * Reads file from disk and pins to Pinata.
 * 
 * @param filePath - Path to file on disk
 * @param metadata - Optional metadata
 * @returns Pinata CID
 */
export async function pinFileToPinata(
  filePath: string,
  metadata?: {
    name?: string;
    keyvalues?: Record<string, string | number>;
  }
): Promise<string> {
  if (!isIPFSEnabled()) {
    throw new Error('IPFS is disabled. Set USE_IPFS=true in .env');
  }

  try {
    const buffer = fs.readFileSync(filePath);
    const filename = path.basename(filePath);
    
    return await uploadToPinata(buffer, filename, metadata);
  } catch (error: any) {
    logger.error(`Failed to pin file to Pinata:`, error.message);
    throw new Error(`File pinning to Pinata failed: ${error.message}`);
  }
}

/**
 * Upload to Both Local IPFS and Pinata
 * 
 * Two-step process:
 * 1. Upload to local IPFS (fast)
 * 2. Pin to Pinata (permanent)
 * 
 * Returns both CIDs for verification.
 * 
 * @param buffer - File buffer to upload
 * @param filename - Original filename
 * @param metadata - Optional metadata for Pinata
 * @returns IPFSUploadResult with both CIDs
 * 
 * @example
 * const result = await uploadToIPFS(fileBuffer, 'profile.jpg', {
 *   name: 'User Profile',
 *   keyvalues: { userId: '123' }
 * });
 * 
 * console.log('Local CID:', result.localCID);
 * console.log('Pinata CID:', result.pinataCID);
 * console.log('Access at:', result.gatewayUrl);
 */
export async function uploadToIPFS(
  buffer: Buffer,
  filename: string,
  metadata?: {
    name?: string;
    keyvalues?: Record<string, string | number>;
  }
): Promise<IPFSUploadResult> {
  // Skip IPFS if disabled
  if (!isIPFSEnabled()) {
    logger.info('IPFS is disabled, skipping upload');
    return {
      success: false,
      error: 'IPFS is disabled'
    };
  }

  const result: IPFSUploadResult = {
    success: false
  };

  try {
    // Step 1: Upload to local IPFS node
    try {
      const localCID = await uploadToLocalIPFS(buffer, filename);
      result.localCID = localCID;
      result.ipfsUrl = `ipfs://${localCID}`;
      
      logger.info(`✅ Local IPFS upload successful: ${localCID}`);
    } catch (error: any) {
      logger.warn(`Local IPFS upload failed, continuing to Pinata...`, error.message);
      result.error = `Local IPFS failed: ${error.message}`;
    }

    // Step 2: Pin to Pinata for permanent storage
    try {
      const pinataCID = await uploadToPinata(buffer, filename, metadata);
      result.pinataCID = pinataCID;
      result.pinataUrl = `https://gateway.pinata.cloud/ipfs/${pinataCID}`;
      result.gatewayUrl = `https://gateway.pinata.cloud/ipfs/${pinataCID}`;
      
      // Backward compatibility
      result.cid = pinataCID;
      result.url = result.gatewayUrl;
      
      logger.info(`✅ Pinata pinning successful: ${pinataCID}`);
      
      // If local failed but Pinata succeeded, still mark as success
      result.success = true;
    } catch (error: any) {
      logger.error(`Pinata pinning failed:`, error.message);
      
      // If both failed, return error
      if (!result.localCID) {
        result.error = `Both IPFS uploads failed. Local: ${result.error || 'failed'}, Pinata: ${error.message}`;
        return result;
      }
      
      // If local succeeded but Pinata failed, still partial success
      result.success = true;
      result.error = `Pinata failed: ${error.message}`;
      result.gatewayUrl = `https://ipfs.io/ipfs/${result.localCID}`;
      
      // Backward compatibility
      result.cid = result.localCID;
      result.url = result.gatewayUrl;
    }

    // Verify CIDs match (they should!)
    if (result.localCID && result.pinataCID && result.localCID !== result.pinataCID) {
      logger.warn(`⚠️  CID mismatch! Local: ${result.localCID}, Pinata: ${result.pinataCID}`);
    }

    return result;
  } catch (error: any) {
    logger.error(`IPFS upload failed:`, error.message);
    return {
      success: false,
      error: error.message
    };
  }
}

/**
 * Get File from IPFS
 * 
 * Retrieves file content from IPFS using CID.
 * 
 * @param cid - IPFS CID
 * @returns File buffer
 * 
 * @example
 * const fileBuffer = await getFromIPFS('QmX123...');
 */
export async function getFromIPFS(cid: string): Promise<Buffer> {
  if (!isIPFSEnabled()) {
    throw new Error('IPFS is disabled');
  }

  try {
    const client = getIPFSClient();
    
    const chunks: Uint8Array[] = [];
    
    for await (const chunk of client.cat(cid)) {
      chunks.push(chunk);
    }
    
    const buffer = Buffer.concat(chunks);
    
    logger.info(`Retrieved ${buffer.length} bytes from IPFS: ${cid}`);
    
    return buffer;
  } catch (error: any) {
    logger.error(`Failed to get from IPFS:`, error.message);
    throw new Error(`IPFS retrieval failed: ${error.message}`);
  }
}

/**
 * Verify IPFS Connection
 * 
 * Tests connection to local IPFS node and Pinata.
 * 
 * @returns Status of IPFS services
 */
export async function verifyIPFSConnection(): Promise<{
  localIPFS: boolean;
  pinata: boolean;
  error?: string;
}> {
  const status = {
    localIPFS: false,
    pinata: false,
    error: undefined as string | undefined
  };

  if (!isIPFSEnabled()) {
    status.error = 'IPFS is disabled (USE_IPFS=false)';
    return status;
  }

  // Test local IPFS
  try {
    const client = getIPFSClient();
    await client.version();
    status.localIPFS = true;
    logger.info('✅ Local IPFS node connected');
  } catch (error: any) {
    logger.error('❌ Local IPFS node connection failed:', error.message);
    status.error = `Local IPFS: ${error.message}`;
  }

  // Test Pinata
  try {
    const apiKey = process.env.PINATA_API_KEY;
    const apiSecret = process.env.PINATA_API_SECRET;

    if (!apiKey || !apiSecret) {
      throw new Error('Pinata credentials not configured');
    }

    const response = await axios.get(
      'https://api.pinata.cloud/data/testAuthentication',
      {
        headers: {
          'pinata_api_key': apiKey,
          'pinata_secret_api_key': apiSecret
        }
      }
    );

    if (response.data.message === 'Congratulations! You are communicating with the Pinata API!') {
      status.pinata = true;
      logger.info('✅ Pinata API connected');
    }
  } catch (error: any) {
    logger.error('❌ Pinata API connection failed:', error.message);
    status.error = status.error 
      ? `${status.error}; Pinata: ${error.message}`
      : `Pinata: ${error.message}`;
  }

  return status;
}

/**
 * Generate IPFS Gateway URLs
 * 
 * Creates multiple gateway URLs for a CID.
 * 
 * @param cid - IPFS CID
 * @returns Object with different gateway URLs
 */
export function generateGatewayURLs(cid: string) {
  return {
    pinata: `https://gateway.pinata.cloud/ipfs/${cid}`,
    ipfsIo: `https://ipfs.io/ipfs/${cid}`,
    cloudflare: `https://cloudflare-ipfs.com/ipfs/${cid}`,
    dweb: `https://dweb.link/ipfs/${cid}`,
    protocol: `ipfs://${cid}`
  };
}

/**
 * Get Gateway URL (Helper for backward compatibility)
 * 
 * Returns the primary gateway URL for a CID.
 * 
 * @param cid - IPFS CID
 * @returns Pinata gateway URL
 */
export function getGatewayUrl(cid: string): string {
  return `https://gateway.pinata.cloud/ipfs/${cid}`;
}

/**
 * Upload Profile Picture (Helper for backward compatibility)
 * 
 * @param buffer - Image buffer
 * @param filename - Original filename
 * @returns IPFS upload result
 */
export async function uploadProfilePicture(
  buffer: Buffer,
  filename: string
): Promise<IPFSUploadResult> {
  return uploadToIPFS(buffer, filename, {
    name: 'Profile Picture',
    keyvalues: {
      type: 'profile',
      timestamp: Date.now()
    }
  });
}

/**
 * Upload Text to IPFS
 * 
 * @param text - Text content to upload
 * @param filename - Filename for the text
 * @returns IPFS upload result
 */
export async function uploadText(
  text: string,
  filename: string
): Promise<IPFSUploadResult> {
  const buffer = Buffer.from(text, 'utf-8');
  return uploadToIPFS(buffer, filename, {
    name: filename,
    keyvalues: {
      type: 'text',
      timestamp: Date.now()
    }
  });
}

/**
 * Fetch Text from IPFS
 * 
 * @param cid - IPFS CID
 * @returns Text content
 */
export async function fetchText(cid: string): Promise<string> {
  const buffer = await getFromIPFS(cid);
  return buffer.toString('utf-8');
}

/**
 * Default Export (for backward compatibility with existing controllers)
 */
export default {
  uploadToIPFS,
  uploadToLocalIPFS,
  uploadToPinata,
  uploadFileToLocalIPFS,
  pinFileToPinata,
  getFromIPFS,
  verifyIPFSConnection,
  generateGatewayURLs,
  getGatewayUrl,
  uploadProfilePicture,
  uploadText,
  fetchText
};
