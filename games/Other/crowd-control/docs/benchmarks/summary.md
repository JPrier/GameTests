### Simulation benchmark (release build, Intel(R) Xeon(R) Processor @ 2.10GHz, 2 cores)

| population | peak agents | p50 ms | p95 ms | p99 ms | max ms | baseline p95 | ratio | status |
|---:|---:|---:|---:|---:|---:|---:|---:|---|
| 500 | 482 | 0.11 | 0.25 | 0.31 | 7.40 | 0.25 | 1.00 | ok |
| 1000 | 664 | 0.17 | 0.35 | 0.45 | 1.19 | 0.35 | 1.00 | ok |
| 5000 | 4286 | 1.56 | 4.10 | 5.59 | 38.25 | 4.10 | 1.00 | ok |
| 10000 | 5267 | 1.92 | 4.84 | 5.78 | 9.38 | 4.84 | 1.00 | ok |

Overall: **ok** (warn above 1.5x, fail above 3.0x the baseline p95)
