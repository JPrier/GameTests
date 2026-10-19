#!/usr/bin/env python3
"""Compare a `crowd bench` JSON report with the recorded baseline and print a Markdown summary.

CI machines differ from the machine that recorded the baseline, so this uses tolerances: a step-time
p95 more than 1.5x the baseline is flagged for investigation, more than 3x fails the job.
  bench_compare.py NEW.json BASELINE.json
"""
import json
import sys

WARN, FAIL = 1.5, 3.0


def main():
    new = json.load(open(sys.argv[1]))
    base = json.load(open(sys.argv[2]))
    by_pop = {r["population"]: r for r in base["results"]}
    print(f"### Simulation benchmark ({new['build']} build, {new['machine']['cpu']}, {new['machine']['logical_cores']} cores)\n")
    print("| population | peak agents | p50 ms | p95 ms | p99 ms | max ms | baseline p95 | ratio | status |")
    print("|---:|---:|---:|---:|---:|---:|---:|---:|---|")
    worst = "ok"
    for r in new["results"]:
        s = r["step_ms"]
        b = by_pop.get(r["population"])
        ratio = s["p95"] / b["step_ms"]["p95"] if b and b["step_ms"]["p95"] > 0 else 0.0
        status = "ok" if ratio <= WARN else ("investigate" if ratio <= FAIL else "REGRESSION")
        if status == "REGRESSION" or (status == "investigate" and worst == "ok"):
            worst = status
        bp = f"{b['step_ms']['p95']:.2f}" if b else "-"
        print(f"| {r['population']} | {r['peak_microscopic_agents']} | {s['p50']:.2f} | {s['p95']:.2f} | {s['p99']:.2f} | {s['max']:.2f} | {bp} | {ratio:.2f} | {status} |")
    print(f"\nOverall: **{worst}** (warn above {WARN}x, fail above {FAIL}x the baseline p95)")
    return 1 if worst == "REGRESSION" else 0


if __name__ == "__main__":
    sys.exit(main())
