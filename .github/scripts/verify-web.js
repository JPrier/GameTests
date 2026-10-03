// Verify every exported game in a real browser, on the engine it will ship with.
//
//   node .github/scripts/verify-web.js <site-dir> [game ...]
//
// For each game (default: every folder in <site-dir> with an index.wasm):
//   1. load it in headless Chrome and wait for the engine to start;
//   2. fail on script/class errors (e.g. a class the slim engine left out);
//   3. run the game's own tests (res://tests/test_*.gd) inside the web build through
//      the AgentBridge autoload, exactly like `gck test --browser`;
//   4. fail if a test fails or the game has no tests: every game must ship a test.
// Writes a summary table to $GITHUB_STEP_SUMMARY (when set) and verify-web.json.
const http = require('http'), fs = require('fs'), path = require('path'), zlib = require('zlib');
const puppeteer = require('puppeteer-core');

const site = path.resolve(process.argv[2] || '_site');
const games = process.argv.slice(3).length ? process.argv.slice(3)
  : fs.readdirSync(site).filter(d => fs.existsSync(path.join(site, d, 'index.wasm'))).sort();
const LOAD_TIMEOUT = 90e3, TEST_TIMEOUT = 15 * 60e3;
// Console errors that mean the build itself is broken, not just a noisy game.
const FATAL = /SCRIPT ERROR|Parse Error|Failed to load script|Failed to instantiate an autoload|Could not find type|Cannot get class|Nonexistent function|Invalid call|Identifier ".*" not declared|RuntimeError|Aborted\(/;
const TYPES = { '.html': 'text/html', '.js': 'application/javascript', '.wasm': 'application/wasm', '.png': 'image/png' };

const server = http.createServer((req, res) => {
  let p = decodeURIComponent(req.url.split('?')[0]);
  if (p.endsWith('/')) p += 'index.html';
  const f = path.join(site, p);
  if (!f.startsWith(site) || !fs.existsSync(f) || fs.statSync(f).isDirectory()) { res.writeHead(404); return res.end(); }
  let body = fs.readFileSync(f);
  const headers = { 'Content-Type': TYPES[path.extname(f)] || 'application/octet-stream' };
  if (/gzip/.test(req.headers['accept-encoding'] || '') && body.length > 1024) {
    body = zlib.gzipSync(body, { level: 6 }); headers['Content-Encoding'] = 'gzip';
  }
  res.writeHead(200, headers); res.end(body);
});

async function chromePath() {
  for (const p of [process.env.CHROME_PATH, '/usr/bin/google-chrome', '/usr/bin/google-chrome-stable', '/usr/bin/chromium', '/usr/bin/chromium-browser'])
    if (p && fs.existsSync(p)) return { executablePath: p, args: [] };
  try { // fallback for sandboxes without Chrome: npm i @sparticuz/chromium
    const c = require('@sparticuz/chromium').default;
    return { executablePath: await c.executablePath(), args: c.args };
  } catch { throw new Error('No Chrome found: set CHROME_PATH'); }
}

function gz(file) { return fs.existsSync(file) ? zlib.gzipSync(fs.readFileSync(file), { level: 9 }).length : 0; }
const mb = n => (n / 1e6).toFixed(2);

async function verify(browser, port, game) {
  const r = { game, ok: false, wasm_mb: mb(fs.statSync(path.join(site, game, 'index.wasm')).size),
    download_mb: mb(['index.wasm', 'index.pck', 'index.js', 'index.html'].reduce((s, f) => s + gz(path.join(site, game, f)), 0)) };
  const page = await browser.newPage();
  const errors = [];
  page.on('console', m => { if (m.type() === 'error') errors.push(m.text()); });
  page.on('pageerror', e => errors.push(String(e)));
  await page.evaluateOnNewDocument(() => {
    window.__bridgeOut = [];
    window.__agentBridgeRegister = cb => { window.__bridgeCb = cb; };
    window.__agentBridgeSend = text => { window.__bridgeOut.push(text); };
  });
  const send = (id, cmd, args = {}) => page.evaluate((m) => window.__bridgeCb(m), JSON.stringify({ id, cmd, args }));
  const reply = (id, timeout) => page.waitForFunction((id) => window.__bridgeOut
    .map(t => { try { return JSON.parse(t); } catch { return null; } })
    .find(m => m && m.type === 'response' && m.id === id), { timeout, polling: 200 }, id).then(h => h.jsonValue());
  try {
    const t0 = Date.now();
    await page.goto(`http://127.0.0.1:${port}/${game}/`, { waitUntil: 'domcontentloaded' });
    await page.waitForFunction(() => !document.getElementById('status'), { timeout: LOAD_TIMEOUT, polling: 50 });
    r.start_s = ((Date.now() - t0) / 1000).toFixed(2);
    await page.waitForFunction(() => !!window.__bridgeCb, { timeout: 15e3 })
      .catch(() => { throw new Error('AgentBridge autoload did not start: ' + (errors.filter(e => FATAL.test(e)).slice(0, 3).join(' | ') || 'no error logged')); });
    await new Promise(res => setTimeout(res, 500));
    const fatal = errors.filter(e => FATAL.test(e));
    if (fatal.length) throw new Error('errors while starting: ' + fatal.slice(0, 3).join(' | '));
    // Like the headless test runner: take the main scene out so tests start clean.
    await send(1, 'eval', { expr: 'scene.queue_free()' });
    await reply(1, 10e3).catch(() => {});
    await send(2, 'run_tests');
    const res = await reply(2, TEST_TIMEOUT);
    if (!res.ok) throw new Error('run_tests failed: ' + res.error);
    const rep = res.result;
    r.tests = `${rep.passed}/${rep.total}`;
    if (!rep.total) throw new Error('no tests found: every game must ship tests/test_*.gd with at least one test_ method');
    const failed = rep.results.filter(t => !t.passed);
    if (failed.length) throw new Error(`${failed.length} test(s) failed in the browser: ` +
      failed.slice(0, 5).map(t => `${t.file.split('/').pop()}::${t.test}: ${t.message}`).join(' | '));
    const late = errors.filter(e => FATAL.test(e));
    if (late.length) throw new Error('errors while testing: ' + late.slice(0, 3).join(' | '));
    r.ok = true;
  } catch (e) {
    r.error = String(e.message || e).slice(0, 600);
  } finally {
    r.console_errors = errors.length;
    await page.close();
  }
  return r;
}

(async () => {
  server.listen(0);
  const port = server.address().port;
  const c = await chromePath();
  const browser = await puppeteer.launch({ executablePath: c.executablePath, headless: true,
    args: [...c.args, '--no-sandbox', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  const results = [];
  for (const g of games) {
    const r = await verify(browser, port, g);
    results.push(r);
    console.log(`${r.ok ? 'PASS' : 'FAIL'} ${g}: engine ${r.wasm_mb} MB, download ${r.download_mb} MB gz, start ${r.start_s ?? '-'} s, tests ${r.tests ?? '-'}${r.error ? '\n  ' + r.error : ''}`);
  }
  await browser.close(); server.close();
  fs.writeFileSync('verify-web.json', JSON.stringify(results, null, 2));
  if (process.env.GITHUB_STEP_SUMMARY) {
    const rows = results.map(r => `| ${r.ok ? '✅' : '❌'} ${r.game} | ${r.wasm_mb} MB | ${r.download_mb} MB | ${r.start_s ?? '–'} s | ${r.tests ?? '–'} | ${r.error ? r.error.replace(/\|/g, '/').slice(0, 200) : ''} |`);
    fs.appendFileSync(process.env.GITHUB_STEP_SUMMARY, ['## Browser verification', '',
      '| Game | Engine (raw) | Download (gzip) | Start | Tests | Problem |', '|---|---:|---:|---:|---:|---|', ...rows, ''].join('\n') + '\n');
  }
  process.exit(results.every(r => r.ok) ? 0 : 1);
})().catch(e => { console.error(e); process.exit(1); });
