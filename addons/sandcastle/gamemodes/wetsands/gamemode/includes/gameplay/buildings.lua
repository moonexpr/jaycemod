-- What a support unit builds, and the rules each keeps (TF2's objects, tf_obj_*.cpp, and an access
-- door of our own): a sentry, a teleporter and an access door. Each goes up over its construction
-- time and is harmed by its enemies and the world, never its own team.
--   SENTRY, TELEPORTER, DOOR; HEALTH[kind], BUILD_TIME[kind]
--   Constructed(kind, startedAt, now) -> 0..1 (an unknown kind refused); Harms(team, attackerTeam)
--   Target(from, candidates, team, sees(candidate)) -> the nearest enemy candidate ({ pos, team })
--     sees within SENTRY_RANGE, or nil; Turn(angle, toward, dt) -> the angle turned toward it at
--     SENTRY_TURN_RATE, the short way round (unwrapped); OnTarget(angle, toward) -> within
--     SENTRY_FIRE_CONE of it, either side
--   Carries(team, riderTeam); Charged(lastTrip, now) (true before the first)
--   Passes(team, walkerTeam): a door lets its own team through, no other
--   Barriers() -> the nav areas standing doors close: Add(id, team, areaIds), Remove(id),
--     Blocks(areaId, walkerTeam) -> whether a door there does not pass walkerTeam
local Teams = gameplay.teams
local Geometry = math.geometry
local ipairs, pairs, error, tostring, abs, setmetatable = ipairs, pairs, error, tostring, math.abs, setmetatable
module (...)

SENTRY, TELEPORTER, DOOR = "sentry", "teleporter", "door"

-- A level-1 object's health (tf_obj_sentrygun.cpp SENTRYGUN_MAX_HEALTH, the teleporter's 150); the
-- door's is ours. Construction is a bot's, quicker than TF2's 10.5 s by hand.
HEALTH = { [SENTRY] = 150, [TELEPORTER] = 150, [DOOR] = 500 }
BUILD_TIME = { [SENTRY] = 5, [TELEPORTER] = 5, [DOOR] = 3 }

-- A level-1 sentry: SENTRY_MAX_RANGE, its bullets' damage and interval; how fast it turns
-- (degrees a second) and how near its aim must be (degrees either side) before it fires.
SENTRY_RANGE, SENTRY_DAMAGE, SENTRY_FIRE_INTERVAL = 1100, 16, 0.25
SENTRY_TURN_RATE, SENTRY_FIRE_CONE = 360, 10

-- A teleporter's recharge after each trip at level 1 (g_flTeleporterRechargeTimes).
TELEPORTER_RECHARGE = 10

-- What a player pays to set one down from the spawn menu.
SPAWN_PRICE = { [SENTRY] = 2000, [TELEPORTER] = 500 }

-- An access door opens for a teammate within DOOR_OPEN_REACH, and shuts DOOR_CLOSE_DELAY after the
-- last has gone.
DOOR_OPEN_REACH, DOOR_CLOSE_DELAY = 96, 1

function Constructed (kind, startedAt, now)
	local time = BUILD_TIME [kind]
	if not time then error ("no building of kind " .. tostring (kind), 2) end
	local share = (now - startedAt) / time
	if share >= 1 then return 1 end
	return share
end

function Harms (team, attackerTeam)
	return attackerTeam ~= team or (team ~= Teams.RED and team ~= Teams.BLUE)
end

function Target (from, candidates, team, sees)
	local best, nearest
	for _, candidate in ipairs (candidates) do
		if candidate.team ~= team and candidate.team >= Teams.FIRST_GAME_TEAM then
			local d = Geometry.Distance (from, candidate.pos)
			if d <= SENTRY_RANGE and (not best or d < nearest) and sees (candidate) then best, nearest = candidate, d end
		end
	end
	return best
end

-- toward - angle, in (-180, 180].
local function Difference (angle, toward)
	local d = (toward - angle) % 360
	if d > 180 then d = d - 360 end
	return d
end

function Turn (angle, toward, dt)
	local d, step = Difference (angle, toward), SENTRY_TURN_RATE * dt
	if abs (d) <= step then return angle + d end
	return angle + (d > 0 and step or -step)
end

function OnTarget (angle, toward) return abs (Difference (angle, toward)) <= SENTRY_FIRE_CONE end

function Carries (team, riderTeam) return team >= Teams.FIRST_GAME_TEAM and riderTeam == team end

function Charged (lastTrip, now) return lastTrip == nil or now - lastTrip >= TELEPORTER_RECHARGE end

function Passes (team, walkerTeam) return walkerTeam >= Teams.FIRST_GAME_TEAM and walkerTeam == team end

local Barrier = {}
Barrier.__index = Barrier

function Barriers () return setmetatable ({ doors = {}, areas = {} }, Barrier) end

function Barrier:Add (id, team, areaIds)
	self.doors [id] = { team = team, areas = areaIds }
	for _, area in ipairs (areaIds) do
		self.areas [area] = self.areas [area] or {}
		self.areas [area] [id] = team
	end
end

function Barrier:Remove (id)
	local door = self.doors [id]
	if not door then return end
	self.doors [id] = nil
	for _, area in ipairs (door.areas) do self.areas [area] [id] = nil end
end

function Barrier:Blocks (areaId, walkerTeam)
	for _, team in pairs (self.areas [areaId] or {}) do
		if not Passes (team, walkerTeam) then return true end
	end
	return false
end
