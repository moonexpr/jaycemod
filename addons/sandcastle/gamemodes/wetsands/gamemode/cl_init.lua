include("shared.lua")
DEFINE_BASECLASS("gamemode_sandcastle")
-- cl_client_settings (WS.PersistClientConVars) loads first: it keeps the
-- other modules' settings. Then the player's feedback, what they hear and
-- see of their own hits (cl_hits), the last thing to fail: it reads nothing
-- of the HUD and loads before any of it. Then cl_ui (WS.UI), which other
-- cl_ modules build their panels on, and cl_tf_hud (WS.TFHud), which the
-- HUD panels draw with; then the rest.

-- A module failing at load is reported with its stack, and the rest load
-- on: one broken panel takes no other module with it.
local Boot = WS.Logger("boot")
local function Load(f)
	Boot("include %s", f)
	xpcall(include, ErrorNoHaltWithStack, f)
end


-- The root's cl_ modules, a line each, written by hand
-- (tests/ws_root_modules_test.lua holds the list to the files); a new one
-- is a line here and its AddCSLuaFile line in init.lua.
Load("cl_client_settings.lua")
Load("cl_hits.lua")
Load("cl_ui.lua")
Load("cl_tf_hud.lua")
Load("cl_admin_panels.lua")
Load("cl_aiwar_slots.lua")
Load("cl_conditions.lua")
Load("cl_economy_tabs.lua")
Load("cl_demo_autorecord.lua")
Load("cl_friendly_id.lua")
Load("cl_gaze.lua")
Load("cl_hud_hidden.lua")
Load("cl_kill_feed.lua")
Load("cl_loadout.lua")
Load("cl_localization.lua")
Load("cl_medic_effects.lua")
Load("cl_menu_inventory.lua")
Load("cl_menu_player.lua")
Load("cl_menu_server.lua")
Load("cl_menu_utilities.lua")
Load("cl_menubar.lua")
Load("cl_nav_progress.lua")
Load("cl_nb_menu.lua")
Load("cl_npc_ragdolls.lua")
Load("cl_ns_debug.lua")
Load("cl_players_menu.lua")
Load("cl_scoreboard.lua")
Load("cl_spawn_manager.lua")
Load("cl_teams.lua")
Load("cl_tf_content.lua")
Load("cl_voice.lua")
Load("cl_votes.lua")

-- Every HUD element of the gamemode, in order (WS.HUD, ws/sh_core.lua).
function GM:HUDPaint()
	BaseClass.HUDPaint(self)
	WS.HUD:Draw(ScrW(), ScrH())
end
