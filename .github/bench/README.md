# Frame budget benchmark

Every build benchmarks every game against an iPhone X class phone at 60 fps, and fails the build
(so nothing deploys) if any game is over budget. Games are found the same way the build finds
them, so a new game is benchmarked the first time it's pushed. There's nothing to register.

## What runs

Each game loads in headless Chromium as a 375×812 touch screen, with the main thread CPU-throttled
to the target in [`target.json`](target.json). Then, with no setup from the game:

| Phase | What happens |
|---|---|
| idle | 4 s on the first screen, untouched |
| taps | a 3×5 grid of taps across the whole screen |
| swipes | vertical and horizontal drags |

Plus any phases the game adds itself (below). Taps can't navigate away: links, popups and dialogs
are blocked so the game stays on screen.

## What's measured

The CPU time of each game frame: Godot's `requestAnimationFrame` callback, minus time blocked in
synchronous WebGL calls. CI runners have no GPU, so WebGL runs on a software rasteriser and those
waits measure the rasteriser, not the game. What's left is game code, engine and draw submission,
which is what the CPU throttle scales to phone speed.

A phase passes when all of these hold (`budget` in `target.json`):

| Check | Budget |
|---|---|
| Sustained fps (frames over 16.7 ms cost extra vsyncs) | ≥ 58 |
| Average frame | ≤ 12 ms, leaving room for the browser and GPU |
| Frames over 16.7 ms | ≤ 3% |
| Worst frame | ≤ 50 ms |

A game that fails is run once more before failing the build, to rule out runner noise.

**Not covered:** GPU fill rate and shader cost on a real phone. CI renders at a low pixel density
(`ciRenderScale`) since pixels only cost software-GPU time; layout is the same because Godot's
`canvas_items` stretch follows the screen's aspect ratio, not its density.

## The CPU target

`cpu.runnerScore / cpu.slowdown` on the `CPU_SCORE` workload in `bench.mjs`. Each run measures its
own machine and sets Chrome's CPU throttle to hit that score, so a faster or slower runner gets the
same target. `slowdown` is the one knob: how much slower than a GitHub runner the phone is. Raise
it to tighten the budget.

## Adding a heavier scenario (optional)

A game can add phases in `bench/scenario.json` in its own folder (add an empty `bench/.gdignore`
so Godot skips the folder). Use it for the expensive moments the generic phases won't reach, like
a late-game save or a big animation.

```json
{
  "phases": [
    {
      "name": "late game",
      "setup": [{ "call": { "path": "", "method": "bench_late_game" } }],
      "steps": [
        { "repeat": { "times": 10, "steps": [{ "tap": [0.5, 0.85] }, { "wait": 0.2 }] } },
        { "drag": { "from": [0.5, 0.8], "to": [0.5, 0.2], "ms": 400 } },
        { "wait": 3 }
      ]
    }
  ]
}
```

`setup` runs before measuring, `steps` while measuring. Coordinates are fractions of the screen.

| Step | Does |
|---|---|
| `{"tap": [x, y]}` | tap |
| `{"drag": {"from": [x, y], "to": [x, y], "ms": 300}}` | drag |
| `{"wait": seconds}` | wait |
| `{"repeat": {"times": n, "steps": [...]}}` | repeat steps |
| `{"key": "Space"}` | key press |
| `{"call": {"path": "", "method": "m", "args": []}}` | call a method on a node (`""` is the main scene); needs the AgentBridge addon |
| `{"eval": "expression"}` | evaluate a Godot expression on the main scene; needs AgentBridge |

## Running it locally

```
GODOT_BIN=godot .github/scripts/build-site.sh
(cd .github/bench && npm install && npx playwright install chromium-headless-shell)
BENCH_ONLY=bloom .github/scripts/bench-site.sh
```

Results go to `_bench/results.json`; in CI they're in the run summary and the `frame-budget`
artifact.
