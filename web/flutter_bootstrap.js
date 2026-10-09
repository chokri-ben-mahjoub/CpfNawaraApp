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

  var registered = new Promise(function (resolve) {
    window.addEventListener('load', function () {
      navigator.serviceWorker.register('offline_sw.js')
        .then(function () { return navigator.serviceWorker.ready; })
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
