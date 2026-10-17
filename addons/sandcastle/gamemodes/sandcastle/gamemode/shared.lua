-- Sandcastle: Sandbox, plus working TF2 gameplay entities. On a map with a
-- tf_gamerules (any TF2 map) the round runs as in TF2; on any other map it is
-- plain Sandbox. Every override below defers to Sandbox first.
GM.Name = "Sandcastle"
GM.Author = "moonexpr"
GM.Email = ""
GM.Website = ""

DeriveGamemode("sandbox")

-- Modules in gamemode/ws/ load by prefix: sh_ on both realms, sv_ on the
-- server, cl_ on clients. sh_core defines the WS table and loads first,
-- including sh_events (the game event library) itself; the rest load in
-- name order.
function GM:WSModules(prefix)
	local files = file.Find(self.FolderName .. "/gamemode/ws/" .. prefix .. "*.lua", "LUA")
	table.sort(files)
	return files
end

local LOADED_FIRST = {
	["sh_core.lua"] = true,
	["sh_events.lua"] = true,
}

include("ws/sh_core.lua")
for _, f in ipairs(GM:WSModules("sh_")) do
	if not LOADED_FIRST[f] then include("ws/" .. f) end
end

-- TF2's team numbers (1 spectator, 2 RED, 3 BLU); GMod reserves only 0, 1001 and 1002.
function GM:CreateTeams()
	self.BaseClass.CreateTeams(self)
	team.SetUp(WS.TEAM_SPECTATOR, "Spectator", Color(200, 200, 200), true)
	team.SetUp(WS.TEAM_RED, "RED", WS.TeamColor[WS.TEAM_RED], false)
	team.SetUp(WS.TEAM_BLUE, "BLU", WS.TeamColor[WS.TEAM_BLUE], false)
end

-- Neither Sandbox nor base defines StartCommand, so there is nothing to defer to.
function GM:StartCommand(ply, cmd)
	if WS.Active() then WS.RestrictCommand(ply, cmd) end
end
