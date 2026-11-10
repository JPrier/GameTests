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
  var glInfo = 'no GL context yet';
  (function () {
    var orig = HTMLCanvasElement.prototype.getContext;
    HTMLCanvasElement.prototype.getContext = function (type) {
      var ctx = orig.apply(this, arguments);
      if (ctx && (type === 'webgl2' || type === 'webgl')) {
        try {
          var a = ctx.getContextAttributes() || {};
          glInfo = type + ' aa ' + a.antialias + ' preserve ' + a.preserveDrawingBuffer + ' alpha ' + a.alpha +
            ' power ' + a.powerPreference + ' buffer ' + ctx.drawingBufferWidth + 'x' + ctx.drawingBufferHeight;
        } catch (e) { glInfo = 'GL attrs ERR ' + e.message; }
        this.addEventListener('webglcontextlost', function () { errors.push(stamp() + 'WEBGL CONTEXT LOST'); render(); });
        this.addEventListener('webglcontextrestored', function () { log('webgl context restored'); });
      }
      return ctx;
    };
  })();
  var envLine = null;
  function env() {
    if (envLine) return envLine;
    var parts = [];
    function add(k, f) { try { parts.push(k + ' ' + f()); } catch (e) { parts.push(k + ' ERR ' + e.message); } }
    add('screen', function () { return screen.width + 'x' + screen.height; });
    add('orient', function () { return (screen.orientation && screen.orientation.type) || window.orientation; });
    add('standalone', function () { return !!navigator.standalone || matchMedia('(display-mode: standalone)').matches; });
    add('reduced-motion', function () { return matchMedia('(prefers-reduced-motion: reduce)').matches; });
    add('pointer', function () { return (matchMedia('(pointer: coarse)').matches ? 'coarse' : 'fine') + (matchMedia('(hover: hover)').matches ? '+hover' : ''); });
    add('inapp', function () { return /FBAN|FBAV|Instagram|Line\/|WhatsApp|Snapchat|GSA\/|CriOS|FxiOS|EdgiOS/.test(navigator.userAgent) || 'no'; });
    add('lang', function () { return navigator.language; });
    add('cores', function () { return navigator.hardwareConcurrency; });
    add('localStorage', function () { localStorage.setItem('_gt_probe', '1'); localStorage.removeItem('_gt_probe'); return 'ok'; });
    add('gpu', function () {
      var gl = document.createElement('canvas').getContext('webgl2');
      if (!gl) return 'NO webgl2';
      var ext = gl.getExtension('WEBGL_debug_renderer_info');
      return ext ? gl.getParameter(ext.UNMASKED_RENDERER_WEBGL) : gl.getParameter(gl.RENDERER);
    });
    envLine = parts.join(' | ');
    try {
      var req = indexedDB.open('_gt_probe');
      req.onsuccess = function () { envLine += ' | indexedDB ok'; try { req.result.close(); } catch (e) {} };
      req.onerror = function () { envLine += ' | indexedDB ERR ' + (req.error && req.error.name); };
    } catch (e) { envLine += ' | indexedDB ERR ' + e.message; }
    return envLine;
  }
  function header() {
    var c = canvas(), r = c ? c.getBoundingClientRect() : null, vv = window.visualViewport;
    return [
      'build ' + (window.__gtBuild || '?') + ' | ' + navigator.userAgent,
      env(),
      'render options ' + JSON.stringify(window.__gtRenderOptions || {}) + ' | ' + glInfo,
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
      panel.style.cssText = 'position:fixed;left:0;right:0;top:0;max-height:62vh;overflow:hidden;z-index:2147483647;' +
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
  var moved = {};
  window.addEventListener('touchstart', function (e) {
    for (var i = 0; i < e.changedTouches.length; i++) moved[e.changedTouches[i].identifier] = 0;
  }, { capture: true, passive: true });
  window.addEventListener('touchmove', function (e) {
    counts.touchmove = (counts.touchmove || 0) + 1;
    for (var i = 0; i < e.changedTouches.length; i++) {
      var t = e.changedTouches[i], n = moved[t.identifier] = (moved[t.identifier] || 0) + 1;
      if (n === 1 || n % 10 === 0) log('touchmove#' + n + ' ' + Math.round(t.clientX) + ',' + Math.round(t.clientY) + ' id ' + t.identifier);
    }
  }, { capture: true, passive: true });
  ['gesturestart', 'gesturechange', 'gestureend', 'contextmenu', 'selectstart', 'dblclick', 'visibilitychange', 'pagehide', 'pageshow'].forEach(function (t) {
    (t === 'visibilitychange' ? document : window).addEventListener(t, function (e) {
      counts[t] = (counts[t] || 0) + 1;
      if (t !== 'gesturechange') log(t + (e.scale !== undefined ? ' scale ' + e.scale.toFixed(2) : '') + (e.defaultPrevented ? ' prevented' : ''));
    }, { capture: true, passive: true });
  });
  if (window.visualViewport) ['resize', 'scroll'].forEach(function (t) {
    visualViewport.addEventListener(t, function () {
      log('visualViewport ' + t + ' ' + Math.round(visualViewport.width) + 'x' + Math.round(visualViewport.height) +
        ' offset ' + Math.round(visualViewport.offsetLeft) + ',' + Math.round(visualViewport.offsetTop) + ' scale ' + visualViewport.scale.toFixed(2));
    });
  });
  window.addEventListener('scroll', function () { log('window scroll ' + Math.round(scrollX) + ',' + Math.round(scrollY)); }, { passive: true });
  window.addEventListener('pointermove', function (e) {
    counts.pointermove = (counts.pointermove || 0) + 1;
    lastMove = ' last move ' + e.pointerType + ' ' + Math.round(e.clientX) + ',' + Math.round(e.clientY) +
      ' mv ' + e.movementX + ',' + e.movementY;
  }, { capture: true, passive: true });
  window.addEventListener('error', function (e) { errors.push(stamp() + 'error: ' + e.message + ' @' + (e.filename || '').split('/').pop() + ':' + e.lineno); render(); });
  window.addEventListener('unhandledrejection', function (e) { errors.push(stamp() + 'rejection: ' + (e.reason && e.reason.message || e.reason)); render(); });
  ['focus', 'blur', 'resize', 'orientationchange'].forEach(function (t) { window.addEventListener(t, function () { log('window ' + t); }); });
  // ?debug=input&tap=190,600;26,540 taps those CSS positions after load (tapwait ms, default 8000;
  // tapgap ms between taps, default 1500), so a remote device can be driven without coordinate taps.
  (function () {
    var m = /[?&]tap=([0-9.,;]+)/.exec(location.search);
    if (!m) return;
    var pts = m[1].split(';').map(function (p) { return p.split(',').map(Number); });
    var wait = +((/[?&]tapwait=(\d+)/.exec(location.search) || [])[1] || 8000);
    var gap = +((/[?&]tapgap=(\d+)/.exec(location.search) || [])[1] || 1500);
    var id = 1000;
    function fire(target, type, x, y, touchId) {
      var t = { identifier: touchId, target: target, clientX: x, clientY: y, pageX: x, pageY: y, screenX: x, screenY: y,
        radiusX: 10, radiusY: 10, force: 1 };
      var e = new Event(type, { bubbles: true, cancelable: true });
      Object.defineProperty(e, 'changedTouches', { value: [t] });
      Object.defineProperty(e, 'touches', { value: type === 'touchend' ? [] : [t] });
      Object.defineProperty(e, 'targetTouches', { value: type === 'touchend' ? [] : [t] });
      target.dispatchEvent(e);
    }
    function pe(target, type, x, y) {
      try {
        target.dispatchEvent(new PointerEvent(type, { bubbles: true, cancelable: true, pointerId: id, pointerType: 'touch',
          isPrimary: true, clientX: x, clientY: y, buttons: type === 'pointerdown' ? 1 : 0 }));
      } catch (e) {}
    }
    function tap(i) {
      if (i >= pts.length) { log('AUTOTAP done'); return; }
      var x = pts[i][0], y = pts[i][1], c = document.querySelector('canvas'), tid = id++;
      if (!c) { log('AUTOTAP no canvas'); return; }
      log('AUTOTAP ' + (i + 1) + '/' + pts.length + ' at ' + x + ',' + y);
      pe(c, 'pointerdown', x, y); fire(c, 'touchstart', x, y, tid);
      setTimeout(function () {
        pe(c, 'pointerup', x, y); fire(c, 'touchend', x, y, tid);
        setTimeout(function () { tap(i + 1); }, gap);
      }, 90);
    }
    setTimeout(function () { tap(0); }, wait);
  })();
  setInterval(render, 1000);
  document.addEventListener('DOMContentLoaded', render);
})();
