// D1 persistence for accounts/account_links (email registration for device
// recovery). Kept separate from otp.ts/email.ts the same way attest-store.ts
// is kept separate from attest.ts — this is the only place these two tables
// are read/written. Not shard-routed; see schema.sql's comment on why.

export interface Account {
  accountUuid: string;
  email: string;
  activeKeyId: string;
  activeDeviceLabel: string | null;
  createdAt: string;
}

interface AccountRow {
  account_uuid: string;
  email: string;
  active_key_id: string;
  active_device_label: string | null;
  created_at: string;
}

function fromRow(row: AccountRow): Account {
  return {
    accountUuid: row.account_uuid,
    email: row.email,
    activeKeyId: row.active_key_id,
    activeDeviceLabel: row.active_device_label,
    createdAt: row.created_at,
  };
}

export async function getAccountByEmail(db: D1Database, email: string): Promise<Account | null> {
  const row = await db
    .prepare("SELECT account_uuid, email, active_key_id, active_device_label, created_at FROM accounts WHERE email = ?")
    .bind(email)
    .first<AccountRow>();
  return row ? fromRow(row) : null;
}

// Resolves an account (and its active_key_id) from a manager_token — the
// register-guard check inside POST /attest/register uses this to decide
// whether an incoming keyId is allowed to become the active device.
export async function getAccountLinkByManagerToken(
  db: D1Database,
  managerToken: string,
): Promise<Account | null> {
  const row = await db
    .prepare(
      `SELECT a.account_uuid, a.email, a.active_key_id, a.active_device_label, a.created_at
       FROM accounts a
       JOIN account_links l ON l.account_uuid = a.account_uuid
       WHERE l.manager_token = ?`,
    )
    .bind(managerToken)
    .first<AccountRow>();
  return row ? fromRow(row) : null;
}

// Resolves the manager_token(s) linked to an email — used by
// POST /account/link-device/request to find what a recovering device
// should be handed once OTP proves ownership.
export async function getManagerTokensByEmail(db: D1Database, email: string): Promise<string[]> {
  const rows = await db
    .prepare(
      `SELECT l.manager_token FROM account_links l
       JOIN accounts a ON a.account_uuid = l.account_uuid
       WHERE a.email = ?`,
    )
    .bind(email)
    .all<{ manager_token: string }>();
  return (rows.results ?? []).map((r) => r.manager_token);
}

export async function upsertAccount(
  db: D1Database,
  params: { accountUuid: string; email: string; activeKeyId: string; activeDeviceLabel?: string | null },
): Promise<void> {
  const now = new Date().toISOString();
  await db
    .prepare(
      `INSERT INTO accounts (account_uuid, email, active_key_id, active_device_label, created_at)
       VALUES (?, ?, ?, ?, ?)
       ON CONFLICT(email) DO UPDATE SET active_key_id = excluded.active_key_id,
         active_device_label = excluded.active_device_label`,
    )
    .bind(params.accountUuid, params.email, params.activeKeyId, params.activeDeviceLabel ?? null, now)
    .run();
}

export async function linkAccount(
  db: D1Database,
  params: { accountUuid: string; managerToken: string },
): Promise<void> {
  const now = new Date().toISOString();
  await db
    .prepare(
      `INSERT INTO account_links (account_uuid, manager_token, linked_at)
       VALUES (?, ?, ?)
       ON CONFLICT(account_uuid, manager_token) DO NOTHING`,
    )
    .bind(params.accountUuid, params.managerToken, now)
    .run();
}

export async function setActiveKeyId(db: D1Database, accountUuid: string, keyId: string): Promise<void> {
  await db
    .prepare("UPDATE accounts SET active_key_id = ? WHERE account_uuid = ?")
    .bind(keyId, accountUuid)
    .run();
}
