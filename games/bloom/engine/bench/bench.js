// Load-time bench for a Godot web export.
//   node bench.js <site-dir> [runs] [profile]
// Serves <site-dir> with on-the-fly gzip (like GitHub Pages), loads it in headless
// Chromium under a throttled network/CPU, and reports time until the Godot loading
// overlay is gone (engine started, first frame scheduled).
const http = require('http'), fs = require('fs'), path = require('path'), zlib = require('zlib');
const puppeteer = require('puppeteer-core');
const chromium = require('@sparticuz/chromium').default;

const dir = path.resolve(process.argv[2]);
const runs = +(process.argv[3] || 3);
const PROFILES = {
  // "good connection": 50 Mbps / 20 ms RTT, desktop CPU
  good: { down: 50e6 / 8, up: 10e6 / 8, latency: 20, cpu: 1 },
  // typical phone on 4G: 12 Mbps / 70 ms, 4x slower CPU
  phone: { down: 12e6 / 8, up: 3e6 / 8, latency: 70, cpu: 4 },
};
const prof = PROFILES[process.argv[4] || 'good'];
const TYPES = { '.html': 'text/html', '.js': 'application/javascript', '.wasm': 'application/wasm', '.pck': 'application/octet-stream', '.png': 'image/png' };
const COMPRESS = new Set(['.html', '.js', '.wasm']);
const cache = {};

const server = http.createServer((req, res) => {
  let p = decodeURIComponent(req.url.split('?')[0]);
  if (p.endsWith('/')) p += 'index.html';
  const f = path.join(dir, p);
  if (!f.startsWith(dir) || !fs.existsSync(f)) { res.writeHead(404); return res.end(); }
  const ext = path.extname(f);
  const headers = { 'Content-Type': TYPES[ext] || 'application/octet-stream' };
  let body = fs.readFileSync(f);
  if (COMPRESS.has(ext) && /gzip/.test(req.headers['accept-encoding'] || '')) {
    body = cache[f] ||= zlib.gzipSync(body, { level: 6 });
    headers['Content-Encoding'] = 'gzip';
  }
  headers['Content-Length'] = body.length;
  res.writeHead(200, headers); res.end(body);
}).listen(0);

(async () => {
  const port = server.address().port;
  const browser = await puppeteer.launch({
    executablePath: await chromium.executablePath(),
    args: [...chromium.args, '--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'],
    headless: true,
  });
  const times = [];
  for (let i = 0; i < runs; i++) {
    const page = await browser.newPage();
    const cdp = await page.createCDPSession();
    await cdp.send('Network.enable');
    await cdp.send('Network.setCacheDisabled', { cacheDisabled: true });
    await cdp.send('Network.emulateNetworkConditions', { offline: false, latency: prof.latency, downloadThroughput: prof.down, uploadThroughput: prof.up });
    await cdp.send('Emulation.setCPUThrottlingRate', { rate: prof.cpu });
    let bytes = 0; const reqs = {};
    cdp.on('Network.loadingFinished', e => { bytes += e.encodedDataLength; });
    cdp.on('Network.requestWillBeSent', e => { const u = e.request.url.split('/').pop(); reqs[u] = (reqs[u] || 0) + 1; });
    const errors = [];
    page.on('pageerror', e => errors.push(String(e)));
    page.on('console', m => { if (m.type() === 'error') errors.push(m.text()); });
    const t0 = Date.now();
    await page.goto(`http://127.0.0.1:${port}/`, { waitUntil: 'domcontentloaded' });
    await page.waitForFunction(() => !document.getElementById('status'), { timeout: 180000, polling: 50 });
    const ms = Date.now() - t0;
    times.push(ms);
    console.log(`run ${i + 1}: ${(ms / 1000).toFixed(2)} s, ${(bytes / 1e6).toFixed(2)} MB over the wire, requests ${JSON.stringify(reqs)}${errors.length ? '\n  errors: ' + errors.slice(0, 5).join(' | ') : ''}`);
    if (i === 0 && process.env.SHOT) { await new Promise(r => setTimeout(r, 1500)); await page.screenshot({ path: process.env.SHOT }); }
    await page.close();
  }
  times.sort((a, b) => a - b);
  console.log(`median ${(times[times.length >> 1] / 1000).toFixed(2)} s`);
  await browser.close(); server.close();
})().catch(e => { console.error(e); process.exit(1); });
