// SwimFitPro Service Worker
const CACHE_NAME = 'swimfitpro-v102';
const CACHE_URLS = [
  './icons/Icon-513.jpeg',
  // index.html intentionally excluded — always fetched fresh from network
];

// Allow page to trigger immediate activation
self.addEventListener('message', event => {
  if(event.data && event.data.type === 'SKIP_WAITING') self.skipWaiting();
});

// Install: cache only non-HTML assets; skip waiting immediately
self.addEventListener('install', event => {
  event.waitUntil(
    caches.open(CACHE_NAME).then(cache => cache.addAll(CACHE_URLS))
  );
  self.skipWaiting();
});

// Activate: wipe ALL old caches, claim all clients immediately
self.addEventListener('activate', event => {
  event.waitUntil(
    caches.keys().then(keys =>
      Promise.all(keys.map(k => caches.delete(k))) // delete everything, including current
    ).then(() => caches.open(CACHE_NAME)) // re-open clean cache
  );
  self.clients.claim();
});

// Fetch strategy:
// - index.html / navigation → always network, no-cache headers, never serve from cache
// - everything else → cache-first (fast, fall back to network)
self.addEventListener('fetch', event => {
  if (event.request.method !== 'GET') return;

  const url = new URL(event.request.url);
  const isNavigation = event.request.mode === 'navigate' ||
    url.pathname === '/' ||
    url.pathname.endsWith('/index.html') ||
    url.pathname.endsWith('/');

  if (isNavigation) {
    // Always fetch HTML fresh — bypass both SW cache and browser cache
    event.respondWith(
      fetch(event.request, { cache: 'no-store' }).then(response => {
        return response;
      }).catch(() => {
        // Offline only: fall back to cached copy if available
        return caches.match('./index.html');
      })
    );
  } else {
    // Cache-first for static assets (icons, images, etc.)
    event.respondWith(
      caches.match(event.request).then(cached => {
        if (cached) return cached;
        return fetch(event.request).then(response => {
          if (response && response.status === 200) {
            const ext = url.pathname.split('.').pop().toLowerCase();
            if (['jpeg','jpg','png','svg','woff','woff2'].includes(ext)) {
              const clone = response.clone();
              caches.open(CACHE_NAME).then(cache => cache.put(event.request, clone));
            }
          }
          return response;
        }).catch(() => null);
      })
    );
  }
});
