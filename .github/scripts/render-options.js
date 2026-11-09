// Rendering switches for diagnosing phones where the game runs and takes input but the screen
// stops updating (seen on an iPhone 14, iOS 18.1). Inert unless the URL asks for one:
//   ?gl=preserve  create the WebGL context with preserveDrawingBuffer: true
//   ?dpr=1        report devicePixelRatio 1, so the canvas is 1x instead of 3x on a phone
// Several can be combined, e.g. ?gl=preserve&dpr=1. The ?debug=input overlay shows which are on.
(function () {
  var q = '';
  try { q = location.search; } catch (e) { return; }
  var gl = (/[?&]gl=([a-z,]+)/.exec(q) || [])[1] || '';
  var opts = window.__gtRenderOptions = {
    preserve: /\bpreserve\b/.test(gl),
    dpr1: /[?&]dpr=1\b/.test(q),
  };
  if (opts.dpr1) {
    try { Object.defineProperty(window, 'devicePixelRatio', { get: function () { return 1; }, configurable: true }); } catch (e) {}
  }
  if (opts.preserve) {
    var orig = HTMLCanvasElement.prototype.getContext;
    HTMLCanvasElement.prototype.getContext = function (type, attrs) {
      if (type === 'webgl2' || type === 'webgl') {
        attrs = Object.assign({}, attrs || {}, { preserveDrawingBuffer: true });
      }
      return orig.call(this, type, attrs);
    };
  }
})();
