const VERSION = "3260968";
const CACHE = 'volt-pro-' + VERSION;
const BASE = "/Volt-Pro/";
const PRECACHE = ["/Volt-Pro/","/Volt-Pro/index.html","/Volt-Pro/manifest.json","/Volt-Pro/volt-logo.png","/Volt-Pro/volt-mark.svg","/Volt-Pro/icons/icon-180.png","/Volt-Pro/icons/icon-192.png","/Volt-Pro/icons/icon-512.png","/Volt-Pro/assets/index-meIjOdQT.js","/Volt-Pro/assets/index-C1uGz2I1.css"];
// Fichiers non haches : leur contenu change sans que l'URL bouge, donc ils
// doivent toujours etre redemandes au reseau en premier.
const NETWORK_FIRST = [BASE, BASE + 'index.html', BASE + 'manifest.json'];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE)
      .then((cache) => cache.addAll(PRECACHE))
      // Un cache incomplet ne doit pas empecher l'installation : l'app
      // fonctionne en ligne et se completera au prochain passage.
      .catch(() => undefined)
      .then(() => self.skipWaiting()),
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys()
      // Seuls les caches Volt Pro sont touches. Les donnees IndexedDB de
      // l'utilisateur ne sont jamais concernees par cette purge.
      .then((keys) => Promise.all(keys.filter((key) => key.startsWith('volt-pro-') && key !== CACHE).map((key) => caches.delete(key))))
      .then(() => self.clients.claim()),
  );
});

self.addEventListener('message', (event) => {
  if (event.data === 'volt-skip-waiting') self.skipWaiting();
  if (event.data === 'volt-version') event.source && event.source.postMessage({ type: 'volt-version', version: VERSION });
});

async function networkFirst(request, cacheKey) {
  try {
    const response = await fetch(request, { cache: 'no-store' });
    if (response && response.ok) {
      const cache = await caches.open(CACHE);
      await cache.put(cacheKey, response.clone());
    }
    return response;
  } catch (error) {
    const cached = await caches.match(cacheKey);
    if (cached) return cached;
    throw error;
  }
}

async function cacheFirst(request) {
  const cached = await caches.match(request);
  if (cached) return cached;
  const response = await fetch(request);
  if (response && response.ok && response.type === 'basic') {
    const cache = await caches.open(CACHE);
    await cache.put(request, response.clone());
  }
  return response;
}

self.addEventListener('fetch', (event) => {
  const request = event.request;
  if (request.method !== 'GET') return;
  const url = new URL(request.url);
  if (url.origin !== self.location.origin) return;
  // Le script du worker ne doit jamais etre servi depuis le cache : une copie
  // figee ferait croire que la version deployee est l ancienne.
  if (url.pathname === BASE + 'sw.js') return;

  if (request.mode === 'navigate') {
    event.respondWith(networkFirst(request, BASE + 'index.html').catch(async () => (await caches.match(BASE + 'index.html')) || Response.error()));
    return;
  }
  if (NETWORK_FIRST.includes(url.pathname)) {
    event.respondWith(networkFirst(request, url.pathname));
    return;
  }
  // Les assets Vite portent un hash de contenu : immuables, donc cache-first.
  event.respondWith(cacheFirst(request));
});