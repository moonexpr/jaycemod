-- Client settings kept in the client's own data folder
-- (garrysmod/data/sandcastle/settings_<name>.txt, encoding.cvarfile),
-- shared by every server and game the client joins: a group of
-- client convars is set from the file as it loads, and the file is written
-- whenever one of them changes. Only the group's convars are read from it.
-- Loaded before the other cl_ modules (cl_init.lua), which keep theirs here.
local CvarFile = WS.require("foundation.encoding.cvarfile")

local DIR = "sandcastle"

-- name: the group's file; convars: its client convars.
function WS.PersistClientConVars(name, convars)
	local path = DIR .. "/settings_" .. name .. ".txt"
	local names = {}
	for i, convar in ipairs(convars) do names[i] = convar:GetName() end
	local saved = file.Read(path, "DATA")
	if saved then
		for convar, value in pairs(CvarFile.Read(saved, names)) do RunConsoleCommand(convar, value) end
	end
	local function Save()
		local values = {}
		for _, convar in ipairs(convars) do values[convar:GetName()] = convar:GetString() end
		file.CreateDir(DIR)
		file.Write(path, CvarFile.Write(names, values))
	end
	for _, convar in ipairs(names) do cvars.AddChangeCallback(convar, Save, "ws_settings_" .. name) end
end
