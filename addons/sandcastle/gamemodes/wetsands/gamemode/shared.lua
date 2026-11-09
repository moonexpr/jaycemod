-- Wetsands: the game built on Sandcastle, with working TF2 gameplay entities.
-- Every map has gamerules: on a map with a tf_gamerules (any TF2 map) the
-- round runs as in TF2; on any other map Wetsands' (ws_gamerules) leave it
-- plain Sandcastle until a game begins. Every override below defers to
-- Sandcastle first.
GM.Name = "Wetsands"
GM.Author = "moonexpr"
GM.Email = ""
GM.Website = ""

-- The gamemode's logging first, so the load itself can log (the boot
-- subsystem); then the gamemode's require, and foundation's namespaces.
include("logging.lua")
local Boot = WS.Logger("boot")
Boot("shared.lua: %s, the gamemode's load begins", SERVER and "server" or "client")

DeriveGamemode("sandcastle")
DEFINE_BASECLASS("gamemode_sandcastle")

include("shared_loader.lua")

-- The root's sh_ modules, on both realms, a line each, written by hand
-- (tests/ws_root_modules_test.lua holds the list to the files): sh_core
-- defines the WS table and loads first, including sh_events (the game
-- event library) itself; the rest in name order. A new sh_ module is a line
-- here and its AddCSLuaFile line in init.lua.
local function Include(path)
	Boot("include %s", path)
	return include(path)
end

Include("sh_core.lua")
Include("sh_admin_properties.lua")
Include("sh_nextsoldier_host.lua")
Include("sh_aiwar.lua")
Include("sh_announcer.lua")
Include("sh_bullets.lua")
Include("sh_cami.lua")
Include("sh_condition_menu.lua")
Include("sh_console.lua")
Include("sh_crit_effects.lua")
Include("sh_editors.lua")
Include("sh_editors_cart.lua")
Include("sh_editors_point.lua")
Include("sh_factions.lua")
Include("sh_footsteps.lua")
Include("sh_gameplay.lua")
Include("sh_hits.lua")
Include("sh_kill_credit.lua")
Include("sh_loadout.lua")
Include("sh_movement.lua")
Include("sh_nav_progress.lua")
Include("sh_nodegraph.lua")
Include("sh_npc_ragdolls.lua")
Include("sh_pathfollower.lua")
Include("sh_permissions.lua")
Include("sh_player_models.lua")
Include("sh_players_menu.lua")
Include("sh_radio_gesture.lua")
Include("sh_respawn_modifiers.lua")
Include("sh_settings.lua")
Include("sh_soundscripts.lua")
Include("sh_spawn_manager.lua")
Include("sh_teamtint.lua")
Include("sh_toggles.lua")
Include("sh_traces.lua")
Include("sh_vendor.lua")
Include("sh_votes.lua")
Include("sh_war_soldier.lua")
Include("sh_weapon_balance.lua")

-- The player classes, the weapon helper they share first.
if SERVER then
	AddCSLuaFile("player_class/simple_weapon_loadout.lua")
	AddCSLuaFile("player_class/player_combatant.lua")
	AddCSLuaFile("player_class/player_combatant_cstrike.lua")
	AddCSLuaFile("player_class/player_sandcastle.lua")
	AddCSLuaFile("player_class/player_spectator.lua")
end
Include("player_class/simple_weapon_loadout.lua")
Include("player_class/player_combatant.lua")
Include("player_class/player_combatant_cstrike.lua")
Include("player_class/player_sandcastle.lua")
Include("player_class/player_spectator.lua")

-- This game's scenarios, on Sandcastle's game_manager.
if SERVER then
	AddCSLuaFile("gamerules/game_control_points.lua")
	AddCSLuaFile("gamerules/game_ctf.lua")
	AddCSLuaFile("gamerules/game_payload.lua")
end
Include("gamerules/game_control_points.lua")
Include("gamerules/game_ctf.lua")
Include("gamerules/game_payload.lua")

-- TF2's team numbers (1 spectator, 2 RED, 3 BLU); GMod reserves only 0, 1001 and 1002.
function GM:CreateTeams()
	BaseClass.CreateTeams(self)
	team.SetUp(WS.TEAM_SPECTATOR, "Spectator", Color(200, 200, 200), true)
	team.SetUp(WS.TEAM_RED, "RED", WS.TeamColor[WS.TEAM_RED], false)
	team.SetUp(WS.TEAM_BLUE, "BLU", WS.TeamColor[WS.TEAM_BLUE], false)
end

-- Neither Sandbox nor base defines StartCommand, so there is nothing to defer to.
function GM:StartCommand(ply, cmd)
	if WS.Active() then WS.RestrictCommand(ply, cmd) end
end
