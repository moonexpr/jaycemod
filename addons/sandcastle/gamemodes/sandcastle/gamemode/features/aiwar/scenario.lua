-- The AI war's scenario: what the war is fought over, as a Strategy chosen
-- from the rounds mode (TF2's CTFBotScenarioMonitor picks its action by game
-- type), never from the map. Each variant is a part,
-- features.aiwar.scenario.<mode>, required on first use so a map loads
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
--     team -> defense share or nil. A stance is features.aiwar.model's: a list
--     of { role, weight }; key names the situation (equal keys, the same
--     stance); critical skips the wait.
--   Front(field, team) -> pos or nil: where the team's lanes lead.
--   SetupAttacks(field) -> team -> pos: the teams that come out through
--     setup gates, and what each heads for.
-- and declares the field's PARTS its Brief reads: NEEDS, which the map
-- must have for the war to start (MapLacks), and AWAITS, which a round
-- brings; the controller briefs only a field that Lacks none.
local error, ipairs, require, setmetatable = error, ipairs, require, setmetatable
local AiWar = require("features.aiwar.model")
local Explore = nextsoldier.explore
local Teams = gameplay.teams
local Class = core.class
local Scenarios = nextsoldier.scenarios
module(...)

ALLOCATION_HOLD = 3 -- docs/aiwar-command.md §2.2

-- games.gameplay.rounds Mode NAMEs -> the variant's module; any other mode, or
-- none, is fought freeform (FREEFORM).
FREEFORM = "features.aiwar.scenario.freeform"
VARIANTS = {
	payload = "features.aiwar.scenario.payload",
	control_points = "features.aiwar.scenario.control_points",
	koth = "features.aiwar.scenario.koth",
	arena = "features.aiwar.scenario.arena",
	ctf = "features.aiwar.scenario.ctf",
	deathmatch = "features.aiwar.scenario.deathmatch",
	mvm = "features.aiwar.scenario.mvm",
}

-- The war's own scenarios, registered as any script registers one
-- (nextsoldier.scenarios): each variant for its rounds mode, at
-- MODE_PRIORITY, required when chosen, and freeform, for any mode, below
-- them. A script's scenario at a higher priority, with its own criteria,
-- takes over where those hold.
FREEFORM_PRIORITY, MODE_PRIORITY = 0, 10

Scenarios.Shared:Register({ name = "freeform", priority = FREEFORM_PRIORITY, scenario = FREEFORM })
Scenarios.Shared:Register({ name = "payload", priority = MODE_PRIORITY, mode = "payload", scenario = VARIANTS.payload })
Scenarios.Shared:Register({ name = "control_points", priority = MODE_PRIORITY, mode = "control_points", scenario = VARIANTS.control_points })
Scenarios.Shared:Register({ name = "koth", priority = MODE_PRIORITY, mode = "koth", scenario = VARIANTS.koth })
Scenarios.Shared:Register({ name = "arena", priority = MODE_PRIORITY, mode = "arena", scenario = VARIANTS.arena })
Scenarios.Shared:Register({ name = "ctf", priority = MODE_PRIORITY, mode = "ctf", scenario = VARIANTS.ctf })
Scenarios.Shared:Register({ name = "deathmatch", priority = MODE_PRIORITY, mode = "deathmatch", scenario = VARIANTS.deathmatch })
Scenarios.Shared:Register({ name = "mvm", priority = MODE_PRIORITY, mode = "mvm", scenario = VARIANTS.mvm })

-- The registered scenarios, compiled: what the war decides from, made
-- once when it starts.
function Compile()
	return Scenarios.Shared:Compile()
end

-- The scenario entry compiled plays in context ({ mode, field }: never the
-- map's name, as the map's entities choose), and its Scenario class.
function Entry(compiled, context)
	local entry = compiled:Choose(context)
	return entry, compiled:Class(entry)
end

-- The Scenario class for a rounds mode's NAME alone, from a fresh compile
-- (for a test or a report, not a think): freeform for a mode without a
-- standard objective, or no rounds at all, unless a registered scenario
-- takes over.
function For(modeName)
	local _, class = Entry(Compile(), { mode = modeName })
	return class
end

local TEAMS = { Teams.RED, Teams.BLUE }

local function BothTeams(byTeam)
	for _, team in ipairs(TEAMS) do
		if byTeam == nil or byTeam[team] == nil then return false end
	end
	return true
end

-- The parts of the controller's field a variant's Brief may read that a map
-- or a moment can lack, each with what having it means: points, the capture
-- HUD's (at least one); bases, both teams'; clocks, both teams' KOTH clocks;
-- waypoints, the nav mesh's to explore (nextsoldier.explore); flags,
-- both teams' (capture the flag); bomb, BLU's flag and the zone it is
-- delivered to (Mann vs. Machine).
POINTS, BASES, CLOCKS, WAYPOINTS, FLAGS, BOMB = "points", "bases", "clocks", "waypoints", "flags", "bomb"
PARTS = {
	[POINTS] = function(field) return field.points ~= nil and #field.points > 0 end,
	[BASES] = function(field) return BothTeams(field.bases) end,
	[CLOCKS] = function(field) return BothTeams(field.clocks) end,
	[WAYPOINTS] = function(field) return field.waypoints ~= nil and #field.waypoints > 0 end,
	[FLAGS] = function(field) return BothTeams(field.flags) end,
	[BOMB] = function(field)
		return field.flags ~= nil and field.flags[Teams.BLUE] ~= nil and field.zones ~= nil and field.zones[Teams.BLUE] ~= nil
	end,
}

-- NEEDS: the parts the map must have, or the war cannot start. AWAITS: the
-- parts a round brings (none in Sandbox mode, none between rounds), which
-- the war waits for: a field lacking any is never briefed.
-- SQUAD_SIZE: the most a squad the war forms holds.
Scenario = {
	NAME = "none",
	NEEDS = { BASES },
	AWAITS = {},
	SQUAD_SIZE = AiWar.FIRE_TEAM_SIZE,
}
Scenario.__index = Scenario

-- The first of parts the field lacks, or nil.
local function FirstMissing(field, parts)
	for _, part in ipairs(parts) do
		if not PARTS[part](field) then return part end
	end
	return nil
end

-- The first part the map lacks for this variant, or nil: the war may start.
function Scenario:MapLacks(field)
	return FirstMissing(field, self.NEEDS)
end

-- The first part the field lacks for this variant, or nil: the field is
-- whole, and Command may brief it.
function Scenario:Lacks(field)
	return FirstMissing(field, self.NEEDS) or FirstMissing(field, self.AWAITS)
end

-- A variant, inheriting what it does not override.
function Scenario:Extend(name)
	return Class.Extend(self, { NAME = name })
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

-- A new round: the stances are chosen afresh and exploring starts over. A
-- variant whose memory is of the round clears it too.
function Scenario:Reset()
	self.pending = {}
	self.current = {}
	self.board = nil
end

-- Every scenario keeps the exploration board (nextsoldier.explore),
-- explore being every doctrine's job: each squad's soldiers mark where they
-- have been and how far along its lane, a squad in contact is engaged, and
-- the field carries the board (field.explore). Then the variant briefs the
-- field and the stances are allocated.
function Scenario:Command(war, field, now)
	self:Explore(field).explore:Survey(war:Members(), now)
	self:Brief(field, now)
	self:Allocate(war, field, now)
end

-- The field with the scenario's exploration board on it (field.explore),
-- made on first use; a variant's Brief may call it too.
function Scenario:Explore(field)
	self.board = self.board or Explore.Board.New(field.waypoints)
	field.explore = self.board
	return field
end

local function NotImplemented(self, name)
	error(self.NAME .. " scenario: " .. name .. " not implemented", 3)
end

-- Each side's soldiers at a team size (mp_aiwar_team_size): as many a side.
function Scenario:TeamSizes(size)
	return { [Teams.RED] = size, [Teams.BLUE] = size }
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
