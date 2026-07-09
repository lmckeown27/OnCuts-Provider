import { Request, Response, NextFunction } from 'express';
import { OAuth2Client } from 'google-auth-library';
import { jwtToAddress } from '@mysten/sui/zklogin';
import { pool } from '../database/connection';
import { ApiError } from '../middleware/errorHandler';
import { AuthRequest } from '../middleware/auth';
import { deriveZkLoginSalt, deriveZkLoginSaltFromGoogleSub } from '../services/salt.service';
import { logger } from '../utils/logger';

const googleOauth = new OAuth2Client();

/**
 * Return deterministic salt for zkLogin (JWT iss + sub on wire; derivation uses sub + MASTER_SEED).
 */
export async function postZkLoginSalt(req: Request, res: Response, next: NextFunction) {
  try {
    const { iss, sub } = req.body as { iss?: string; sub?: string };
    if (!iss || !sub) {
      throw new ApiError(400, 'iss and sub required');
    }
    const salt = deriveZkLoginSalt(iss, sub);
    res.json({ success: true, salt });
  } catch (e) {
    next(e);
  }
}

/**
 * Verify Google `id_token`, derive salt + Sui zkLogin address with @mysten/sui/zklogin, persist.
 * Requires `GOOGLE_OAUTH_WEB_CLIENT_ID` matching the web app `VITE_GOOGLE_OAUTH_CLIENT_ID`.
 */
export async function postZkLoginGoogleComplete(req: AuthRequest, res: Response, next: NextFunction) {
  try {
    const userId = req.user!.userId;
    const { idToken } = req.body as { idToken?: string };
    if (!idToken?.trim()) {
      throw new ApiError(400, 'idToken required');
    }

    const audience = process.env.GOOGLE_OAUTH_WEB_CLIENT_ID?.trim();
    if (!audience) {
      throw new ApiError(500, 'GOOGLE_OAUTH_WEB_CLIENT_ID is not configured');
    }

    let ticket;
    try {
      ticket = await googleOauth.verifyIdToken({
        idToken: idToken.trim(),
        audience,
      });
    } catch {
      throw new ApiError(401, 'Invalid or expired Google token');
    }

    const payload = ticket.getPayload();
    if (!payload?.sub) {
      throw new ApiError(400, 'Invalid Google token payload');
    }

    const saltStr = deriveZkLoginSaltFromGoogleSub(payload.sub);
    const suiAddress = jwtToAddress(idToken.trim(), saltStr, false);

    await pool.query(
      `UPDATE users SET sui_address = $1, zk_login_salt = $2, "updatedAt" = NOW() WHERE id = $3`,
      [suiAddress, saltStr, userId]
    );

    logger.info('User linked zkLogin Sui address (native Google + salt)', { userId });

    res.json({ success: true, suiAddress });
  } catch (e) {
    next(e);
  }
}

/** Persist zkLogin Sui address for the authenticated user (barber or consumer). */
export async function putZkLoginAddress(req: AuthRequest, res: Response, next: NextFunction) {
  try {
    const userId = req.user!.userId;
    const { suiAddress, zkLoginSalt } = req.body as {
      suiAddress?: string;
      zkLoginSalt?: string;
    };
    if (!suiAddress || !/^0x[0-9a-fA-F]{64}$/.test(suiAddress)) {
      throw new ApiError(400, 'Valid suiAddress (0x + 64 hex) required');
    }

    await pool.query(
      `UPDATE users SET sui_address = $1, zk_login_salt = COALESCE($2, zk_login_salt), "updatedAt" = NOW() WHERE id = $3`,
      [suiAddress, zkLoginSalt || null, userId]
    );

    logger.info('User linked zkLogin Sui address', { userId });

    res.json({ success: true, suiAddress });
  } catch (e) {
    next(e);
  }
}
