{{flutter_js}}
{{flutter_build_config}}

// Hors ligne : PuitsTrack garde ses propres fichiers en cache (offline_sw.js)
// pour s'ouvrir sans réseau ; les données sont dans IndexedDB (base SQLite).
(function () {
  if (!('serviceWorker' in navigator)) return;

  // Évite que le navigateur efface la base locale quand l'espace manque.
  if (navigator.storage && navigator.storage.persist) {
    navigator.storage.persisted()
      .then(function (persisted) { if (!persisted) return navigator.storage.persist(); })
      .catch(function () {});
  }

  // Mise à jour automatique : quand une nouvelle version de l'app prend la
  // main (déploiement), la page se recharge d'elle-même une seule fois, sans
  // Ctrl+F5. Pas de rechargement à la toute première installation.
  var hadController = !!navigator.serviceWorker.controller;
  var reloading = false;
  navigator.serviceWorker.addEventListener('controllerchange', function () {
    if (!hadController || reloading) return;
    reloading = true;
    window.location.reload();
  });

  var registered = new Promise(function (resolve) {
    window.addEventListener('load', function () {
      navigator.serviceWorker.register('offline_sw.js')
        .then(function (registration) {
          // Cherche une nouvelle version à chaque retour sur l'app et toutes
          // les 10 minutes (onglet laissé ouvert).
          var check = function () { registration.update().catch(function () {}); };
          document.addEventListener('visibilitychange', function () {
            if (document.visibilityState === 'visible') check();
          });
          setInterval(check, 10 * 60 * 1000);
          return navigator.serviceWorker.ready;
        })
        .then(resolve)
        .catch(function (e) { console.warn('PuitsTrack : mode hors ligne indisponible', e); });
    });
  });

  // Dès la première image : fichiers réellement chargés par cette page (dont
  // la variante de CanvasKit choisie par le navigateur), gardés pour la
  // prochaine ouverture hors ligne.
  window.addEventListener('flutter-first-frame', function () {
    registered.then(function (registration) {
      var urls = performance.getEntriesByType('resource')
        .map(function (entry) { return entry.name; })
        .filter(function (url) { return url.indexOf(location.origin + '/') === 0; });
      if (registration.active) registration.active.postMessage({ type: 'cache-urls', urls: urls });
    });
  });
})();

_flutter.loader.load();
