# ingame

**Question:** do Sandcastle's features work in game, map by map? The September harness: it starts
the server on each map in its plan, runs `ingame/checks/<name>.lua` one at a time through
`ingame/runner.lua`, and writes a report. ROADMAP.md keeps "the in-game checks" open.

```bash
python3 .workbench/experiments/ingame/ingame_tests.py --maps koth_viaduct   # starts and stops its own server
python3 .workbench/experiments/ingame/ingame_one.py <check>                  # one check on the server running now
```

Results: `results/` (ignored by git). Status: open. The dev workbench (`dev.reload`, scenarios)
replaced it for day-to-day checks; close it, or move its checks into the workbench, when the
roadmap item is settled.
