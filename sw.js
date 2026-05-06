// =====================================================================
// Service Worker · MKT para Eventos Médicos
// Estrategia:
//   - App shell (index.html, manifest, íconos) → Cache First
//   - Supabase API → Network First (nunca cachear datos sensibles)
//   - CDN externas (jsQR, Tesseract) → Stale While Revalidate
// =====================================================================

const CACHE_NAME = 'mkt-medico-v1';
const CACHE_VERSION = 1;

// Recursos que se cachean al instalar el SW (app shell)
const APP_SHELL = [
  '/',
  '/index.html',
  '/manifest.json',
  '/supabase.json',
  '/icons/icon-192.png',
  '/icons/icon-512.png',
];

// CDN externas que usamos (jsQR, Tesseract)
const CDN_ORIGINS = [
  'cdn.jsdelivr.net',
];

// Supabase — nunca cachear
const SUPABASE_ORIGINS = [
  'supabase.co',
];

// ===== Instalación: pre-cachear el app shell =====
self.addEventListener('install', event => {
  event.waitUntil(
    caches.open(CACHE_NAME).then(cache => {
      // Cachear lo que existe. Si un recurso falla, no bloquear la instalación.
      return Promise.allSettled(
        APP_SHELL.map(url =>
          cache.add(url).catch(e => console.warn('SW: no se pudo cachear', url, e.message))
        )
      );
    }).then(() => self.skipWaiting())
  );
});

// ===== Activación: limpiar caches viejas =====
self.addEventListener('activate', event => {
  event.waitUntil(
    caches.keys().then(keys =>
      Promise.all(
        keys
          .filter(key => key !== CACHE_NAME)
          .map(key => {
            console.log('SW: eliminando cache vieja:', key);
            return caches.delete(key);
          })
      )
    ).then(() => self.clients.claim())
  );
});

// ===== Fetch: estrategia según el origen =====
self.addEventListener('fetch', event => {
  const url = new URL(event.request.url);

  // Supabase → siempre Network, nunca cachear (datos sensibles y en tiempo real)
  if (SUPABASE_ORIGINS.some(o => url.hostname.includes(o))) {
    event.respondWith(fetch(event.request));
    return;
  }

  // Solo cachear GET
  if (event.request.method !== 'GET') {
    event.respondWith(fetch(event.request));
    return;
  }

  // CDN externas → Stale While Revalidate
  // Sirve desde cache mientras actualiza en background
  if (CDN_ORIGINS.some(o => url.hostname.includes(o))) {
    event.respondWith(staleWhileRevalidate(event.request));
    return;
  }

  // App shell (mismo origen) → Cache First con fallback a network
  if (url.origin === self.location.origin) {
    event.respondWith(cacheFirst(event.request));
    return;
  }

  // Todo lo demás → Network First
  event.respondWith(networkFirst(event.request));
});

// ===== Estrategias =====

// Cache First: sirve desde cache, si no hay va a la red y guarda
async function cacheFirst(request) {
  const cached = await caches.match(request);
  if (cached) return cached;
  try {
    const response = await fetch(request);
    if (response.ok) {
      const cache = await caches.open(CACHE_NAME);
      cache.put(request, response.clone());
    }
    return response;
  } catch (e) {
    // Sin red y sin cache → página de offline
    return offlineFallback();
  }
}

// Network First: va a la red, si falla sirve desde cache
async function networkFirst(request) {
  try {
    const response = await fetch(request);
    if (response.ok) {
      const cache = await caches.open(CACHE_NAME);
      cache.put(request, response.clone());
    }
    return response;
  } catch (e) {
    const cached = await caches.match(request);
    return cached || offlineFallback();
  }
}

// Stale While Revalidate: sirve desde cache Y actualiza en background
async function staleWhileRevalidate(request) {
  const cache = await caches.open(CACHE_NAME);
  const cached = await cache.match(request);

  const networkPromise = fetch(request).then(response => {
    if (response.ok) cache.put(request, response.clone());
    return response;
  }).catch(() => null);

  return cached || networkPromise;
}

// Página de offline cuando no hay nada en cache
function offlineFallback() {
  return new Response(
    `<!DOCTYPE html>
    <html lang="es-AR">
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <meta name="theme-color" content="#1F4E79">
      <title>Sin conexión · MKT Médico</title>
      <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
          font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
          background: #1F4E79;
          min-height: 100vh;
          display: flex;
          align-items: center;
          justify-content: center;
          padding: 24px;
        }
        .card {
          background: white;
          border-radius: 20px;
          padding: 40px 28px;
          max-width: 360px;
          width: 100%;
          text-align: center;
        }
        .icon { font-size: 64px; margin-bottom: 20px; }
        h1 { font-size: 24px; color: #1F4E79; margin-bottom: 12px; }
        p { font-size: 16px; color: #5C6573; line-height: 1.6; margin-bottom: 24px; }
        button {
          width: 100%;
          padding: 16px;
          font-size: 17px;
          font-weight: 600;
          background: #1F4E79;
          color: white;
          border: none;
          border-radius: 12px;
          cursor: pointer;
          min-height: 54px;
        }
      </style>
    </head>
    <body>
      <div class="card">
        <div class="icon">📡</div>
        <h1>Sin conexión</h1>
        <p>La app funciona offline para cargar leads. Conectate a internet para sincronizar con Supabase.</p>
        <button onclick="location.reload()">Reintentar</button>
      </div>
    </body>
    </html>`,
    {
      headers: { 'Content-Type': 'text/html; charset=utf-8' },
      status: 200
    }
  );
}

// ===== Mensajes desde el cliente =====
// El cliente puede forzar un update del SW
self.addEventListener('message', event => {
  if (event.data === 'SKIP_WAITING') {
    self.skipWaiting();
  }
  if (event.data === 'GET_VERSION') {
    event.source.postMessage({ type: 'VERSION', version: CACHE_VERSION, cache: CACHE_NAME });
  }
});
