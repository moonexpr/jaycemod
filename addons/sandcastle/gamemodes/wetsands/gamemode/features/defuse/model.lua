-- Bomb defusal: the rules of CS:S's de_ maps as a value, apart from any
-- entity. RED (the terrorists) carries the bomb to a bomb site and plants
-- it; planted, it explodes when its timer runs out (RED wins, TARGET_BOMBED)
-- unless BLU (the counter-terrorists) defuses it first (BOMB_DEFUSED).
-- Before the plant either side wins by killing the other, and BLU when the
-- round's time runs out (TARGET_SAVED); after it, killing all of BLU still
-- wins for RED, but killing all of RED does not win for BLU: the bomb must
-- still be defused, and with nobody left it decides.
--
-- A round is immutable: each move returns a new round, and refuses what the
-- rules do not allow as an error at the caller's line. Where the sites lie
-- and who carries the bomb belong to the controller; a site here is any
-- value that tells one from another.
local error, setmetatable = error, setmetatable
local Rounds = gameplay.rounds
local Teams = gameplay.teams
module(...)

CARRIED, PLANTED, DEFUSED, EXPLODED = "carried", "planted", "defused", "exploded"

local RED, BLUE = Teams.RED, Teams.BLUE
local W = Rounds.WINREASON

local Round = {}
Round.__index = Round

local function Made(t) return setmetatable(t, Round) end

function New() return Made({ state = CARRIED }) end

function Round:State() return self.state end
function Round:Site() return self.site end

local function Refuse(round, wanted)
	error("the bomb is " .. round.state .. ", not " .. wanted, 3)
end

-- Planted at site at now, to explode `seconds` later.
function Round:Plant(site, now, seconds)
	if self.state ~= CARRIED then Refuse(self, CARRIED) end
	if seconds <= 0 then error("a bomb's timer runs for some time, not " .. seconds, 2) end
	return Made({ state = PLANTED, site = site, explodeAt = now + seconds })
end

function Round:Defuse()
	if self.state ~= PLANTED then Refuse(self, PLANTED) end
	return Made({ state = DEFUSED, site = self.site })
end

-- Whether a planted bomb's timer has run out by now.
function Round:Due(now)
	return self.state == PLANTED and now >= self.explodeAt
end

-- Seconds left on a planted bomb's timer.
function Round:Remaining(now)
	if self.state ~= PLANTED then Refuse(self, PLANTED) end
	return self.explodeAt - now
end

function Round:Explode(now)
	if not self:Due(now) then Refuse(self, "due") end
	return Made({ state = EXPLODED, site = self.site })
end

-- Whether team, the only one left alive (nil: neither), wins by it.
function Round:EliminationWins(team)
	if self.state ~= PLANTED then return true end
	return team == RED
end

-- alive: team -> its living count; timeUp: the round's time has run out.
-- The winner and why, or nil while the round runs on.
function Round:Outcome(alive, timeUp)
	if self.state == EXPLODED then return RED, W.TARGET_BOMBED end
	if self.state == DEFUSED then return BLUE, W.BOMB_DEFUSED end
	if alive[BLUE] == 0 and alive[RED] > 0 then return RED, W.OPPONENTS_DEAD end
	if self.state == PLANTED then return nil end
	if alive[RED] == 0 and alive[BLUE] > 0 then return BLUE, W.OPPONENTS_DEAD end
	if timeUp then return BLUE, W.TARGET_SAVED end
	return nil
end
