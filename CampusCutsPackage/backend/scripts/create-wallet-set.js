/**
 * Create Circle Wallet Set (JavaScript version)
 * 
 * Simple script to create a wallet set for CampusCuts.
 * Can be run directly without TypeScript compilation.
 * 
 * Usage:
 *   node scripts/create-wallet-set.js
 */

require('dotenv').config();
const axios = require('axios');
const { v4: uuidv4 } = require('uuid');

async function createWalletSet(name) {
  const apiKey = process.env.CIRCLE_TEST_API_KEY || process.env.CIRCLE_API_KEY;
  const apiUrl = process.env.CIRCLE_API_URL || 'https://api-sandbox.circle.com';

  if (!apiKey) {
    throw new Error('Circle API key not configured. Add CIRCLE_TEST_API_KEY to .env');
  }

  const response = await axios.post(
    `${apiUrl}/v1/w3s/developer/walletSets`,
    { name },
    {
      headers: {
        'Authorization': `Bearer ${apiKey}`,
        'Content-Type': 'application/json',
        'X-Request-Id': uuidv4()
      }
    }
  );

  return response.data.data.walletSet.id;
}

async function main() {
  console.log('════════════════════════════════════════════════════');
  console.log('  🏦 Circle Wallet Set Creation');
  console.log('════════════════════════════════════════════════════\n');

  // Check existing configuration
  const existingWalletSetId = process.env.CIRCLE_WALLET_SET_ID;
  
  if (existingWalletSetId && existingWalletSetId.trim() !== '') {
    console.log('⚠️  Wallet set already configured in .env:');
    console.log(`   CIRCLE_WALLET_SET_ID=${existingWalletSetId}\n`);
    console.log('A wallet set already exists. Exiting...\n');
    console.log('To create a new one, remove CIRCLE_WALLET_SET_ID from .env first.\n');
    process.exit(0);
  }

  // Check API configuration
  const apiKey = process.env.CIRCLE_TEST_API_KEY || process.env.CIRCLE_API_KEY;
  const apiUrl = process.env.CIRCLE_API_URL || 'https://api-sandbox.circle.com';

  if (!apiKey) {
    console.error('❌ Error: Circle API key not configured\n');
    console.error('Please add to your .env file:');
    console.error('CIRCLE_TEST_API_KEY=TEST_API_KEY:your_key_here');
    console.error('CIRCLE_API_URL=https://api-sandbox.circle.com\n');
    process.exit(1);
  }

  console.log('Configuration:');
  console.log('─────────────────────────────────────────────────────');
  console.log(`API URL:     ${apiUrl}`);
  console.log(`API Key:     ${apiKey.substring(0, 20)}...`);
  console.log(`Mode:        ${apiKey.startsWith('TEST_') ? '🧪 SANDBOX' : '🔴 PRODUCTION'}`);
  console.log('─────────────────────────────────────────────────────\n');

  try {
    console.log('Creating wallet set "CampusCuts Main"...\n');
    
    const walletSetId = await createWalletSet('CampusCuts Main');
    
    console.log('✅ Success! Wallet set created.\n');
    console.log('════════════════════════════════════════════════════');
    console.log('  📋 Add this to your .env file:');
    console.log('════════════════════════════════════════════════════\n');
    console.log(`CIRCLE_WALLET_SET_ID=${walletSetId}\n`);
    console.log('════════════════════════════════════════════════════');
    console.log('\nNext steps:');
    console.log('1. Copy the line above');
    console.log('2. Add it to backend/.env');
    console.log('3. Restart your backend: pm2 restart all');
    console.log('4. Your Circle integration is ready! 🎉\n');

  } catch (error) {
    console.error('\n❌ Failed to create wallet set\n');
    console.error('Error:', error.message);
    
    if (error.response?.data) {
      console.error('Details:', JSON.stringify(error.response.data, null, 2));
    }

    console.error('\nTroubleshooting:');
    console.error('─────────────────────────────────────────────────────');
    console.error('1. Verify your API key is correct');
    console.error('2. Check you have permissions in Circle dashboard');
    console.error('3. Ensure CIRCLE_API_URL matches your key type:');
    console.error('   - TEST key → https://api-sandbox.circle.com');
    console.error('   - Production → https://api.circle.com');
    console.error('4. Review Circle API status: https://status.circle.com/\n');
    
    process.exit(1);
  }
}

// Run the script
main().catch(error => {
  console.error('Unexpected error:', error);
  process.exit(1);
});

