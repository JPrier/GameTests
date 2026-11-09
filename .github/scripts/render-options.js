// iOS 18 frozen-canvas fix for every exported game.
//
// Symptom: on iOS 18 Safari (and every iOS browser, all WebKit) the game runs, takes input and changes
// state, but the screen keeps showing the first frame. iOS 26 is fine.
//
// Root cause (reproduced on a real iPhone 14 with iOS 18.0 via BrowserStack, with a WebGL call census):
// Godot sets texParameteri(TEXTURE_2D, TEXTURE_MAX_LEVEL, 0) on every texture without mipmaps. With
// that set, iOS 18's WebGL stops applying anything drawn into Godot's 2D render target after the
// first frame: no GL error, reads keep returning frame 1, so frame 1 is presented forever. Skipping
// MAX_LEVEL 0 only on render-target textures was not enough; textures sampled while drawing also
// trigger it, so it is skipped for all of them.
//
// Fix: ignore TEXTURE_MAX_LEVEL 0. For a single-level texture with a non-mipmap filter (how Godot uses
// MAX_LEVEL 0) the GL default (1000) samples and renders identically. Mipmapped textures, which set
// other values, are untouched. Checked on the device: with the fix Drinkle updates normally; with
// ?gl=nortfix the same page freezes again.
//
// On by default in WebKit browsers (all iOS browsers, Safari on macOS), off elsewhere.
//   ?gl=rtfix     force it on      ?gl=nortfix   force it off (to reproduce the bug)
// The ?debug=input overlay shows whether it is on and how many calls it skipped.
(function () {
  var q = '';
  try { q = location.search; } catch (e) { return; }
  var gl = (/[?&]gl=([a-z,]+)/.exec(q) || [])[1] || '', ua = navigator.userAgent || '';
  var webkit = (/AppleWebKit/.test(ua) && !/(Chrome|Chromium|Edg|Android)\//.test(ua)) || /(CriOS|FxiOS|EdgiOS)/.test(ua);
  var opts = window.__gtRenderOptions = {
    rtfix: /\bnortfix\b/.test(gl) ? false : (/\brtfix\b/.test(gl) || webkit),
  };
  if (!opts.rtfix || !window.WebGL2RenderingContext) return;
  var P = WebGL2RenderingContext.prototype, MAX_LEVEL = 0x813D;
  var oTexI = P.texParameteri, oTexF = P.texParameterf;
  opts.rtfixApplied = 0;
  P.texParameteri = function (target, pname, value) {
    if (pname === MAX_LEVEL && value === 0) { opts.rtfixApplied++; return; }
    return oTexI.apply(this, arguments);
  };
  P.texParameterf = function (target, pname, value) {
    if (pname === MAX_LEVEL && value === 0) { opts.rtfixApplied++; return; }
    return oTexF.apply(this, arguments);
  };
})();
