# foundation-bench

**Question:** are the foundation modules the hand-rolled-code epic (#12) built faster than the code
they replaced, as Lua twins and as native twins?

```bash
luajit .workbench/experiments/foundation-bench/bench_foundation.lua              # the Lua twins
WS_NATIVE=1 luajit .workbench/experiments/foundation-bench/bench_foundation.lua  # the native twins
```

Results: `results/` (ignored by git). Status: open.
