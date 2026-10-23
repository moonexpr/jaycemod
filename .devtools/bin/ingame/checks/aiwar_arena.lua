-- The AI war in arena (features.aiwar.scenario.arena), soldiers only, on
-- an arena map, three rounds made to end one way each:
--   tie          soldiers take no damage, the point never opens, and
--                mp_arena_round_time runs out: a stalemate
--   capture      soldiers take no damage, BLU is held where it stands and
--                the point opens after CAP_ENABLE: RED's capture wins
--   elimination  the point never opens: one side kills the other
-- Before the point opens every soldier explores in its squad, in the arena
-- phase (no hunt, no sight of every enemy); after, some go for the point.
-- The war may already be on: it starts itself on a map it can fight over
-- (ws/sh_aiwar.lua); the check then uses it, and the next round.
local Tests = WS_TESTS
local AiWar = WS.require("features.aiwar.model")
local Rounds = gameplay.rounds
local S = WS.STATE
local NEVER = 9999 -- mp_arena_override_cap_enable_time: the point stays shut
local CAP_ENABLE = 15
local TIE_TIME = 40 -- mp_arena_round_time for the tie
local BONUS_TIME = 5
local START_TIMEOUT = 60 -- the war's start, Gameplay mode's countdown and the pre-round
local ROUND_TIMEOUT = 40 -- from a win to the next arena round
local EXPLORE_WATCH = 10 -- seconds the explorers are watched moving
local MOVED = 200 -- units a squad leader must cover while exploring
local CAPTURE_TIMEOUT = 150
local ELIMINATION_TIMEOUT = 240
local GOD_TIMER = "ws_tests_aiwar_arena_god"
local GOD_HEALTH = 1000000 -- kept on every soldier while they may not die
local GOD_INTERVAL = 0.2
local PHASE_TIMEOUT = 3 -- the war's field follows the round within its think
local SPLIT_TIMEOUT = 10 -- the stance holds ALLOCATION_HOLD before it changes

local function Reason() return GetGlobal2Int("ws_round_win_reason", Rounds.WINREASON.NONE) end

local function Outcome()
	return string.format("%s, winner %d, reason %d", Tests.StateName(WS.State()), Tests.Winner(), Reason())
end

-- The war's members by job, "job:n ...".
local function Jobs(war)
	local counts, list = {}, {}
	for _, member in ipairs(war:Members()) do counts[member.role or "none"] = (counts[member.role or "none"] or 0) + 1 end
	for job, n in pairs(counts) do list[#list + 1] = job .. ":" .. n end
	table.sort(list)
	return table.concat(list, " ")
end

-- The explorer squads' leaders (medics are squads of their own).
local function Leaders(aiwar)
	local list = {}
	for ent in pairs(aiwar.soldiers) do
		local member = IsValid(ent) and aiwar.war:Member(ent)
		if member and member.role == AiWar.EXPLORE and member.fireTeam
			and nextsoldier.squad.Leader(member.fireTeam) == member then
			list[#list + 1] = ent
		end
	end
	return list
end

-- Waits for the next arena round with the convars set as given.
local function NextRound(t, timeout)
	if WS.State() == S.STALEMATE then t:WaitFor(ROUND_TIMEOUT, function() return WS.State() ~= S.STALEMATE end) end
	return t:WaitFor(timeout, function() return WS.State() == S.STALEMATE end)
end

return function(t)
	if DrGBase == nil then return t:Skip("DrGBase is not loaded (the war's soldiers)") end
	local rounds = t:Feature("rounds")
	if not (rounds and t:Loaded("arena")) then return t:Skip("not an arena map") end
	Tests.KickBots()
	local size = GetConVar("mp_aiwar_team_size"):GetInt()
	local bonusBefore = GetConVar("mp_bonusroundtime"):GetString()
	RunConsoleCommand("mp_bonusroundtime", tostring(BONUS_TIME))
	RunConsoleCommand("mp_arena_override_cap_enable_time", tostring(NEVER))
	RunConsoleCommand("mp_arena_round_time", tostring(TIE_TIME))
	local aiwar = WS.Feature("aiwar")
	-- soldiers that may not die: their health kept out of any burst's reach
	-- (an EntityTakeDamage hook may never run: an earlier one can answer);
	-- held soldiers (entity -> position) kept where they stand
	local held = {}
	timer.Create(GOD_TIMER, GOD_INTERVAL, 0, function()
		for ent in pairs(aiwar.soldiers) do
			if IsValid(ent) and ent:Health() > 0 then
				ent:SetHealth(GOD_HEALTH)
				if held[ent] then ent:SetPos(held[ent]) end
			end
		end
	end)

	-- the tie
	local startedHere = not aiwar:Active()
	if startedHere then
		local ok, why = aiwar:Start()
		t:Check("mp_aiwar_start takes the arena map", ok == true, tostring(why))
		if not ok then return end
	end
	t:Check("the war fights the arena scenario", aiwar.scenario.NAME == "arena", aiwar.scenario.NAME)
	-- the convars above apply from the next arena round: restart the one on
	rounds:RestartRound()
	local fought = NextRound(t, START_TIMEOUT + ROUND_TIMEOUT)
	t:Check("an arena round with the war's soldiers", fought ~= nil, Tests.StateName(WS.State()))
	t:WaitFor(PHASE_TIMEOUT, function() return aiwar.war:Field() and aiwar.war:Field().phase == AiWar.PHASES.arena end)
	local field = aiwar.war:Field()
	t:Check("the war is in the arena phase", field and field.phase == AiWar.PHASES.arena, field and field.phase.name or "no field")
	t:Info("waypoints", field and #field.waypoints)
	t:Wait(2)
	-- medics are a job apart (AiWar.MedicsFor)
	local medics = AiWar.MedicsFor(size) * 2
	local expected = "explore:" .. size * 2 - medics .. (medics > 0 and (" medic:" .. medics) or "")
	t:Check("everyone but the medics explores while the point is shut", Jobs(aiwar.war) == expected, Jobs(aiwar.war))
	local leaders, from = Leaders(aiwar), {}
	for _, ent in ipairs(leaders) do from[ent] = ent:GetPos() end
	t:Wait(EXPLORE_WATCH)
	local moved = 0
	for _, ent in ipairs(leaders) do
		if IsValid(ent) and ent:GetPos():Distance(from[ent]) > MOVED then moved = moved + 1 end
	end
	t:Check("the squad leaders set off exploring", #leaders > 0 and moved == #leaders, moved .. " of " .. #leaders .. " moved")
	local tied = t:WaitFor(TIE_TIME + 5, function() return WS.State() == S.TEAM_WIN end)
	t:Check("tie: the round's time out with both sides alive is a stalemate",
		tied ~= nil and Tests.Winner() == WS.TEAM_UNASSIGNED and Reason() == Rounds.WINREASON.STALEMATE, Outcome())

	-- the capture: with nobody dying, a contested point never falls, so BLU
	-- is held where it stands and RED's capturers take it unopposed
	RunConsoleCommand("mp_arena_round_time", "0")
	RunConsoleCommand("mp_arena_override_cap_enable_time", tostring(CAP_ENABLE))
	t:Check("the next arena round", NextRound(t, ROUND_TIMEOUT) ~= nil, Tests.StateName(WS.State()))
	for ent, entry in pairs(aiwar.soldiers) do
		if IsValid(ent) and entry.soldier.team == WS.TEAM_BLUE then held[ent] = ent:GetPos() end
	end
	t:WaitFor(CAP_ENABLE + 5, function() return rounds:PointsMayBeCaptured() end)
	t:WaitFor(SPLIT_TIMEOUT, function() return (Jobs(aiwar.war):find("capture", 1, true)) ~= nil end)
	t:Info("jobs_after_open", Jobs(aiwar.war))
	t:Check("once open some go for the point", (Jobs(aiwar.war):find("capture", 1, true)) ~= nil, Jobs(aiwar.war))
	local captured, took = t:WaitFor(CAPTURE_TIMEOUT, function() return WS.State() == S.TEAM_WIN end)
	t:Info("capture_seconds", took)
	t:Check("capture: RED's capturers win by the point",
		captured ~= nil and Tests.Winner() == WS.TEAM_RED and Reason() == Rounds.WINREASON.ALL_POINTS_CAPTURED, Outcome())
	held = {}

	-- the elimination
	timer.Remove(GOD_TIMER)
	for ent in pairs(aiwar.soldiers) do
		if IsValid(ent) and ent:Health() > 0 then ent:SetHealth(ent:GetMaxHealth()) end
	end
	RunConsoleCommand("mp_arena_override_cap_enable_time", tostring(NEVER))
	t:Check("the last arena round", NextRound(t, ROUND_TIMEOUT) ~= nil, Tests.StateName(WS.State()))
	local eliminated, fightTook = t:WaitFor(ELIMINATION_TIMEOUT, function() return WS.State() == S.TEAM_WIN end)
	t:Info("elimination_seconds", fightTook)
	t:Check("elimination: one side kills the other",
		eliminated ~= nil and Tests.Winner() ~= WS.TEAM_UNASSIGNED and Reason() == Rounds.WINREASON.OPPONENTS_DEAD, Outcome())

	if startedHere then aiwar:End() end
	RunConsoleCommand("mp_arena_override_cap_enable_time", "-1")
	RunConsoleCommand("mp_arena_round_time", "0")
	RunConsoleCommand("mp_bonusroundtime", bonusBefore)
end
