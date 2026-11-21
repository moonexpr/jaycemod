-- logic_sc_roundrules loaded in a fake GMod: the match's limits as the engine's own counters,
-- each a math_counter whose maximum is its convar's limit (CheckWinLimit, CheckMaxRounds).
local T = dofile ("tests/harness.lua")

local SOURCE = "addons/sandcastle/gamemodes/sandcastle/entities/entities/logic_sc_roundrules.lua"

-- limits: the convars' values by name. Returns the entity, initialized, and what it spawned by name.
local function Load (limits)
	local spawned, fired = {}, {}
	local function Convar (name) return { GetInt = function () return limits [name] or 0 end, GetBool = function () return false end } end
	local function Entity (class)
		local ent = { class = class, keys = {}, inputs = {} }
		function ent:SetKeyValue (key, value) self.keys [key] = value end
		function ent:SetName (name) self.name = name spawned [name] = self end
		function ent:Spawn () end
		function ent:Fire (input, value) self.inputs [#self.inputs + 1] = { input, value } end
		function ent:Remove () end
		return ent
	end
	local env = setmetatable (
		{
			ENT = {},
			GetConVar = function (name) return Convar (name) end,
			CreateConVar = function (name) return Convar (name) end,
			FCVAR_REPLICATED = 0,
			FCVAR_NOTIFY = 0,
			round_manager = { Preserve = function () end, SetWaiting = function () end, Waiting = function () return false end },
			ents = { Create = Entity },
			hook = { Add = function () end },
			CurTime = function () return 0 end,
			IsValid = function (v) return v ~= nil end
		}, { __index = _G })
	setfenv (assert (loadfile (SOURCE)), env) ()
	local rules = setmetatable ({}, { __index = env.ENT })
	function rules:SetName () end
	function rules:NextThink () end
	function rules:TriggerOutput () end
	rules:Initialize ()
	return rules, spawned
end

local WINS = { "sc_roundrules_wins_red", "sc_roundrules_wins_blue" }

T.test ("each team's wins count to mp_winlimit, the rounds to mp_maxrounds", function ()
	local _, spawned = Load ({ mp_winlimit = 3, mp_maxrounds = 5 })
	for _, name in ipairs (WINS) do
		T.eq (spawned [name].class,    "math_counter", name)
		T.eq (spawned [name].keys.max, "3",            name .. ": the win limit")
		T.eq (spawned [name].keys.min, "0",            name)
	end
	T.eq (spawned.sc_roundrules_rounds.keys.max, "5", "the round limit")
end)

-- Gameplay's win conditions set mp_winlimit to 0 for a map whose captures score (an attack/defend
-- map's stopwatch): a win limit there would end the match a capture in. A math_counter whose
-- minimum and maximum are both 0 has no limit, and never hits it.
T.test ("mp_winlimit may be 0, no limit: a team's wins then never take the match", function ()
	local _, spawned = Load ({ mp_winlimit = 0 })
	for _, name in ipairs (WINS) do
		T.eq (spawned [name].keys.min == "0" and spawned [name].keys.max == "0", true, name .. " has no limit")
	end
end)

T.test ("a limit changed mid-match moves its counters' maximum, without firing", function ()
	local limits = { mp_winlimit = 3 }
	local rules, spawned = Load (limits)
	limits.mp_winlimit = 2
	rules:UpdateLimits ()
	local inputs = spawned [WINS [1]].inputs
	T.eq (inputs [#inputs] [1], "SetMaxValueNoFire", "no output fired")
	T.eq (inputs [#inputs] [2], 2,                   "the new limit")
end)

T.finish ()
