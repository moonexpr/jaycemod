# ns-bench

**Question:** where do soldiers fail to walk on real geometry? A bench is a region of a shipped map
cut out by a cordon; its errands (walks from a start to a goal in a time) run again and again.

```bash
python3 .workbench/experiments/ns-bench/ns_bench_map.py dev_watchtower_ns_locomotion [--install]
python3 .workbench/experiments/ns-bench/ns_bench_run.py dev_watchtower_ns_locomotion [--kind follower|bot|both]
```

Results: `results/<bench>/` (ignored by git). Status: open.
