# routes

**Question:** what do the server's route searches cost, and do they answer the same when told the
blockers and spawn rooms as data up front instead of asking Lua rules area by area? Searches are
recorded live and replayed offline under plain LuaJIT.

| Script | Does |
|---|---|
| `record_routes.lua` | Records the server's route searches (WSRouteRecord) |
| `capture_routes.lua` | Captures routes as the war walks them (WSRouteCapture) |
| `capture_nav_section.lua` | A section of the mesh as a test fixture |
| `route_replay.lua` | Replays a record offline: cost, and whether each replay matched |
| `route_told_check.lua` | Asked rules against told data, on the live mesh |

Results: `results/recorded/` (ignored by git). Status: open.
