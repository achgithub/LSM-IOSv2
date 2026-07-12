/// <reference lib="webworker" />
import { precacheAndRoute } from 'workbox-precaching';

declare const self: ServiceWorkerGlobalScope;

precacheAndRoute(self.__WB_MANIFEST);

// A new SW normally sits in "waiting" until every tab closes. This lets the
// page (useUpdateAvailable's applyUpdate) force it to activate immediately
// instead of making the player close the app to get the update.
self.addEventListener('message', (event) => {
  if (event.data === 'SKIP_WAITING') self.skipWaiting();
});
