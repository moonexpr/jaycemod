-- The games a gamemode can play, classes registered as player_manager's are.
-- A game is a file of the gamemode's gamerules/ folder, included by hand as a
-- player_class/ file is, ending in game_manager.RegisterClass(name, GAME, base).
-- Sandcastle's rounds ask these and name no game of their own; a gamemode
-- derived from Sandcastle registers its own after, and a class of the same
-- name replaces Sandcastle's, for the classes derived from it too.
--
-- A class has Applies(self) -> whether this map plays it. More than one may
-- apply: a payload map has control points too.
local baseclass, error, format, ipairs, setmetatable, sort, tostring, type =
	baseclass, error, string.format, ipairs, setmetatable, table.sort, tostring, type
local insert = table.insert
module( "game_manager", package.seeall )

local Type = {}
local names = {}

function RegisterClass(name, tab, base)
	if base then
		if not Type[base] then error(format("game class %q derives from unknown class %q", name, tostring(base)), 2) end
		setmetatable(tab, { __index = function(_, key) return Type[base][key] end })
	end
	if type(tab.Applies) ~= "function" then
		error(format("game class %q has no Applies(self) to say when it is played", name), 2)
	end
	if not Type[name] then
		insert(names, name)
		sort(names)
	end
	Type[name] = tab
	baseclass.Set(name, tab)
end

function GetClass(name)
	return Type[name]
end

-- The names of the classes this map plays, in name order.
function Active()
	local active = {}
	for _, name in ipairs(names) do
		if Type[name]:Applies() then active[#active + 1] = name end
	end
	return active
end

function RunClass(name, funcname, ...)
	local class = Type[name]
	if not class then error(format("no game class %q", tostring(name)), 2) end
	local func = class[funcname]
	if not func then error(format("%s not found on game class %q", tostring(funcname), name), 2) end
	return func(class, ...)
end

-- The method on each class this map plays.
function RunActive(funcname, ...)
	for _, name in ipairs(Active()) do RunClass(name, funcname, ...) end
end
