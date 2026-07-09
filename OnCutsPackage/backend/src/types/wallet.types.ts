/**
 * Custodial Wallet Types
 * 
 * Defines all types and enums for the internal ledger system
 */

// Transaction Types
export enum TransactionType {
  DEPOSIT = 'DEPOSIT',                    // User adds funds via Stripe/card
  WITHDRAWAL = 'WITHDRAWAL',              // User withdraws to bank
  BOOKING_PAYMENT = 'BOOKING_PAYMENT',    // Customer pays for booking
  BOOKING_REFUND = 'BOOKING_REFUND',      // Booking cancelled, refund issued
  SERVICE_COMPLETION = 'SERVICE_COMPLETION', // Funds released from pending to available
  TIP = 'TIP',                            // Tip given/received
  PLATFORM_FEE = 'PLATFORM_FEE',          // Platform commission deducted
  PROMOTIONAL_CREDIT = 'PROMOTIONAL_CREDIT', // Platform issues credit/promo
  DISPUTE_HOLD = 'DISPUTE_HOLD',          // Funds locked due to dispute
  DISPUTE_RELEASE = 'DISPUTE_RELEASE',    // Dispute resolved, funds released
  ADJUSTMENT = 'ADJUSTMENT'               // Manual adjustment by platform
}

// Balance Types
export enum BalanceType {
  AVAILABLE = 'available',  // Funds available for use/withdrawal
  PENDING = 'pending',      // Funds held pending service completion
  LOCKED = 'locked'         // Funds locked for disputes/holds
}

// Withdrawal Status
export enum WithdrawalStatus {
  PENDING = 'pending',
  PROCESSING = 'processing',
  COMPLETED = 'completed',
  FAILED = 'failed',
  CANCELLED = 'cancelled'
}

// Ledger Entry Interface
export interface LedgerEntry {
  id: string;
  user_id: string;
  amount: number;              // In cents
  type: TransactionType;
  balance_type: BalanceType;
  balance_after: number;       // In cents
  reference_type?: string;     // 'booking', 'payout', 'stripe_charge', etc.
  reference_id?: string;       // ID of related entity
  metadata?: Record<string, any>;
  description?: string;
  created_at: Date;
  created_by?: string;         // User ID of admin who created (if applicable)
}

// User Balance Interface
export interface UserBalance {
  user_id: string;
  balance_available: number;   // In cents
  balance_pending: number;     // In cents
  balance_locked: number;      // In cents
  total_balance: number;       // In cents (sum of all balances)
}

// Withdrawal Request Interface
export interface WithdrawalRequest {
  id: string;
  user_id: string;
  amount: number;              // In cents
  status: WithdrawalStatus;
  stripe_payout_id?: string;
  stripe_destination_id?: string;
  failure_reason?: string;
  requested_at: Date;
  processed_at?: Date;
  completed_at?: Date;
}

// Ledger Operation Input
export interface CreateLedgerEntryInput {
  user_id: string;
  amount: number;              // In cents
  type: TransactionType;
  balance_type: BalanceType;
  reference_type?: string;
  reference_id?: string;
  metadata?: Record<string, any>;
  description?: string;
  created_by?: string;
}

// Withdrawal Request Input
export interface CreateWithdrawalInput {
  user_id: string;
  amount: number;              // In cents
  stripe_destination_id: string; // Stripe Connect account ID
}

// Transfer Between Users Input
export interface InternalTransferInput {
  from_user_id: string;
  to_user_id: string;
  amount: number;              // In cents
  type: TransactionType;      // TIP, BOOKING_PAYMENT, etc.
  reference_type?: string;
  reference_id?: string;
  description?: string;
}

// Booking Payment Flow
export interface BookingPaymentInput {
  booking_id: string;
  customer_id: string;
  barber_id: string;
  total_amount: number;        // In cents
  platform_fee: number;        // In cents
  tip_amount?: number;         // In cents
}

// Helper: Convert dollars to cents
export const dollarsToCents = (dollars: number): number => {
  return Math.round(dollars * 100);
};

// Helper: Convert cents to dollars
export const centsToDollars = (cents: number): number => {
  return cents / 100;
};

// Helper: Format cents as USD string
export const formatCentsAsUSD = (cents: number): string => {
  const dollars = centsToDollars(cents);
  return new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency: 'USD',
  }).format(dollars);
};

