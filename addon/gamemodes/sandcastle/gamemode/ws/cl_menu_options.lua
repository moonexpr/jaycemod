-- The spawn menu's Options tab, Sandcastle's category: controls over the
-- match itself. Stubs for now: each says what it will do, and its button
-- stays off until it exists. Votes are the Server tab's (ws/cl_menu_server.lua).
local CATEGORY = "Sandcastle"
local PENDING = " (coming soon)"

local MATCH = {
	{
		name = "Scramble the teams",
		help = "Deal the players out to RED and BLU afresh.",
	},
	{
		name = "Extend the time limit",
		help = "Add time to the round's clock.",
	},
	{
		name = "Pause the match",
		help = "Hold the round's clock and freeze everyone in place.",
	},
}

local function Stubs(panel, stubs)
	panel:ClearControls()
	for _, stub in ipairs(stubs) do
		panel:Button(stub.name .. PENDING):SetEnabled(false)
		panel:ControlHelp(stub.help)
	end
end

hook.Add("PopulateToolMenu", "ws_menu_options", function()
	spawnmenu.AddToolMenuOption("Options", CATEGORY, "ws_match", "Match", "", "", function(panel) Stubs(panel, MATCH) end)
end)
