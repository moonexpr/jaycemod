-- NextSoldier's tactics told for debugging (ns_squads_print, ns_lanes_print,
-- ns_battlelines_print and the overlay's labels): each squad's formation and what it is
-- doing as one (contact, bounding, flanking, falling back, its lane); each
-- team's lanes against each other and who holds them; and the shape of a
-- battle line, the posts a team holds, ordered across the way it faces.
--
-- Squads are fire teams, members roster entries (place, pos, hero), both
-- still features.aiwar.model's; lanes are games.nextsoldier.lanes' (they move to
-- NextSoldier in docs/ns-split.md). Positions are
-- { x, y, z } tables.
local ipairs, sort = ipairs, table.sort
local atan2, floor, max, min, sqrt, HUGE = math.atan2, math.floor, math.max, math.min, math.sqrt, math.huge
local format, concat = string.format, table.concat
local Tactics = require("games.nextsoldier.tactics")
local Squad = require("games.nextsoldier.squad")
local Orders = require("features.aiwar.orders")
local Distance = require("foundation.math.geometry").Distance
module(...)

local LEFT = 1 -- Tactics.FlankSide's side to the left

local function Round(n) return floor(n + 0.5) end

-- Squads ---------------------------------------------------------------------------

-- "escort 2"
function Name(fireTeam)
	return fireTeam.role .. " " .. fireTeam.index
end

local function BoundPhrase(fireTeam, members, now)
	local bound = fireTeam.bound
	local moving, there = 0, 0
	for _, member in ipairs(members) do
		if Tactics.Element(member) == bound.moving then
			moving = moving + 1
			if bound.arrived[member.place] then there = there + 1 end
		end
	end
	local swaps = max(0, Tactics.BOUND_TIME - (now - bound.since))
	return format("bounding: element %d moving, %d of %d there, swaps in %s s", bound.moving, there, moving, Round(swaps))
end

-- What the squad is doing as one, as phrases: its contact, its bound, its
-- flank, its steps back and its lane.
function Phrases(fireTeam, members, now)
	local phrases = {}
	local contact = Tactics.Contact(fireTeam, now)
	phrases[1] = contact and format("contact %s s ago", Round(now - contact.time)) or "no contact"
	if fireTeam.bound then phrases[#phrases + 1] = BoundPhrase(fireTeam, members, now) end
	if fireTeam.flankDone then
		phrases[#phrases + 1] = "flanked"
	elseif fireTeam.flank then
		phrases[#phrases + 1] = "flanking " .. (Tactics.FlankSide(fireTeam) == LEFT and "left" or "right")
	end
	if fireTeam.fallback then
		phrases[#phrases + 1] = format("fell back %d of %d steps", fireTeam.fallback, Tactics.FALLBACK_STEPS)
	end
	if fireTeam.laneIndex then phrases[#phrases + 1] = "lane " .. fireTeam.laneIndex end
	return phrases
end

-- One line: "escort 2: 4 strong; contact 2 s ago; bounding: ...".
function Summary(fireTeam, members, now)
	return format("%s: %d strong; %s", Name(fireTeam), #members, concat(Phrases(fireTeam, members, now), "; "))
end

-- How far the member is from its leader, or nil while either has no
-- position yet (its orders have not run since it joined).
local function FromLeader(member, leader)
	if not (leader and member.pos and leader.pos) then return nil end
	return Distance(member.pos, leader.pos)
end

-- The squad's report: a heading (its summary, its leader and how far its
-- farthest member is from it), then a line per member in place order,
-- flagging those past Orders.REGROUP_RANGE. describe(member) -> its label
-- ("#45") and what it is doing, or nil.
function SquadLines(fireTeam, members, now, describe)
	local leader = Squad.Leader(fireTeam)
	local leaderLabel = leader and describe(leader) or "no one"
	local spread = 0
	for _, member in ipairs(members) do
		if member ~= leader then spread = max(spread, FromLeader(member, leader) or 0) end
	end
	local lines = {
		format("%s; led by %s%s; spread %d u", Summary(fireTeam, members, now), leaderLabel,
			leader and leader.hero and " (hero)" or "", Round(spread)),
	}
	for _, member in ipairs(members) do
		local label, doing = describe(member)
		local line
		if member == leader then
			line = format("place %d %s leads", member.place, label)
			if doing then line = line .. ": " .. doing end
		else
			local away = FromLeader(member, leader)
			line = format("place %d %s: ", member.place, label)
				.. (away and format("%d u from its leader", Round(away)) or "no position yet")
			if doing then line = line .. ", " .. doing end
			if away and away > Orders.REGROUP_RANGE then line = line .. format("; straggling (past %d)", Orders.REGROUP_RANGE) end
		end
		lines[#lines + 1] = line
	end
	return lines
end

-- Lanes ------------------------------------------------------------------------------

-- The names of the team's squads holding lane `index` of this plan, in the
-- fire teams' order.
function Holders(lanes, index, fireTeams, team)
	local names = {}
	for _, fireTeam in ipairs(fireTeams) do
		if fireTeam.team == team and fireTeam.laneKey == lanes.key and fireTeam.laneIndex == index then
			names[#names + 1] = Name(fireTeam)
		end
	end
	return names
end

-- "lane 2 (flank): 900 u, raid 2" for the overlay.
function LaneLabel(lanes, index, fireTeams, team)
	local label = format("lane %d (%s): %d u", index, lanes[index].kind, Round(lanes[index].length))
	local holders = Holders(lanes, index, fireTeams, team)
	if #holders > 0 then label = label .. ", " .. concat(holders, ", ") end
	return label
end

-- Why a team has no new lanes yet, or nil.
function PlanStatus(plan, now)
	if not plan then return nil end
	if plan.planning then return format("planning: lane %d of %d", plan.tries, #plan.specs) end
	if plan.retryAt and now < plan.retryAt then
		return format("no route found; trying again in %d s", Round(plan.retryAt - now))
	end
	return nil
end

-- A line per lane: its kind, length and waypoints, and who holds it. With
-- no lanes, that and why. plan: the controller's lane plan for the team, or nil.
function LaneLines(lanes, fireTeams, team, plan, now)
	local lines = {}
	local status = PlanStatus(plan, now)
	if not lanes or #lanes == 0 then
		lines[1] = "no lanes"
		if status then lines[2] = status end
		return lines
	end
	for i, lane in ipairs(lanes) do
		local holders = Holders(lanes, i, fireTeams, team)
		lines[i] = format("lane %d (%s): %d u, %d waypoints; held by %s", i, lane.kind, Round(lane.length), #lane.points,
			#holders > 0 and concat(holders, ", ") or "no squad")
	end
	if status then lines[#lines + 1] = status end
	return lines
end

-- Battle lines -----------------------------------------------------------------------

local function Centre(points)
	local x, y = 0, 0
	for _, p in ipairs(points) do x, y = x + p.x, y + p.y end
	return x / #points, y / #points
end

-- The way a team's posts face: out from its base, through their middle.
function FacingFrom(points, base)
	local x, y = Centre(points)
	return {
		x = x - base.x,
		y = y - base.y,
	}
end

-- A line through the posts: facing (a direction on the ground, toward the
-- enemy) orders them across it, left to right as it faces, and measures
-- its width (across) and depth (along); with no facing, or one of no
-- length, the posts are held all round: a closed ring ordered by angle
-- round their centre, its width the farthest two apart across it.
-- Returns { points, closed, width, depth }.
function Shape(points, facing)
	local length = facing and sqrt(facing.x * facing.x + facing.y * facing.y) or 0
	local ordered = {}
	for i, p in ipairs(points) do ordered[i] = p end
	if #ordered == 0 then
		return {
			points = ordered,
			closed = false,
			width = 0,
			depth = 0,
		}
	end
	if length == 0 then
		local cx, cy = Centre(ordered)
		local angle, radius = {}, 0
		for _, p in ipairs(ordered) do
			angle[p] = atan2(p.y - cy, p.x - cx)
			radius = max(radius, sqrt((p.x - cx) ^ 2 + (p.y - cy) ^ 2))
		end
		sort(ordered, function(a, b) return angle[a] < angle[b] end)
		return {
			points = ordered,
			closed = true,
			width = radius * 2,
			depth = nil,
		}
	end
	local fx, fy = facing.x / length, facing.y / length
	-- to the left of the facing is (-fy, fx)
	local across, along = {}, {}
	local lo, hi, back, front = HUGE, -HUGE, HUGE, -HUGE
	for _, p in ipairs(ordered) do
		across[p], along[p] = -fy * p.x + fx * p.y, fx * p.x + fy * p.y
		lo, hi = min(lo, across[p]), max(hi, across[p])
		back, front = min(back, along[p]), max(front, along[p])
	end
	sort(ordered, function(a, b) return across[a] > across[b] end)
	return {
		points = ordered,
		closed = false,
		width = hi - lo,
		depth = front - back,
	}
end

-- "guard posts: 8, 1240 u wide and 310 u deep", or "... all round, 600 u across".
function LineReport(name, shape)
	local count = #shape.points
	if count == 0 then return name .. ": none" end
	if shape.closed then return format("%s: %d all round, %d u across", name, count, Round(shape.width)) end
	return format("%s: %d, %d u wide and %d u deep", name, count, Round(shape.width), Round(shape.depth))
end
