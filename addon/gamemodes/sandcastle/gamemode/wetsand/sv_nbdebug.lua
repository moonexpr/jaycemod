-- The NextBot debug layer's commands, after the engine's nb_select, nb_debug
-- and nb_debug_filter. The layer itself is the nbdebug feature
-- (features/nbdebug), loaded by the first command anyone may run. For
-- superadmins, or the listen server's host.
local COMMANDS = {
	{
		name = "wetsand_nb_select",
		help = "Select the Sandcastle NPC under your crosshair for wetsand_nb_debug; aim at nothing to clear",
	},
	{
		name = "wetsand_nb_debug",
		help = "Toggle NPC debug layers: PATH, COST, BEHAVIOR, NAV, AIWAR, or ALL; OFF or no argument stops",
	},
	{
		name = "wetsand_nb_debug_filter",
		help = "Add entity indexes, classes or variant names to the NPC debug filter; no argument clears it",
	},
	{
		name = "wetsand_nb_dump",
		help = "Write the selected NPC's last path search to garrysmod/data/wetsand_nb/ as JSON",
	},
}

local function Allowed(ply)
	return IsValid(ply) and (ply:IsSuperAdmin() or ply:IsListenServerHost())
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
		WETSAND.Feature("nbdebug"):Command(command.name, ply, args)
	end, nil, command.help)
end
