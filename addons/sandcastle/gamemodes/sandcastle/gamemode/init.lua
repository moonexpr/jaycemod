AddCSLuaFile("shared.lua")
AddCSLuaFile("logging.lua")
AddCSLuaFile("shared_loader.lua")
AddCSLuaFile("cl_init.lua")

include("shared.lua")

-- Clients are sent every file under the module folders (foundation/,
-- includes/, wartactics/, features/, vendor/) but the server's (sv.lua,
-- sv_*), as source: nothing there runs until a client loads it (WS.require,
-- or WS.Feature once the server loads the feature, sh_core.lua). This sends
-- them; it includes nothing. Each folder is read where the loader reads it
-- (WS.LoaderFile): the tactics engine's from its addon. NextSoldier sends its
-- own (nextsoldier/sh_init.lua).
do
	local Features = system.features
	local GamemodeFiles = {}
	function GamemodeFiles:Find(dir)
		return file.Find(WS.LoaderFile(dir) .. "*", "LUA")
	end
	for _, path in ipairs(Features.ClientFiles(GamemodeFiles, Features.CLIENT_DIRS)) do
		AddCSLuaFile(WS.LoaderFile(path))
	end
end

-- The root's modules clients run, a line each, written by hand
-- (tests/ws_root_modules_test.lua holds the list to the files): every sh_
-- and cl_ one.
AddCSLuaFile("sh_admin_properties.lua")
AddCSLuaFile("sh_aiwar.lua")
AddCSLuaFile("sh_announcer.lua")
AddCSLuaFile("sh_bullets.lua")
AddCSLuaFile("sh_cami.lua")
AddCSLuaFile("sh_condition_menu.lua")
AddCSLuaFile("sh_console.lua")
AddCSLuaFile("sh_core.lua")
AddCSLuaFile("sh_crit_effects.lua")
AddCSLuaFile("sh_editors.lua")
AddCSLuaFile("sh_editors_cart.lua")
AddCSLuaFile("sh_editors_point.lua")
AddCSLuaFile("sh_events.lua")
AddCSLuaFile("sh_factions.lua")
AddCSLuaFile("sh_footsteps.lua")
AddCSLuaFile("sh_gameplay.lua")
AddCSLuaFile("sh_hits.lua")
AddCSLuaFile("sh_kill_credit.lua")
AddCSLuaFile("sh_loadout.lua")
AddCSLuaFile("sh_movement.lua")
AddCSLuaFile("sh_nav_progress.lua")
AddCSLuaFile("sh_nodegraph.lua")
AddCSLuaFile("sh_npc_ragdolls.lua")
AddCSLuaFile("sh_pathfollower.lua")
AddCSLuaFile("sh_permissions.lua")
AddCSLuaFile("sh_player_models.lua")
AddCSLuaFile("sh_players_menu.lua")
AddCSLuaFile("sh_radio_gesture.lua")
AddCSLuaFile("sh_respawn_modifiers.lua")
AddCSLuaFile("sh_settings.lua")
AddCSLuaFile("sh_soundscripts.lua")
AddCSLuaFile("sh_spawn_manager.lua")
AddCSLuaFile("sh_teamtint.lua")
AddCSLuaFile("sh_toggles.lua")
AddCSLuaFile("sh_vendor.lua")
AddCSLuaFile("sh_votes.lua")
AddCSLuaFile("sh_nextsoldier_host.lua")
AddCSLuaFile("sh_war_soldier.lua")
AddCSLuaFile("sh_weapon_balance.lua")
AddCSLuaFile("cl_admin_panels.lua")
AddCSLuaFile("cl_aiwar_slots.lua")
AddCSLuaFile("cl_client_settings.lua")
AddCSLuaFile("cl_conditions.lua")
AddCSLuaFile("cl_economy_tabs.lua")
AddCSLuaFile("cl_gaze.lua")
AddCSLuaFile("cl_hits.lua")
AddCSLuaFile("cl_hud_hidden.lua")
AddCSLuaFile("cl_kill_feed.lua")
AddCSLuaFile("cl_loadout.lua")
AddCSLuaFile("cl_localization.lua")
AddCSLuaFile("cl_medic_effects.lua")
AddCSLuaFile("cl_menu_inventory.lua")
AddCSLuaFile("cl_menu_player.lua")
AddCSLuaFile("cl_menu_server.lua")
AddCSLuaFile("cl_menu_utilities.lua")
AddCSLuaFile("cl_menubar.lua")
AddCSLuaFile("cl_nav_progress.lua")
AddCSLuaFile("cl_nb_menu.lua")
AddCSLuaFile("cl_npc_ragdolls.lua")
AddCSLuaFile("cl_ns_debug.lua")
AddCSLuaFile("cl_players_menu.lua")
AddCSLuaFile("cl_scoreboard.lua")
AddCSLuaFile("cl_spawn_manager.lua")
AddCSLuaFile("cl_teams.lua")
AddCSLuaFile("cl_tf_content.lua")
AddCSLuaFile("cl_tf_hud.lua")
AddCSLuaFile("cl_ui.lua")
AddCSLuaFile("cl_voice.lua")
AddCSLuaFile("cl_votes.lua")

WS.Feature("system")

-- The root's sv_ modules, a line each, written by hand
-- (tests/ws_root_modules_test.lua holds the list to the files); a new one
-- is a line here.
local Boot = WS.Logger("boot")
local function Include(path)
	Boot("include %s", path)
	return include(path)
end

Include("sv_analytics.lua")
Include("sv_arrivals.lua")
Include("sv_builder.lua")
Include("sv_content.lua")
Include("sv_defaults.lua")
Include("sv_economy.lua")
Include("sv_handicap.lua")
Include("sv_hits.lua")
Include("sv_idle.lua")
Include("sv_jit.lua")
Include("sv_kill_credit.lua")
Include("sv_loadout.lua")
Include("sv_maps.lua")
Include("sv_match_control.lua")
Include("sv_medic_call.lua")
Include("sv_nav.lua")
Include("sv_nbdebug.lua")
Include("sv_npc_ragdolls.lua")
Include("sv_player_analytics.lua")
Include("sv_players_menu.lua")
Include("sv_proxy.lua")
Include("sv_respawn_modifiers.lua")
Include("sv_scoreboard.lua")
Include("sv_spawn_manager.lua")
Include("sv_teams.lua")
Include("sv_teams_conditions.lua")
Include("sv_teams_pickups.lua")
Include("sv_teams_spawn.lua")
Include("sv_use.lua")
Include("sv_voices.lua")
Include("sv_votes.lua")
Include("sv_world.lua")

-- As in TF2, a new player joins no team: they watch until they pick one
-- from the team menu (auto-assign is one click there). Only in team play
-- (WS.TeamPlay): otherwise, as in Sandbox, they spawn and play.
function GM:PlayerInitialSpawn(ply, transition)
	self.BaseClass.PlayerInitialSpawn(self, ply, transition)
	if WS.TeamPlay() then WS.SetInitialTeam(ply) end
end

function GM:PlayerSpawn(ply, transition)
	local teamPlay = WS.TeamPlay()
	WS.Spectator.PrepareSpawn(ply)
	local spectator = WS.Spectator.SelectSpawnClass(ply, teamPlay,
		WS.PlayMode() == system.play_mode.SANDBOX)

	if not teamPlay then
		self.BaseClass.BaseClass.PlayerSpawn(self, ply, transition)
		WS.ApplyMovement(ply)
		return
	end
	if spectator then
		WS.Spectator.SpawnAsSpectator(ply)
		return
	end
	self.BaseClass.BaseClass.PlayerSpawn(self, ply, transition)
	WS.ApplyMovement(ply)
	-- another addon's team change is undone by sv_teams.lua's hooks
end

-- A player spawns with Sandbox's loadout (its Half-Life 2 set and tools)
-- while sbox_weapons is on, as it is by default, and in Sandbox mode; on TF2
-- maps with it off, with their loadout (sv_loadout.lua, the Player tab),
-- keeping Sandbox's tools.
local SANDBOX_TOOLS = { "gmod_camera", "gmod_tool", "weapon_physgun" }

-- Disabled because this strips weapons
-- function GM:PlayerLoadout(ply)
-- 	if not WS.Active() or cvars.Bool("sbox_weapons", true) then return self.BaseClass.PlayerLoadout(self, ply) end
-- 	for _, class in ipairs(SANDBOX_TOOLS) do ply:Give(class) end
-- 	WS.GiveLoadout(ply)
-- end

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
	WS.Spectator.AfterPlayerDeath(ply)
end

-- On maps with rounds the team keys (F2's gm_showteam, changeteam) open the
-- team menu on the client (cl_teams.lua), never through here:
-- Sandbox's own team menu stays shut.
function GM:ShowTeam(ply)
	if WS.Active() then return end
	self.BaseClass.ShowTeam(self, ply)
end

-- Base's changeteam command goes through TF2's join rules on TF2 maps,
-- whenever a team may be picked (WS.MayPickTeam); without a team index it
-- does nothing here (the client's bind opens the menu).
local JOIN_NAME = {
	[WS.TEAM_SPECTATOR] = "spectate",
	[WS.TEAM_RED] = "red",
	[WS.TEAM_BLUE] = "blue",
}

function GM:PlayerRequestTeam(ply, teamIndex)
	if WS.Active() then
		if WS.MayPickTeam() and JOIN_NAME[teamIndex] then WS.JoinTeam(ply, JOIN_NAME[teamIndex]) end
		return
	end
	self.BaseClass.PlayerRequestTeam(self, ply, teamIndex)
end
