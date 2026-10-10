AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")

include("shared.lua")

-- Foundation modules are pure logic, safe to send; clients load them with
-- WS.require. A system's parts sit in its folder (foundation/payload/).
local function SendFoundation(dir)
	local root = GM.FolderName .. "/gamemode/"
	for _, f in ipairs(file.Find(root .. dir .. "*.lua", "LUA")) do AddCSLuaFile(dir .. f) end
	local _, dirs = file.Find(root .. dir .. "*", "LUA")
	for _, d in ipairs(dirs) do SendFoundation(dir .. d .. "/") end
end
SendFoundation("foundation/")

-- Every feature's client parts are sent as source; nothing runs until the
-- server loads the feature and tells clients (WS.Feature, sh_core.lua).
-- sv.lua stays on the server.
local function SendFeatureClientParts()
	local Features = WS.require("foundation.features")
	local root = GM.FolderName .. "/gamemode/"
	local _, names = file.Find(root .. Features.ROOT .. "*", "LUA")
	for _, name in ipairs(names) do
		for _, part in ipairs(Features.CLIENT_PARTS) do
			local path = Features.PartPath(name, part)
			if file.Exists(root .. path, "LUA") then AddCSLuaFile(path) end
		end
	end
end
SendFeatureClientParts()

for _, f in ipairs(GM:WSModules("sh_")) do AddCSLuaFile("ws/" .. f) end
for _, f in ipairs(GM:WSModules("cl_")) do AddCSLuaFile("ws/" .. f) end
for _, f in ipairs(GM:WSModules("sv_")) do include("ws/" .. f) end

-- As in TF2, a new player joins no team: they watch until they pick one
-- from the team menu (auto-assign is one click there).
function GM:PlayerInitialSpawn(ply, transition)
	self.BaseClass.PlayerInitialSpawn(self, ply, transition)
	if WS.Active() then WS.SetInitialTeam(ply) end
end

function GM:PlayerSpawn(ply, transition)
	if not WS.Active() then
		self.BaseClass.PlayerSpawn(self, ply, transition)
		return
	end
	-- CTFPlayer::StateEnterWELCOME: a player without a team is an observer,
	-- never a live Sandbox player.
	if ply.wsTeam == WS.TEAM_UNASSIGNED then
		WS.StartObserving(ply)
	else
		self.BaseClass.PlayerSpawn(self, ply, transition)
		if ply:Team() == WS.TEAM_SPECTATOR then WS.StartObserving(ply) end
	end
	-- Other addons move players between teams in their own spawn hooks (one
	-- puts everyone on a "Runner" team), so correct the team after them.
	timer.Simple(0, function()
		if IsValid(ply) and WS.Active() then WS.RestoreTeam(ply) end
	end)
end

-- Spawn at the team's next valid info_player_teamspawn for this round.
function GM:PlayerSelectSpawn(ply, transition)
	if WS.Active() then
		WS.RestoreTeam(ply)
		local spot = WS.PickSpawn(WS.TeamOf(ply))
		if spot then return spot end
	end
	return self.BaseClass.PlayerSelectSpawn(self, ply, transition)
end

-- On TF2 maps, players come back with tf_gamerules' respawn waves rather than
-- when they click; in Sandbox mode, as in Sandbox, when they click.
function GM:PlayerDeathThink(ply)
	if WS.Active() and not WS.GameplayStopped() then return false end
	return self.BaseClass.PlayerDeathThink(self, ply)
end

-- CTFPlayer::Event_Killed drops an ammo pack where the player died.
function GM:DoPlayerDeath(ply, attacker, dmg)
	self.BaseClass.DoPlayerDeath(self, ply, attacker, dmg)
	if WS.Active() and not ply.wsChangingTeam then WS.DropAmmoPack(ply) end
end

-- Neither Sandbox nor base defines PostPlayerDeath.
function GM:PostPlayerDeath(ply)
	if IsValid(WS.Rules) then WS.Rules:OnPlayerDeath(ply) end
end

-- On maps with rounds the team keys (F2's gm_showteam, changeteam) open the
-- team menu on the client (ws/cl_teams.lua), never through here:
-- Sandbox's own team menu stays shut.
function GM:ShowTeam(ply)
	if WS.Active() then return end
	self.BaseClass.ShowTeam(self, ply)
end

-- Base's changeteam command goes through TF2's join rules on TF2 maps;
-- without a team index it does nothing here (the client's bind opens the menu).
local JOIN_NAME = {
	[WS.TEAM_SPECTATOR] = "spectate",
	[WS.TEAM_RED] = "red",
	[WS.TEAM_BLUE] = "blue",
}

function GM:PlayerRequestTeam(ply, teamIndex)
	if WS.Active() then
		if JOIN_NAME[teamIndex] then WS.JoinTeam(ply, JOIN_NAME[teamIndex]) end
		return
	end
	self.BaseClass.PlayerRequestTeam(self, ply, teamIndex)
end
