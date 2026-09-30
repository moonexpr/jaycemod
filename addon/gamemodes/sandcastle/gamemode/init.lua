AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")

include("shared.lua")

-- Foundation modules are pure logic, safe to send; clients load them with
-- WETSAND.require. A system's parts sit in its folder (foundation/payload/).
local function SendFoundation(dir)
	local root = GM.FolderName .. "/gamemode/"
	for _, f in ipairs(file.Find(root .. dir .. "*.lua", "LUA")) do AddCSLuaFile(dir .. f) end
	local _, dirs = file.Find(root .. dir .. "*", "LUA")
	for _, d in ipairs(dirs) do SendFoundation(dir .. d .. "/") end
end
SendFoundation("foundation/")

-- Every feature's client parts are sent as source; nothing runs until the
-- server loads the feature and tells clients (WETSAND.Feature, sh_core.lua).
-- sv.lua stays on the server.
local function SendFeatureClientParts()
	local Features = WETSAND.require("foundation.features")
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

for _, f in ipairs(GM:WetsandModules("sh_")) do AddCSLuaFile("wetsand/" .. f) end
for _, f in ipairs(GM:WetsandModules("cl_")) do AddCSLuaFile("wetsand/" .. f) end
for _, f in ipairs(GM:WetsandModules("sv_")) do include("wetsand/" .. f) end

-- As in TF2, a new player joins no team: they watch until they pick one
-- from the team menu (auto-assign is one click there).
function GM:PlayerInitialSpawn(ply, transition)
	self.BaseClass.PlayerInitialSpawn(self, ply, transition)
	if WETSAND.Active() then WETSAND.SetInitialTeam(ply) end
end

function GM:PlayerSpawn(ply, transition)
	if not WETSAND.Active() then
		self.BaseClass.PlayerSpawn(self, ply, transition)
		return
	end
	-- CTFPlayer::StateEnterWELCOME: a player without a team is an observer,
	-- never a live Sandbox player.
	if ply.wetsandTeam == WETSAND.TEAM_UNASSIGNED then
		WETSAND.StartObserving(ply)
	else
		self.BaseClass.PlayerSpawn(self, ply, transition)
		if ply:Team() == WETSAND.TEAM_SPECTATOR then WETSAND.StartObserving(ply) end
	end
	-- Other addons move players between teams in their own spawn hooks (one
	-- puts everyone on a "Runner" team), so correct the team after them.
	timer.Simple(0, function()
		if IsValid(ply) and WETSAND.Active() then WETSAND.RestoreTeam(ply) end
	end)
end

-- Spawn at the team's next valid info_player_teamspawn for this round.
function GM:PlayerSelectSpawn(ply, transition)
	if WETSAND.Active() then
		WETSAND.RestoreTeam(ply)
		local spot = WETSAND.PickSpawn(WETSAND.TeamOf(ply))
		if spot then return spot end
	end
	return self.BaseClass.PlayerSelectSpawn(self, ply, transition)
end

-- On TF2 maps, players come back with tf_gamerules' respawn waves rather than
-- when they click.
function GM:PlayerDeathThink(ply)
	if WETSAND.Active() then return false end
	return self.BaseClass.PlayerDeathThink(self, ply)
end

-- CTFPlayer::Event_Killed drops an ammo pack where the player died.
function GM:DoPlayerDeath(ply, attacker, dmg)
	self.BaseClass.DoPlayerDeath(self, ply, attacker, dmg)
	if WETSAND.Active() and not ply.wetsandChangingTeam then WETSAND.DropAmmoPack(ply) end
end

-- Neither Sandbox nor base defines PostPlayerDeath.
function GM:PostPlayerDeath(ply)
	if IsValid(WETSAND.Rules) then WETSAND.Rules:OnPlayerDeath(ply) end
end

-- On maps with rounds the team keys (F2's gm_showteam, changeteam) open the
-- team menu on the client (wetsand/cl_teams.lua), never through here:
-- Sandbox's own team menu stays shut.
function GM:ShowTeam(ply)
	if WETSAND.Active() then return end
	self.BaseClass.ShowTeam(self, ply)
end

-- Base's changeteam command goes through TF2's join rules on TF2 maps;
-- without a team index it does nothing here (the client's bind opens the menu).
local JOIN_NAME = {
	[WETSAND.TEAM_SPECTATOR] = "spectate",
	[WETSAND.TEAM_RED] = "red",
	[WETSAND.TEAM_BLUE] = "blue",
}

function GM:PlayerRequestTeam(ply, teamIndex)
	if WETSAND.Active() then
		if JOIN_NAME[teamIndex] then WETSAND.JoinTeam(ply, JOIN_NAME[teamIndex]) end
		return
	end
	self.BaseClass.PlayerRequestTeam(self, ply, teamIndex)
end
