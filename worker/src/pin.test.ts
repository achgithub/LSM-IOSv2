import { describe, expect, it } from "vitest";
import { hashPin, makeSalt, verifyPin } from "./pin";

describe("Cloud Publish PIN hashing", () => {
  it("verifies the correct PIN against its own salt+hash", async () => {
    const salt = makeSalt();
    const hash = await hashPin("4242", salt);
    expect(await verifyPin("4242", salt, hash)).toBe(true);
  });

  it("rejects the wrong PIN", async () => {
    const salt = makeSalt();
    const hash = await hashPin("4242", salt);
    expect(await verifyPin("0000", salt, hash)).toBe(false);
  });

  it("hashes the same PIN differently per salt (no shared rainbow-table hit)", async () => {
    const a = await hashPin("1234", makeSalt());
    const b = await hashPin("1234", makeSalt());
    expect(a).not.toBe(b);
  });

  it("produces unique salts", () => {
    expect(makeSalt()).not.toBe(makeSalt());
  });
});
