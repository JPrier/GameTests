#!/usr/bin/env node
// Frame-rate benchmark for every game on the built site (_site/<slug>/).
//
// Each game runs in headless Chromium emulating the target phone in target.json (iPhone X:
// 375x812 CSS px at 3x, touch). The main thread is CPU-throttled to the target's
// CPU score, calibrated against this machine on every run, so the target does not depend on
// how fast the CI runner happens to be.
//
// For every game, with no setup needed:
//   idle   - the first screen, untouched
//   taps   - a grid of taps across the whole screen
//   swipes - vertical and horizontal drags
// A game can add heavier phases in bench/scenario.json (see README.md next to this file).
//
// What's measured: the main-thread CPU time of each game frame (Godot's requestAnimationFrame
// callback), minus time blocked in synchronous WebGL calls. CI has no GPU, so those calls wait on
// a software rasteriser and say nothing about a phone. A phase passes when its sustained fps,
// average frame, share of frames over 16.7 ms and worst frame are all inside the budget.
//
//   node bench.mjs <site_dir> <game_dir>...       (game dirs come from gamelist.py)
// Env: BENCH_ONLY=slug[,slug]   BENCH_OUT=results.json   CHROMIUM_PATH=/path/to/chrome
//      BENCH_RATE=<n> skips calibration and throttles by exactly n
import fs from "node:fs";
import http from "node:http";
import path from "node:path";
import { chromium } from "playwright";

const HERE = path.dirname(new URL(import.meta.url).pathname);
const TARGET = JSON.parse(fs.readFileSync(path.join(HERE, "target.json"), "utf8"));
TARGET.cpu.score = Math.round(TARGET.cpu.runnerScore / TARGET.cpu.slowdown);
const [siteDir, ...gameDirs] = process.argv.slice(2);
if (!siteDir || gameDirs.length === 0) {
  console.error("usage: bench.mjs <site_dir> <game_dir>...");
  process.exit(2);
}
const only = (process.env.BENCH_ONLY || "").split(",").map((s) => s.trim()).filter(Boolean);
const games = gameDirs
  .map((dir) => ({ dir, slug: path.basename(dir) }))
  .filter((g) => only.length === 0 || only.includes(g.slug));

const VSYNC_MS = 1000 / 60;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const gh = (line) => process.env.GITHUB_ACTIONS && console.log(line);

// ------------------------------------------------------------------ static server

const MIME = {
  ".html": "text/html", ".js": "text/javascript", ".wasm": "application/wasm", ".pck": "application/octet-stream",
  ".png": "image/png", ".jpg": "image/jpeg", ".webp": "image/webp", ".svg": "image/svg+xml",
  ".json": "application/json", ".css": "text/css", ".ico": "image/x-icon",
};
function serve(dir) {
  const root = path.resolve(dir);
  const server = http.createServer((req, res) => {
    let p = decodeURIComponent(new URL(req.url, "http://x").pathname);
    if (p.endsWith("/")) p += "index.html";
    const file = path.join(root, path.normalize(p));
    if (!file.startsWith(root) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) {
      res.writeHead(404).end();
      return;
    }
    res.writeHead(200, { "Content-Type": MIME[path.extname(file)] || "application/octet-stream", "Cache-Control": "no-store" });
    fs.createReadStream(file).pipe(res);
  });
  return new Promise((r) => server.listen(0, "127.0.0.1", () => r(server)));
}

// ------------------------------------------------------------------ page instrumentation

// Runs in every page before the game: frame clock, long tasks, and the AgentBridge web hooks
// (the bridge talks to window.__agentBridgeRegister/__agentBridgeSend when it finds them).
const INIT = () => {
  const b = (window.__bench = { ticks: [], work: [], longtasks: [], errors: [], ready: false, bridge: null, responses: {}, nextId: 1 });
  const raf = window.requestAnimationFrame.bind(window);
  const loop = (t) => { b.ticks.push(t); raf(loop); };
  raf(loop);

  // CI has no GPU: WebGL runs on SwiftShader, and synchronous GL calls block the main thread until
  // the software rasteriser catches up. Time spent inside them is counted as GPU wait and taken out,
  // so what's left is the frame's real CPU cost: game code, engine and GL command submission.
  const wait = { ms: 0, calls: 0, depth: 0 };
  const SYNC = ["getParameter", "getError", "finish", "readPixels", "clientWaitSync", "getSyncParameter",
    "getBufferSubData", "getQueryParameter", "checkFramebufferStatus", "getProgramParameter",
    "getShaderParameter", "getProgramInfoLog", "getShaderInfoLog", "getFramebufferAttachmentParameter",
    "getActiveUniform", "getUniformLocation", "getAttribLocation", "getTexParameter", "getExtension"];
  for (const C of [window.WebGLRenderingContext, window.WebGL2RenderingContext]) {
    if (!C) continue;
    for (const name of SYNC) {
      const orig = C.prototype[name];
      if (typeof orig !== "function") continue;
      C.prototype[name] = function (...args) {
        if (wait.depth++) { try { return orig.apply(this, args); } finally { wait.depth--; } }
        const s = performance.now();
        try { return orig.apply(this, args); } finally { wait.ms += performance.now() - s; wait.calls++; wait.depth--; }
      };
    }
  }
  // Every other rAF callback is the game's frame (Godot's main loop runs once per animation frame).
  window.requestAnimationFrame = (cb) => raf((t) => {
    const w0 = wait.ms, c0 = wait.calls, s = performance.now();
    try { cb(t); } finally {
      const total = performance.now() - s, gpu = wait.ms - w0;
      b.work.push([s, Math.max(0, total - gpu), gpu, wait.calls - c0]);
    }
  });

  try {
    new PerformanceObserver((l) => l.getEntries().forEach((e) => b.longtasks.push([e.startTime, e.duration])))
      .observe({ type: "longtask", buffered: true });
  } catch {}
  window.__agentBridgeRegister = (cb) => { b.bridge = cb; };
  window.__agentBridgeSend = (text) => {
    let m;
    try { m = JSON.parse(text); } catch { return; }
    if (m.type === "event" && m.event === "ready") b.ready = true;
    if (m.type === "event" && m.event === "log" && m.entry && m.entry.level === "error") b.errors.push(m.entry.text);
    if (m.type === "response") b.responses[m.id] = m;
  };
  b.call = (msg) => {
    if (!b.bridge) return null;
    const id = b.nextId++;
    b.bridge(JSON.stringify({ ...msg, id }));
    return id;
  };
};

// CPU score: iterations per second of a mixed workload (float math, allocation + sort, Map and
// string keys) that the JIT cannot optimise away, roughly what a frame of game code does.
const CPU_SCORE = () => {
  let n = 0, sink = 0;
  const t0 = performance.now();
  while (performance.now() - t0 < 1000) {
    const a = new Float64Array(4096);
    for (let i = 0; i < a.length; i++) a[i] = Math.sin(i * 0.01 + n) * 1000;
    const objs = [];
    for (let i = 0; i < 512; i++) objs.push({ k: a[(i * 7) % 4096] | 0, i });
    objs.sort((x, y) => x.k - y.k);
    const m = new Map();
    for (let i = 0; i < 256; i++) m.set("k" + (objs[i].k & 127), i);
    sink += m.size + objs[0].k;
    n++;
  }
  window.__sink = sink;
  return Math.round(n / ((performance.now() - t0) / 1000));
};

// ------------------------------------------------------------------ browser

async function launch() {
  return chromium.launch({
    headless: true,
    executablePath: process.env.CHROMIUM_PATH || undefined,
    args: [
      "--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist",
      "--disable-background-timer-throttling", "--disable-renderer-backgrounding",
      "--disable-backgrounding-occluded-windows", "--autoplay-policy=no-user-gesture-required",
      "--no-sandbox",
    ],
  });
}

async function newPhone(browser) {
  const context = await browser.newContext({
    viewport: TARGET.viewport,
    // Layout comes from the CSS viewport (Godot's canvas_items stretch follows the aspect ratio),
    // so the game does the same work at any pixel density. CI renders at a low density because
    // pixels only cost software-GPU time, which is not measured.
    deviceScaleFactor: TARGET.ciRenderScale ?? TARGET.deviceScaleFactor,
    isMobile: true,
    hasTouch: true,
  });
  const page = await context.newPage();
  const cdp = await context.newCDPSession(page);
  return { context, page, cdp };
}

async function calibrate(browser) {
  const { context, page, cdp } = await newPhone(browser);
  await page.goto("about:blank");
  const host = Math.max(...[await page.evaluate(CPU_SCORE), await page.evaluate(CPU_SCORE), await page.evaluate(CPU_SCORE)]);
  if (process.env.BENCH_RATE) {
    await context.close();
    return { host: Math.round(host), rate: +process.env.BENCH_RATE, throttled: null };
  }
  let rate = Math.max(1, host / TARGET.cpu.score);
  let measured = host;
  for (let i = 0; i < 3 && rate > 1; i++) {
    await cdp.send("Emulation.setCPUThrottlingRate", { rate });
    measured = await page.evaluate(CPU_SCORE);
    const err = measured / TARGET.cpu.score;
    if (Math.abs(err - 1) < 0.08) break;
    rate = Math.max(1, rate * err);
  }
  await context.close();
  return { host: Math.round(host), rate: +rate.toFixed(2), throttled: Math.round(measured) };
}

// ------------------------------------------------------------------ input

async function touch(cdp, type, points) {
  await cdp.send("Input.dispatchTouchEvent", {
    type,
    touchPoints: points.map(([x, y]) => ({ x, y, radiusX: 4, radiusY: 4, force: 1, id: 0 })),
  });
}
const px = ([fx, fy]) => [fx * TARGET.viewport.width, fy * TARGET.viewport.height];

async function tap(cdp, at) {
  await touch(cdp, "touchStart", [px(at)]);
  await sleep(60);
  await touch(cdp, "touchEnd", []);
}

async function drag(cdp, from, to, ms = 300) {
  const [a, b] = [px(from), px(to)];
  const steps = Math.max(2, Math.round(ms / VSYNC_MS));
  await touch(cdp, "touchStart", [a]);
  for (let i = 1; i <= steps; i++) {
    const t = i / steps;
    await touch(cdp, "touchMove", [[a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t]]);
    await sleep(VSYNC_MS);
  }
  await touch(cdp, "touchEnd", []);
}

async function bridgeCall(page, msg, timeoutMs = 30000) {
  const id = await page.evaluate((m) => window.__bench.call(m), msg);
  if (id === null) throw new Error(`"${msg.cmd}" needs the AgentBridge addon in this game`);
  const res = await page
    .waitForFunction((i) => window.__bench.responses[i], id, { timeout: timeoutMs, polling: 50 })
    .then((h) => h.jsonValue());
  if (!res.ok) throw new Error(`${msg.cmd} failed: ${res.error}`);
  return res.result;
}

// Scenario steps (bench/scenario.json). Coordinates are fractions of the screen: [0.5, 0.9].
async function runStep(page, cdp, step) {
  if (step.tap) return tap(cdp, step.tap);
  if (step.drag) return drag(cdp, step.drag.from, step.drag.to, step.drag.ms);
  if (step.wait !== undefined) return sleep(step.wait * 1000);
  if (step.repeat) {
    for (let i = 0; i < step.repeat.times; i++) for (const s of step.repeat.steps) await runStep(page, cdp, s);
    return;
  }
  if (step.call) return bridgeCall(page, { cmd: "call", args: step.call });
  if (step.eval) return bridgeCall(page, { cmd: "eval", args: typeof step.eval === "string" ? { expr: step.eval } : step.eval });
  if (step.key) return page.keyboard.press(step.key);
  throw new Error(`unknown scenario step: ${JSON.stringify(step)}`);
}

// ------------------------------------------------------------------ measuring

const now = (page) => page.evaluate(() => performance.now());

async function measure(page, name, body) {
  const t0 = await now(page);
  await body();
  const t1 = await now(page);
  const { work, ticks } = await page.evaluate(([a, b]) => ({
    work: window.__bench.work.filter(([s]) => s >= a && s <= b),
    ticks: window.__bench.ticks.filter((t) => t >= a && t <= b),
  }), [t0, t1]);
  return { name, ...stats(work, ticks) };
}

const pct = (sorted, q) => sorted[Math.min(sorted.length - 1, Math.floor(sorted.length * q))];
const r1 = (x) => +x.toFixed(1);

function stats(work, ticks) {
  if (work.length < 10) return { frames: work.length, avgMs: Infinity, p95Ms: Infinity, maxMs: Infinity, overPct: 100, fps: 0, cpuFps: 0, gpuWaitMs: 0, syncCalls: 0 };
  const cpu = work.map((w) => w[1]).sort((a, b) => a - b);
  const avg = cpu.reduce((a, b) => a + b, 0) / cpu.length;
  const over = cpu.filter((x) => x > VSYNC_MS).length;
  const span = ticks.length > 1 ? ticks[ticks.length - 1] - ticks[0] : 1;
  return {
    frames: work.length,
    avgMs: r1(avg),
    p95Ms: r1(pct(cpu, 0.95)),
    maxMs: r1(cpu[cpu.length - 1]),
    overPct: r1((over / cpu.length) * 100),
    // Frame rate the CPU side can sustain at a 60 Hz display: frames that fit a vsync take one,
    // longer ones take as many vsyncs as they need.
    cpuFps: r1((60 * cpu.length) / cpu.reduce((a, x) => a + Math.max(1, Math.ceil(x / VSYNC_MS)), 0)),
    // What the software-GPU browser actually showed. Not gated: it measures SwiftShader.
    fps: r1(((ticks.length - 1) / span) * 1000),
    gpuWaitMs: r1(work.reduce((a, w) => a + w[2], 0) / work.length),
    syncCalls: r1(work.reduce((a, w) => a + w[3], 0) / work.length),
  };
}

function judge(phase) {
  const b = TARGET.budget;
  const why = [];
  if (phase.frames < 10) why.push(`only ${phase.frames} frames rendered`);
  if (phase.cpuFps < b.minFps) why.push(`${phase.cpuFps} fps < ${b.minFps}`);
  if (phase.avgMs > b.maxAvgFrameMs) why.push(`avg frame ${phase.avgMs} ms > ${b.maxAvgFrameMs} ms`);
  if (phase.overPct > b.maxSlowFramePct) why.push(`${phase.overPct}% of frames over 16.7 ms > ${b.maxSlowFramePct}%`);
  if (phase.maxMs > b.maxFrameMs) why.push(`worst frame ${phase.maxMs} ms > ${b.maxFrameMs} ms`);
  return why;
}

// ------------------------------------------------------------------ one game

function loadScenario(dir) {
  const file = path.join(dir, "bench", "scenario.json");
  if (!fs.existsSync(file)) return null;
  return JSON.parse(fs.readFileSync(file, "utf8"));
}

async function benchGame(browser, base, game, rate) {
  const P = TARGET.phases;
  const url = `${base}/${game.slug}/`;
  const { context, page, cdp } = await newPhone(browser);
  const pageErrors = [];
  try {
    await page.addInitScript(INIT);
    // Stay on the game: a tap on a link or share button must not navigate away mid-measurement.
    let loaded = false;
    await page.route("**/*", (route) => {
      const r = route.request();
      if (loaded && r.isNavigationRequest() && r.frame() === page.mainFrame()) return route.abort();
      return route.continue();
    });
    context.on("page", (p) => p.close().catch(() => {}));
    page.on("pageerror", (e) => pageErrors.push(String(e.message || e)));
    page.on("dialog", (d) => d.dismiss().catch(() => {}));
    await cdp.send("Emulation.setCPUThrottlingRate", { rate });

    const start = Date.now();
    await page.goto(url, { waitUntil: "load", timeout: TARGET.loadTimeoutSeconds * 1000 });
    // Ready = AgentBridge said so, or (no bridge) the default shell's loading overlay is gone.
    await page.waitForFunction(() => {
      if (window.__bench.ready) return true;
      const s = document.getElementById("status");
      return !!document.querySelector("canvas") && (!s || getComputedStyle(s).display === "none") && window.__bench.work.length > 30;
    }, null, { timeout: TARGET.loadTimeoutSeconds * 1000, polling: 100 }).catch(async (e) => {
      const st = await page.evaluate(() => window.__bench && { ready: window.__bench.ready, frames: window.__bench.work.length, bridge: !!window.__bench.bridge }).catch(() => null);
      throw new Error(`game never became ready in ${TARGET.loadTimeoutSeconds}s (${JSON.stringify(st)})`);
    });
    const loadSeconds = +((Date.now() - start) / 1000).toFixed(1);
    loaded = true;
    await sleep(P.warmupSeconds * 1000);

    const phases = [];
    phases.push(await measure(page, "idle", () => sleep(P.idleSeconds * 1000)));

    phases.push(await measure(page, "taps", async () => {
      const { cols, rows, pauseMs } = P.tapGrid;
      for (let r = 0; r < rows; r++)
        for (let c = 0; c < cols; c++) {
          await tap(cdp, [(c + 0.5) / cols, (r + 0.5) / rows]);
          await sleep(pauseMs);
        }
    }));

    phases.push(await measure(page, "swipes", async () => {
      const moves = [
        [[0.5, 0.75], [0.5, 0.25]], [[0.5, 0.25], [0.5, 0.75]],
        [[0.8, 0.5], [0.2, 0.5]], [[0.2, 0.5], [0.8, 0.5]],
      ];
      for (let i = 0; i < P.swipes; i++) {
        const [from, to] = moves[i % moves.length];
        await drag(cdp, from, to, 350);
        await sleep(250);
      }
    }));

    const scenario = loadScenario(game.dir);
    for (const sp of scenario?.phases || []) {
      for (const s of sp.setup || []) await runStep(page, cdp, s);
      phases.push(await measure(page, sp.name, async () => {
        for (const s of sp.steps || []) await runStep(page, cdp, s);
      }));
    }

    const errors = await page.evaluate(() => window.__bench.errors.slice(0, 5));
    for (const p of phases) p.fail = judge(p);
    return { slug: game.slug, loadSeconds, phases, errors: [...pageErrors, ...errors].slice(0, 5), scenario: !!scenario };
  } catch (e) {
    return { slug: game.slug, crash: String(e.message || e).split("\n")[0], phases: [], errors: pageErrors.slice(0, 5) };
  } finally {
    await context.close().catch(() => {});
  }
}

const failed = (r) => !!r.crash || r.phases.some((p) => p.fail.length);
// When retrying, keep the run whose worst phase did best.
const score = (r) => (r.crash ? -1e9 : -r.phases.reduce((a, p) => a + p.fail.length * 1000 + p.overPct + p.avgMs, 0));

// ------------------------------------------------------------------ main

const server = await serve(siteDir);
const base = `http://127.0.0.1:${server.address().port}`;
const browser = await launch();
const cal = await calibrate(browser);
console.log(`Target: ${TARGET.device} ${TARGET.viewport.width}x${TARGET.viewport.height}@${TARGET.deviceScaleFactor}x, ` +
  `CPU score ${TARGET.cpu.score} (runner ${cal.host}, throttle ${cal.rate}x -> ${cal.throttled})`);

const results = [];
for (const game of games) {
  if (!fs.existsSync(path.join(siteDir, game.slug, "index.html"))) {
    results.push({ slug: game.slug, crash: "not on the built site", phases: [], errors: [] });
    continue;
  }
  let r = await benchGame(browser, base, game, cal.rate);
  for (let i = 0; i < TARGET.retries && failed(r); i++) {
    console.log(`  ${game.slug}: over budget, retrying to rule out runner noise`);
    const again = await benchGame(browser, base, game, cal.rate);
    if (score(again) > score(r)) r = again;
  }
  results.push(r);
  const summary = r.crash ? `CRASH ${r.crash}` :
    r.phases.map((p) => `${p.name} ${p.cpuFps}fps avg${p.avgMs} p95 ${p.p95Ms} max${p.maxMs}ms slow${p.overPct}% (gpu-wait ${p.gpuWaitMs}ms, ${p.syncCalls} sync, shown ${p.fps}fps)${p.fail.length ? " ✗" : ""}`).join(" | ");
  console.log(`${failed(r) ? "FAIL" : "ok  "} ${game.slug} (load ${r.loadSeconds ?? "-"}s): ${summary}`);
}
await browser.close();
server.close();

// ------------------------------------------------------------------ report

const b = TARGET.budget;
const lines = [
  `## Frame budget: ${TARGET.device} at 60 fps`,
  "",
  `Screen ${TARGET.viewport.width}×${TARGET.viewport.height} @${TARGET.deviceScaleFactor}x with touch. ` +
  `Main thread throttled ${cal.rate}× (this runner's CPU score ${cal.host} → ${cal.throttled ?? "fixed rate"}; ` +
  `target ${TARGET.cpu.score}, ${TARGET.cpu.slowdown}× slower than a reference runner). ` +
  `Each frame is the CPU time of the game's frame with time blocked on CI's software GPU removed.`,
  "",
  `Budget per phase: ≥ ${b.minFps} fps, average frame ≤ ${b.maxAvgFrameMs} ms, ≤ ${b.maxSlowFramePct}% of frames over 16.7 ms, no frame over ${b.maxFrameMs} ms.`,
  "",
  "| Game | Load | Phase | fps | Avg | p95 | Worst | Over 16.7 ms | |",
  "|---|---|---|---|---|---|---|---|---|",
];
for (const r of results) {
  if (r.crash) {
    lines.push(`| **${r.slug}** | | | | | | | | ❌ ${r.crash} |`);
    continue;
  }
  r.phases.forEach((p, i) => {
    lines.push(`| ${i === 0 ? `**${r.slug}**` : ""} | ${i === 0 ? `${r.loadSeconds}s` : ""} | ${p.name} | ${p.cpuFps} | ${p.avgMs} ms | ${p.p95Ms} ms | ${p.maxMs} ms | ${p.overPct}% | ${p.fail.length ? "❌ " + p.fail.join("; ") : "✅"} |`);
  });
}
const bad = results.filter(failed);
lines.push("", bad.length ? `**${bad.length} of ${results.length} games over budget.**` : `All ${results.length} games inside the budget.`);
const md = lines.join("\n") + "\n";
if (process.env.GITHUB_STEP_SUMMARY) fs.appendFileSync(process.env.GITHUB_STEP_SUMMARY, md);
fs.writeFileSync(process.env.BENCH_OUT || "bench-results.json", JSON.stringify({ target: TARGET, calibration: cal, results }, null, 2));

gh(`::notice title=Frame budget calibration::runner CPU score ${cal.host}, throttle ${cal.rate}x, throttled score ${cal.throttled ?? "-"}, target ${TARGET.cpu.score}`);
for (const r of results.filter((x) => !failed(x))) {
  gh(`::notice title=${r.slug} inside the budget::${r.phases.map((p) => `${p.name} ${p.cpuFps} fps, avg ${p.avgMs} ms, worst ${p.maxMs} ms`).join("; ")}`);
}
for (const r of bad) {
  const why = r.crash || r.phases.filter((p) => p.fail.length).map((p) => `${p.name}: ${p.fail.join(", ")}`).join("; ");
  gh(`::error title=${r.slug} over the ${TARGET.device} 60 fps budget::${why}`);
}
if (!process.env.GITHUB_ACTIONS) console.log("\n" + md);
process.exit(bad.length ? 1 : 0);
