-- What a support unit builds, and the rules each keeps (TF2's objects, tf_obj_*.cpp, and an access
-- door of our own): a sentry, a teleporter, a dispenser and an access door. Each goes up over its construction
-- time and is harmed by its enemies and the world, never its own team.
--   SENTRY, TELEPORTER, DISPENSER, DOOR; HEALTH[kind], BUILD_TIME[kind]
--   Constructed(kind, startedAt, now) -> 0..1 (an unknown kind refused); Harms(team, attackerTeam)
--   Target(from, candidates, team, sees(candidate)) -> the nearest enemy candidate ({ pos, team })
--     sees within SENTRY_RANGE, or nil; Turn(angle, toward, dt) -> the angle turned toward it at
--     SENTRY_TURN_RATE, the short way round (unwrapped); OnTarget(angle, toward) -> within
--     SENTRY_FIRE_CONE of it, either side; Pose(yaw, pitch) -> its model's aim_yaw and aim_pitch
--     for an aim from its facing
--   Carries(team, riderTeam); Charged(lastTrip, now) (true before the first)
--   A wrench: Tends(team, wielderTeam); Repaired(health, maxHealth) -> health after a hit;
--     Hurried(kind, startedAt, now) -> when it began, a hit later; Upkeep(buildings) -> of
--     { constructed, health, max }s, the one furthest from whole, or nil with all whole
--   A dispenser: Serves(team, bodyTeam); Dispensed(health, maxHealth, dt) -> health after dt of
--     healing; AmmoGiven(count, most) -> the rounds of a weapon's ammo given an interval
--   Passes(team, walkerTeam): a door lets its own team through, no other
--   Barriers() -> the nav areas standing doors close: Add(id, team, areaIds), Remove(id),
--     Blocks(areaId, walkerTeam) -> whether a door there does not pass walkerTeam
local Teams = gameplay.teams
local Geometry = math.geometry
local ipairs, pairs, error, tostring, abs, setmetatable = ipairs, pairs, error, tostring, math.abs, setmetatable
local min, max, floor = math.min, math.max, math.floor
module (...)

SENTRY, TELEPORTER, DISPENSER, DOOR = "sentry", "teleporter", "dispenser", "door"

-- A level-1 object's health (tf_obj_sentrygun.cpp SENTRYGUN_MAX_HEALTH, the teleporter's 150); the
-- door's is ours. Construction is a bot's, quicker than TF2's 10.5 s by hand.
HEALTH = { [SENTRY] = 150, [TELEPORTER] = 150, [DISPENSER] = 150, [DOOR] = 500 }
BUILD_TIME = { [SENTRY] = 5, [TELEPORTER] = 5, [DISPENSER] = 5, [DOOR] = 3 }

-- A level-1 sentry: SENTRY_MAX_RANGE, its bullets' damage and interval; how fast it turns
-- (degrees a second) and how near its aim must be (degrees either side) before it fires.
SENTRY_RANGE, SENTRY_DAMAGE, SENTRY_FIRE_INTERVAL = 1100, 16, 0.25
-- A sentry by its level (CObjectSentrygun's upgrades): its health and its guns' interval; at level 3
-- its rocket's interval, damage and speed (FireRocket, CTFProjectile_SentryRocket's).
SENTRY_LEVELS =
{
	[1] = { health = 150, interval = SENTRY_FIRE_INTERVAL },
	[3] = { health = 216, interval = 0.1, rocketInterval = 3, rocketDamage = 100, rocketSpeed = 1100 }
}
SENTRY_TURN_RATE, SENTRY_FIRE_CONE = 360, 10
-- How far up or down its gun turns (CObjectSentrygun::Attack's pin to [-50, 50]).
SENTRY_PITCH_MAX = 50
-- Searching, it sweeps SENTRY_SEARCH_ARC either side of its facing (CObjectSentrygun::OnGoActive's
-- bounds), at SENTRY_SEARCH_SHARE of its turn rate.
SENTRY_SEARCH_ARC, SENTRY_SEARCH_SHARE = 50, 0.25

-- A teleporter's recharge after each trip at level 1 (g_flTeleporterRechargeTimes).
TELEPORTER_RECHARGE = 10

-- What a player pays to set one down from the spawn menu.
SPAWN_PRICE = { [SENTRY] = 2000, [TELEPORTER] = 500, [DISPENSER] = 1000 }

-- A level-1 dispenser (tf_obj_dispenser.cpp): how near a teammate is served, the health it gives a
-- second, and the share of what a body may carry of its weapon's ammo given each interval.
DISPENSER_RANGE, DISPENSER_HEAL_RATE = 64, 10
DISPENSER_AMMO_SHARE, DISPENSER_AMMO_INTERVAL = 0.2, 1

-- A wrench (tf_weapon_wrench): what a hit mends of a built building (TF2's 105, without metal), how
-- many seconds it takes off one going up, what it does to anything else, how far it reaches and how
-- often it swings (TF2's melee range and the wrench's interval). A bot tends its team's buildings
-- within TEND_REACH of it.
WRENCH_REPAIR, WRENCH_HURRY, WRENCH_DAMAGE = 105, 1, 65
WRENCH_RANGE, WRENCH_INTERVAL = 64, 0.8
TEND_REACH = 2000

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

function Tends (team, wielderTeam) return wielderTeam == team end

function Serves (team, bodyTeam) return bodyTeam == team end

function Dispensed (health, maxHealth, dt) return min (health + DISPENSER_HEAL_RATE * dt, maxHealth) end

function AmmoGiven (count, most)
	if count >= most then return 0 end
	return min (max (floor (most * DISPENSER_AMMO_SHARE), 1), most - count)
end

function Repaired (health, maxHealth) return min (health + WRENCH_REPAIR, maxHealth) end

function Hurried (kind, startedAt, now) return max (startedAt - WRENCH_HURRY, now - BUILD_TIME [kind]) end

-- How near whole one is: the less of its construction and its share of health.
local function Whole (building) return min (building.constructed, building.health / building.max) end

function Upkeep (buildings)
	local worst, least
	for _, building in ipairs (buildings) do
		local whole = Whole (building)
		if whole < 1 and (not worst or whole < least) then worst, least = building, whole end
	end
	return worst
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

function Pose (yaw, pitch) return -Difference (0, yaw), -pitch end

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
