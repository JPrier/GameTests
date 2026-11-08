// Touch/input diagnostics for every exported game. Inert unless the URL has ?debug=input.
// Shows what the browser delivers to the page (touch, pointer, mouse events), what the game receives
// (GAME lines from gtui.gd), JS and engine errors, so a player on a phone we can't test can send a
// screenshot. The panel ignores touches, so the game stays playable. A two-finger tap copies the
// whole log to the clipboard so it can be pasted into a message.
(function () {
  try {
    if (!/[?&]debug=input\b/.test(location.search)) return;
  } catch (e) { return; }
  var lines = [], counts = {}, panel = null, errors = [], fps = 0, frames = 0, lastMove = '', t0 = Date.now();
  function stamp() { return ((Date.now() - t0) / 1000).toFixed(2) + 's '; }
  // engine and script errors (Godot reports GDScript errors through console.error / console.warn)
  ['error', 'warn'].forEach(function (level) {
    var orig = console[level];
    console[level] = function () {
      try {
        errors.push(stamp() + level + ': ' + Array.prototype.map.call(arguments, String).join(' ').slice(0, 300));
        if (errors.length > 200) errors.shift();
        render();
      } catch (e) {}
      return orig.apply(console, arguments);
    };
  });
  // the game's shared UI (gtui.gd) echoes what Godot actually receives through this
  window.__gtDebugInput = function (s) { log('GAME ' + s); };
  (function tick() { frames++; requestAnimationFrame(tick); })();
  setInterval(function () { fps = frames; frames = 0; }, 1000);
  function esc(s) { return String(s).replace(/[&<>]/g, function (c) { return {'&': '&amp;', '<': '&lt;', '>': '&gt;'}[c]; }); }
  function canvas() { return document.querySelector('canvas'); }
  function describe(el) {
    if (!el) return 'null';
    var s = el.tagName ? el.tagName.toLowerCase() : String(el);
    if (el.id) s += '#' + el.id;
    return s;
  }
  function header() {
    var c = canvas(), r = c ? c.getBoundingClientRect() : null, vv = window.visualViewport;
    return [
      'build ' + (window.__gtBuild || '?') + ' | ' + navigator.userAgent,
      'viewport ' + innerWidth + 'x' + innerHeight + ' dpr ' + devicePixelRatio +
        (vv ? ' vv ' + Math.round(vv.width) + 'x' + Math.round(vv.height) + ' scale ' + vv.scale.toFixed(2) : ''),
      c ? 'canvas ' + c.width + 'x' + c.height + ' at ' + Math.round(r.left) + ',' + Math.round(r.top) + ' ' +
        Math.round(r.width) + 'x' + Math.round(r.height) + ' focused ' + (document.activeElement === c) : 'no canvas yet',
      'ontouchstart ' + ('ontouchstart' in window) + ' maxTouchPoints ' + (navigator.maxTouchPoints || 0) +
        ' PointerEvent ' + (typeof PointerEvent),
      'page fps ' + fps + ' ' + document.visibilityState + ' hasFocus ' + document.hasFocus() + lastMove,
      'touch-fix dropped ' + JSON.stringify(window.__gtTouchFixDrops || 'n/a'),
      'counts ' + Object.keys(counts).map(function (k) { return k + ':' + counts[k]; }).join(' '),
    ];
  }
  function render() {
    if (!panel) {
      if (!document.body) return;
      panel = document.createElement('div');
      panel.style.cssText = 'position:fixed;left:0;right:0;top:0;max-height:45vh;overflow:hidden;z-index:2147483647;' +
        'pointer-events:none;background:rgba(0,0,0,.78);color:#9f9;font:10px/1.3 ui-monospace,Menlo,monospace;' +
        'padding:4px 6px;white-space:pre-wrap;word-break:break-all';
      document.body.appendChild(panel);
    }
    panel.innerHTML = esc(header().join('\n')) +
      '\n2-finger tap: copy full log' + (errors.length ? ' | ' + errors.length + ' errors' : '') +
      (errors.length ? '\n<span style="color:#f88">' + esc(errors.slice(-4).join('\n')) + '</span>' : '') +
      '\n' + esc(lines.slice(-16).join('\n'));
  }
  function log(s) { lines.push(stamp() + s); if (lines.length > 500) lines.shift(); render(); }
  function fullText() { return header().concat(['-- errors --'], errors, ['-- log --'], lines).join('\n'); }
  function copyLog() {
    var text = fullText(), done = function (ok) { log(ok ? 'COPIED ' + text.length + ' chars: paste it into a message' : 'copy failed'); };
    try {
      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(text).then(function () { done(true); }, function () { done(fallback(text)); });
      } else done(fallback(text));
    } catch (e) { done(fallback(text)); }
  }
  function fallback(text) {
    try {
      var ta = document.createElement('textarea');
      ta.value = text; ta.setAttribute('readonly', ''); ta.style.cssText = 'position:fixed;top:0;left:0;opacity:0';
      document.body.appendChild(ta); ta.select(); ta.setSelectionRange(0, text.length);
      var ok = document.execCommand('copy'); document.body.removeChild(ta); return ok;
    } catch (e) { return false; }
  }
  var twoFinger = false;
  window.addEventListener('touchstart', function (e) { if (e.touches && e.touches.length >= 2) twoFinger = true; }, { capture: true, passive: true });
  window.addEventListener('touchend', function (e) {
    if (twoFinger && (!e.touches || e.touches.length === 0)) { twoFinger = false; copyLog(); }
  }, { capture: true, passive: true });
  function point(e) {
    var t = e.changedTouches && e.changedTouches[0];
    return t ? { x: t.clientX, y: t.clientY, id: t.identifier } : { x: e.clientX, y: e.clientY };
  }
  ['touchstart', 'touchend', 'touchcancel', 'pointerdown', 'pointerup', 'pointercancel', 'mousedown', 'mouseup', 'click']
    .forEach(function (type) {
      window.addEventListener(type, function (e) {
        counts[type] = (counts[type] || 0) + 1;
        var p = point(e), x = Math.round(p.x), y = Math.round(p.y);
        var top = document.elementFromPoint ? document.elementFromPoint(x, y) : null;
        // read defaultPrevented after the page's own handlers (bubble phase on canvas) have run
        setTimeout(function () {
          var tg = describe(e.target), tp = describe(top);
          log(type + (e.pointerType ? '(' + e.pointerType + ')' : '') + ' ' + x + ',' + y +
            (p.id !== undefined ? ' id ' + p.id : '') + (tg === tp ? ' on ' + tg : ' target ' + tg + ' top ' + tp) +
            ' prevented ' + e.defaultPrevented + (e.cancelable ? '' : ' NOT-cancelable'));
        }, 0);
      }, { capture: true, passive: true });
    });
  window.addEventListener('pointermove', function (e) {
    counts.pointermove = (counts.pointermove || 0) + 1;
    lastMove = ' last move ' + e.pointerType + ' ' + Math.round(e.clientX) + ',' + Math.round(e.clientY) +
      ' mv ' + e.movementX + ',' + e.movementY;
  }, { capture: true, passive: true });
  window.addEventListener('error', function (e) { errors.push(stamp() + 'error: ' + e.message + ' @' + (e.filename || '').split('/').pop() + ':' + e.lineno); render(); });
  window.addEventListener('unhandledrejection', function (e) { errors.push(stamp() + 'rejection: ' + (e.reason && e.reason.message || e.reason)); render(); });
  ['focus', 'blur', 'resize', 'orientationchange'].forEach(function (t) { window.addEventListener(t, function () { log('window ' + t); }); });
  setInterval(render, 1000);
  document.addEventListener('DOMContentLoaded', render);
})();
