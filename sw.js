// SwimFitPro Service Worker
//
// Delivery contract: the app is one HTML file, and it must never be served stale.
// index.html is always fetched from the network and is never cached, so a deploy
// reaches a returning user on their next load. Only static binary assets (icons)
// are cached, for offline/speed — they are content-addressed by filename and
// rarely change.
//
// BUMP CACHE_VERSION on every deploy that changes this file. Changing the string
// changes the worker's bytes, which is what makes the browser install the new
// worker, run activate (clearing stale caches from any older worker), and hand
// control to it. A prior worker that cached index.html is how users got stuck on
// old code; a clean version bump plus skipWaiting/claim evicts it.
const CACHE_VERSION = 'v129';
const CACHE_NAME = 'swimfitpro-' + CACHE_VERSION;
const ASSET_URLS = [
  './icons/Icon-513.jpeg',
  // index.html is intentionally NOT here — it is always network-fetched.
];

// The page can tell a waiting worker to activate immediately.
self.addEventListener('message', event => {
  if (event.data && event.data.type === 'SKIP_WAITING') self.skipWaiting();
});

// Install: pre-cache static assets, then WAIT.
// Deliberately no skipWaiting() here. A new worker installs and then waits, so the
// page can show its tap-to-refresh bar and the swimmer chooses when to update —
// never a reload dropped on them mid-set. skipWaiting fires only when the page
// posts SKIP_WAITING from that button (see the message handler above). On a
// first-ever install there is no active worker to wait behind, so this still
// activates immediately.
self.addEventListener('install', event => {
  event.waitUntil(
    caches.open(CACHE_NAME)
      .then(cache => cache.addAll(ASSET_URLS))
      .catch(() => {}) // a missing asset must not block install
  );
});

// Activate: delete only OTHER caches (never the one install just filled), then
// take control of open pages so the new worker is authoritative immediately.
self.addEventListener('activate', event => {
  event.waitUntil(
    caches.keys()
      .then(keys => Promise.all(keys.filter(k => k !== CACHE_NAME).map(k => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', event => {
  if (event.request.method !== 'GET') return;
  const url = new URL(event.request.url);
  const isNavigation = event.request.mode === 'navigate' ||
    url.pathname.endsWith('/') ||
    url.pathname.endsWith('/index.html');

  if (isNavigation) {
    // App shell: network-first, cache bypassed both ways. Fall back to any cached
    // copy only when genuinely offline.
    event.respondWith(
      fetch(event.request, { cache: 'no-store' }).catch(() => caches.match('./index.html'))
    );
    return;
  }

  // Static assets: cache-first for speed, populate on first fetch.
  event.respondWith(
    caches.match(event.request).then(cached => {
      if (cached) return cached;
      return fetch(event.request).then(response => {
        if (response && response.status === 200) {
          const ext = url.pathname.split('.').pop().toLowerCase();
          if (['jpeg','jpg','png','svg','woff','woff2','ico'].includes(ext)) {
            const clone = response.clone();
            caches.open(CACHE_NAME).then(cache => cache.put(event.request, clone));
          }
        }
        return response;
      }).catch(() => cached || null);
    })
  );
});
