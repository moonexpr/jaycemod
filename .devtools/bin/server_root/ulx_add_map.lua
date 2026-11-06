if not Watch then return end

-- `ulx addmap <item> [map] [change]`, "!addmap" in chat: a Workshop map onto this
-- server, for the dedicated server (server_root.py). Lua cannot download an item,
-- so the command asks the host: a line of the watch log, which add_map.py --serve
-- follows, answering in chat. Alone on the server the map changes; with others on
-- it only when asked. ULX includes this module on both sides; the command runs on
-- the server.
local REQUEST = "add_map_request"
local ACK_TIMER = "ws_add_map_ack" -- add_map.py removes it as it takes a request
local ACK_SECONDS = 5
local NO_WORKER = "add_map: nothing answered on the host. Run there: dt add_map --serve"
local MAP_HINT = "map, of an item of several"

local function OthersOn(ply)
	for _, human in ipairs(player.GetHumans()) do
		if human ~= ply then return true end
	end
	return false
end

local function AddMap(ply, item, map, change)
	if map == MAP_HINT then map = "" end -- XGUI's box starts as the hint, and sends it
	Watch.Emit(REQUEST, util.TableToJSON({ item = item, map = map, change = change or not OthersOn(ply) }))
	ulx.fancyLogAdmin(ply, "#A asked for Workshop map #s", item)
	timer.Create(ACK_TIMER, ACK_SECONDS, 1, function() ULib.tsay(nil, NO_WORKER) end)
end

local cmd = ulx.command("Sandcastle Dev", "ulx addmap", AddMap, "!addmap")
cmd:addParam({ type = ULib.cmds.StringArg, hint = "Workshop item or link" })
cmd:addParam({ type = ULib.cmds.StringArg, hint = MAP_HINT, ULib.cmds.optional })
cmd:addParam({ type = ULib.cmds.BoolArg, hint = "change map though others are on", ULib.cmds.optional })
cmd:defaultAccess(ULib.ACCESS_SUPERADMIN)
cmd:help("Downloads a Workshop map to this server, mounts it and changes to it, with no restart.")
