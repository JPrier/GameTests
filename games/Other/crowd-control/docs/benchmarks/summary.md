### Simulation benchmark (release build, Intel(R) Xeon(R) Processor @ 2.10GHz, 2 cores)

| population | peak agents | p50 ms | p95 ms | p99 ms | max ms | baseline p95 | ratio | status |
|---:|---:|---:|---:|---:|---:|---:|---:|---|
| 500 | 496 | 0.31 | 2.49 | 3.11 | 4.37 | 2.49 | 1.00 | ok |
| 1000 | 793 | 0.64 | 3.00 | 4.08 | 31.76 | 3.00 | 1.00 | ok |
| 5000 | 4414 | 2.13 | 6.17 | 7.90 | 11.40 | 6.17 | 1.00 | ok |
| 10000 | 6636 | 3.54 | 11.37 | 14.00 | 20.37 | 11.37 | 1.00 | ok |

Overall: **ok** (warn above 1.5x, fail above 3.0x the baseline p95)
