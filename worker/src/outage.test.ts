import { Hono } from "hono";
import { describe, expect, it } from "vitest";
import { getOutageFlag, outageGate, setOutageFlag } from "./outage";

// Minimal in-memory KV stand-in — only the get/put shape outage.ts uses.
function fakeKV(): KVNamespace {
  const store = new Map<string, string>();
  return {
    get: async (key: string) => store.get(key) ?? null,
    put: async (key: string, value: string) => void store.set(key, value),
  } as unknown as KVNamespace;
}

function buildApp() {
  const app = new Hono<{ Bindings: { SCORES: KVNamespace } }>();
  app.get("/health", (c) => c.json({ ok: true }));
  app.use("*", outageGate);
  app.get("/leagues/PL/scores", (c) => c.json({ ok: true }));
  app.get("/admin/leagues", (c) => c.json({ ok: true }));
  return app;
}

describe("outage flag storage", () => {
  it("defaults to off when unset", async () => {
    expect(await getOutageFlag(fakeKV())).toEqual({ on: false });
  });

  it("round-trips on + message", async () => {
    const kv = fakeKV();
    await setOutageFlag(kv, true, "back in 10 minutes");
    expect(await getOutageFlag(kv)).toEqual({ on: true, message: "back in 10 minutes" });
  });

  it("round-trips off", async () => {
    const kv = fakeKV();
    await setOutageFlag(kv, true, "x");
    await setOutageFlag(kv, false);
    expect((await getOutageFlag(kv)).on).toBe(false);
  });
});

describe("outageGate middleware", () => {
  it("lets data routes through when the flag is off", async () => {
    const kv = fakeKV();
    const app = buildApp();
    const res = await app.request("/leagues/PL/scores", {}, { SCORES: kv });
    expect(res.status).toBe(200);
  });

  it("503s data routes when the flag is on", async () => {
    const kv = fakeKV();
    await setOutageFlag(kv, true, "down for a bit");
    const app = buildApp();
    const res = await app.request("/leagues/PL/scores", {}, { SCORES: kv });
    expect(res.status).toBe(503);
    expect(await res.json()).toEqual({ error: "maintenance", message: "down for a bit" });
  });

  it("still serves /health when the flag is on", async () => {
    const kv = fakeKV();
    await setOutageFlag(kv, true, "down");
    const app = buildApp();
    const res = await app.request("/health", {}, { SCORES: kv });
    expect(res.status).toBe(200);
  });

  it("still serves /admin/* when the flag is on", async () => {
    const kv = fakeKV();
    await setOutageFlag(kv, true, "down");
    const app = buildApp();
    const res = await app.request("/admin/leagues", {}, { SCORES: kv });
    expect(res.status).toBe(200);
  });
});
