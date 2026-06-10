-- Migration: WebAuthn credentials for biometric login (Touch ID / Face ID)
-- Stores public keys for passwordless authentication

CREATE TABLE IF NOT EXISTS webauthn_credentials (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    
    -- WebAuthn credential data
    credential_id TEXT NOT NULL UNIQUE,           -- Base64URL encoded credential ID
    public_key TEXT NOT NULL,                      -- Base64URL encoded public key
    counter BIGINT NOT NULL DEFAULT 0,             -- Signature counter (prevents replay attacks)
    
    -- Credential metadata
    device_type VARCHAR(50),                       -- 'singleDevice' or 'multiDevice'
    backed_up BOOLEAN DEFAULT false,               -- Whether credential is backed up (e.g., iCloud Keychain)
    transports TEXT[],                             -- Array of transports: 'usb', 'ble', 'nfc', 'internal'
    
    -- User-friendly naming
    friendly_name VARCHAR(255),                    -- e.g., "MacBook Touch ID", "iPhone Face ID"
    
    -- Audit fields
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    last_used_at TIMESTAMP WITH TIME ZONE,
    
    -- Each user can have multiple credentials (different devices)
    CONSTRAINT unique_credential_per_user UNIQUE(user_id, credential_id)
);

-- Indexes for efficient lookups
CREATE INDEX IF NOT EXISTS idx_webauthn_user ON webauthn_credentials(user_id);
CREATE INDEX IF NOT EXISTS idx_webauthn_credential_id ON webauthn_credentials(credential_id);

-- Add challenge storage to users table for WebAuthn flow
ALTER TABLE users ADD COLUMN IF NOT EXISTS webauthn_challenge TEXT;
ALTER TABLE users ADD COLUMN IF NOT EXISTS webauthn_challenge_expires_at TIMESTAMP WITH TIME ZONE;

