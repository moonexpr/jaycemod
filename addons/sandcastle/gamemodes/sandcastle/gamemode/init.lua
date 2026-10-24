AddCSLuaFile("shared.lua")
AddCSLuaFile("shared_loader.lua")
AddCSLuaFile("cl_init.lua")

include("shared.lua")

-- Clients are sent every file under foundation/, features/ and ws/ but the
-- server's (sv.lua, sv_*), as source: foundation and feature modules, feature
-- client and shared parts, and ws/ sh_, cl_ and unprefixed modules. Nothing
-- runs until a client loads it (WS.require, or WS.Feature once the server
-- loads the feature, sh_core.lua).
do
	local Features = system.features
	local root = GM.FolderName .. "/gamemode/"
	local GamemodeFiles = {}
	function GamemodeFiles:Find(dir)
		return file.Find(root .. dir .. "*", "LUA")
	end
	for _, path in ipairs(Features.ClientFiles(GamemodeFiles, Features.CLIENT_DIRS)) do AddCSLuaFile(path) end
end

for _, f in ipairs(GM:WSModules("sv_")) do include("ws/" .. f) end

-- As in TF2, a new player joins no team: they watch until they pick one
-- from the team menu (auto-assign is one click there). Only in team play
-- (WS.TeamPlay): otherwise, as in Sandbox, they spawn and play.
function GM:PlayerInitialSpawn(ply, transition)
	self.BaseClass.PlayerInitialSpawn(self, ply, transition)
	if WS.TeamPlay() then WS.SetInitialTeam(ply) end
end

function GM:PlayerSpawn(ply, transition)
	if not WS.TeamPlay() then
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
	-- another addon's team change is undone by ws/sv_teams.lua's hooks
end

-- A player spawns with Sandbox's loadout (its Half-Life 2 set and tools)
-- while sbox_weapons is on, as it is by default, and in Sandbox mode; on TF2
-- maps with it off, with their loadout (ws/sv_loadout.lua, the Player tab),
-- keeping Sandbox's tools.
local SANDBOX_TOOLS = { "gmod_camera", "gmod_tool", "weapon_physgun" }

function GM:PlayerLoadout(ply)
	if not WS.Active() or cvars.Bool("sbox_weapons", true) then return self.BaseClass.PlayerLoadout(self, ply) end
	for _, class in ipairs(SANDBOX_TOOLS) do ply:Give(class) end
	WS.GiveLoadout(ply)
end

-- Spawn at the team's next valid info_player_teamspawn for this round.
function GM:PlayerSelectSpawn(ply, transition)
	if WS.Active() then
		if WS.TeamPlay() then WS.RestoreTeam(ply) end
		local spot = WS.PickSpawn(WS.TeamOf(ply))
		if spot then return spot end
	end
	return self.BaseClass.PlayerSelectSpawn(self, ply, transition)
end

-- With rounds, players come back with the gamerules' respawn waves rather than
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

-- Every map has gamerules (WS.Rules) from its load on: its own tf_gamerules,
-- or those the rounds controller makes (its SetUpMap).
hook.Add("InitPostEntity", "ws_gamerules", function() WS.Feature("rounds"):SetUpMap() end)

-- Neither Sandbox nor base defines PostPlayerDeath.
function GM:PostPlayerDeath(ply)
	WS.Rules:OnPlayerDeath(ply)
end

-- On maps with rounds the team keys (F2's gm_showteam, changeteam) open the
-- team menu on the client (ws/cl_teams.lua), never through here:
-- Sandbox's own team menu stays shut.
function GM:ShowTeam(ply)
	if WS.Active() then return end
	self.BaseClass.ShowTeam(self, ply)
end

-- Base's changeteam command goes through TF2's join rules on TF2 maps,
-- whenever a team may be picked (WS.TeamChoice); without a team index it
-- does nothing here (the client's bind opens the menu).
local JOIN_NAME = {
	[WS.TEAM_SPECTATOR] = "spectate",
	[WS.TEAM_RED] = "red",
	[WS.TEAM_BLUE] = "blue",
}

function GM:PlayerRequestTeam(ply, teamIndex)
	if WS.Active() then
		if WS.TeamChoice() and JOIN_NAME[teamIndex] then WS.JoinTeam(ply, JOIN_NAME[teamIndex]) end
		return
	end
	self.BaseClass.PlayerRequestTeam(self, ply, teamIndex)
end
