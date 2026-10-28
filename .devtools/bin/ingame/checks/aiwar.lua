-- The AI war and NextSoldier's debugging commands (docs/aiwar-koth-cp.md §6,
-- docs/ns-debugging.md): mp_aiwar_start, then each ns_* command runs (the
-- harness finds any Lua error it printed in console.log).
local NS_COMMANDS = {
	"ns_squads_print",
	"ns_lanes_print",
	"ns_lanes_replan",
	"ns_battlelines_print",
	"ns_tactics_list",
	"ns_tactics_tune",
	"ns_tactics_reset",
}
local START_TIMEOUT = 40
local SETTLE = 1

return function(t)
	game.ConsoleCommand("mp_aiwar_start\n")
	local registered = t:WaitFor(START_TIMEOUT, function() return concommand.GetTable()[NS_COMMANDS[1]] ~= nil end)
	t:Check("mp_aiwar_start registers the ns_ commands", registered ~= nil, "")
	if not registered then return end
	for _, name in ipairs(NS_COMMANDS) do
		t:Check(name .. " exists", concommand.GetTable()[name] ~= nil, "")
		game.ConsoleCommand(name .. "\n")
		t:Wait(SETTLE)
	end
end
