# dev-3house

**Question:** do squads carry out room operations (muster, stage, assault, clear, evacuate) on a
small known map, a stage at a time, and how do armed assaults on a held building go?

| Script | Does |
|---|---|
| `dev_3house_map.py` | Builds the map through hammer-mcp |
| `dev_3house_nav.lua` | Its nav mesh, on a live server |
| `dev_3house_bench.lua` | The room-operations bench, stage by stage |
| `dev_3house_trial.lua` | Armed assault trials, RED on BLU |

`.devtools/bin/rooms/assault_view.py` draws the bench's placements. Status: open.
