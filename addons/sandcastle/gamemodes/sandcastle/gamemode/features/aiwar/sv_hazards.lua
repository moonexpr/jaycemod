-- Part of the AI war controller (sv.lua): the nav areas that keep forcing
-- its soldiers to respawn (wartactics.hazards). Every think it notes the
-- area each soldier stands on while on the ground (NoteFooting); a soldier
-- dead to the world (no combatant's hand: an enemy's push is kill credit's
-- and the enemy's) or recovered back to its spawn (sv_posts.lua's Recover)
-- lays it on that area, unless the area is a spawn room's or a door, brush
-- or the engine blocks it already. An area that reaches
-- Hazards.THRESHOLD is disabled: the npc feature closes it to every team
-- (SetDisabledAreas), so routes plan round it. The hazards are saved at
-- once, before a map change and at shutdown (the controller's hazardStore:
-- data/sandcastle/nav_hazards/<map>.json), and applied again on the map's
-- next load (only areas whose centre is still where it was: a mesh made
-- since may number its areas otherwise) until someone inspects and clears
-- them (ns_hazards_print, ns_hazards_clear). When the disabled areas cut a
-- team's spawns off from the objective it fights for, which they could
-- reach before, the war requests a forced match closure from the gamerules
-- (the rounds feature's RequestMatchClosure), which decide how the match
-- ends; the intermission then changes the map. With no gamerules running,
-- the next map is loaded.
--
-- Judging separation is walks over the whole mesh, and nothing waits on
-- it: it is a transaction on the slow lane (WS.SlowTransactions) that
-- yields between its walks and has SEPARATION_TIME to finish in (WS.Deadline),
-- so the tick is left to the soldiers' combat and pathfinding.
local Controller, Map = ...
local Hazards = wartactics.hazards
local Transaction = transaction
local HL2Path = WS.require("foundation.wetsands.path.hl2")
local Path = wetsands.path
local Graph = graph.search
local RED, BLUE = Map.RED, Map.BLUE
local Point, ToVector, SpawnSpots = Map.Point, Map.ToVector, Map.SpawnSpots

-- The area underfoot is looked for this far below a soldier on the ground.
local FOOT_REACH = 36
-- A saved area is still the mesh's own while its centre is within this of
-- where it was.
local SAME_AREA = 32
-- A spawn or a front finds its nav area within this.
local AREA_REACH = 256
-- A walk is followed this far (every area of any map).
local WALK_LIMIT = 1e7
local SEPARATED = "the AI war's soldiers are cut off from the objective by nav areas disabled as hazards"
-- A separation check that has not finished in this many seconds is given up.
local SEPARATION_TIME = 30

-- The map's hazards, read from its save the first time they are asked.
function Controller:Hazards()
	if not self.hazards then
		local saved = self.hazardStore:Read()
		self.hazards = saved and Hazards.Decode(saved) or Hazards.New()
		self.hazardsSaved = saved ~= nil
	end
	return self.hazards
end

-- Saved when there is anything to keep, or a save to empty.
function Controller:SaveHazards()
	if not self.hazards or (#self.hazards:Entries() == 0 and not self.hazardsSaved) then return end
	self.hazardStore:Write(Hazards.Encode(self.hazards))
	self.hazardsSaved = true
end

-- A disabled hazard's area on this mesh, or nil when the mesh's area of
-- that id is no longer the one saved.
local function AreaOf(entry)
	local area = navmesh.GetNavAreaByID(entry.id)
	if not IsValid(area) then return nil end
	if area:GetCenter():Distance(ToVector(entry.where)) > SAME_AREA then return nil end
	return area
end

-- The disabled areas still the mesh's own, id -> true.
function Controller:DisabledAreas()
	local set = {}
	for _, entry in ipairs(self:Hazards():Entries()) do
		if entry.disabled and AreaOf(entry) then set[entry.id] = true end
	end
	return set
end

function Controller:ApplyHazards()
	WS.Feature("npc"):SetDisabledAreas(self:DisabledAreas())
end

-- Every think: the area each soldier stands on, kept while it is on the ground.
function Controller:NoteFooting(ent)
	local grounded
	if ent:IsPlayer() then grounded = ent:OnGround() else grounded = ent.loco ~= nil and ent.loco:IsOnGround() end
	if not grounded then return end
	local area = navmesh.GetNavArea(ent:GetPos(), FOOT_REACH)
	if IsValid(area) then self.footAreas[ent] = area:GetID() end
end

-- A soldier forced to respawn (cause, Hazards.FELL or RECOVERED): laid on
-- the last area it stood on.
function Controller:NoteHazard(ent, cause)
	local id = self.footAreas[ent]
	local area = id and navmesh.GetNavAreaByID(id)
	if not IsValid(area) then return end
	local npcs = WS.Feature("npc")
	if npcs:SpawnOrBlocked(area) then return end
	if not self:Hazards():Record(id, cause, Point(area:GetCenter())) then return end
	print(string.format("AI war: nav area %d at %s disabled: soldiers were forced to respawn from it %d times (ns_hazards_print, ns_hazards_clear)",
		id, tostring(area:GetCenter()), Hazards.THRESHOLD))
	self:ApplyHazards()
	self:SaveHazards()
	self:CheckSeparation()
end

-- The walks from starts (area ids) over the mesh, closed areas left out.
local function Walks(starts, closed)
	return Graph.Distances(starts, function(id)
		local area, list = navmesh.GetNavAreaByID(id), {}
		local center = area:GetCenter()
		for _, other in ipairs(area:GetAdjacentAreas()) do
			local to = other:GetID()
			if not closed[to] and Path.Walkable(area:ComputeAdjacentConnectionHeightChange(other), HL2Path.SOLDIER_LIMITS)
				and WS.NavLinkCrossable(area, other) then
				list[#list + 1] = { node = to, cost = center:Distance(other:GetCenter()) }
			end
		end
		return list
	end, WALK_LIMIT)
end

-- Whether the team's spawns reach the front it fights for, with and
-- without the disabled areas; nil, nil when it has no spawn or front to
-- judge.
function Controller:Reaches(team, front, disabled, work)
	local starts = {}
	for _, spot in ipairs(SpawnSpots(team)) do
		local area = navmesh.GetNearestNavArea(spot:GetPos(), false, AREA_REACH)
		if IsValid(area) and not disabled[area:GetID()] then starts[#starts + 1] = area:GetID() end
	end
	local goal = navmesh.GetNearestNavArea(ToVector(front), false, AREA_REACH)
	if #starts == 0 or not IsValid(goal) then return nil, nil end
	local id = goal:GetID()
	local before = Walks(starts, {})[id] ~= nil
	work:Yield() -- the second walk on another turn
	return before, Walks(starts, disabled)[id] ~= nil
end

-- The judgement itself, as a transaction's work: whether the disabled
-- areas cut a team off from its objective, which it reached without them;
-- if so, the gamerules are asked to close the match (else, with no
-- gamerules, the next map is loaded). Yields between the walks.
function Controller:JudgeSeparation(work)
	local field = self.war and self.war:Field()
	if not field then return false end
	local disabled = self:DisabledAreas()
	if next(disabled) == nil then return false end
	local fronts = {}
	for _, team in ipairs({ RED, BLUE }) do
		local front = self.scenario:Front(field, team)
		if front then
			local before, now = self:Reaches(team, front, disabled, work)
			if before then fronts[#fronts + 1] = { team = team, reaches = now } end
		end
		work:CheckYield()
	end
	-- the war may have ended, or the areas been cleared, while it yielded
	if not self.war or not Hazards.Separated(fronts) or next(self:DisabledAreas()) == nil then return false end
	print("AI war: " .. SEPARATED)
	if WS.Active() and WS.FeatureLoaded("rounds") then
		local closing = WS.Feature("rounds"):RequestMatchClosure(SEPARATED)
		closing:OnSettle(function(tx)
			if tx:State() == Transaction.COMMITTED then
				local winner = tx:Value().winner
				print("AI war: the match is closed, " .. (winner and ("won by team " .. winner) or "a sudden death deciding it"))
			elseif tx:State() == Transaction.DECLINED then
				print("AI war: the gamerules declined to close the match: " .. Transaction.Message(tx:Refusal()))
			else
				ErrorNoHalt("AI war: closing the match failed: " .. tostring(tx:Error()) .. "\n")
			end
		end)
	else
		WS.ChangeToNextMap()
	end
	return true
end

-- Judges separation on the slow lane, one judgement at a time: asked
-- while one is under way, it is judged again once that one is done.
function Controller:CheckSeparation()
	if not (self.war and self.war:Field()) then return end
	if self.separationCheck then
		self.separationAgain = true
		return
	end
	local tx = Transaction.Spawn(WS.SlowTransactions, function(work) return self:JudgeSeparation(work) end)
		:Within(WS.Deadline(SEPARATION_TIME))
	self.separationCheck = tx
	tx:OnSettle(function(settled)
		self.separationCheck = nil
		if settled:State() == Transaction.DECLINED then
			print("AI war: the separation check was dropped: " .. Transaction.Message(settled:Refusal()))
		elseif settled:State() == Transaction.FAILED then
			ErrorNoHalt("AI war: the separation check failed: " .. tostring(settled:Error()) .. "\n")
		end
		if self.separationAgain then
			self.separationAgain = nil
			self:CheckSeparation()
		end
	end)
end

-- The hazards saved on a load find the war's first field: applied, and the
-- map judged at once (a map its hazards cut off ends its match).
function Controller:HazardsThink()
	if self.hazardsApplied then return end
	self.hazardsApplied = true
	if next(self:DisabledAreas()) == nil then return end
	self:ApplyHazards()
	self:CheckSeparation()
end

local function Died(victim, attacker)
	if not (Controller.war and Controller.soldiers[victim]) then return end
	if IsValid(attacker) and WS.Combatant(attacker) then return end
	Controller:NoteHazard(victim, Hazards.FELL)
end
hook.Add("PlayerDeath", "ws_aiwar_hazards", function(victim, _, attacker) Died(victim, attacker) end)
hook.Add("OnNPCKilled", "ws_aiwar_hazards", function(npc, attacker) Died(npc, attacker) end)

local function Save() Controller:SaveHazards() end
hook.Add("ShutDown", "ws_aiwar_hazards", Save)
hook.Add("WSChangeLevel", "ws_aiwar_hazards", Save)

-- Inspecting them ------------------------------------------------------------------------

concommand.Add("ns_hazards_print", function(ply)
	if IsValid(ply) and not ply:IsSuperAdmin() then return end
	local entries = Controller:Hazards():Entries()
	print(string.format("ns_hazards_print: %d nav areas laid on, disabled at %d", #entries, Hazards.THRESHOLD))
	for _, entry in ipairs(entries) do
		local causes = {}
		for cause, count in SortedPairs(entry.causes) do causes[#causes + 1] = cause .. " " .. count end
		print(string.format("  area %d at %d %d %d: %d (%s)%s%s", entry.id, entry.where.x, entry.where.y, entry.where.z, entry.count,
			table.concat(causes, ", "), entry.disabled and ", disabled" or "",
			entry.disabled and not AreaOf(entry) and ", not applied: the mesh's area is another now" or ""))
	end
end, nil, "List the nav areas the AI war laid soldiers' forced respawns on, and those it disabled")

concommand.Add("ns_hazards_clear", function(ply, _, args)
	if IsValid(ply) and not ply:IsSuperAdmin() then return end
	local hazards = Controller:Hazards()
	if args[1] == "all" then
		hazards:ClearAll()
	elseif tonumber(args[1]) then
		if not hazards:Clear(tonumber(args[1])) then print("ns_hazards_clear: no nav area " .. args[1] .. " laid on") return end
	else
		print("ns_hazards_clear <area id|all>")
		return
	end
	Controller:ApplyHazards()
	Controller:SaveHazards()
	print("ns_hazards_clear: cleared " .. args[1])
end, nil, "Open nav areas the AI war disabled as hazards again, once inspected: one by its id, or all")
