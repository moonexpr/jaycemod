-- Part of the AI war controller (sv.lua): starting and ending the war, pausing, and squads and jobs by hand.
local Controller, Map = ...
local AiWar = WS.require("foundation.aiwar")
local Scenario = WS.require("foundation.aiwar.scenario")
local Notices = WS.require("foundation.admin_notices")
local Gamemode = WS.require("games.system.gamemode")
local RED, BLUE = Map.RED, Map.BLUE
local RoundsModeName = Map.RoundsModeName

local ACTIVE_KEY = "ws.aiwar" -- Global2: the Utilities menu reads it

-- Pausing, squads and jobs by hand (ns_soldiers_paused, ns_squads_*, ns_jobs_*) --------------

-- Paused, every soldier stands where it is: its DrGBase AI is off (it
-- neither moves nor shoots), its orders wait and no wave comes. The war is
-- paused by hand (ns_soldiers_paused) or while the server is idle
-- (WS.ServerIdle, ws/sv_idle.lua), when nobody is there to fight it; the
-- rounds run on either way.
function Controller:ShouldPause()
	return GetConVar("ns_soldiers_paused"):GetBool() or WS.ServerIdle()
end

function Controller:SetPaused(on)
	self.paused = on
	for ent in pairs(self.soldiers) do
		if IsValid(ent) then ent:SetAIDisabled(on) end
	end
end

-- The soldiers with these entity indexes, as the war's members; or nil and
-- the line saying which index is none.
function Controller:MembersAt(command, indexes)
	local byIndex = {}
	for ent in pairs(self.soldiers) do
		if IsValid(ent) then byIndex[ent:EntIndex()] = ent end
	end
	local members = {}
	for i, index in ipairs(indexes) do
		local ent = byIndex[index]
		if ent == nil then return nil, { string.format("%s: #%d is no soldier of the war", command, index) } end
		members[i] = self.war:Member(ent)
	end
	return members
end

-- A squad by hand: the first soldier leads, the others join it.
function Controller:FormSquadOf(indexes)
	local members, told = self:MembersAt("ns_squads_form", indexes)
	if members == nil then return told end
	local squad = self.war:FormSquad(members[1])
	local lines = { string.format("ns_squads_form: #%d leads a new squad", indexes[1]) }
	for i = 2, #members do
		local ok, why = self.war:JoinSquad(members[i], squad)
		lines[#lines + 1] = ok and string.format("ns_squads_form: #%d joined it", indexes[i]) or ("ns_squads_form: " .. why)
	end
	return lines
end

-- The soldiers join the squad the soldier `leaderIndex` is in.
function Controller:JoinSquadOf(leaderIndex, indexes)
	local leaders, told = self:MembersAt("ns_squads_join", { leaderIndex })
	if leaders == nil then return told end
	local squad = leaders[1].fireTeam
	if squad == nil then return { string.format("ns_squads_join: #%d is in no squad", leaderIndex) } end
	local members, unknown = self:MembersAt("ns_squads_join", indexes)
	if members == nil then return unknown end
	local lines = {}
	for i, member in ipairs(members) do
		local ok, why = self.war:JoinSquad(member, squad)
		lines[#lines + 1] = ok and string.format("ns_squads_join: #%d joined #%d's squad", indexes[i], leaderIndex) or ("ns_squads_join: " .. why)
	end
	return lines
end

function Controller:LeaveSquadOf(indexes)
	local members, told = self:MembersAt("ns_squads_leave", indexes)
	if members == nil then return told end
	for _, member in ipairs(members) do self.war:LeaveSquad(member) end
	return { string.format("ns_squads_leave: %d soldiers left their squads", #members) }
end

function Controller:DissolveSquads()
	self.war:DissolveSquads()
	return { "ns_squads_dissolve: every squad dissolved" .. (self.war.autoSquads and "; automatic squads regrouped them" or "") }
end

-- The jobs the scenario's doctrine has, sorted; none before the first field.
function Controller:Jobs()
	local field = self.war and self.war:Field()
	local jobs = {}
	for job in pairs(field and field.doctrine.ROLES or {}) do jobs[#jobs + 1] = job end
	table.sort(jobs)
	return jobs
end

function Controller:AssignJob(job, indexes)
	local jobs = self:Jobs()
	local known = false
	for _, each in ipairs(jobs) do known = known or each == job end
	if not known then return { string.format("ns_jobs_assign: %s is no job here (%s)", job, table.concat(jobs, ", ")) } end
	local members, told = self:MembersAt("ns_jobs_assign", indexes)
	if members == nil then return told end
	local lines = {}
	for i, member in ipairs(members) do
		local ok, why = self.war:SetRole(member, job)
		lines[#lines + 1] = ok and string.format("ns_jobs_assign: #%d does %s", indexes[i], job) or ("ns_jobs_assign: " .. why)
	end
	return lines
end

function Controller:ReleaseJob(indexes)
	local members, told = self:MembersAt("ns_jobs_release", indexes)
	if members == nil then return told end
	for _, member in ipairs(members) do self.war:ReleaseRole(member) end
	return { string.format("ns_jobs_release: %d soldiers' jobs are the war's again", #members) }
end

-- Starting and ending ------------------------------------------------------------------

-- The war as the gamemode tells it (features/gamemode): its sides and size
-- in the chat when it starts or joins the countdown to Gameplay mode, an
-- announcement when it starts in Gameplay mode.
local function Story()
	local red, blue = Controller.war:Faction(WS.TEAM_RED).name, Controller.war:Faction(WS.TEAM_BLUE).name
	local sizes = Controller:Sizes()
	local strength = sizes[RED] == sizes[BLUE] and string.format("%d soldiers a side", sizes[RED])
		or string.format("%d %s and %d %s soldiers", sizes[RED], red, sizes[BLUE], blue)
	return {
		title = "AI war declared!",
		lines = {
			string.format("The %s fight for %s, the %s for %s.", red, WS.TeamName[WS.TEAM_RED], blue,
				WS.TeamName[WS.TEAM_BLUE]),
			strength .. ", reinforced in respawn waves; the soldiers you spawn join their side.",
		},
		announcement = string.format("AI war: the %s and the %s join the fight, %s", red, blue, strength),
	}
end

-- Why a map lacking a part its scenario needs (Scenario:MapLacks) is refused.
local MAP_LACKS = {
	[Scenario.BASES] = "this map has no spawn points for both teams, where the AI war's soldiers join the fight",
	[Scenario.POINTS] = "this map's round has no control points for the AI war to fight over",
	[Scenario.FLAGS] = "this map has no intelligence for both teams for the AI war to fight over",
	[Scenario.BOMB] = "this map has no bomb and hatch for the AI war's robots to deliver it to",
}
local NO_NAV_MESH = "this map has no navigation mesh for the soldiers to walk; "
	.. "run mp_nav_generate in the console to make one (a few minutes), then start the war"
-- arena's squads explore the nav mesh's waypoints
MAP_LACKS[Scenario.WAYPOINTS] = NO_NAV_MESH

-- Starts the war at once and requests Gameplay mode, whose countdown
-- restarts the rounds. The scenario is the rounds mode's (the map's own
-- entities chose it), never the map's name. Returns true, or false and why
-- not.
function Controller:Start()
	if self.war then return false, "the war is already on" end
	if not WS.SoldiersEnabled() then return false, "NextSoldier is switched off on this server (ns_soldiers_enabled 0)" end
	if not DrGBase then return false, "the AI war needs DrGBase (Steam Workshop) for its soldiers" end
	-- a map whose mode is none the war knows is fought freeform
	local variant = Scenario.For(RoundsModeName())
	self.baseCache = nil
	local flags, zones = self:FlagsSnapshot()
	local lacks = variant:MapLacks({
		flags = flags,
		zones = zones,
		points = self:PointsSnapshot(),
		bases = self:Bases().bases,
		waypoints = self:Waypoints(),
	})
	if lacks then return false, MAP_LACKS[lacks] end
	if not WS.NavMeshUsable() then return false, NO_NAV_MESH end
	self.scenario = variant:New()
	self.winner = nil
	self.waitingFor = nil
	self.war = AiWar.War.New()
	self.war:SetAutoSquads(GetConVar("ns_squads_auto_enabled"):GetBool())
	self.war:SetSquadsMax(GetConVar("ns_squads_max"):GetInt())
	self.war:SetSquadsMin(GetConVar("ns_squads_min"):GetInt())
	self.war:SetFireTeamSize(self.scenario.SQUAD_SIZE)
	self.paused = self:ShouldPause()
	self.gates = nil
	SetGlobal2Bool(ACTIVE_KEY, true)
	self:PublishSides()
	WS.Notify(Notices.WarStarted())
	self:OpenDoorsToSoldiers()
	self:SetForcefieldsPassable(true)
	for _, ent in ipairs(ents.GetAll()) do
		self:Consider(ent)
		self:NoteMonster(ent)
	end
	WS.Feature("gamemode"):Request(Gamemode.GAMEPLAY, Gamemode.SOURCE_AI_WAR, nil, Story())
	return true
end

-- The war's own soldiers leave; the ones players spawned stay, back under
-- the engine's AI alone.
function Controller:End()
	if not self.war then return false, "no war is on" end
	self:DisbandReserve()
	local entries = {}
	for ent, entry in pairs(self.soldiers) do entries[#entries + 1] = { ent = ent, entry = entry } end
	for _, e in ipairs(entries) do
		if IsValid(e.ent) then
			local drafted = self.war:Member(e.ent).drafted
			e.entry.soldier:Release()
			self:Discharge(e.ent)
			if drafted then e.ent:Remove() elseif self.paused then e.ent:SetAIDisabled(false) end
		end
	end
	self.soldiers = {}
	self.losers = nil
	self:SweepGadgets(nil, true)
	self.heroes = nil
	self:CloseDoorsToSoldiers()
	self:SetForcefieldsPassable(false)
	self.war = nil
	self.scenario = nil
	self.winner = nil
	SetGlobal2Bool(ACTIVE_KEY, false)
	self:PublishSides()
	WS.Notify(Notices.WarEnded())
	return true
end

-- The team the Combine fight for, for clients (the kill feed's colours:
-- foundation.aiwar's SIDES_KEY); without a war, their home.
function Controller:PublishSides()
	local combine = self.war and self.war:TeamOf(AiWar.COMBINE) or AiWar.FACTIONS[AiWar.COMBINE].home
	SetGlobal2Int(AiWar.SIDES_KEY, combine)
end

local function Repause()
	Controller:SetPaused(Controller:ShouldPause())
end

cvars.AddChangeCallback("ns_soldiers_paused", Repause, "ws_aiwar")
hook.Add("WSServerIdle", "ws_aiwar", Repause)
hook.Add("WSServerActive", "ws_aiwar", Repause)

cvars.AddChangeCallback("ns_squads_auto_enabled", function(_, _, value)
	if Controller.war then Controller.war:SetAutoSquads(value ~= "0") end
end, "ws_aiwar")

-- New bounds hold from the next squad formed; the squads already formed stay.
cvars.AddChangeCallback("ns_squads_max", function()
	if Controller.war then Controller.war:SetSquadsMax(GetConVar("ns_squads_max"):GetInt()) end
end, "ws_aiwar")

cvars.AddChangeCallback("ns_squads_min", function()
	if Controller.war then Controller.war:SetSquadsMin(GetConVar("ns_squads_min"):GetInt()) end
end, "ws_aiwar")

-- Frozen (mp_chattime at the match's end): every soldier stands still and
-- holds its fire (the bridge's NSFrozen).
hook.Add("WSFreeze", "ws_aiwar", function(on)
	for ent in pairs(Controller.soldiers) do
		if IsValid(ent) then ent.NSFrozen = on or nil end
	end
end)

-- Sudden death over: its surviving soldiers overhealed as its players are
-- (reward: max health, health -> the new health).
hook.Add("WSSuddenDeathOver", "ws_aiwar", function(reward)
	for ent in pairs(Controller.soldiers) do
		if IsValid(ent) and ent:Health() > 0 then ent:SetHealth(reward(ent:GetMaxHealth(), ent:Health())) end
	end
end)

-- The team's live soldiers, who fight sudden death out with its players.
hook.Add("WSTeamCombatants", "ws_aiwar", function(team)
	if not Controller.war then return end
	local count = 0
	for ent, entry in pairs(Controller.soldiers) do
		if entry.soldier.team == team and IsValid(ent) and ent:Health() > 0 then count = count + 1 end
	end
	return count
end)

-- The round keeps running with no human on a team while the war is on.
hook.Add("WSHaveCombatants", "ws_aiwar", function()
	if Controller.war then return true end
end)
