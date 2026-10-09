'use strict';

// PuitsTrack — ouverture de la version web sans réseau.
//
// La liste des fichiers et la version sont remplies après chaque
// `flutter build web` par tool/gen_offline_sw.py (voir tool/build_web.ps1) :
// une nouvelle version de l'app change ce fichier, le navigateur installe
// alors le nouveau cache et supprime l'ancien.
//
// - Fichiers de l'app (même origine) : depuis le cache, sinon le réseau.
// - Page (index.html) : réseau d'abord, cache si hors ligne.
// - Firebase (autres origines) : jamais mis en cache — la synchronisation
//   reprend d'elle-même au retour du réseau.

const VERSION = '__CACHE_VERSION__';
const PRECACHE = [/*PRECACHE*/];

const CACHE = 'puitstrack-' + VERSION;
const SCOPE = self.registration.scope;
const INDEX = new URL('index.html', SCOPE).href;

function sameOrigin(url) {
  return new URL(url, SCOPE).origin === self.location.origin;
}

function isSelf(url) {
  return new URL(url, SCOPE).pathname.endsWith('/offline_sw.js');
}

self.addEventListener('install', (event) => {
  event.waitUntil((async () => {
    const cache = await caches.open(CACHE);
    // Un fichier introuvable ne bloque pas l'installation.
    await Promise.all(PRECACHE.map(async (path) => {
      try {
        await cache.add(new Request(new URL(path, SCOPE).href, { cache: 'reload' }));
      } catch (e) {
        // Ignoré : sera mis en cache à son premier chargement.
      }
    }));
    await self.skipWaiting();
  })());
});

self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    for (const key of await caches.keys()) {
      // Anciennes versions de l'app et cache de l'ancien service worker Flutter.
      if ((key.startsWith('puitstrack-') && key !== CACHE) || key.startsWith('flutter-')) {
        await caches.delete(key);
      }
    }
    await self.clients.claim();
  })());
});

// Fichiers chargés par la page avant que ce service worker la contrôle
// (premier lancement) : ajoutés au cache.
self.addEventListener('message', (event) => {
  const data = event.data || {};
  if (data.type !== 'cache-urls' || !Array.isArray(data.urls)) return;
  event.waitUntil((async () => {
    const cache = await caches.open(CACHE);
    for (const url of data.urls) {
      if (!sameOrigin(url) || isSelf(url)) continue;
      if (await cache.match(url, { ignoreSearch: true })) continue;
      try {
        await cache.add(url);
      } catch (e) {
        // Hors ligne au même moment : réessayé à la prochaine ouverture.
      }
    }
  })());
});

self.addEventListener('fetch', (event) => {
  const request = event.request;
  if (request.method !== 'GET' || !sameOrigin(request.url) || isSelf(request.url)) return;

  if (request.mode === 'navigate') {
    event.respondWith((async () => {
      try {
        const response = await fetch(request);
        if (response.ok) {
          const cache = await caches.open(CACHE);
          await cache.put(INDEX, response.clone());
        }
        return response;
      } catch (e) {
        return (await caches.match(INDEX)) || Response.error();
      }
    })());
    return;
  }

  event.respondWith((async () => {
    const cache = await caches.open(CACHE);
    const cached = await cache.match(request, { ignoreSearch: true });
    if (cached) return cached;
    const response = await fetch(request);
    if (response.ok && response.type === 'basic') await cache.put(request, response.clone());
    return response;
  })());
});
