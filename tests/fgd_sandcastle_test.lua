-- addons/sandcastle/sandcastle.fgd: what it tells Hammer is what the gamemode implements. Each class
-- it declares is an entity of the gamemode's, and each of its keyvalues, inputs and outputs (its
-- own and its base classes' that are TF2's, not garrysmod.fgd's) is read or fired by that entity.
local T = dofile ("tests/harness.lua")

local ENTITIES = "addons/sandcastle/gamemodes/sandcastle/entities/entities/"

local function Read (path)
	local f = io.open (path, "r")
	if not f then return nil end
	local text = f:read ("*a")
	f:close ()
	return text
end

local fgd = Read ("addons/sandcastle/sandcastle.fgd")

-- Each class: { kind, name, bases, keys, inputs, outputs }.
local function Classes (text)
	local classes, bases = {}, {}
	for kind, header, body in text:gmatch ("@(%a+)([^%[@]-)(%b[])") do
		local name = header:match ("=%s*([%w_]+)")
		local entry = { kind = kind, name = name, bases = {}, keys = {}, inputs = {}, outputs = {} }
		for base in (header:match ("base%(([^)]*)%)") or ""):gmatch ("[%w_]+") do entry.bases [#entry.bases + 1] = base end
		for line in body:gmatch ("[^\n]+") do
			local input = line:match ("^%s*input%s+([%w_]+)")
			local output = line:match ("^%s*output%s+([%w_]+)")
			local key = not input and not output and line:match ("^%s*([%w_]+)%(")
			if input then entry.inputs [#entry.inputs + 1] = input end
			if output then entry.outputs [#entry.outputs + 1] = output end
			if key then entry.keys [#entry.keys + 1] = key end
		end
		if kind == "BaseClass" then bases [name] = entry else classes [#classes + 1] = entry end
	end
	return classes, bases
end

local classes, bases = Classes (fgd or "")

T.test ("the FGD declares Sandcastle's own entities, and garrysmod.fgd's under them", function ()
	T.eq (fgd ~= nil,                                            true, "it exists")
	T.eq (fgd:find ('@include "garrysmod.fgd"', 1, true) ~= nil, true, "after garrysmod.fgd")
	local names = {}
	for _, class in ipairs (classes) do names [class.name] = true end
	T.eq (names.info_room and names.ent_room_alarm, true, "info_room and ent_room_alarm")
end)

-- The engine's own classes the gamemode reads the keyvalues of, and where.
local ENGINE = { info_player_teamspawn = "addons/sandcastle/gamemodes/sandcastle/gamemode/includes/gameplay/spawn.lua" }

-- An entity's code with its bases' (ENT.Base), as far as the gamemode's go.
local function Code (name)
	local code = Read (ENTITIES .. name .. ".lua") or Read (ENTITIES .. name .. "/init.lua")
	if not code then return nil end
	local base = code:match ('ENT%.Base%s*=%s*"([%w_]+)"')
	return code .. (base and Code (base) or "")
end

T.test ("every class it declares is an entity of the gamemode's, with what it says the entity reads and fires", function ()
	for _, class in ipairs (classes) do
		local code = Code (class.name) or (ENGINE [class.name] and Read (ENGINE [class.name]))
		T.eq (code ~= nil, true, class.name .. " is the gamemode's")
		code = (code or ""):lower ()
		local function Check (kind, list)
			for _, name in ipairs (list) do
				T.eq (code:find (name:lower (), 1, true) ~= nil, true, string.format ("%s's %s %s", class.name, kind, name))
			end
		end
		Check ("keyvalue", class.keys)
		Check ("input",    class.inputs)
		Check ("output",   class.outputs)
		-- its own base classes' keys (TFTeam, RoomClass), not garrysmod.fgd's (Targetname, Angles...)
		local function Bases (list)
			for _, base in ipairs (list) do
				local entry = bases [base]
				if entry then
					Check ("keyvalue of " .. base, entry.keys)
					Check ("input of " .. base,    entry.inputs)
					Bases (entry.bases)
				end
			end
		end
		Bases (class.bases)
	end
end)

T.finish ()
