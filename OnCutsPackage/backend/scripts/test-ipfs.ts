/**
 * IPFS Connection Test Script
 * 
 * Tests connectivity to:
 * - Local IPFS node
 * - Pinata API
 * 
 * Usage:
 *   npx ts-node scripts/test-ipfs.ts
 *   (run from backend directory)
 */

import dotenv from 'dotenv';
import path from 'path';

// Load environment variables
dotenv.config({ path: path.join(__dirname, '../.env') });

import { verifyIPFSConnection, uploadToIPFS } from '../src/services/ipfs.service';
import { logger } from '../src/utils/logger';

async function testIPFS() {
  console.log('\n════════════════════════════════════════════════════');
  console.log('  🔍 IPFS Connection Test');
  console.log('════════════════════════════════════════════════════\n');

  // Check if IPFS is enabled
  if (process.env.USE_IPFS !== 'true') {
    console.error('❌ IPFS is disabled');
    console.log('\n💡 To enable IPFS, add to your .env file:');
    console.log('   USE_IPFS=true\n');
    process.exit(1);
  }

  console.log('✅ IPFS is enabled\n');

  // Display configuration
  console.log('Configuration:');
  console.log('─────────────────────────────────────────────────────');
  console.log(`USE_IPFS:          ${process.env.USE_IPFS || 'not set'}`);
  console.log(`IPFS_NODE_URL:     ${process.env.IPFS_NODE_URL || 'not set (default: http://localhost:5001)'}`);
  console.log(`PINATA_API_KEY:    ${process.env.PINATA_API_KEY ? '✓ configured' : '❌ not set'}`);
  console.log(`PINATA_API_SECRET: ${process.env.PINATA_API_SECRET ? '✓ configured' : '❌ not set'}`);
  console.log('─────────────────────────────────────────────────────\n');

  // Test connections
  console.log('Testing Connections...\n');
  
  try {
    const status = await verifyIPFSConnection();

    console.log('Results:');
    console.log('─────────────────────────────────────────────────────');
    console.log(`Local IPFS Node:   ${status.localIPFS ? '✅ Connected' : '❌ Failed'}`);
    console.log(`Pinata API:        ${status.pinata ? '✅ Connected' : '❌ Failed'}`);
    console.log('─────────────────────────────────────────────────────\n');

    if (status.error) {
      console.error('Error Details:');
      console.error(`  ${status.error}\n`);
    }

    // Test upload if both services are working
    if (status.localIPFS || status.pinata) {
      console.log('Testing File Upload...\n');
      
      // Create a test file buffer
      const testContent = `CampusCuts IPFS Test\nTimestamp: ${new Date().toISOString()}`;
      const testBuffer = Buffer.from(testContent, 'utf-8');
      
      try {
        const uploadResult = await uploadToIPFS(
          testBuffer,
          'campuscuts-test.txt',
          {
            name: 'CampusCuts IPFS Test File',
            keyvalues: {
              type: 'test',
              timestamp: Date.now()
            }
          }
        );

        if (uploadResult.success) {
          console.log('✅ Upload Test Successful!\n');
          console.log('Upload Results:');
          console.log('─────────────────────────────────────────────────────');
          
          if (uploadResult.localCID) {
            console.log(`Local CID:    ${uploadResult.localCID}`);
          }
          
          if (uploadResult.pinataCID) {
            console.log(`Pinata CID:   ${uploadResult.pinataCID}`);
          }
          
          if (uploadResult.gatewayUrl) {
            console.log(`\nAccess via:   ${uploadResult.gatewayUrl}`);
          }
          
          if (uploadResult.ipfsUrl) {
            console.log(`IPFS URL:     ${uploadResult.ipfsUrl}`);
          }
          
          console.log('─────────────────────────────────────────────────────\n');
          
          // Verify CIDs match (if both exist)
          if (uploadResult.localCID && uploadResult.pinataCID) {
            if (uploadResult.localCID === uploadResult.pinataCID) {
              console.log('✅ CIDs match perfectly!\n');
            } else {
              console.log('⚠️  CIDs differ (this is OK - different versions/chunking)\n');
              console.log(`   Local:  ${uploadResult.localCID}`);
              console.log(`   Pinata: ${uploadResult.pinataCID}\n`);
            }
          }
        } else {
          console.error('❌ Upload Test Failed\n');
          console.error(`Error: ${uploadResult.error}\n`);
        }
      } catch (uploadError: any) {
        console.error('❌ Upload Test Error\n');
        console.error(`Error: ${uploadError.message}\n`);
      }
    }

    // Summary
    console.log('\n════════════════════════════════════════════════════');
    console.log('  Summary');
    console.log('════════════════════════════════════════════════════\n');

    if (status.localIPFS && status.pinata) {
      console.log('🎉 All systems operational!');
      console.log('\nYour IPFS integration is fully functional.');
      console.log('You can now upload files to both local IPFS and Pinata.\n');
      process.exit(0);
    } else if (status.localIPFS || status.pinata) {
      console.log('⚠️  Partial functionality');
      console.log('\nOne service is working, uploads will continue.');
      
      if (!status.localIPFS) {
        console.log('\n💡 To fix local IPFS:');
        console.log('   1. Install IPFS Desktop: https://docs.ipfs.tech/install/ipfs-desktop/');
        console.log('   2. Or run: ipfs daemon');
        console.log('   3. Or skip local node and use Pinata only\n');
      }
      
      if (!status.pinata) {
        console.log('\n💡 To fix Pinata:');
        console.log('   1. Get API keys from: https://app.pinata.cloud/keys');
        console.log('   2. Add to .env:');
        console.log('      PINATA_API_KEY=your_key');
        console.log('      PINATA_API_SECRET=your_secret\n');
      }
      
      process.exit(1);
    } else {
      console.log('❌ IPFS not operational');
      console.log('\nNeither local IPFS nor Pinata are working.');
      console.log('\nNext Steps:');
      console.log('───────────────────────────────────────────────────');
      console.log('\n1. Install IPFS Desktop:');
      console.log('   https://docs.ipfs.tech/install/ipfs-desktop/');
      console.log('\n2. Get Pinata API keys:');
      console.log('   https://app.pinata.cloud/keys');
      console.log('\n3. Add to backend/.env:');
      console.log('   USE_IPFS=true');
      console.log('   IPFS_NODE_URL=http://localhost:5001');
      console.log('   PINATA_API_KEY=your_key_here');
      console.log('   PINATA_API_SECRET=your_secret_here');
      console.log('\n4. Restart backend and run this test again\n');
      process.exit(1);
    }
  } catch (error: any) {
    console.error('\n❌ Test Failed\n');
    console.error(`Error: ${error.message}\n`);
    process.exit(1);
  }
}

// Run test
testIPFS().catch(error => {
  console.error('\n❌ Unexpected Error\n');
  console.error(error);
  process.exit(1);
});

