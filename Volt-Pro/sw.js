const CACHE = 'volt-pro-assetsindexBTyhLtDcssassetsindexBiFy5UR1js';
const BASE = "/Volt-Pro/";
const PRECACHE = ["/Volt-Pro/","/Volt-Pro/index.html","/Volt-Pro/manifest.json","/Volt-Pro/volt-logo.png","/Volt-Pro/volt-mark.svg","/Volt-Pro/icons/icon-180.png","/Volt-Pro/icons/icon-192.png","/Volt-Pro/icons/icon-512.png","/Volt-Pro/assets/index-BiFy5UR1.js","/Volt-Pro/assets/index-BTyhL_tD.css"];
self.addEventListener('install', (event) => {
  event.waitUntil(caches.open(CACHE).then((cache) => cache.addAll(PRECACHE)).then(() => self.skipWaiting()));
});
self.addEventListener('activate', (event) => {
  event.waitUntil(caches.keys().then((keys) => Promise.all(keys.filter((key) => key.startsWith('volt-pro-') && key !== CACHE).map((key) => caches.delete(key)))).then(() => self.clients.claim()));
});
self.addEventListener('fetch', (event) => {
  if (event.request.method !== 'GET' || new URL(event.request.url).origin !== self.location.origin) return;
  if (event.request.mode === 'navigate') {
    event.respondWith(fetch(event.request, { cache: 'no-store' }).then((response) => {
      if (response.ok) caches.open(CACHE).then((cache) => cache.put(BASE + 'index.html', response.clone()));
      return response;
    }).catch(async () => (await caches.match(BASE + 'index.html')) || Response.error()));
    return;
  }
  event.respondWith(caches.match(event.request).then((cached) => cached || fetch(event.request).then((response) => {
    if (response.ok) caches.open(CACHE).then((cache) => cache.put(event.request, response.clone()));
    return response;
  })));
});