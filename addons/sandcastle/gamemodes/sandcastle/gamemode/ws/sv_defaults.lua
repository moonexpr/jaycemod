-- ws_defaults_apply: puts every Sandcastle convar back to its default by
-- running addon/cfg/sandcastle_defaults.cfg. GMod's exec reads only
-- garrysmod/cfg/, but the addon's own folders are on the GAME search path,
-- so the server reads the file from there and runs its lines itself
-- (foundation.core.parsers.consolecfg). For admins, or the server console.
local Cfg = WS.require("foundation.core.parsers.consolecfg")

local DEFAULTS_CFG = "cfg/sandcastle_defaults.cfg"
local COMMAND = "ws_defaults_apply"

local function Tell(ply, text)
	print(text)
	if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, text) end
end

concommand.Add(COMMAND, function(ply)
	if not WS.Can(ply, WS.require("foundation.permissions").RULES) then return end
	local text = file.Read(DEFAULTS_CFG, "GAME")
	if not text then
		Tell(ply, COMMAND .. ": " .. DEFAULTS_CFG .. " not found on the GAME path; is the addon mounted?")
		return
	end
	local commands, refused = Cfg.Commands(text)
	for _, command in ipairs(commands) do game.ConsoleCommand(command .. "\n") end
	for _, line in ipairs(refused) do Tell(ply, COMMAND .. ": skipped a line chaining commands: " .. line) end
	Tell(ply, string.format("%s: ran %d lines of %s (convars of systems this map has not loaded report Unknown command)",
		COMMAND, #commands, DEFAULTS_CFG))
end, nil, "Put every Sandcastle convar back to its default, from the addon's cfg/sandcastle_defaults.cfg")
