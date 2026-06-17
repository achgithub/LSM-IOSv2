import { describe, expect, it } from "vitest";
import { issueChallenge, verifyChallenge } from "./attest";

const SECRET = "test-challenge-secret-do-not-ship";
const MAX_AGE = 5 * 60_000;

describe("App Attest stateless challenges", () => {
  it("verifies a freshly issued challenge", async () => {
    const challenge = await issueChallenge(SECRET);
    expect(await verifyChallenge(SECRET, challenge, MAX_AGE)).toBe(true);
  });

  it("rejects a challenge signed with a different secret", async () => {
    const challenge = await issueChallenge(SECRET);
    expect(await verifyChallenge("other-secret", challenge, MAX_AGE)).toBe(false);
  });

  it("rejects a tampered payload (HMAC no longer matches)", async () => {
    const challenge = await issueChallenge(SECRET);
    const [v, nonce, ts, mac] = challenge.split(".");
    const tampered = [v, nonce, String(Number(ts) + 1), mac].join(".");
    expect(await verifyChallenge(SECRET, tampered, MAX_AGE)).toBe(false);
  });

  it("rejects an expired challenge", async () => {
    const challenge = await issueChallenge(SECRET);
    // maxAge of 0 → anything older than "now" is expired.
    expect(await verifyChallenge(SECRET, challenge, -1)).toBe(false);
  });

  it("rejects malformed input", async () => {
    expect(await verifyChallenge(SECRET, "not-a-challenge", MAX_AGE)).toBe(false);
    expect(await verifyChallenge(SECRET, "", MAX_AGE)).toBe(false);
    expect(await verifyChallenge(SECRET, "v2.abc.123.bWFj", MAX_AGE)).toBe(false);
  });

  it("issues unique challenges", async () => {
    const a = await issueChallenge(SECRET);
    const b = await issueChallenge(SECRET);
    expect(a).not.toBe(b);
  });
});
