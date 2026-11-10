// Browser smoke test for the built site: every game boots, and tapping a real button changes both
// the game's state and the pixels on screen. That is the check the iOS 18 bug failed (taps reached
// the game, the screen never updated), run here in Chromium and WebKit with the shipped scripts.
//
//   node .github/tests/smoke.mjs [_site] [--browsers chromium,webkit] [--games drinkle,bloom]
//
// It needs the page's ?debug=input overlay (input-debug.js) and gtui.gd's debug lines:
//   "GAME targets id@x,y;..."   tappable controls, centres in canvas backing pixels
//   "GAME state changed: ..."   the game's get_agent_state() changed after a tap
// Linux WebKit does not reproduce the iOS 18 driver bug itself (that needs a real iPhone); here it
// proves the WebKit code path, render fix included, still boots, renders and reacts to taps.
import http from 'node:http';
import { readFile, readdir, stat } from 'node:fs/promises';
import path from 'node:path';
import { chromium, webkit } from 'playwright';

const args = process.argv.slice(2);
const opt = (k, d) => { const i = args.indexOf(k); return i >= 0 ? args[i + 1] : d; };
const SITE = path.resolve(args.find((a, i) => !a.startsWith('--') && !(args[i - 1] || '').startsWith('--')) || '_site');
const BROWSERS = opt('--browsers', 'chromium,webkit').split(',');
const ONLY = opt('--games', '');
// --self-test: freeze what reaches the screen just before each tap (as iOS 18 did) and require
// the smoke test to catch it, so a broken check can't pass silently.
const SELF_TEST = args.includes('--self-test');
const BOOT_MS = 90000, TAP_TRIES = 6;

const MIME = { '.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm', '.pck': 'application/octet-stream',
  '.png': 'image/png', '.json': 'application/json', '.svg': 'image/svg+xml', '.webp': 'image/webp', '.css': 'text/css' };

function serve(root) {
  const server = http.createServer(async (req, res) => {
    try {
      let p = decodeURIComponent(new URL(req.url, 'http://x').pathname);
      let f = path.join(root, p);
      if (!f.startsWith(root)) throw new Error('outside');
      if ((await stat(f)).isDirectory()) f = path.join(f, 'index.html');
      const body = await readFile(f);
      res.writeHead(200, { 'Content-Type': MIME[path.extname(f)] || 'application/octet-stream', 'Cache-Control': 'no-store' });
      res.end(body);
    } catch { res.writeHead(404); res.end('not found'); }
  });
  return new Promise(r => server.listen(0, '127.0.0.1', () => r(server)));
}

async function games(root) {
  const out = [];
  for (const d of (await readdir(root, { withFileTypes: true })).filter(d => d.isDirectory() && d.name !== 'engine')) {
    try { await stat(path.join(root, d.name, 'index.pck')); out.push(d.name); } catch {}
  }
  return ONLY ? out.filter(g => ONLY.split(',').includes(g)) : out.sort();
}

// Captures every GAME line the game sends to the overlay, in order.
const CAPTURE = () => {
  window.__gtLog = [];
  let inner;
  Object.defineProperty(window, '__gtDebugInput', {
    configurable: true,
    get() { return inner && ((s) => { window.__gtLog.push(String(s)); return inner(s); }); },
    set(f) { inner = f; },
  });
};

// Stops presenting new frames once window.__gtFreeze is set: Godot keeps running, the screen doesn't.
const FREEZE = () => {
  const P = WebGL2RenderingContext.prototype, blit = P.blitFramebuffer, draw = P.drawArrays;
  P.blitFramebuffer = function () { if (!window.__gtFreeze) return blit.apply(this, arguments); };
  P.drawArrays = function () {
    if (window.__gtFreeze && this.getParameter(this.DRAW_FRAMEBUFFER_BINDING) === null) return;
    return draw.apply(this, arguments);
  };
};

const differs = (a, b) => a !== b;

async function checkGame(browserType, browser, base, game) {
  const context = await browser.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2 });
  const page = await context.newPage();
  const problems = [], notes = [];
  page.on('pageerror', e => problems.push(`page error: ${e.message}`));
  page.on('console', m => { if (m.type() === 'error') problems.push(`console error: ${m.text().slice(0, 300)}`); });
  await page.addInitScript(CAPTURE);
  if (SELF_TEST) await page.addInitScript(FREEZE);
  try {
    await page.goto(`${base}/${game}/?debug=input`, { waitUntil: 'load' });
    await page.waitForFunction(() => {
      const s = document.getElementById('status');
      return !s || getComputedStyle(s).display === 'none' || s.style.visibility === 'hidden';
    }, null, { timeout: BOOT_MS });
    const canvas = page.locator('canvas').first();
    const box = await canvas.boundingBox();
    if (!box || box.width < 50) throw new Error('no visible canvas after boot');

    // Prime the game's debug echo (sends env + targets), then read the buttons on screen.
    await page.mouse.move(box.x + 3, box.y + 3);
    await page.waitForFunction(() => window.__gtLog.some(l => l.startsWith('targets ')), null, { timeout: 15000 })
      .catch(() => { throw new Error('the game never reported its buttons (no "targets" debug line)'); });

    const ro = await page.evaluate(() => window.__gtRenderOptions);
    if (browserType === 'webkit') {
      if (!ro || ro.rtfix !== true) problems.push(`render fix not enabled in WebKit: ${JSON.stringify(ro)}`);
      else if (!(ro.rtfixApplied > 0)) problems.push('render fix is on but intercepted no TEXTURE_MAX_LEVEL calls: Godot changed how it sets texture levels, re-check the iOS 18 fix');
    } else if (ro && ro.rtfix) problems.push(`render fix unexpectedly on in ${browserType}`);

    // The canvas's own pixels (the page draws with preserveDrawingBuffer), not a page screenshot:
    // the debug overlay sits on top of the canvas and changes on every tap.
    const pixels = () => canvas.evaluate(c => c.toDataURL('image/png'));
    const scale = await canvas.evaluate(c => c.getBoundingClientRect().width / c.width);
    const tried = new Set();
    let ok = false;
    for (let attempt = 0; attempt < TAP_TRIES && !ok; attempt++) {
      const line = await page.evaluate(() => [...window.__gtLog].reverse().find(l => l.startsWith('targets ')));
      const targets = line.slice(8).split(';').filter(Boolean).map(t => {
        const at = t.lastIndexOf('@');   // Control-node ids are node paths, which contain '@'
        const [x, y] = t.slice(at + 1).split(',').map(Number);
        return { id: t.slice(0, at), x, y };
      }).filter(t => !tried.has(t.id));
      if (!targets.length) break;
      const t = targets[0];
      tried.add(t.id);
      if (SELF_TEST) await page.evaluate(() => { window.__gtFreeze = true; });
      await page.waitForTimeout(400);
      const before = await pixels();
      const n = await page.evaluate(() => window.__gtLog.length);
      await page.mouse.click(box.x + t.x * scale, box.y + t.y * scale);
      const state = await page.waitForFunction(n => window.__gtLog.slice(n).find(l => l.startsWith('state ')), n, { timeout: 5000 })
        .then(h => h.jsonValue()).catch(() => 'no state line');
      await page.waitForTimeout(600);
      const after = await pixels();
      const changed = state.startsWith('state changed');
      const drawn = differs(before, after);
      notes.push(`tap ${t.id.split('/').pop()}: ${changed ? 'state changed' : 'state unchanged'}, screen ${drawn ? 'updated' : 'NOT updated'}`);
      if (changed && !drawn) problems.push(`tap on "${t.id}" changed the game state but the screen did not update (the iOS 18 symptom)`);
      ok = drawn;   // some games keep tab or overlay state out of get_agent_state(); a redraw is the reaction
    }
    if (!ok && !problems.length) problems.push(`no button tap updated the screen (tried ${[...tried].join(', ') || 'none'})`);
  } catch (e) {
    problems.push(e.message.split('\n')[0]);
  } finally {
    if (problems.length) await page.screenshot({ path: `smoke-${browserType}-${game}.png` }).catch(() => {});
    await context.close();
  }
  return { problems, notes };
}

const server = await serve(SITE);
const base = `http://127.0.0.1:${server.address().port}`;
const list = await games(SITE);
let failed = 0;
for (const name of BROWSERS) {
  const type = { chromium, webkit }[name];
  const browser = await type.launch();
  for (const game of list) {
    const { problems, notes } = await checkGame(name, browser, base, game);
    console.log(`${problems.length ? 'FAIL' : 'ok  '} ${name.padEnd(8)} ${game}  ${notes.join(' | ')}`);
    for (const p of problems) console.log(`::error::smoke ${name} ${game}: ${p}`);
    failed += problems.length ? 1 : 0;
  }
  await browser.close();
}
server.close();
const runs = list.length * BROWSERS.length;
if (SELF_TEST) {
  console.log(`smoke self-test: ${failed}/${runs} frozen runs caught`);
  process.exit(failed === runs ? 0 : 1);
}
console.log(`smoke: ${list.length} games x ${BROWSERS.length} browsers, ${failed} failed`);
process.exit(failed ? 1 : 0);
