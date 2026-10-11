-- The spawn menu's Options tab, Sandcastle's category: the votes a player
-- can call, and controls over the match itself. Stubs for now: each says
-- what it will do, and its button stays off until it exists.
local CATEGORY = "Sandcastle"
local PENDING = " (coming soon)"

local VOTES = {
	{
		name = "Vote for the next map",
		help = "Choose the map that follows this one.",
	},
	{
		name = "Vote to kick a player",
		help = "Remove a player from the server.",
	},
	{
		name = "Vote to support the other team",
		help = "Raise your own team's difficulty: the other team gets more NPCs or a health boost.",
	},
	{
		name = "Vote to reset the round",
		help = "Start the current round over.",
	},
}

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
	spawnmenu.AddToolMenuOption("Options", CATEGORY, "ws_votes", "Voting", "", "", function(panel) Stubs(panel, VOTES) end)
	spawnmenu.AddToolMenuOption("Options", CATEGORY, "ws_match", "Match", "", "", function(panel) Stubs(panel, MATCH) end)
end)
