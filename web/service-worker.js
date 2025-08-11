self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open('v1').then((cache) => {
      return cache.addAll([
        '/',
        '/index.html',
        '/main.dart.js',
        '/manifest.json',
        '/flutter.js',
        '/flutter_service_worker.js',
        '/favicon.png',
        '/icons/icon-192.png',
        '/icons/icon-512.png',
        '/assets/fonts/MaterialIcons-Regular.otf',
        '/assets/packages/cupertino_icons/assets/CupertinoIcons.ttf'
      ]);
    })
  );
});

self.addEventListener('fetch', (event) => {
  if (event.request.url.indexOf('firebasestorage.googleapis.com') !== -1) {
    // Для файлов Firebase используем сеть с fallback на кеш
    event.respondWith(
      fetch(event.request).catch(() => caches.match(event.request))
    );
  } else {
    // Для остальных ресурсов используем кеш с fallback на сеть
    event.respondWith(
      caches.match(event.request).then((response) => {
        return response || fetch(event.request);
      })
    );
  }
  // Для изображений Supabase - обходим кеш
  if (event.request.url.includes('supabase.co/storage')) {
    event.respondWith(
      fetch(event.request, {cache: 'no-store'})
    );
  } else {
    event.respondWith(
      caches.match(event.request)
        .then(cached => cached || fetch(event.request))
    );
  }
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((cacheNames) => {
      return Promise.all(
        cacheNames.map((cacheName) => {
          if (cacheName !== 'v1') {
            return caches.delete(cacheName);
          }
        })
      );
    })
  );
});

// Фоновое обновление контента
self.addEventListener('periodicsync', (event) => {
  if (event.tag === 'update-content') {
    event.waitUntil(updateContent());
  }
});

async function updateContent() {
  // Здесь можно добавить логику обновления контента
  console.log('Updating content in background...');
}