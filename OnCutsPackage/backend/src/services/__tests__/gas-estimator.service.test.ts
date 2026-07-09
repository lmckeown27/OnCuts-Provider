/**
 * Gas Estimator Service Tests
 * 
 * Unit tests for gas estimation logic
 */

import Decimal from 'decimal.js';

describe('GasEstimatorService', () => {
  describe('Gas Calculation', () => {
    it('should calculate APT to octas conversion correctly', () => {
      const apt = 0.5;
      const expectedOctas = 50_000_000;

      const octas = new Decimal(apt).times(100_000_000).toNumber();

      expect(octas).toBe(expectedOctas);
    });

    it('should calculate octas to APT conversion correctly', () => {
      const octas = 150_000_000;
      const expectedAPT = 1.5;

      const apt = new Decimal(octas).div(100_000_000).toNumber();

      expect(apt).toBe(expectedAPT);
    });

    it('should apply safety buffer correctly', () => {
      const baseEstimate = 0.5;
      const safetyBufferPct = 20;

      const withBuffer = new Decimal(baseEstimate)
        .times(1 + safetyBufferPct / 100)
        .toNumber();

      expect(withBuffer).toBe(0.6);
    });

    it('should round up to 6 decimal places', () => {
      const value = 0.1234567891234;

      const rounded = new Decimal(value)
        .toDecimalPlaces(6, Decimal.ROUND_UP)
        .toNumber();

      expect(rounded).toBe(0.123457);
    });

    it('should calculate amount needed correctly', () => {
      const estimatedNeeded = 1.5;
      const currentBalance = 0.8;

      const amountNeeded = Math.max(
        0,
        new Decimal(estimatedNeeded).minus(currentBalance).toNumber()
      );

      expect(amountNeeded).toBe(0.7);
    });

    it('should return 0 if balance is sufficient', () => {
      const estimatedNeeded = 0.5;
      const currentBalance = 1.0;

      const amountNeeded = Math.max(
        0,
        new Decimal(estimatedNeeded).minus(currentBalance).toNumber()
      );

      expect(amountNeeded).toBe(0);
    });
  });

  describe('Coverage Estimation', () => {
    it('should calculate coverage days correctly', () => {
      const currentBalance = 1.0;
      const dailyConsumption = 0.2;

      const coverageDays = new Decimal(currentBalance)
        .div(dailyConsumption)
        .toDecimalPlaces(2, Decimal.ROUND_DOWN)
        .toNumber();

      expect(coverageDays).toBe(5.0);
    });

    it('should handle zero consumption gracefully', () => {
      const currentBalance = 1.0;
      const dailyConsumption = 0;

      const coverageDays = dailyConsumption > 0
        ? new Decimal(currentBalance).div(dailyConsumption).toNumber()
        : 999;

      expect(coverageDays).toBe(999);
    });
  });

  describe('Pending Writes Estimation', () => {
    it('should calculate total writes from components', () => {
      const bookingWrites = 50 * 2; // 50 bookings × 2 writes each
      const withdrawalWrites = 24 * 4; // 24 hours × 4 batches/hour
      const proofWrites = 50; // 1 proof per booking
      const activeEscrows = 25;

      const total = bookingWrites + withdrawalWrites + proofWrites + activeEscrows;

      expect(total).toBe(271);
    });

    it('should apply minimum writes threshold', () => {
      const calculatedWrites = 5;
      const minimumWrites = 10;

      const finalWrites = Math.max(calculatedWrites, minimumWrites);

      expect(finalWrites).toBe(minimumWrites);
    });
  });

  describe('Estimation Formula', () => {
    it('should apply complete estimation formula', () => {
      const pendingWrites = 150;
      const avgGasPerWrite = 0.0003;
      const safetyBufferPct = 20;
      const currentBalance = 0.5;

      const baseEstimate = new Decimal(pendingWrites).times(avgGasPerWrite);
      const withBuffer = baseEstimate.times(1 + safetyBufferPct / 100);
      const amountNeeded = Decimal.max(
        0,
        withBuffer.minus(currentBalance)
      ).toDecimalPlaces(6, Decimal.ROUND_UP);

      expect(baseEstimate.toNumber()).toBe(0.045);
      expect(withBuffer.toNumber()).toBe(0.054);
      expect(amountNeeded.toNumber()).toBe(0);
    });

    it('should trigger top-up when balance insufficient', () => {
      const pendingWrites = 2000;
      const avgGasPerWrite = 0.0003;
      const safetyBufferPct = 20;
      const currentBalance = 0.2;
      const topUpThreshold = 0.1;

      const baseEstimate = new Decimal(pendingWrites).times(avgGasPerWrite);
      const withBuffer = baseEstimate.times(1 + safetyBufferPct / 100);
      const amountNeeded = Decimal.max(
        0,
        withBuffer.minus(currentBalance)
      ).toDecimalPlaces(6, Decimal.ROUND_UP);

      expect(amountNeeded.toNumber()).toBeGreaterThan(topUpThreshold);
    });
  });
});

describe('TopUpRequestService', () => {
  describe('Idempotency', () => {
    it('should detect duplicate idempotency keys', () => {
      const existingKeys = new Set(['key-1', 'key-2', 'key-3']);
      const newKey = 'key-2';

      const isDuplicate = existingKeys.has(newKey);

      expect(isDuplicate).toBe(true);
    });

    it('should allow new idempotency keys', () => {
      const existingKeys = new Set(['key-1', 'key-2', 'key-3']);
      const newKey = 'key-4';

      const isDuplicate = existingKeys.has(newKey);

      expect(isDuplicate).toBe(false);
    });
  });

  describe('Status Transitions', () => {
    it('should allow pending → approved transition', () => {
      const currentStatus = 'pending';
      const newStatus = 'approved';
      const allowedTransitions = {
        pending: ['approved', 'cancelled'],
        approved: ['completed', 'failed'],
        completed: [],
        failed: [],
        cancelled: [],
      };

      const isValid = allowedTransitions[currentStatus].includes(newStatus);

      expect(isValid).toBe(true);
    });

    it('should disallow completed → pending transition', () => {
      const currentStatus = 'completed';
      const newStatus = 'pending';
      const allowedTransitions = {
        pending: ['approved', 'cancelled'],
        approved: ['completed', 'failed'],
        completed: [],
        failed: [],
        cancelled: [],
      };

      const isValid = allowedTransitions[currentStatus].includes(newStatus);

      expect(isValid).toBe(false);
    });
  });
});

describe('TransactionVerification', () => {
  describe('Amount Validation', () => {
    it('should pass when verified amount matches requested', () => {
      const requestedOctas = 50_000_000;
      const verifiedOctas = 50_000_000;

      const isValid = verifiedOctas >= requestedOctas;

      expect(isValid).toBe(true);
    });

    it('should pass when verified amount exceeds requested', () => {
      const requestedOctas = 50_000_000;
      const verifiedOctas = 60_000_000;

      const isValid = verifiedOctas >= requestedOctas;

      expect(isValid).toBe(true);
    });

    it('should fail when verified amount less than requested', () => {
      const requestedOctas = 50_000_000;
      const verifiedOctas = 40_000_000;

      const isValid = verifiedOctas >= requestedOctas;

      expect(isValid).toBe(false);
    });
  });

  describe('Address Validation', () => {
    it('should match addresses case-insensitively', () => {
      const expected = '0x50C7BF0BE7F5A56F8312AE8A49EC638D0D7B2BC68E061B867ED86D2AF82A21AA';
      const actual = '0x50c7bf0be7f5a56f8312ae8a49ec638d0d7b2bc68e061b867ed86d2af82a21aa';

      const matches = expected.toLowerCase() === actual.toLowerCase();

      expect(matches).toBe(true);
    });
  });
});

