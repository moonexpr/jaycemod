-- The spawn menu's Utilities tab, User category: comfort settings any player
-- has. Stop sounds and remove ragdolls act at once; the three switches are
-- saved client convars for effects to honour (none reads them yet). An
-- admin's gameplay and server settings stay in the Admin category
-- (Gameplay Settings, ws/sh_gameplay.lua, and Sandbox's own).
local CATEGORY = "User"

local REDUCE_MOTION = CreateClientConVar("cl_reduce_motion", "0", true, false,
	"Calm camera shake, view punch and other motion effects.", 0, 1)
local REDUCE_FLASHING = CreateClientConVar("cl_reduce_flashing", "0", true, false,
	"Soften flashing lights and screen flashes.", 0, 1)
local HIDE_EFFECTS = CreateClientConVar("cl_hide_effects", "0", true, false,
	"Hide special effects: particles, sprites and screen overlays.", 0, 1)

local function BuildPanel(panel)
	panel:ClearControls()
	panel:Button("Stop all sounds", "stopsound")
	panel:Button("Remove ragdolls").DoClick = function() game.RemoveRagdolls() end
	panel:CheckBox("Reduce motion", REDUCE_MOTION:GetName())
	panel:ControlHelp(REDUCE_MOTION:GetHelpText())
	panel:CheckBox("Reduce flashing lights", REDUCE_FLASHING:GetName())
	panel:ControlHelp(REDUCE_FLASHING:GetHelpText())
	panel:CheckBox("Hide special effects", HIDE_EFFECTS:GetName())
	panel:ControlHelp(HIDE_EFFECTS:GetHelpText())
end

hook.Add("PopulateToolMenu", "ws_menu_utilities", function()
	spawnmenu.AddToolMenuOption("Utilities", CATEGORY, "ws_comfort", "Sandcastle", "", "", BuildPanel)
end)
