-- Hostage rescue: the rules of CS:S's hostage maps (cs_office and the other
-- cs_ maps) as a value, apart from any entity. A hostage is held where the
-- map put it, follows whoever uses it, and ends rescued (led into a rescue
-- zone) or killed. The rescuers win once no hostage is unresolved, held or
-- following, and at least half of all were rescued; with fewer, the round
-- runs on to the other side's win by time or elimination (Valve Developer
-- Community, "Hostage Rescue"). Source's bug, where rescuing the last
-- hostage wins however many were killed, is not kept.
--
-- A round is immutable: each move returns a new round, and refuses what the
-- rules do not allow as an error at the caller's line, so a round that exists
-- is a valid one. Who the rescuers are and where the zones lie belong to the
-- controller; a rescuer here is any value that tells one from another.
local error, ipairs, pairs, setmetatable, type = error, ipairs, pairs, setmetatable, type
module(...)

HELD, FOLLOWING, RESCUED, KILLED = "held", "following", "rescued", "killed"

-- Outcome: the rescuers won.
RESCUED_WIN = "rescued"

-- How near a rescuer must stand to a held hostage to take it (CS:S's use
-- reach), in units.
USE_RANGE = 80

-- A rescued fraction of the total at which the rescuers win, once none is
-- left unresolved.
RESCUE_SHARE = 0.5

local Round = {}
Round.__index = Round

local function Copy(round, changes)
	local states, rescuers = {}, {}
	for id, state in pairs(round.states) do states[id] = state end
	for id, rescuer in pairs(round.rescuers) do rescuers[id] = rescuer end
	for id, change in pairs(changes) do
		states[id] = change.state
		rescuers[id] = change.rescuer
	end
	return setmetatable({ ids = round.ids, states = states, rescuers = rescuers }, Round)
end

-- ids: the map's hostages, a non-empty list of distinct strings.
function New(ids)
	if type(ids) ~= "table" or #ids == 0 then error("a hostage round needs hostages", 2) end
	local states = {}
	for _, id in ipairs(ids) do
		if type(id) ~= "string" then error("a hostage is named by a string, not " .. type(id), 2) end
		if states[id] then error("hostage " .. id .. " is named twice", 2) end
		states[id] = HELD
	end
	local listed = {}
	for i, id in ipairs(ids) do listed[i] = id end
	return setmetatable({ ids = listed, states = states, rescuers = {} }, Round)
end

local function Known(round, id)
	local state = round.states[id]
	if not state then error("no hostage " .. tostring(id), 3) end
	return state
end

local function Refuse(id, state, wanted)
	error("hostage " .. id .. " is " .. state .. ", not " .. wanted, 3)
end

function Round:Total() return #self.ids end

function Round:Has(id) return self.states[id] ~= nil end

function Round:StateOf(id) return Known(self, id) end

-- Who a following hostage follows; nil otherwise.
function Round:RescuerOf(id)
	Known(self, id)
	return self.rescuers[id]
end

local function CountOf(round, ...)
	local wanted, n = { ... }, 0
	for _, state in pairs(round.states) do
		for _, w in ipairs(wanted) do
			if state == w then n = n + 1 end
		end
	end
	return n
end

function Round:Rescued() return CountOf(self, RESCUED) end

function Round:Killed() return CountOf(self, KILLED) end

-- Held or following: not yet rescued or killed.
function Round:Unresolved() return CountOf(self, HELD, FOLLOWING) end

-- A held hostage follows its rescuer (the use key).
function Round:Follow(id, rescuer)
	local state = Known(self, id)
	if rescuer == nil then error("a hostage is followed by someone", 2) end
	if state ~= HELD then Refuse(id, state, HELD) end
	return Copy(self, { [id] = { state = FOLLOWING, rescuer = rescuer } })
end

-- A following hostage is let go where it stands.
function Round:Release(id)
	local state = Known(self, id)
	if state ~= FOLLOWING then Refuse(id, state, FOLLOWING) end
	return Copy(self, { [id] = { state = HELD } })
end

-- Every hostage following this rescuer is let go: they died or left. A
-- rescuer nobody follows changes nothing.
function Round:ReleaseFrom(rescuer)
	local changes = {}
	for id, who in pairs(self.rescuers) do
		if who == rescuer then changes[id] = { state = HELD } end
	end
	return Copy(self, changes)
end

-- A following hostage reaches a rescue zone.
function Round:Rescue(id)
	local state = Known(self, id)
	if state ~= FOLLOWING then Refuse(id, state, FOLLOWING) end
	return Copy(self, { [id] = { state = RESCUED } })
end

-- A held or following hostage dies.
function Round:Kill(id)
	local state = Known(self, id)
	if state == RESCUED or state == KILLED then Refuse(id, state, "alive") end
	return Copy(self, { [id] = { state = KILLED } })
end

-- RESCUED_WIN when the rescuers have won; nil while the round runs on.
function Round:Outcome()
	if self:Unresolved() > 0 then return nil end
	if self:Rescued() >= self:Total() * RESCUE_SHARE then return RESCUED_WIN end
	return nil
end
