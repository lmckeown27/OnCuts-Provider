/**
 * Hash proofs for audit trails; submission goes through `sui-chain.service` (Sui / stub).
 */

import crypto from 'crypto';
import { pool } from '../database/connection';
import { logger } from '../utils/logger';
import suiChainService from './sui-chain.service';

export enum RecordType {
  BOOKING_HASH = 'booking_hash',
  PAYMENT_HASH = 'payment_hash',
  REVIEW_HASH = 'review_hash',
  WITHDRAWAL = 'withdrawal',
  BATCH_ANCHOR = 'batch_anchor'
}

export interface OnChainRecord {
  id: number;
  record_type: RecordType;
  subject_id?: string;
  chain: string;
  tx_hash: string;
  block_number?: number;
  timestamp: Date;
  raw_receipt?: Record<string, any>;
  proof_data?: Record<string, any>;
}

export interface AnchorProofInput {
  record_type: RecordType;
  subject_id: string;
  data: Record<string, any>;  // Data to hash
}

export interface BatchAnchorInput {
  proofs: Array<{
    record_type: RecordType;
    subject_id: string;
    data: Record<string, any>;
  }>;
}

class OnChainAnchorService {
  /**
   * Create a SHA-256 hash of data
   */
  private createHash(data: Record<string, any>): string {
    const normalized = JSON.stringify(data, Object.keys(data).sort());
    return crypto.createHash('sha256').update(normalized).digest('hex');
  }

  /**
   * Create Merkle root from multiple hashes (for batching)
   */
  private createMerkleRoot(hashes: string[]): string {
    if (hashes.length === 0) return '';
    if (hashes.length === 1) return hashes[0];

    // Simple merkle tree implementation
    let currentLevel = hashes;
    
    while (currentLevel.length > 1) {
      const nextLevel: string[] = [];
      
      for (let i = 0; i < currentLevel.length; i += 2) {
        const left = currentLevel[i];
        const right = i + 1 < currentLevel.length ? currentLevel[i + 1] : left;
        const combined = crypto.createHash('sha256')
          .update(left + right)
          .digest('hex');
        nextLevel.push(combined);
      }
      
      currentLevel = nextLevel;
    }

    return currentLevel[0];
  }

  /**
   * Anchor a single proof on-chain
   */
  async anchorProof(input: AnchorProofInput): Promise<OnChainRecord> {
    try {
      // 1. Create hash of data
      const hash = this.createHash(input.data);

      // 2. Submit proof (Sui / stub)
      const txHash = await suiChainService.submitHashProof(
        input.record_type,
        input.subject_id,
        hash
      );

      // 3. Store record in database
      const result = await pool.query(
        `INSERT INTO onchain_records (
          record_type, subject_id, chain, tx_hash,
          proof_data, timestamp
        )
        VALUES ($1, $2, $3, $4, $5, NOW())
        RETURNING *`,
        [
          input.record_type,
          input.subject_id,
          'sui',
          txHash,
          JSON.stringify({
            hash,
            original_data_keys: Object.keys(input.data),
          }),
        ]
      );

      logger.info('On-chain proof anchored', {
        record_type: input.record_type,
        subject_id: input.subject_id,
        tx_hash: txHash,
        hash,
      });

      return result.rows[0];
    } catch (error) {
      logger.error('Failed to anchor proof on-chain', {
        input,
        error,
      });
      throw error;
    }
  }

  /**
   * Anchor multiple proofs in a single batch (gas efficient)
   * Creates a Merkle root and stores only that on-chain
   */
  async anchorBatch(input: BatchAnchorInput): Promise<OnChainRecord> {
    try {
      // 1. Create hashes for all proofs
      const proofHashes = input.proofs.map(proof => ({
        subject_id: proof.subject_id,
        record_type: proof.record_type,
        hash: this.createHash(proof.data),
      }));

      // 2. Create Merkle root
      const merkleRoot = this.createMerkleRoot(proofHashes.map(p => p.hash));

      // 3. Store Merkle root on-chain (single transaction for all proofs)
      const txHash = await suiChainService.submitHashProof(
        'batch_anchor',
        `batch_${Date.now()}`,
        merkleRoot
      );

      // 4. Store batch record
      const result = await pool.query(
        `INSERT INTO onchain_records (
          record_type, chain, tx_hash,
          proof_data, timestamp
        )
        VALUES ($1, $2, $3, $4, NOW())
        RETURNING *`,
        [
          RecordType.BATCH_ANCHOR,
          'sui',
          txHash,
          JSON.stringify({
            merkle_root: merkleRoot,
            proof_count: input.proofs.length,
            proofs: proofHashes,
          }),
        ]
      );

      // 5. Store individual proof records (for querying)
      for (const proofHash of proofHashes) {
        await pool.query(
          `INSERT INTO onchain_records (
            record_type, subject_id, chain, tx_hash,
            proof_data, timestamp
          )
          VALUES ($1, $2, $3, $4, $5, NOW())`,
          [
            proofHash.record_type,
            proofHash.subject_id,
            'sui',
            txHash,  // Same tx_hash for all in batch
            JSON.stringify({
              hash: proofHash.hash,
              merkle_root: merkleRoot,
              batch: true,
            }),
          ]
        );
      }

      logger.info('Batch proof anchored on-chain', {
        proof_count: input.proofs.length,
        merkle_root: merkleRoot,
        tx_hash: txHash,
      });

      return result.rows[0];
    } catch (error) {
      logger.error('Failed to anchor batch proof', {
        proof_count: input.proofs.length,
        error,
      });
      throw error;
    }
  }

  /**
   * Verify a proof against on-chain record
   */
  async verifyProof(subjectId: string, data: Record<string, any>): Promise<boolean> {
    try {
      // 1. Compute hash of provided data
      const computedHash = this.createHash(data);

      // 2. Get on-chain record
      const result = await pool.query(
        `SELECT proof_data FROM onchain_records
         WHERE subject_id = $1
         ORDER BY timestamp DESC
         LIMIT 1`,
        [subjectId]
      );

      if (result.rows.length === 0) {
        return false;
      }

      const storedProof = result.rows[0].proof_data;

      // 3. Compare hashes
      return storedProof.hash === computedHash;
    } catch (error) {
      logger.error('Proof verification failed', { subjectId, error });
      return false;
    }
  }

  /**
   * Get on-chain record for a subject
   */
  async getProofRecord(subjectId: string): Promise<OnChainRecord | null> {
    const result = await pool.query(
      `SELECT * FROM onchain_records
       WHERE subject_id = $1
       ORDER BY timestamp DESC
       LIMIT 1`,
      [subjectId]
    );

    return result.rows[0] || null;
  }

  /**
   * Get all on-chain records for a type
   */
  async getRecordsByType(recordType: RecordType, limit: number = 50): Promise<OnChainRecord[]> {
    const result = await pool.query(
      `SELECT * FROM onchain_records
       WHERE record_type = $1
       ORDER BY timestamp DESC
       LIMIT $2`,
      [recordType, limit]
    );

    return result.rows;
  }

  /**
   * Helper: Anchor booking completion
   */
  async anchorBookingCompletion(bookingId: string, details: Record<string, any>): Promise<OnChainRecord> {
    return this.anchorProof({
      record_type: RecordType.BOOKING_HASH,
      subject_id: bookingId,
      data: {
        booking_id: bookingId,
        status: 'completed',
        timestamp: new Date().toISOString(),
        ...details,
      },
    });
  }

  /**
   * Helper: Anchor payment
   */
  async anchorPayment(paymentId: string, details: Record<string, any>): Promise<OnChainRecord> {
    return this.anchorProof({
      record_type: RecordType.PAYMENT_HASH,
      subject_id: paymentId,
      data: {
        payment_id: paymentId,
        timestamp: new Date().toISOString(),
        ...details,
      },
    });
  }
}

export default new OnChainAnchorService();

