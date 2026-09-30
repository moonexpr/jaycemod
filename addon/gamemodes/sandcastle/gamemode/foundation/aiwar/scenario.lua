-- The AI war's scenario: what the war is fought over, as a Strategy chosen
-- from the rounds mode (TF2's CTFBotScenarioMonitor picks its action by game
-- type), never from the map. Each variant is a part,
-- foundation.aiwar.scenario.<mode>, required on first use so a map loads
-- only its own. The aiwar controller makes one instance per war and calls
-- Command once per think; Reset at each new round.
--
-- Command is the Commander's tick (docs/aiwar-command.md §2), a template
-- method: Brief puts the variant's reading of the field on it (the
-- doctrine, field.doctrine, and the variant's own parts), then Allocate
-- sets each team's stance. The default Allocate damps: a team's stance
-- changes only once the new one has held ALLOCATION_HOLD seconds, unless it
-- is critical or the team has none yet.
--
-- A variant fills in:
--   Brief(field, now)
--   Stances(field, now) -> team -> { stance, key, critical } or nil, and
--     team -> defense share or nil. A stance is foundation.aiwar's: a list
--     of { role, weight }; key names the situation (equal keys, the same
--     stance); critical skips the wait.
--   Front(field, team) -> pos or nil: where the team's lanes lead.
--   SetupAttacks(field) -> team -> pos: the teams that come out through
--     setup gates, and what each heads for.
local error, ipairs, require, setmetatable = error, ipairs, require, setmetatable
local Teams = require("foundation.teams")
module(...)

ALLOCATION_HOLD = 3 -- docs/aiwar-command.md §2.2

-- foundation.rounds Mode NAMEs -> the variant's module.
VARIANTS = {
	payload = "foundation.aiwar.scenario.payload",
	control_points = "foundation.aiwar.scenario.control_points",
	koth = "foundation.aiwar.scenario.koth",
}

-- The variant's Scenario class for a rounds mode's NAME, or nil for a mode
-- the war cannot fight over (or no rounds at all).
function For(modeName)
	local path = modeName and VARIANTS[modeName]
	return path and require(path).Scenario or nil
end

local TEAMS = { Teams.RED, Teams.BLUE }

Scenario = { NAME = "none" }
Scenario.__index = Scenario

-- A variant, inheriting what it does not override.
function Scenario:Extend(name)
	local class = setmetatable({}, self)
	class.__index = class
	class.NAME = name
	return class
end

-- memory: the variant's own, across ticks; pending: team -> the key waiting
-- and since when; current: team -> the stance entry applied.
function Scenario:New()
	return setmetatable({
		memory = {},
		pending = {},
		current = {},
	}, self)
end

-- A new round: the stances are chosen afresh. A variant whose memory is of
-- the round clears it too.
function Scenario:Reset()
	self.pending = {}
	self.current = {}
end

function Scenario:Command(war, field, now)
	self:Brief(field, now)
	self:Allocate(war, field, now)
end

local function NotImplemented(self, name)
	error(self.NAME .. " scenario: " .. name .. " not implemented", 3)
end

function Scenario:Brief(field, now) NotImplemented(self, "Brief") end
function Scenario:Stances(field, now) NotImplemented(self, "Stances") end
function Scenario:Front(field, team) NotImplemented(self, "Front") end
function Scenario:SetupAttacks(field) NotImplemented(self, "SetupAttacks") end

-- The entry to apply for the team now, or nil to leave it as it is.
function Scenario:Damp(team, entry, now)
	local current = self.current[team]
	if current == nil or entry.critical or entry.key == current.key then
		self.pending[team] = nil
		return entry
	end
	local pending = self.pending[team]
	if pending == nil or pending.key ~= entry.key then
		self.pending[team] = {
			key = entry.key,
			since = now,
		}
		return nil
	end
	if now - pending.since >= ALLOCATION_HOLD then
		self.pending[team] = nil
		return entry
	end
	return nil
end

function Scenario:Allocate(war, field, now)
	local entries, defense = self:Stances(field, now)
	local chosen = {}
	for _, team in ipairs(TEAMS) do
		local entry = entries[team] and self:Damp(team, entries[team], now)
		if entry then
			self.current[team] = entry
			chosen[team] = entry.stance
		end
	end
	war:AssignStances(chosen, defense)
end
