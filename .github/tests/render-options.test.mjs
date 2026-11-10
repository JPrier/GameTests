// Unit tests for .github/scripts/render-options.js, the iOS 18 frozen-screen fix.
//   node --test .github/tests/
// The script runs in a sandbox with a fake WebGL2RenderingContext, so we can check which browsers
// get the patch and that it drops exactly texParameter(TEXTURE_MAX_LEVEL, 0) and nothing else.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const SRC = readFileSync(new URL('../scripts/render-options.js', import.meta.url), 'utf8');
const MAX_LEVEL = 0x813d, BASE_LEVEL = 0x813c, MIN_FILTER = 0x2801, TEX_2D = 0x0de1;

const UA = {
  iphone18: 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1',
  iphone26: 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1',
  ipadDesktop: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15',
  iosChrome: 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) CriOS/130.0.6723.90 Mobile/15E148 Safari/604.1',
  iosFirefox: 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) FxiOS/132.0 Mobile/15E148 Safari/605.1.15',
  inAppWebView: 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 Instagram 350.0',
  desktopChrome: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36',
  android: 'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Mobile Safari/537.36',
  edge: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36 Edg/130.0.0.0',
  firefox: 'Mozilla/5.0 (X11; Linux x86_64; rv:132.0) Gecko/20100101 Firefox/132.0',
};

function run(ua, search = '') {
  const calls = [];
  class WebGL2RenderingContext {}
  WebGL2RenderingContext.prototype.texParameteri = function (t, p, v) { calls.push(['i', t, p, v]); };
  WebGL2RenderingContext.prototype.texParameterf = function (t, p, v) { calls.push(['f', t, p, v]); };
  const window = { WebGL2RenderingContext };
  const ctx = vm.createContext({ window, WebGL2RenderingContext, navigator: { userAgent: ua }, location: { search } });
  vm.runInContext(SRC, ctx);
  const gl = new WebGL2RenderingContext();
  return { opts: window.__gtRenderOptions, gl, calls };
}

for (const name of ['iphone18', 'iphone26', 'ipadDesktop', 'iosChrome', 'iosFirefox', 'inAppWebView']) {
  test(`patch is on for Apple WebKit: ${name}`, () => {
    const { opts } = run(UA[name]);
    assert.equal(opts.rtfix, true);
    assert.equal(opts.rtfixApplied, 0);
  });
}

for (const name of ['desktopChrome', 'android', 'edge', 'firefox']) {
  test(`patch is off elsewhere: ${name}`, () => {
    const { opts, gl, calls } = run(UA[name]);
    assert.equal(opts.rtfix, false);
    gl.texParameteri(TEX_2D, MAX_LEVEL, 0);
    assert.deepEqual(calls, [['i', TEX_2D, MAX_LEVEL, 0]], 'calls pass straight through');
  });
}

test('drops only TEXTURE_MAX_LEVEL = 0, for both texParameteri and texParameterf', () => {
  const { opts, gl, calls } = run(UA.iphone18);
  gl.texParameteri(TEX_2D, MAX_LEVEL, 0);
  gl.texParameterf(TEX_2D, MAX_LEVEL, 0);
  gl.texParameteri(TEX_2D, MAX_LEVEL, 4);
  gl.texParameteri(TEX_2D, BASE_LEVEL, 0);
  gl.texParameteri(TEX_2D, MIN_FILTER, 0x2601);
  assert.equal(opts.rtfixApplied, 2);
  assert.deepEqual(calls, [
    ['i', TEX_2D, MAX_LEVEL, 4],
    ['i', TEX_2D, BASE_LEVEL, 0],
    ['i', TEX_2D, MIN_FILTER, 0x2601],
  ]);
});

test('calls that pass through keep their `this` and return value', () => {
  class WebGL2RenderingContext {}
  WebGL2RenderingContext.prototype.texParameteri = function () { return this; };
  WebGL2RenderingContext.prototype.texParameterf = function () { return this; };
  const window = { WebGL2RenderingContext };
  vm.runInContext(SRC, vm.createContext({ window, WebGL2RenderingContext, navigator: { userAgent: UA.iphone18 }, location: { search: '' } }));
  const gl = new WebGL2RenderingContext();
  assert.equal(gl.texParameteri(TEX_2D, BASE_LEVEL, 0), gl);
  assert.equal(gl.texParameterf(TEX_2D, MAX_LEVEL, 2), gl);
});

test('?gl=nortfix turns the patch off on iOS (control for repro)', () => {
  const { opts, gl, calls } = run(UA.iphone18, '?gl=nortfix');
  assert.equal(opts.rtfix, false);
  gl.texParameteri(TEX_2D, MAX_LEVEL, 0);
  assert.equal(calls.length, 1);
});

test('?gl=rtfix forces the patch on in other browsers', () => {
  const { opts } = run(UA.desktopChrome, '?debug=input&gl=rtfix');
  assert.equal(opts.rtfix, true);
  assert.equal(opts.rtfixApplied, 0);
});

test('no WebGL2 (old browser) is a no-op, not an error', () => {
  const window = {};
  const ctx = vm.createContext({ window, navigator: { userAgent: UA.iphone18 }, location: { search: '' } });
  vm.runInContext(SRC, ctx);
  assert.equal(window.__gtRenderOptions.rtfix, true);
  assert.equal(window.__gtRenderOptions.rtfixApplied, undefined);
});
