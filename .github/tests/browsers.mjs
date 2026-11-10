// Plays every exported game the way players run it: in real browser engines, on phone- and
// desktop-shaped screens, with touch and with a mouse. Godot's headless tests check game logic;
// this checks the built web page: the engine boots, nothing throws, the canvas fills the screen,
// tapping a real button redraws it, and rotating the phone re-lays it out.
//
//   node .github/tests/browsers.mjs [_site] [--browsers chromium,firefox,webkit]
//        [--profiles phone,desktop] [--games drinkle,bloom] [--self-test]
//
// Buttons come from the page's ?debug=input overlay (input-debug.js) and gtui.gd's debug lines:
//   "GAME targets id@x,y;..."   tappable controls, centres in canvas backing pixels
//   "GAME state changed: ..."   the game's get_agent_state() changed after a tap
// --self-test stops new frames from reaching the screen and requires every run to fail, to show
// the redraw check can't pass on a page that doesn't update.
//
// Real iPhones are still needed for iOS-only bugs (see CLAUDE.md): engines here are Linux builds.
import http from 'node:http';
import { readFile, readdir, stat } from 'node:fs/promises';
import path from 'node:path';
import { chromium, firefox, webkit } from 'playwright';

const args = process.argv.slice(2);
const opt = (k, d) => { const i = args.indexOf(k); return i >= 0 ? args[i + 1] : d; };
const SITE = path.resolve(args.find((a, i) => !a.startsWith('--') && !(args[i - 1] || '').startsWith('--')) || '_site');
const BROWSERS = opt('--browsers', 'chromium,firefox,webkit').split(',');
const PROFILES = opt('--profiles', 'phone,desktop').split(',');
const ONLY = opt('--games', '');
const SELF_TEST = args.includes('--self-test');
const BOOT_MS = 90000, TAP_TRIES = 6;

// Screen shapes and input. Phones get touch, a 3x display and a rotation to landscape.
const PROFILE = {
  phone: { viewport: { width: 390, height: 844 }, deviceScaleFactor: 3, hasTouch: true, touch: true, rotate: { width: 844, height: 390 } },
  desktop: { viewport: { width: 1280, height: 800 }, deviceScaleFactor: 1, hasTouch: false, touch: false },
};

const MIME = { '.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm', '.pck': 'application/octet-stream',
  '.png': 'image/png', '.json': 'application/json', '.svg': 'image/svg+xml', '.webp': 'image/webp', '.css': 'text/css' };

function serve(root) {
  const server = http.createServer(async (req, res) => {
    try {
      const p = decodeURIComponent(new URL(req.url, 'http://x').pathname);
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
  return (ONLY ? out.filter(g => ONLY.split(',').includes(g)) : out).sort();
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

// Self-test: once window.__gtFreeze is set, Godot keeps running but nothing new reaches the screen.
const FREEZE = () => {
  const P = WebGL2RenderingContext.prototype, blit = P.blitFramebuffer, draw = P.drawArrays;
  P.blitFramebuffer = function () { if (!window.__gtFreeze) return blit.apply(this, arguments); };
  P.drawArrays = function () {
    if (window.__gtFreeze && this.getParameter(this.DRAW_FRAMEBUFFER_BINDING) === null) return;
    return draw.apply(this, arguments);
  };
};

const parseTargets = line => line.slice(8).split(';').filter(Boolean).map(t => {
  const at = t.lastIndexOf('@');   // Control-node ids are node paths, which contain '@'
  const [x, y] = t.slice(at + 1).split(',').map(Number);
  return { id: t.slice(0, at), x, y };
});

async function checkGame(browserName, browser, profileName, base, game) {
  const prof = PROFILE[profileName];
  const context = await browser.newContext({
    viewport: prof.viewport, deviceScaleFactor: prof.deviceScaleFactor, hasTouch: prof.hasTouch,
    ...(browserName === 'chromium' && prof.touch ? { isMobile: true } : {}),
  });
  const page = await context.newPage();
  const problems = [], notes = [];
  page.on('pageerror', e => problems.push(`page error: ${e.message.split('\n')[0]}`));
  page.on('console', m => { if (m.type() === 'error') problems.push(`console error: ${m.text().slice(0, 300)}`); });
  await page.addInitScript(CAPTURE);
  if (SELF_TEST) await page.addInitScript(FREEZE);
  const canvas = page.locator('canvas').first();
  // The canvas's own pixels (the export draws with preserveDrawingBuffer), not a page screenshot:
  // the debug overlay sits on top of the canvas and changes on every tap.
  const pixels = () => canvas.evaluate(c => c.toDataURL('image/png'));
  const fills = async (vp) => {
    const s = await canvas.evaluate(c => ({ w: c.width, h: c.height, cw: c.getBoundingClientRect().width, ch: c.getBoundingClientRect().height }));
    const want = { w: Math.round(vp.width * prof.deviceScaleFactor), h: Math.round(vp.height * prof.deviceScaleFactor) };
    const ok = Math.abs(s.cw - vp.width) <= 1 && Math.abs(s.ch - vp.height) <= 1 && Math.abs(s.w - want.w) <= 2 && Math.abs(s.h - want.h) <= 2;
    return { ok, msg: `canvas ${s.w}x${s.h} shown at ${s.cw}x${s.ch}, expected ${want.w}x${want.h} at ${vp.width}x${vp.height}` };
  };
  const tapAt = (x, y) => prof.touch ? page.touchscreen.tap(x, y) : page.mouse.click(x, y);

  try {
    await page.goto(`${base}/${game}/?debug=input`, { waitUntil: 'load' });
    await page.waitForFunction(() => {
      const s = document.getElementById('status');
      return !s || getComputedStyle(s).display === 'none' || s.style.visibility === 'hidden';
    }, null, { timeout: BOOT_MS }).catch(() => { throw new Error(`did not boot within ${BOOT_MS / 1000}s`); });
    await page.waitForTimeout(500);
    const box = await canvas.boundingBox();
    if (!box) throw new Error('no canvas after boot');
    const fit = await fills(prof.viewport);
    if (!fit.ok) problems.push(`canvas doesn't fill the screen: ${fit.msg}`);

    // Prime the game's debug echo (sends env + targets), then read the buttons on screen.
    await page.mouse.move(box.x + 3, box.y + 3);
    await page.waitForFunction(() => window.__gtLog.some(l => l.startsWith('targets ')), null, { timeout: 15000 })
      .catch(() => { throw new Error('the game never reported its buttons (no "targets" debug line)'); });

    const scale = await canvas.evaluate(c => c.getBoundingClientRect().width / c.width);
    const tried = new Set();
    let reacted = false;
    for (let attempt = 0; attempt < TAP_TRIES && !reacted; attempt++) {
      const line = await page.evaluate(() => [...window.__gtLog].reverse().find(l => l.startsWith('targets ')));
      const t = parseTargets(line).find(t => !tried.has(t.id));
      if (!t) break;
      tried.add(t.id);
      if (SELF_TEST) await page.evaluate(() => { window.__gtFreeze = true; });
      await page.waitForTimeout(400);
      const before = await pixels();
      const n = await page.evaluate(() => window.__gtLog.length);
      await tapAt(box.x + t.x * scale, box.y + t.y * scale);
      const state = await page.waitForFunction(n => window.__gtLog.slice(n).find(l => l.startsWith('state ')), n, { timeout: 5000 })
        .then(h => h.jsonValue()).catch(() => 'no state line');
      await page.waitForTimeout(600);
      const drawn = before !== await pixels();
      const changed = state.startsWith('state changed');
      notes.push(`${t.id.split('/').pop()}: ${changed ? 'state changed' : 'state same'}, ${drawn ? 'redrawn' : 'NOT redrawn'}`);
      if (changed && !drawn) problems.push(`tapping "${t.id}" changed the game but not the screen`);
      reacted = drawn;   // some games keep tab or overlay state out of get_agent_state(); a redraw is the reaction
    }
    if (!reacted && !problems.length) problems.push(`no button tap redrew the screen (tried ${[...tried].join(', ') || 'none'})`);

    if (prof.rotate && !SELF_TEST) {
      const before = await pixels();
      await page.setViewportSize(prof.rotate);
      await page.waitForTimeout(1500);
      const r = await fills(prof.rotate);
      if (!r.ok) problems.push(`after rotating to landscape the canvas doesn't fill the screen: ${r.msg}`);
      else if (before === await pixels()) problems.push('after rotating to landscape the screen was not redrawn');
      else notes.push('rotated: re-laid out');
    }
  } catch (e) {
    problems.push(e.message.split('\n')[0]);
  } finally {
    if (problems.length) await page.screenshot({ path: `browsers-${browserName}-${profileName}-${game}.png` }).catch(() => {});
    await context.close();
  }
  return { problems, notes };
}

const server = await serve(SITE);
const base = `http://127.0.0.1:${server.address().port}`;
const list = await games(SITE);
let failed = 0, runs = 0;
for (const name of BROWSERS) {
  const browser = await { chromium, firefox, webkit }[name].launch();
  for (const profile of PROFILES) {
    for (const game of list) {
      const { problems, notes } = await checkGame(name, browser, profile, base, game);
      runs++;
      console.log(`${problems.length ? 'FAIL' : 'ok  '} ${name.padEnd(8)} ${profile.padEnd(7)} ${game}  ${notes.join(' | ')}`);
      for (const p of problems) console.log(`::error::${name} ${profile} ${game}: ${p}`);
      failed += problems.length ? 1 : 0;
    }
  }
  await browser.close();
}
server.close();
if (SELF_TEST) {
  console.log(`self-test: ${failed}/${runs} runs with a frozen screen were caught`);
  process.exit(failed === runs ? 0 : 1);
}
console.log(`browsers: ${list.length} games, ${runs} runs, ${failed} failed`);
process.exit(failed ? 1 : 0);
