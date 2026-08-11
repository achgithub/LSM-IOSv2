// D1 persistence for attested devices (attest_devices table). Kept separate from
// attest.ts so the crypto stays pure/testable; this is the only place the device
// public key + monotonic counter are read/written.

import type { AttestEnvironment } from "./attest";

export interface AttestDevice {
  keyId: string;
  publicKey: string; // base64 raw P-256 point
  signCount: number;
  environment: AttestEnvironment;
  managerToken?: string | null;
}

interface DeviceRow {
  key_id: string;
  public_key: string;
  sign_count: number;
  environment: string;
}

export async function getDevice(db: D1Database, keyId: string): Promise<AttestDevice | null> {
  const row = await db
    .prepare("SELECT key_id, public_key, sign_count, environment FROM attest_devices WHERE key_id = ?")
    .bind(keyId)
    .first<DeviceRow>();
  if (!row) return null;
  return {
    keyId: row.key_id,
    publicKey: row.public_key,
    signCount: row.sign_count,
    environment: row.environment as AttestEnvironment,
  };
}

export async function insertDevice(db: D1Database, device: AttestDevice): Promise<void> {
  const now = new Date().toISOString();
  const managerToken = device.managerToken ?? null;
  // ON CONFLICT: re-registration of the same key (e.g. after the client lost its
  // local state) overwrites — the attestation was just cryptographically verified,
  // and the counter legitimately resets with a new attested key.
  await db
    .prepare(
      `INSERT INTO attest_devices (key_id, public_key, sign_count, environment, manager_token, created_at, updated_at)
       VALUES (?, ?, ?, ?, ?, ?, ?)
       ON CONFLICT(key_id) DO UPDATE SET
         public_key = excluded.public_key, sign_count = excluded.sign_count,
         environment = excluded.environment,
         manager_token = COALESCE(attest_devices.manager_token, excluded.manager_token),
         updated_at = excluded.updated_at`,
    )
    .bind(device.keyId, device.publicKey, device.signCount, device.environment, managerToken, now, now)
    .run();
}

export async function updateSignCount(
  db: D1Database,
  keyId: string,
  signCount: number,
): Promise<void> {
  await db
    .prepare("UPDATE attest_devices SET sign_count = ?, updated_at = ? WHERE key_id = ?")
    .bind(signCount, new Date().toISOString(), keyId)
    .run();
}
