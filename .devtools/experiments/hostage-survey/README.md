# hostage-survey

**Question:** how does the AI war's hostage rescue play on each CS:S map, and where do the maps
need hotfixes? Each round's winner, reason and hostages, the nav areas soldiers were stranded on,
the Lua errors, and whether the map changed under it.

| Script | Does |
|---|---|
| `hostage_survey.py` | Plays each map a while and records it |
| `hostage_watch.py` | Samples one running game every few seconds |
| `hostage_status.lua` | What both read from the server |

Results: `results/` (ignored by git). Status: open.
