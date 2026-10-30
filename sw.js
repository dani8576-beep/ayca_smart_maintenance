const CACHE = 'ayca-v23';  // ← incrementar al desplegar cambios

const LOCAL = [
  'index.html',
  'css/styles.css',
  'js/app.js',
  'js/mediciones.js',
  'js/grafico.js',
  'js/pdf.js',
  'js/database.js',
  'js/historial.js',
  'js/utils.js',
  'js/permisos.js',
  'js/carbones.js',
  'js/ventilador.js',
  'js/sync.js',
  'js/bodega.js',
  'js/eventos.js',
  'js/ordenTrabajo.js',
  'js/usuarios.js'
];

// Instalar: cachear archivos locales
self.addEventListener('install', e => {
  e.waitUntil(
    caches.open(CACHE)
      .then(cache => cache.addAll(LOCAL))
      .then(() => self.skipWaiting())
  );
});

// Activar: limpiar caches viejas
self.addEventListener('activate', e => {
  e.waitUntil(
    caches.keys()
      .then(keys => Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

// Fetch: estrategia por tipo de recurso
self.addEventListener('fetch', e => {
  const url = new URL(e.request.url);

  // Supabase REST API → solo red (nunca cachear respuestas de datos)
  if (url.hostname.includes('supabase.co') && url.pathname.startsWith('/rest/')) return;

  // Archivos locales → Cache First (se actualizan con nueva versión de caché)
  if (url.origin === self.location.origin) {
    e.respondWith(
      caches.match(e.request).then(cached => {
        if (cached) return cached;
        return fetch(e.request).then(res => {
          caches.open(CACHE).then(c => c.put(e.request, res.clone()));
          return res;
        });
      })
    );
    return;
  }

  // CDN (jsPDF, Supabase SDK) → Red primero, caché como respaldo
  e.respondWith(
    fetch(e.request)
      .then(res => {
        caches.open(CACHE).then(c => c.put(e.request, res.clone()));
        return res;
      })
      .catch(() => caches.match(e.request))
  );
});
