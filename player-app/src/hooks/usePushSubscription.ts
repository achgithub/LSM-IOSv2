import { useEffect, useState } from 'react';
import { API_BASE } from '../api';

// Player links are anonymous (the token in the URL is the credential — see
// player-app/README.md), so push subscriptions are keyed to the submission
// token rather than a user_id. This calls /s/:token/push/* on worker-api,
// which does not exist yet — it needs a token-keyed push_subscriptions table
// and matching routes before `enable()` will succeed. Until then this hook
// degrades safely: `enable()` throws internally and is swallowed, leaving
// `subscribed` false.
const supported = typeof window !== 'undefined' && 'serviceWorker' in navigator && 'PushManager' in window;

function b64urlToBytes(b64: string): Uint8Array {
  const padded = b64.replace(/-/g, '+').replace(/_/g, '/') + '='.repeat((4 - (b64.length % 4)) % 4);
  const binary = atob(padded);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

export function usePushSubscription(token: string | null) {
  const [permission, setPermission] = useState<NotificationPermission>(
    supported ? Notification.permission : 'denied'
  );
  const [subscribed, setSubscribed] = useState(false);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    if (!supported) return;
    navigator.serviceWorker.ready
      .then((reg) => reg.pushManager.getSubscription())
      .then((sub) => setSubscribed(!!sub))
      .catch(() => {});
  }, []);

  async function enable() {
    if (!supported || !token || busy) return;
    setBusy(true);
    try {
      const keyRes = await fetch(`${API_BASE}/s/${token}/push/vapid-public-key`);
      if (!keyRes.ok) throw new Error('Push not available yet');
      const { key } = (await keyRes.json()) as { key: string };
      const reg = await navigator.serviceWorker.ready;

      if (Notification.permission !== 'granted') {
        const perm = await Notification.requestPermission();
        setPermission(perm);
        if (perm !== 'granted') return;
      }

      let sub = await reg.pushManager.getSubscription();
      if (!sub) {
        sub = await reg.pushManager.subscribe({
          userVisibleOnly: true,
          applicationServerKey: b64urlToBytes(key).buffer.slice(0) as ArrayBuffer,
        });
      }

      const json = sub.toJSON() as { endpoint: string; keys: { p256dh: string; auth: string } };
      await fetch(`${API_BASE}/s/${token}/push/subscribe`, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ endpoint: json.endpoint, p256dh: json.keys.p256dh, auth: json.keys.auth }),
      });
      setPermission('granted');
      setSubscribed(true);
    } catch {
      // Non-fatal: push is an enhancement, not required for submitting picks.
    } finally {
      setBusy(false);
    }
  }

  async function disable() {
    if (!supported || !token || busy) return;
    setBusy(true);
    try {
      const reg = await navigator.serviceWorker.ready;
      const sub = await reg.pushManager.getSubscription();
      if (sub) {
        const json = sub.toJSON() as { endpoint: string; keys: { p256dh: string; auth: string } };
        await fetch(`${API_BASE}/s/${token}/push/subscribe`, {
          method: 'DELETE',
          headers: { 'content-type': 'application/json' },
          body: JSON.stringify({ endpoint: json.endpoint }),
        });
        await sub.unsubscribe();
      }
      setSubscribed(false);
    } catch {
      // Non-fatal
    } finally {
      setBusy(false);
    }
  }

  return { supported, permission, subscribed, busy, enable, disable };
}
