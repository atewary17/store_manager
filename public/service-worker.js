// Store Manager — PWA service worker (PWA-lite).
//
// Strategy (deliberately conservative for a multi-tenant, transactional ERP):
//   • Navigations  → network-first, fall back to a cached offline page when
//     truly offline. HTML is NEVER served stale (avoids wrong-tenant / stale data).
//   • Static assets (icons, /vendor/, fingerprinted /assets/) → cache-first
//     (stale-while-revalidate) for instant loads.
//   • Everything else (APIs, POSTs, cross-origin) → straight to network.
//
// Bump CACHE_VERSION to force clients to drop old caches.
const CACHE_VERSION = 'sm-v1';
const APP_SHELL = `${CACHE_VERSION}-shell`;
const ASSETS    = `${CACHE_VERSION}-assets`;

const PRECACHE = [
  '/offline.html',
  '/icon-192.png',
  '/icon-512.png',
  '/manifest.json'
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(APP_SHELL).then((cache) => cache.addAll(PRECACHE)).then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((keys) => Promise.all(
      keys.filter((k) => !k.startsWith(CACHE_VERSION)).map((k) => caches.delete(k))
    )).then(() => self.clients.claim())
  );
});

function isCacheableAsset(url) {
  return url.origin === self.location.origin && (
    url.pathname.startsWith('/vendor/') ||
    url.pathname.startsWith('/assets/') ||
    /\/icon-\d+\.png$/.test(url.pathname) ||
    url.pathname === '/manifest.json'
  );
}

self.addEventListener('fetch', (event) => {
  const req = event.request;
  if (req.method !== 'GET') return;               // never touch POST/PATCH/etc.

  const url = new URL(req.url);

  // 1) Page navigations → network-first, offline fallback.
  if (req.mode === 'navigate') {
    event.respondWith(
      fetch(req).catch(() => caches.match('/offline.html'))
    );
    return;
  }

  // 2) Static assets → cache-first, then refresh in background.
  if (isCacheableAsset(url)) {
    event.respondWith(
      caches.match(req).then((cached) => {
        const network = fetch(req).then((res) => {
          if (res && res.status === 200) {
            const copy = res.clone();
            caches.open(ASSETS).then((c) => c.put(req, copy));
          }
          return res;
        }).catch(() => cached);
        return cached || network;
      })
    );
    return;
  }

  // 3) Everything else → network (no caching).
});
