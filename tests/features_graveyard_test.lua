-- features.graveyard.model: arena_lumberyard_event's graveyard.nut as rules.
-- After setup the dead come back as ghosts; a team's last player alive is
-- announced once; a team with nobody left alive loses.
local T = dofile("tests/harness.lua")
local Teams = gameplay.teams
local Model = T.require("features.graveyard.model")
local RED, BLUE = Teams.RED, Teams.BLUE

local function Counts(red, blue) return { [RED] = red, [BLUE] = blue } end

local function Started()
	local game = Model.New()
	game:FinishSetup()
	return game
end

local function Kinds(events)
	local list = {}
	for i, e in ipairs(events) do list[i] = e.kind .. (e.team and (" " .. e.team) or "") end
	return table.concat(list, ", ")
end

T.test("nobody is a ghost during setup; after it every playing team's spawn is one", function()
	local game = Model.New()
	T.eq(game:GhostOnSpawn(RED), false, "in setup")
	game:FinishSetup()
	T.eq(game:GhostOnSpawn(RED), true, "RED")
	T.eq(game:GhostOnSpawn(BLUE), true, "BLU")
	T.eq(game:GhostOnSpawn(Teams.SPECTATOR), false, "a spectator")
	T.eq(game:GhostOnSpawn(Teams.UNASSIGNED), false, "no team")
end)

T.test("nothing is decided during setup", function()
	T.eq(#Model.New():Check(Counts(0, 3), Counts(3, 3)), 0)
end)

T.test("a team's last player alive is announced once", function()
	local game = Started()
	T.eq(Kinds(game:Check(Counts(1, 3), Counts(3, 3))), Model.LAST_MAN .. " " .. RED, "first")
	T.eq(#game:Check(Counts(1, 2), Counts(3, 3)), 0, "not again")
end)

T.test("both teams may have their last player", function()
	T.eq(Kinds(Started():Check(Counts(1, 1), Counts(3, 3))), Model.LAST_MAN .. " " .. RED .. ", " .. Model.LAST_MAN .. " " .. BLUE)
end)

T.test("a team with nobody alive loses, to the other", function()
	T.eq(Kinds(Started():Check(Counts(0, 2), Counts(3, 3))), Model.WIN .. " " .. BLUE, "RED gone")
	T.eq(Kinds(Started():Check(Counts(2, 0), Counts(3, 3))), Model.WIN .. " " .. RED, "BLU gone")
end)

T.test("both teams gone at once is a stalemate", function()
	T.eq(Kinds(Started():Check(Counts(0, 0), Counts(3, 3))), Model.STALEMATE)
end)

-- TF2 waits for both teams; Sandcastle may start with one.
T.test("a team with no players at all decides nothing", function()
	T.eq(#Started():Check(Counts(1, 0), Counts(1, 0)), 0, "nobody to play")
	T.eq(#Started():Check(Counts(0, 0), Counts(0, 0)), 0, "an empty server")
end)

T.test("a decided round decides nothing more", function()
	local game = Started()
	game:Check(Counts(0, 2), Counts(3, 3))
	T.eq(#game:Check(Counts(0, 0), Counts(3, 3)), 0)
end)

T.test("a ghost heals by the dispenser's rate, never past full", function()
	T.eq(Model.Healed(50, 125, 1), 50 + Model.HEAL_PER_SECOND, "a second's")
	T.eq(Model.Healed(120, 125, 1), 125, "held at full")
end)

T.test("the map's script line prints the spell's message", function()
	T.eq(type(Model.CODE["printSpellMessage()"]), "string", "known")
	T.eq(Model.CODE["somethingElse()"], nil, "unknown")
end)

-- logic_script: a map's VScript, played by the feature ported from it.
local function LogicScript(loaded)
	local ENT = {}
	local env = setmetatable({
		ENT = ENT,
		WS = { Feature = function(name)
			loaded[#loaded + 1] = name
			return { RunScriptCode = function(_, code) loaded.code = code end }
		end },
	}, { __index = _G })
	setfenv(assert(loadfile("addons/sandcastle/gamemodes/sandcastle/entities/entities/logic_script.lua")), env)()
	return ENT
end

T.test("logic_script loads the port of its script, whatever the case", function()
	local loaded = {}
	local ent = LogicScript(loaded)
	ent:KeyValue("VScripts", "Graveyard.nut")
	ent:Initialize()
	T.eq(loaded[1], "graveyard", "the feature")
	T.eq(ent:AcceptInput("RunScriptCode", nil, nil, "printSpellMessage()"), true, "taken")
	T.eq(loaded.code, "printSpellMessage()", "handed to the port")
end)

T.test("logic_script with a script nobody ported does nothing", function()
	local loaded = {}
	local ent = LogicScript(loaded)
	ent:KeyValue("vscripts", "someone_elses.nut")
	ent:Initialize()
	T.eq(#loaded, 0, "no feature")
	T.eq(ent:AcceptInput("RunScriptCode", nil, nil, "x()"), true, "accepted, and ignored")
	T.eq(loaded.code, nil, "ran nothing")
end)

T.finish()
