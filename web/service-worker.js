const CACHE_NAME = 'tankograd-v1';
const urlsToCache = [
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
];

self.addEventListener('install', (event) => {
  self.skipWaiting(); // Немедленная активация нового сервис-воркера
  
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => {
      return cache.addAll(urlsToCache);
    })
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((cacheNames) => {
      return Promise.all(
        cacheNames.map((cacheName) => {
          if (cacheName !== CACHE_NAME) {
            return caches.delete(cacheName);
          }
        })
      );
    }).then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (event) => {
  // Для файлов Firebase Storage и Supabase Storage - обходим кеш
  if (event.request.url.indexOf('firebasestorage.googleapis.com') !== -1 ||
      event.request.url.includes('supabase.co/storage')) {
    event.respondWith(
      fetch(event.request, {cache: 'no-store'})
    );
    return;
  }
  
  // Для статических ресурсов приложения - кешируем с проверкой обновлений
  if (urlsToCache.some(url => event.request.url.includes(url))) {
    event.respondWith(
      caches.open(CACHE_NAME).then(cache => {
        return cache.match(event.request).then(response => {
          const fetchPromise = fetch(event.request).then(networkResponse => {
            // Обновляем кеш свежей версией
            cache.put(event.request, networkResponse.clone());
            return networkResponse;
          });
          
          // Возвращаем из кеша, но обновляем кеш в фоне
          return response || fetchPromise;
        });
      })
    );
    return;
  }
  
  // Для всех остальных запросов - сеть с fallback на кеш
  event.respondWith(
    fetch(event.request)
      .then(response => {
        // Клонируем ответ, так как он может быть использован только один раз
        const responseClone = response.clone();
        
        caches.open(CACHE_NAME).then(cache => {
          cache.put(event.request, responseClone);
        });
        
        return response;
      })
      .catch(() => caches.match(event.request))
  );
});

// Фоновая синхронизация для проверки обновлений
self.addEventListener('periodicsync', (event) => {
  if (event.tag === 'update-check') {
    event.waitUntil(checkForUpdates());
  }
});

async function checkForUpdates() {
  try {
    const response = await fetch('/version.json?t=' + Date.now());
    if (response.ok) {
      const versionInfo = await response.json();
      
      // Здесь можно добавить логику уведомления о новых версиях
      console.log('Current version info:', versionInfo);
    }
  } catch (error) {
    console.error('Error checking for updates:', error);
  }
}