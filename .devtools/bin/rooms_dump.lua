-- The running map's room graph and windows (the AI war controller's
-- RoomGraph, what wartactics.rooms.Partition is given) as JSON, for
-- rooms_view.py to partition and draw off the server:
--     dt lua -f .devtools/bin/rooms_dump.lua > .devtools/artifacts/rooms/<map>.graph.json
-- Area ids are keys as strings; everything else is as the graph holds it.
local Controller = WS.Feature("aiwar")
local graph, windows = Controller:RoomGraph({ CheckYield = function() end })
local areas = {}
for id, area in pairs(graph) do areas[tostring(id)] = area end
print(util.TableToJSON({ map = game.GetMap(), areas = areas, windows = windows }))
