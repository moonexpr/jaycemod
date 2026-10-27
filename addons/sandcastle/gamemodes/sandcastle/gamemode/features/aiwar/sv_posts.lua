-- Part of the AI war controller (sv.lua): the observer, and the posts where soldiers hold their line.
local Controller, Map = ...
local AiWar = WS.require("features.aiwar.model")
local Posts = nextsoldier.posts
local Memo = cache.memo
local Debug = WS.require("features.nbdebug.model")
local SPAWN_LIFT = Map.SPAWN_LIFT
local Point, ToVector, SpawnSpots, OnFloor = Map.Point, Map.ToVector, Map.SpawnSpots, Map.OnFloor
local ClearSpotNear, GroundBelow = Map.ClearSpotNear, Map.GroundBelow

-- The observer ---------------------------------------------------------------------------------
-- A soldier that fell out of the map, or is wedged where nothing gets it
-- out, is put back: one outside the world, or off the nav mesh for
-- OFF_MESH_TIME, where it last stood on the mesh (on its own side of any
-- wall; the nearest nav area may be beyond one), else at its spawn; one
-- that has tried to move for AiWar.STRANDED_TIME without getting
-- STRANDED_PROGRESS from where it was, and not for a fight
-- (AiWar.StrandedWatch), onto the next waypoint of its route when a player
-- could walk there. A soldier recovered again within
-- RELAPSE_TIME goes back to spawn. The mesh leaves gaps along walls and
-- round corners, which a soldier sliding along a wall walks into: it is
-- off the mesh only with no nav area it can see within OFF_MESH_REACH.
local WATCH_INTERVAL = 2
local STRANDED_PROGRESS = 48
local OFF_MESH_BELOW, OFF_MESH_LIFT = 96, Vector(0, 0, 16)
local OFF_MESH_REACH, OFF_MESH_TIME = 48, 5
local RELAPSE_TIME = 60

function Controller:OnMesh(pos)
	if IsValid(navmesh.GetNavArea(pos + OFF_MESH_LIFT, OFF_MESH_BELOW)) then return true end
	return IsValid(navmesh.GetNearestNavArea(pos + OFF_MESH_LIFT, false, OFF_MESH_REACH, true, true))
end

function Controller:SpawnSpot(team)
	local spots = SpawnSpots(team)
	if #spots == 0 then return nil end
	local spot = spots[math.random(#spots)]
	return ClearSpotNear(spot:GetPos())
end

function Controller:Recover(ent, entry, reason, pos)
	local soldier, now = entry.soldier, CurTime()
	local relapse = soldier.recoveredAt and now - soldier.recoveredAt < RELAPSE_TIME
	if relapse or not pos then
		pos = self:SpawnSpot(soldier.team)
		reason = reason .. (relapse and ", again: back to spawn" or ": back to spawn")
	end
	soldier.recoveredAt = now
	soldier.recoveries = (soldier.recoveries or 0) + 1
	soldier.recoveredWhy = reason
	soldier.watch = nil
	if not pos then
		-- nowhere to put it: the next wave replaces it
		soldier:Mark(Debug.MARK_RECOVERED, reason .. ", but no spawn to put it at: killed for the next wave", nil)
		ent:TakeDamage(ent:Health() + 1, game.GetWorld(), game.GetWorld())
		return
	end
	soldier:Mark(Debug.MARK_RECOVERED, reason, pos + SPAWN_LIFT)
	soldier:Release()
	ent:SetPos(pos + SPAWN_LIFT)
	if ent.loco then ent.loco:SetVelocity(vector_origin) end
end

function Controller:Watch(ent, entry, now)
	local soldier = entry.soldier
	local pos = ent:GetPos()
	local inWorld = util.IsInWorld(pos + OFF_MESH_LIFT)
	if inWorld and self:OnMesh(pos) then
		soldier.lastOnMesh = pos
		soldier.offMeshSince = nil
	else
		soldier.offMeshSince = soldier.offMeshSince or now
		if not inWorld or now - soldier.offMeshSince >= OFF_MESH_TIME then
			soldier.offMeshSince = nil
			local spot = soldier.lastOnMesh and ClearSpotNear(soldier.lastOnMesh)
			return self:Recover(ent, entry, inWorld and "off the nav mesh" or "out of the world", spot)
		end
	end
	local watch = soldier.watch
	local verdict = watch and AiWar.StrandedWatch({
		travelling = soldier.moveTarget ~= nil,
		fighting = soldier:HasEnemy(),
		moved = pos:Distance(watch.pos) > STRANDED_PROGRESS,
		since = watch.since,
		now = now,
	}) or AiWar.WATCH_AGAIN
	if verdict == AiWar.WATCH_AGAIN then
		soldier.watch = { pos = pos, since = now }
		return
	end
	if verdict == AiWar.WATCHING then return end
	local state = entry.npc:State()
	local waypoint = state.route and state.route[math.min((state.routeIndex or 1) + 1, #state.route)]
	local spot = waypoint and ClearSpotNear(OnFloor(ToVector(waypoint)))
	-- never through what would stop a player: a shut door, a wall
	if spot and soldier:Sweep(pos, spot).Hit then spot = nil end
	self:Recover(ent, entry, "stranded", spot)
end

-- Posts: where soldiers establish their line ----------------------------------------------
-- games.nextsoldier.posts picks among the nav mesh's hiding spots (with
-- their cover and sniper flags) and the centres of areas well above or
-- below the place in question (high ground, pits), each tested for a
-- clear line from eye height:
-- - a team's defenders: near the checkpoint the enemy cart heads for,
--   seeing it; found once per checkpoint;
-- - a team's escorts: ahead of its own cart along the track, seeing the
--   cart; found again every FORWARD_STEP the cart moves, so the line is
--   pushed forward with it.
local HIDING_IN_COVER, HIDING_GOOD_SNIPER, HIDING_IDEAL_SNIPER = 1, 2, 4 -- CNavArea hiding spot flags
local POST_EYE, TARGET_EYE = Vector(0, 0, 64), Vector(0, 0, 48)
local HIGH_OR_LOW = 48 -- an area this far above or below the place is high or low ground
local SEARCH_HEIGHT = 1000
local FORWARD_STEP = 200

local function Sees(pos, target)
	local tr = util.TraceLine({ start = pos + POST_EYE, endpos = target + TARGET_EYE, mask = MASK_SOLID_BRUSHONLY })
	return not tr.Hit
end

-- Every candidate spot within radius of center, once each, with its flags.
local function CandidateSpots(center, radius)
	local spots, order = {}, {}
	local function Add(pos, cover, sniper)
		local key = string.format("%d %d %d", pos.x, pos.y, pos.z)
		local spot = spots[key]
		if not spot then
			spot = { pos = pos, cover = false, sniper = 0 }
			spots[key] = spot
			order[#order + 1] = spot
		end
		spot.cover = spot.cover or cover
		spot.sniper = math.max(spot.sniper, sniper)
	end
	for _, area in ipairs(navmesh.Find(center, radius, SEARCH_HEIGHT, SEARCH_HEIGHT)) do
		for _, pos in ipairs(area:GetHidingSpots(HIDING_IN_COVER) or {}) do Add(pos, true, 0) end
		for _, pos in ipairs(area:GetHidingSpots(HIDING_GOOD_SNIPER) or {}) do Add(pos, false, Posts.GOOD_SNIPER) end
		for _, pos in ipairs(area:GetHidingSpots(HIDING_IDEAL_SNIPER) or {}) do Add(pos, false, Posts.IDEAL_SNIPER) end
		local areaCenter = area:GetCenter()
		if math.abs(areaCenter.z - center.z) >= HIGH_OR_LOW then Add(areaCenter, false, 0) end
	end
	return order
end

function Controller:CachedPosts(kind, team, key, find)
	self.postCache = self.postCache or Memo.New({})
	return self.postCache:Fetch(kind .. team, key, find)
end

-- Where a team's defenders wait for the enemy cart.
function Controller:DefendersPosts(team, cart)
	if not cart.nextCheckpoint then return nil end
	return self:CachedPosts("defend", team, tostring(cart.track) .. "@" .. cart.nextCheckpoint, function()
		local objective = GroundBelow(ToVector(cart.track:PointAt(cart.nextCheckpoint)))
		local cartPos = ToVector(cart.pos)
		local candidates = {}
		for _, spot in ipairs(CandidateSpots(objective, Posts.MAX_RANGE)) do
			candidates[#candidates + 1] = {
				pos = Point(spot.pos),
				sees = Sees(spot.pos, objective),
				toObjective = spot.pos:Distance(objective),
				toCart = spot.pos:Distance(cartPos),
				elevation = spot.pos.z - objective.z,
				cover = spot.cover,
				sniper = spot.sniper,
			}
		end
		return Posts.Pick(candidates, AiWar.TEAM_SIZE_MAX)
	end)
end

-- Where a team's escorts push their line ahead of their own cart.
function Controller:ForwardPosts(team, cart)
	local step = math.floor(cart.distance / FORWARD_STEP)
	return self:CachedPosts("forward", team, tostring(cart.track) .. "@" .. step, function()
		local cartPos = ToVector(cart.pos)
		local ahead = GroundBelow(ToVector(cart.track:PointAt(cart.distance + Posts.MAX_LEAD / 2)))
		local candidates = {}
		for _, spot in ipairs(CandidateSpots(ahead, Posts.MAX_LEAD)) do
			local point = Point(spot.pos)
			candidates[#candidates + 1] = {
				pos = point,
				sees = Sees(spot.pos, cartPos),
				ahead = cart.track:DistanceOf(point) - cart.distance,
				toCart = spot.pos:Distance(cartPos),
				elevation = spot.pos.z - cartPos.z,
				cover = spot.cover,
				sniper = spot.sniper,
			}
		end
		return Posts.Pick(candidates, AiWar.TEAM_SIZE_MAX, Posts.ScoreForward)
	end)
end

-- Where a team's defenders guard the point its scenario has it guard
-- (field.objectives[team].guard), found once per guard point: TF2's defense
-- areas round a point (CSelectDefenseAreaForPoint), scored by
-- Posts.ScoreGuard. past is how much farther from the team's base the spot
-- is than the point, TF2's incursion distance's stand-in; anywhere lifts
-- the limit on it (the scenario's GUARDS_ALL_ROUND, KOTH's hill). Payload's
-- posts, when it wrote any, stand.
function Controller:GuardPosts(field)
	for team, objectives in pairs(field.objectives or {}) do
		local guard, base = objectives.guard, field.bases[team]
		if guard and guard.zone and base and not field.posts[team] then
			field.posts[team] = self:CachedPosts("guard", team, guard.rank, function()
				local point, home = ToVector(guard.zone.center), ToVector(base)
				local toPointFromHome = home:Distance(point)
				local candidates = {}
				for _, spot in ipairs(CandidateSpots(point, Posts.MAX_GUARD_RANGE)) do
					candidates[#candidates + 1] = {
						pos = Point(spot.pos),
						sees = Sees(spot.pos, point),
						toPoint = spot.pos:Distance(point),
						elevation = spot.pos.z - point.z,
						cover = spot.cover,
						sniper = spot.sniper,
						past = home:Distance(spot.pos) - toPointFromHome,
						anywhere = self.scenario.GUARDS_ALL_ROUND,
					}
				end
				return Posts.Pick(candidates, AiWar.TEAM_SIZE_MAX, Posts.ScoreGuard)
			end)
		end
	end
end

return WATCH_INTERVAL
