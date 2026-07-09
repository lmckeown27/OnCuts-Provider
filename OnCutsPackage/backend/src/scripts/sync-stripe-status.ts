/**
 * Sync Stripe Connect Status Script
 * 
 * This script queries Stripe API for each barber with a stripe_account_id
 * and updates their stripe_payouts_enabled and stripe_charges_enabled columns
 * 
 * Run with: npx ts-node src/scripts/sync-stripe-status.ts
 * Or: npm run sync-stripe-status
 */

import { Pool } from 'pg';
import dotenv from 'dotenv';
import { getDefaultStripeClient } from '../config/stripe';

// Load environment variables
dotenv.config();

function stripeSdk() {
  return getDefaultStripeClient();
}

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
});

interface BarberAccount {
  user_id: string;
  email: string;
  first_name: string;
  stripe_account_id: string;
}

async function syncStripeStatus(): Promise<void> {
  console.log('🔄 Starting Stripe Connect status sync...\n');

  try {
    // Get all users with stripe_account_id
    const result = await pool.query<BarberAccount>(`
      SELECT id as user_id, email, first_name, stripe_account_id
      FROM users
      WHERE stripe_account_id IS NOT NULL
      ORDER BY first_name
    `);

    const barbers = result.rows;
    console.log(`Found ${barbers.length} barbers with Stripe accounts\n`);

    let updated = 0;
    let errors = 0;

    for (const barber of barbers) {
      try {
        // Query Stripe API for account status
        const account = await stripeSdk().accounts.retrieve(barber.stripe_account_id);

        const payoutsEnabled = account.payouts_enabled || false;
        const chargesEnabled = account.charges_enabled || false;

        // Update database
        await pool.query(`
          UPDATE users 
          SET stripe_payouts_enabled = $1, stripe_charges_enabled = $2
          WHERE id = $3
        `, [payoutsEnabled, chargesEnabled, barber.user_id]);

        const status = payoutsEnabled ? '✅ Verified' : '❌ Restricted';
        console.log(`${status} | ${barber.first_name} (${barber.email})`);
        
        if (!payoutsEnabled) {
          // Log requirements if restricted
          if (account.requirements?.currently_due?.length) {
            console.log(`   └─ Currently due: ${account.requirements.currently_due.join(', ')}`);
          }
          if (account.requirements?.past_due?.length) {
            console.log(`   └─ Past due: ${account.requirements.past_due.join(', ')}`);
          }
          if (account.requirements?.disabled_reason) {
            console.log(`   └─ Reason: ${account.requirements.disabled_reason}`);
          }
        }

        updated++;
      } catch (error: any) {
        console.log(`⚠️  Error | ${barber.first_name} (${barber.email}): ${error.message}`);
        
        // If account doesn't exist in Stripe, set to false
        if (error.code === 'account_invalid' || error.type === 'StripeInvalidRequestError') {
          await pool.query(`
            UPDATE users 
            SET stripe_payouts_enabled = false, stripe_charges_enabled = false
            WHERE id = $1
          `, [barber.user_id]);
          console.log(`   └─ Set to restricted (invalid Stripe account)`);
        }
        
        errors++;
      }
    }

    console.log(`\n✅ Sync complete!`);
    console.log(`   Updated: ${updated}`);
    console.log(`   Errors: ${errors}`);

  } catch (error) {
    console.error('Fatal error:', error);
    process.exit(1);
  } finally {
    await pool.end();
  }
}

// Run the script
syncStripeStatus();

