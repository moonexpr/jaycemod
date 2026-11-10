-- The games a gamemode can play, classes registered as player_manager's are.
-- A game is a file of the gamemode's gamerules/ folder, included by hand as a
-- player_class/ file is, ending in game_manager.RegisterClass(name, GAME, base).
-- Sandcastle's rounds ask these and name no game of their own; a gamemode
-- derived from Sandcastle registers its own after, and a class of the same
-- name replaces Sandcastle's, for the classes derived from it too.
--
-- A class has Applies(self) -> whether this map plays it. More than one may
-- apply: a payload map has control points too. A map's entities say which it
-- plays with Enable. CreatePanel(self) builds the game's objective vgui.
--
-- A class with bonus_suddendeath can settle a tie, and is only ever played
-- as that bonus round, never as a normal one.
local baseclass, error, format, ipairs, setmetatable, sort, tostring, type =
baseclass, error, string.format, ipairs, setmetatable, table.sort, tostring, type
local insert = table.insert
module ("game_manager", package.seeall)

local Type = {}
local names = {}

function RegisterClass (name, tab, base)
	if base then
		if not Type [base] then error (format ("game class %q derives from unknown class %q", name, tostring (base)), 2) end
		setmetatable (tab, { __index = function (_, key) return Type [base] [key] end })
	end
	if type (tab.Applies) ~= "function" then
		error (format ("game class %q has no Applies(self) to say when it is played", name), 2)
	end
	if not Type [name] then
		insert (names, name)
		sort (names)
	end
	Type [name] = tab
	baseclass.Set (name, tab)
end

function GetClass (name)
	return Type [name]
end

local ENABLED = "game_manager.enabled."
local BONUS = "game_manager.bonus"

-- On the server: this map plays the game.
function Enable (name)
	SetGlobal2Bool (ENABLED .. name, true)
end

function Enabled (name)
	return GetGlobal2Bool (ENABLED .. name, false)
end

-- The names of the classes being played, in name order: during a bonus round
-- that round's alone, otherwise every normal one this map plays.
function Active ()
	local bonus = GetGlobal2String (BONUS, "")
	if bonus ~= "" then return { bonus } end
	local active = {}
	for _, name in ipairs (names) do
		local class = Type [name]
		if not class.bonus_suddendeath and class:Applies () then active [#active + 1] = name end
	end
	return active
end

-- The bonus round that can settle a tie on this map, or nil.
function Tiebreaker ()
	for _, name in ipairs (names) do
		local class = Type [name]
		if class.bonus_suddendeath and class:Applies () then return name end
	end
end

-- On the server: begins the bonus round, or ends it with nil.
function SetBonus (name)
	SetGlobal2String (BONUS, name or "")
end

function RunClass (name, funcname, ...)
	local class = Type [name]
	if not class then error (format ("no game class %q", tostring (name)), 2) end
	local func = class [funcname]
	if not func then error (format ("%s not found on game class %q", tostring (funcname), name), 2) end
	return func (class, ...)
end

-- The method on each class this map plays.
function RunActive (funcname, ...)
	for _, name in ipairs (Active ()) do RunClass (name, funcname, ...) end
end

local Scenario = {}

-- What the classes this map plays ask of it, merged. Every key is optional:
-- a map's entity reads one with a default of its own, assuming no game.
function Scenario:GetRules ()
	local rules = {}
	for _, name in ipairs (Active ()) do
		for key, value in pairs (RunClass (name, "GetRules")) do rules [key] = value end
	end
	return rules
end

function GetCurrentScenario ()
	return Scenario
end

local panels = {}

-- On the client, each Think: every game being played has its panel, and a
-- game no longer played has none.
function UpdatePanels ()
	local active = {}
	for _, name in ipairs (Active ()) do
		active [name] = true
		if panels [name] == nil then
			panels [name] = false
			panels [name] = RunClass (name, "CreatePanel") or false
		end
	end
	for name, panel in pairs (panels) do
		if not active [name] then
			if IsValid (panel) then panel:Remove () end
			panels [name] = nil
		end
	end
end
