import { useEffect, useRef, useState } from 'react';

export function useUpdateAvailable() {
  const [updateAvailable, setUpdateAvailable] = useState(false);
  const registration = useRef<ServiceWorkerRegistration | null>(null);
  const waitingWorker = useRef<ServiceWorker | null>(null);
  const reloading = useRef(false);

  useEffect(() => {
    if (!('serviceWorker' in navigator)) return;

    navigator.serviceWorker.addEventListener('controllerchange', () => {
      if (reloading.current) return;
      reloading.current = true;
      window.location.reload();
    });

    navigator.serviceWorker.ready.then((reg) => {
      registration.current = reg;

      // A worker can already be waiting from before this page load (e.g. an
      // update landed while the app was in the background).
      if (reg.waiting) {
        waitingWorker.current = reg.waiting;
        setUpdateAvailable(true);
      }

      reg.addEventListener('updatefound', () => {
        const newWorker = reg.installing;
        if (!newWorker) return;
        newWorker.addEventListener('statechange', () => {
          if (newWorker.state === 'installed' && navigator.serviceWorker.controller) {
            waitingWorker.current = newWorker;
            setUpdateAvailable(true);
          }
        });
      });
    });

    // The browser only checks sw.js for changes on its own schedule, which
    // can be hours away — so a session left open (or just backgrounded and
    // brought back) can sit on stale code indefinitely otherwise. Asking
    // explicitly here is a static-asset fetch against our own Pages host,
    // not worker-api, so it costs nothing extra on the backend.
    function checkOnForeground() {
      if (document.visibilityState === 'visible') registration.current?.update();
    }
    document.addEventListener('visibilitychange', checkOnForeground);
    window.addEventListener('focus', checkOnForeground);
    return () => {
      document.removeEventListener('visibilitychange', checkOnForeground);
      window.removeEventListener('focus', checkOnForeground);
    };
  }, []);

  function applyUpdate() {
    waitingWorker.current?.postMessage('SKIP_WAITING');
  }

  // Second natural trigger point: piggybacks on the existing manual refresh
  // action rather than adding a new one.
  function checkForUpdate() {
    registration.current?.update();
  }

  return { updateAvailable, applyUpdate, checkForUpdate };
}
