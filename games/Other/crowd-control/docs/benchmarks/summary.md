### Simulation benchmark (release build, Intel(R) Xeon(R) Processor @ 2.10GHz, 2 cores)

| population | peak agents | p50 ms | p95 ms | p99 ms | max ms | baseline p95 | ratio | status |
|---:|---:|---:|---:|---:|---:|---:|---:|---|
| 1200 | 1200 | 0.72 | 5.31 | 6.79 | 19.23 | 5.31 | 1.00 | ok |
| 6000 | 3047 | 1.17 | 5.57 | 6.75 | 15.80 | 5.57 | 1.00 | ok |
| 12000 | 3047 | 1.31 | 5.94 | 7.12 | 26.97 | 5.94 | 1.00 | ok |

Overall: **ok** (warn above 1.5x, fail above 3.0x the baseline p95)
