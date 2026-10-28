-- Part of the AI war controller (sv.lua): describing soldiers, the reports, and the debug overlay.
local Controller, Map, ARRIVED = ...
local AiWar = WS.require("features.aiwar.model")
local Orders = WS.require("features.aiwar.orders")
local Tactics = wartactics.fireteam
local Squad = wartactics.squad
local Inspect = WS.require("features.aiwar.inspect")
local RED, BLUE = Map.RED, Map.BLUE
local ToVector, IsDoor = Map.ToVector, Map.IsDoor

-- Debugging: ws_aiwar_report and ws_aiwar_debug ------------------------------

local DEBUG_INTERVAL = 0.5
local DEBUG_MAX_POINTS = 24

local TEAM_LABEL = { [RED] = "RED", [BLUE] = "BLU" }

local function Round(n) return math.floor(n + 0.5) end

-- A soldier's action for reports: "SquadLeader …/Push/Travel", or the full
-- name when something above the job holds it (Humiliated).
-- A soldier's squad for reports: its place and its leader.
local function SquadLine(member)
	local fireTeam = member.fireTeam
	if not fireTeam then return "none" end
	local leader = Squad.Leader(fireTeam)
	local count = 0
	for _ in pairs(fireTeam.members) do count = count + 1 end
	local of = string.format("%s %d, %d strong", fireTeam.role, fireTeam.index, count)
	if leader == member then return "leads " .. of .. (member.hero and " (hero)" or "") end
	local handle = leader and leader.handle
	return string.format("in %s, led by #%s", of, IsValid(handle) and handle:EntIndex() or "?")
end

-- ws_aiwar_debug_full shows the whole action stack instead, one
-- level per step: NextSoldier > StrategyMonitor > ... > Travel
-- (created with the war's other convars, in ws/sh_aiwar.lua).
local DEBUG_FULL = GetConVar("ws_aiwar_debug_full")

local function ActionLine(fullName)
	if DEBUG_FULL:GetBool() then return (fullName:gsub("/", " > ")) end
	local job, role, side = Orders.JobOf(fullName)
	if not job then return fullName end
	return role .. " …/" .. side .. "/" .. job
end

-- A soldier described: a heading that says who it is ("BLU npc_citizen
-- #45"), and labelled lines on what it is for, what it is doing, and where
-- its route stands.
function Controller:Describe(ent, entry)
	local member = self.war:Member(ent)
	local state, soldier = entry.npc:State(), entry.soldier
	local route = "none"
	if soldier.result == nil and soldier.ticket > 0 then route = "searching" end
	if soldier.result == false then route = "off the nav mesh" end
	if state.route then route = string.format("waypoint %d of %d", state.routeIndex, #state.route) end
	local heading = string.format("%s %s #%d", TEAM_LABEL[soldier.team], ent:GetClass(), ent:EntIndex())
	local lines = {
		"Role: " .. (member.role and (member.role .. " " .. member.slot) or "none")
			.. string.format(" (team %d%% on defense)", math.floor((self.war.defense[soldier.team] or 0) * 100 + 0.5))
			.. ((member.role == AiWar.RAID or member.role == AiWar.SUPPORT) and self.war:Field()
				and (", working " .. ((Orders.Focus(self.war:Field(), member) == "defense") and "the enemy's cart" or "its own cart")) or ""),
		-- the monitors' chain is the same for everyone doing a job: only its
		-- squad role is shown
		"Action: " .. ActionLine(entry.npc:Describe()),
		"Squad: " .. SquadLine(member),
		"Lane: " .. (member.fireTeam and member.fireTeam.laneIndex and ("lane " .. member.fireTeam.laneIndex .. (state.onLane and ", walking it" or "")) or "none"),
		"Route: " .. route,
		"Goal: " .. (state.goal and (Round(soldier:RangeTo(state.goal)) .. " units away") or "none"),
		"Last trip: " .. (state.trip or "none"),
		"Movement: " .. (soldier:RunState() or "left to the engine's AI"),
		"Enemy: " .. (soldier:HasEnemy() and "in sight" or "none in sight"),
	}
	if ent.NSHopWhy then lines[#lines + 1] = "Hop: a plain one the last time it was stuck, no vault (" .. ent.NSHopWhy .. ")" end
	if state.wandering then lines[#lines + 1] = "Setup: wandering until it ends" end
	if state.following then lines[#lines + 1] = "Following: its cart" end
	if state.fighting then
		local fireTeam = member.fireTeam
		lines[#lines + 1] = string.format("Fighting: %s (fire team %s %d)", state.tactic or "?", fireTeam and fireTeam.role or "-", fireTeam and fireTeam.index or 0)
	end
	if state.patrolling then lines[#lines + 1] = "Patrol: walking its rounds near its post until it or the objective moves" end
	if entry.disarmed then lines[#lines + 1] = "Humiliated: cannot attack, fears the winners" end
	if soldier.failures then
		lines[#lines + 1] = string.format("Engine runs failed: %d refused, %d stalled; last target %s over the node graph",
			soldier.failures.refused or 0, soldier.failures.stalled or 0,
			soldier.graphPath == nil and "untested" or (soldier.graphPath and "had a path" or "had NO path"))
	end
	if soldier.recoveries then lines[#lines + 1] = string.format("Recovered: %d time(s), last %s", soldier.recoveries, soldier.recoveredWhy) end
	if soldier.kit and soldier.kit.name then
		lines[#lines + 1] = "Kit: " .. soldier.kit.name .. (state.gadget and ("; last used " .. state.gadget) or "")
	end
	if state.cleared then lines[#lines + 1] = "Raid: round the enemy's line" end
	if soldier.cartRescues then lines[#lines + 1] = "Pulled out of a cart: " .. soldier.cartRescues .. " time(s)" end
	if soldier.seat then lines[#lines + 1] = "Riding: seat " .. soldier.seat.index .. " on its cart" end
	if state.retreats then lines[#lines + 1] = "Retreated: " .. state.retreats .. " time(s)" end
	if state.chases then lines[#lines + 1] = "Chased: " .. state.chases .. " weakened enemies" end
	if state.hops then lines[#lines + 1] = "Hops: " .. state.hops end
	if state.passed then lines[#lines + 1] = "Let through: " .. state.passed .. " NPC-only blocker(s)" end
	local blocked = self:BlockedBy(soldier)
	if blocked then lines[#lines + 1] = "Blocked by: " .. blocked end
	return heading, lines
end

-- What holds a soldier that is running but barely moving, in words, or nil.
local SLOW_RUN = 20

local function DescribeBlocker(blocker)
	if blocker:IsWorld() then return "map geometry (world brushes, func_detail among them)" end
	local text = blocker:GetClass()
	if blocker:GetName() ~= "" then text = text .. " '" .. blocker:GetName() .. "'" end
	if blocker:GetClass() == "func_brush" then
		text = text .. string.format(" (solidity %s, excluded NPC '%s', inverted %s)",
			tostring(blocker:GetInternalVariable("m_iSolidity")), tostring(blocker:GetInternalVariable("m_iszExcludedClass")),
			tostring(blocker:GetInternalVariable("m_bInvertExclusion")))
	end
	local door = IsDoor(blocker) and WS.Feature("npc"):DoorState(blocker)
	if door then
		local opener = door.controlled and ("a trigger" .. (door.owner and (" for " .. (TEAM_LABEL[door.owner] or door.owner)) or "")) or "none"
		local routes = door.blocks == nil and "open" or door.blocks == "any" and "closed to everyone" or ("closed to " .. (TEAM_LABEL[door.blocks] or door.blocks))
		text = text .. string.format(" (%s%s, opened by %s, routes: %s)", door.closed and "shut" or "open", door.locked and ", locked" or "", opener, routes)
		local noted = Controller.shutDoors and Controller.shutDoors[blocker]
		if noted then
			local teams = {}
			for team in pairs(noted.teams) do teams[#teams + 1] = TEAM_LABEL[team] or tostring(team) end
			text = text .. "; labelled blocked for " .. table.concat(teams, " and ") .. " this round"
		end
	end
	return text
end

function Controller:BlockedBy(soldier)
	local target = soldier.moveTarget
	if not target or soldier:RangeTo(target) <= ARRIVED then return nil end
	if (soldier.walkSpeed or 0) > SLOW_RUN then return nil end
	local blocker, playersPass = soldier:Blocker(target)
	if not blocker then return "nothing in the way (the floor ahead is too steep, too high a step or missing)" end
	return DescribeBlocker(blocker) .. (playersPass and "; a player would pass" or "; blocks players too")
end

-- The team's scenario, the key of the stance it applied (payload's
-- allocation has none) and the ranks of its target, guard and staging
-- points; "-" for none.
local function RankOf(point) return point and tostring(point.rank) or "-" end

function Controller:ScenarioLine(field, team)
	local entry = self.scenario.current[team]
	local objectives = field and field.objectives and field.objectives[team] or {}
	return string.format("  %s %s: stance %s, target %s, guard %s, staging %s", TEAM_LABEL[team], self.scenario.NAME,
		entry and entry.key or "-", RankOf(objectives.target), RankOf(objectives.guard), RankOf(objectives.staging))
end

function Controller:Report()
	local lines = {}
	local field = self.war:Field()
	lines[1] = string.format("AI war, %s scenario: phase %s, %d nav areas, %d spawn-door triggers open to NPCs, %d route searches running",
		self.scenario.NAME, field and field.phase.name or "none", navmesh.GetNavAreaCount(), table.Count(self.doorFlags),
		WS.Feature("npc"):SearchesRunning())
	if self.waitingFor then lines[#lines + 1] = "  waiting for the field's " .. self.waitingFor .. ", which the round brings" end
	for _, team in ipairs({ RED, BLUE }) do lines[#lines + 1] = self:ScenarioLine(field, team) end
	for team, cart in pairs(field and field.carts or {}) do
		lines[#lines + 1] = string.format("  %s cart: %d of %d units along its track", TEAM_LABEL[team], Round(cart.distance), Round(cart.track:Length()))
	end
	for team, gates in pairs(self.gates or {}) do
		for _, gate in ipairs(gates) do
			lines[#lines + 1] = string.format("  %s must pass gate %s at (%d, %d, %d)", TEAM_LABEL[team], tostring(gate.door), Round(gate.pos.x), Round(gate.pos.y), Round(gate.pos.z))
		end
	end
	local list = {}
	for ent, entry in pairs(self.soldiers) do
		if IsValid(ent) then list[#list + 1] = { ent = ent, entry = entry } end
	end
	table.sort(list, function(a, b) return a.ent:EntIndex() < b.ent:EntIndex() end)
	for _, item in ipairs(list) do
		local heading, details = self:Describe(item.ent, item.entry)
		lines[#lines + 1] = "  " .. heading
		for _, detail in ipairs(details) do lines[#lines + 1] = "    " .. detail end
	end
	if #list == 0 then lines[#lines + 1] = "  no soldiers" end
	return lines
end

-- Squads, lanes and battle lines: ns_squads_print, ns_lanes_print, ns_battlelines_print

-- Each fire team with members, and its members in place order.
function Controller:Squads()
	local squads = {}
	for _, fireTeam in ipairs(self.war.fireTeams) do
		local members = self.war:FireTeamMembers(fireTeam)
		if #members > 0 then
			squads[#squads + 1] = {
				fireTeam = fireTeam,
				members = members,
			}
		end
	end
	return squads
end

-- A roster member's label ("#45") and what it is doing: its tactic in a
-- fight, else its action.
function Controller:DescribeMember(member)
	local handle = member.handle
	if not IsValid(handle) then return "#?", nil end
	local entry = self.soldiers[handle]
	local label = "#" .. handle:EntIndex()
	if not entry then return label, nil end
	local state = entry.npc:State()
	if state.fighting and state.tactic then return label, state.tactic end
	return label, ActionLine(entry.npc:Describe())
end

-- team: RED or BLUE, or nil for both.
function Controller:SquadReport(team)
	local lines, now = { "NextSoldier squads:" }, CurTime()
	local function Describe(member) return self:DescribeMember(member) end
	for _, squad in ipairs(self:Squads()) do
		local fireTeam = squad.fireTeam
		if team == nil or fireTeam.team == team then
			local body = Inspect.SquadLines(fireTeam, squad.members, now, Describe)
			lines[#lines + 1] = "  " .. TEAM_LABEL[fireTeam.team] .. " " .. body[1]
			for i = 2, #body do lines[#lines + 1] = "    " .. body[i] end
		end
	end
	if #lines == 1 then lines[2] = "  no squads" end
	return lines
end

local function PosText(p)
	return string.format("(%d, %d, %d)", Round(p.x), Round(p.y), Round(p.z or 0))
end

function Controller:LaneReport()
	local lines, now = { "NextSoldier lanes:" }, CurTime()
	local field = self.war:Field()
	for _, team in ipairs({ RED, BLUE }) do
		local front = field and self.scenario:Front(field, team)
		lines[#lines + 1] = string.format("  %s, toward %s:", TEAM_LABEL[team], front and PosText(front) or "no front")
		local lanes, plan = self.laneSets and self.laneSets[team], self.lanePlans and self.lanePlans[team]
		for _, line in ipairs(Inspect.LaneLines(lanes, self.war.fireTeams, team, plan, now)) do
			lines[#lines + 1] = "    " .. line
		end
	end
	return lines
end

-- Plans every team's lanes again at the next think (ns_lanes_replan,
-- or a lanes constant tuned); the lanes found stand until then.
function Controller:ReplanLanes()
	self.lanePlans = {}
end

-- The team's battle lines: its posts (a ring round a hill all may be
-- attacked from, else facing out from its base) and its forward posts, as
-- { kind, shape } (features.aiwar.inspect's Shape).
function Controller:BattleLines(field, team)
	local base = field.bases and field.bases[team]
	local lines = {}
	local function Add(kind, points, allRound)
		if not points or #points == 0 then return end
		local facing = (not allRound and base) and Inspect.FacingFrom(points, base) or nil
		lines[#lines + 1] = {
			kind = kind,
			shape = Inspect.Shape(points, facing),
		}
	end
	Add("posts", field.posts and field.posts[team], self.scenario.GUARDS_ALL_ROUND)
	Add("forward posts", field.forwardPosts and field.forwardPosts[team], false)
	return lines
end

function Controller:LineReport()
	local field, now = self.war:Field(), CurTime()
	if not field then return { "NextSoldier battle lines: no field yet" .. (self.waitingFor and (", waiting for its " .. self.waitingFor) or "") } end
	local lines = { "NextSoldier battle lines:" }
	local squads = self:Squads()
	for _, team in ipairs({ RED, BLUE }) do
		local front = self.scenario:Front(field, team)
		lines[#lines + 1] = string.format("  %s, front %s:", TEAM_LABEL[team], front and PosText(front) or "none")
		local battleLines = self:BattleLines(field, team)
		for _, line in ipairs(battleLines) do lines[#lines + 1] = "    " .. Inspect.LineReport(line.kind, line.shape) end
		if #battleLines == 0 then lines[#lines + 1] = "    no posts" end
		for _, squad in ipairs(squads) do
			local fireTeam = squad.fireTeam
			if fireTeam.team == team and (fireTeam.fallback or Tactics.Contact(fireTeam, now)) then
				lines[#lines + 1] = "    " .. Inspect.Summary(fireTeam, squad.members, now)
			end
		end
	end
	return lines
end

-- The overlay: each soldier's line, goal and remaining route, to the
-- admins who asked for it.
function Controller:SendDebug(now)
	if now < (self.nextDebug or 0) then return end
	self.nextDebug = now + DEBUG_INTERVAL
	local viewers = {}
	for _, ply in ipairs(player.GetAll()) do
		if ply.wsAiwarDebug then viewers[#viewers + 1] = ply end
	end
	if #viewers == 0 then return end
	local list = {}
	for ent, entry in pairs(self.soldiers) do
		if IsValid(ent) then list[#list + 1] = { ent = ent, entry = entry } end
	end
	-- The game_aiwar_debug game event (features/nbdebug/sh.lua), for the nbdebug
	-- view. Every squad with a leader: its summary, and in a fight where it
	-- last saw the enemy and its flank point.
	local fireTeams, teamIndex = {}, {}
	for _, squad in ipairs(self:Squads()) do
		local fireTeam = squad.fireTeam
		local leader = Squad.Leader(fireTeam)
		if leader and IsValid(leader.handle) and #fireTeams < 255 then
			local contact = Tactics.Contact(fireTeam, now)
			fireTeams[#fireTeams + 1] = {
				team = fireTeam.team,
				name = Inspect.Name(fireTeam),
				summary = Inspect.Summary(fireTeam, squad.members, now),
				leader = leader.handle,
				contact = contact and ToVector(contact.pos) or nil,
				flank = contact and fireTeam.flank and not fireTeam.flankDone and ToVector(fireTeam.flank) or nil,
			}
			teamIndex[fireTeam] = #fireTeams
		end
	end
	-- the support sphere of each team with a cart
	local spheres = {}
	local field = self.war:Field()
	for team, cart in pairs(field and field.carts or {}) do
		local center, radius = Orders.SupportSphere(cart)
		spheres[#spheres + 1] = {
			team = team,
			center = ToVector(center),
			radius = radius,
			push = false,
		}
	end
	-- each team's lanes, named with the squads holding them
	local lanes = {}
	for team, set in pairs(field and field.lanes or {}) do
		for index, lane in ipairs(set) do
			if #lanes < 15 then
				local points = {}
				for j = 1, math.min(#lane.points, 63) do points[j] = ToVector(lane.points[j]) end
				lanes[#lanes + 1] = {
					team = team,
					index = index,
					label = Inspect.LaneLabel(set, index, self.war.fireTeams, team),
					points = points,
				}
			end
		end
	end
	-- each team's battle lines and front
	local lines, fronts = {}, {}
	for _, team in ipairs(field and { RED, BLUE } or {}) do
		for _, line in ipairs(self:BattleLines(field, team)) do
			local points = {}
			for j = 1, math.min(#line.shape.points, 63) do points[j] = ToVector(line.shape.points[j]) end
			lines[#lines + 1] = {
				team = team,
				kind = line.kind,
				points = points,
				closed = line.shape.closed,
			}
		end
		local front = self.scenario:Front(field, team)
		if front then
			fronts[#fronts + 1] = {
				team = team,
				pos = ToVector(front),
			}
		end
	end
	local soldiers = {}
	for i = 1, math.min(#list, 255) do
		local item = list[i]
		local state = item.entry.npc:State()
		local heading, all = self:Describe(item.ent, item.entry)
		local details = {}
		for j = 1, math.min(#all, 15) do details[j] = all[j] end
		local route, first = state.route or {}, state.routeIndex or 1
		local points = {}
		for j = first, math.min(#route, first + DEBUG_MAX_POINTS - 1) do points[#points + 1] = ToVector(route[j]) end
		-- its squad (1-based in the list above, 0 for none); in a fight, its
		-- element and cover
		local fireTeam = state.member and state.member.fireTeam
		soldiers[i] = {
			ent = item.ent,
			team = item.entry.soldier.team,
			heading = heading,
			details = details,
			goal = state.goal and ToVector(state.goal) or nil,
			route = points,
			fire_team = fireTeam and teamIndex[fireTeam] or 0,
			fighting = state.fighting == true,
			moving = state.element == "moving",
			cover = state.coverSpot and ToVector(state.coverSpot) or nil,
		}
	end
	WS.Events.Fire("game_aiwar_debug", {
		fire_teams = fireTeams,
		lines = lines,
		fronts = fronts,
		spheres = spheres,
		lanes = lanes,
		soldiers = soldiers,
	}, viewers)
end
