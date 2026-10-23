-- The NextBot debug layer's commands, after the engine's nb_select, nb_debug
-- and nb_debug_filter. The layer itself is the nbdebug feature
-- (features/nbdebug), loaded by the first command anyone may run. For
-- superadmins, or the listen server's host.
local COMMANDS = {
	{
		name = "ws_nb_select",
		help = "Select a Sandcastle NPC for ws_nb_debug: by entity index (0 clears), else the one under your crosshair; aim at nothing to clear",
	},
	{
		name = "ws_nb_debug",
		help = "Toggle NPC debug layers: PATH, COST, BEHAVIOR, NAV, AIWAR, MARKS, or ALL; OFF or no argument stops",
	},
	{
		name = "ws_nb_debug_filter",
		help = "Add entity indexes, classes or variant names to the NPC debug filter; no argument clears it",
	},
	{
		name = "ws_nb_dump",
		help = "Write the selected NPC's last path search to garrysmod/data/ws_nb/ as JSON",
	},
	{
		name = "ws_nb_behavior_print",
		help = "Print an NPC's action stack to your console, in TDBN and OBN, with its recent changes: by entity index, else the selected one",
	},
}

local function Allowed(ply)
	return IsValid(ply) and WS.Can(ply, system.permissions.NPC_DEBUG) == true
end

for _, command in ipairs(COMMANDS) do
	concommand.Add(command.name, function(ply, _, args)
		if not IsValid(ply) then
			print(command.name .. ": run it from a player's console; it draws for that player")
			return
		end
		if not Allowed(ply) then
			ply:ChatPrint(command.name .. ": superadmins only")
			return
		end
		WS.Feature("nbdebug"):Command(command.name, ply, args)
	end, nil, command.help)
end
