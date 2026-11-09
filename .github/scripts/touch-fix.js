// Touch hardening for every exported game (always on). Godot's web runtime reads touches from
// touchstart/move/end and also turns every window `pointermove` into a real-mouse motion event.
// On phones that gives the game a second, separate pointer stream during each touch, and phones
// can also send "ghost" mouse events after a tap. Games only need the touch stream (the engine
// turns it into mouse events itself), so the extras are dropped before the engine sees them.
// Mouse and pen input are untouched.
(function () {
  var GHOST_MS = 800, lastTouch = -1e9, drops = window.__gtTouchFixDrops = {};
  function drop(e) { drops[e.type] = (drops[e.type] || 0) + 1; e.stopImmediatePropagation(); }
  function now() { return (window.performance && performance.now) ? performance.now() : Date.now(); }
  function markTouch() { lastTouch = now(); }
  ['touchstart', 'touchmove', 'touchend', 'touchcancel'].forEach(function (t) {
    window.addEventListener(t, markTouch, { capture: true, passive: true });
  });
  // 1. Touch pointermoves: Godot already gets these moves from touchmove.
  window.addEventListener('pointermove', function (e) {
    if (e.pointerType === 'touch') drop(e);
  }, { capture: true });
  // 2. Compatibility mouse events a browser may fire after a tap: they would arrive as a second
  //    press/release on top of the one the engine already made from the touch.
  ['mousedown', 'mouseup', 'mousemove'].forEach(function (t) {
    window.addEventListener(t, function (e) {
      if (now() - lastTouch < GHOST_MS) drop(e);
    }, { capture: true });
  });
  // 3. No grey tap flash or callout over the canvas on iOS.
  var css = document.createElement('style');
  css.textContent = 'html,body,canvas{-webkit-tap-highlight-color:transparent;-webkit-touch-callout:none}';
  (document.head || document.documentElement).appendChild(css);
})();
