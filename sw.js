// SwimFitPro Service Worker
const CACHE_NAME = 'swimfitpro-v65';
const CACHE_URLS = [
  './index.html',
  './icons/Icon-513.jpeg',
];

// Install: cache core assets
self.addEventListener('install', event => {
  event.waitUntil(
    caches.open(CACHE_NAME).then(cache => cache.addAll(CACHE_URLS))
  );
  self.skipWaiting();
});

// Activate: clean up old caches and immediately take control of all clients
self.addEventListener('activate', event => {
  event.waitUntil(
    caches.keys().then(keys =>
      Promise.all(keys.filter(k => k !== CACHE_NAME).map(k => caches.delete(k)))
    )
  );
  self.clients.claim();
});

// Fetch strategy:
// - index.html → network-first (always get latest, fall back to cache if offline)
// - everything else → cache-first (fast, fall back to network)
self.addEventListener('fetch', event => {
  if (event.request.method !== 'GET') return;

  const url = new URL(event.request.url);
  const isNavigation = event.request.mode === 'navigate' ||
    url.pathname === '/' ||
    url.pathname.endsWith('/index.html') ||
    url.pathname.endsWith('/');

  if (isNavigation) {
    // Network-first for the app shell — always get fresh HTML
    event.respondWith(
      fetch(event.request).then(response => {
        if (response && response.status === 200) {
          const clone = response.clone();
          caches.open(CACHE_NAME).then(cache => cache.put(event.request, clone));
        }
        return response;
      }).catch(() => {
        // Offline fallback
        return caches.match('./index.html');
      })
    );
  } else {
    // Cache-first for all other assets (icons, images, etc.)
    event.respondWith(
      caches.match(event.request).then(cached => {
        if (cached) return cached;
        return fetch(event.request).then(response => {
          if (response && response.status === 200) {
            const ext = url.pathname.split('.').pop().toLowerCase();
            if (['js','css','jpeg','jpg','png','svg','woff','woff2'].includes(ext)) {
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
