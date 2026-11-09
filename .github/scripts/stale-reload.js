// Stale-page guard for every exported game (always on). Phones keep open tabs and Home Screen
// apps in memory for days without refetching, so a player can keep running an old build long
// after a fix ships. The site build writes build.json next to the games; when the page is opened
// or brought back to the foreground and its own stamp (window.__gtBuild) differs, reload once.
(function () {
  var mine = window.__gtBuild, last = 0;
  if (!mine || mine.indexOf('local') === 0 || !window.fetch) return;
  function check() {
    var t = Date.now();
    if (t - last < 30000) return;
    last = t;
    var url;
    try { url = new URL('../build.json', location.href).href + '?t=' + t; } catch (e) { return; }
    fetch(url, { cache: 'no-store' }).then(function (r) { return r.ok ? r.json() : null; }).then(function (j) {
      if (!j || !j.build || j.build === mine) return;
      var key = 'gt_reloaded_for', done = null;
      try { done = sessionStorage.getItem(key); sessionStorage.setItem(key, j.build); } catch (e) {}
      if (done !== j.build) location.reload();   // at most once per new build, so never a reload loop
    }).catch(function () {});
  }
  check();
  window.addEventListener('pageshow', function (e) { if (e.persisted) { last = 0; check(); } });
  document.addEventListener('visibilitychange', function () { if (document.visibilityState === 'visible') check(); });
})();
