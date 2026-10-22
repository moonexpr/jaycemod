-- Arena (tf_logic_arena; foundation.rounds.arena) from Sandbox mode, with
-- mp_arena_override_cap_enable_time at a few seconds: gameplay starts with
-- bots on both teams; the pre-round lasts mp_arena_preround_time and ends in
-- the arena round (STALEMATE) with OnArenaRoundStart; BLU bots on the point
-- cannot take it before the cap-enable time; OnCapEnabled fires once as it
-- passes (arena_well's shows cap_flag) and BLU's capture wins. The next
-- round, a dead RED bot stays dead and killing the last RED hands BLU the
-- round by elimination. The third, timed by mp_arena_round_time, ends in a
-- stalemate with both teams alive.
local Tests = WS_TESTS
local Gamemode = WS.require("games.system.gamemode")
local Rounds = WS.require("games.gameplay.rounds")
local S = WS.STATE
local RED, BLUE = WS.TEAM_RED, WS.TEAM_BLUE
local TEAM_SIZE = 2
local CAP_ENABLE = 15 -- mp_arena_override_cap_enable_time for the check
local GAMEPLAY_TIMEOUT = Gamemode.COUNTDOWN + 5
local ROUND_TIMEOUT = 40 -- from a win or Begin to the next arena round
local TOLERANCE = 0.5
local SHUT_WATCH = 6 -- seconds the bots stand on the shut point
local CAPTURE_TIMEOUT = 40
local DEAD_WATCH = 12 -- longer than any respawn wave would be
local WIN_TIMEOUT = 5
local ROUND_TIME = 8 -- mp_arena_round_time for the tie
local BONUS_TIME = 5 -- mp_bonusroundtime's least, to keep the check short

-- Times the logic's output has fired: every line of an output fires
-- together (arena_well's OnArenaRoundStart has two), so its first line's.
local function Fired(ent, name)
	for _, o in ipairs(WS.KeyValues(ent).outputs) do
		if o.name == name then return o.fired end
	end
	return 0
end

local function Reason() return GetGlobal2Int("ws_round_win_reason", Rounds.WINREASON.NONE) end

return function(t)
	local rounds, capture, gamemode, arena = t:Feature("rounds"), t:Feature("capture"), t:Feature("gamemode"), t:Feature("arena")
	if not (rounds and capture and gamemode and arena) then return t:Skip("arena, rounds, capture or gamemode not loaded") end
	t:Check("the round is arena's", rounds:Mode().NAME == "arena", rounds:Mode().NAME)
	t:Check("tf_logic_arena is bound", IsValid(arena.logicEnt), tostring(arena.logicEnt))
	t:Info("cap_enable_delay", arena.logic and arena.logic.capEnableDelay)
	RunConsoleCommand("mp_arena_override_cap_enable_time", tostring(CAP_ENABLE))
	local bonusBefore = GetConVar("mp_bonusroundtime"):GetString()
	RunConsoleCommand("mp_bonusroundtime", tostring(BONUS_TIME))

	local bots = t:Bots(TEAM_SIZE * 2)
	if gamemode.mode:Mode() ~= Gamemode.GAMEPLAY then
		RunConsoleCommand("sv_gameplay_enabled", "1")
		t:WaitFor(GAMEPLAY_TIMEOUT, function() return gamemode.mode:Mode() == Gamemode.GAMEPLAY end)
	end
	t:Check("gameplay runs", not WS.GameplayStopped(), tostring(WS.GameplayStopped()))
	local red, blue = { bots[1], bots[2] }, { bots[3], bots[4] }
	t:Join(red, RED)
	t:Join(blue, BLUE)

	local pre = t:WaitFor(ROUND_TIMEOUT, function() return WS.State() == S.PREROUND end)
	t:Check("a pre-round", pre ~= nil, Tests.StateName(WS.State()))
	local preEnd = GetGlobal2Float("ws_preround_end_time", 0)
	local preLeft = preEnd - CurTime()
	local preroundTime = GetConVar("mp_arena_preround_time"):GetInt()
	t:Check("the pre-round lasts mp_arena_preround_time", preLeft <= preroundTime + TOLERANCE and preLeft > preroundTime - 3,
		string.format("%.1f s left of %d", preLeft, preroundTime))

	local fought = t:WaitFor(preroundTime + 5, function() return WS.State() == S.STALEMATE end)
	local startedAt = CurTime()
	t:Check("the pre-round ends in the arena round (STALEMATE)", fought ~= nil, Tests.StateName(WS.State()))
	t:Check("it ends on time", math.abs(startedAt - preEnd) < 1, string.format("%.1f s after the pre-round's end", startedAt - preEnd))
	local logic = arena.logicEnt
	t:Check("OnArenaRoundStart fired once", Fired(logic, "OnArenaRoundStart") == 1, Fired(logic, "OnArenaRoundStart") .. " times")
	local enableAt = rounds:CapEnableTime()
	t:Check("the cap-enable time is the override's", enableAt ~= nil and math.abs(enableAt - startedAt - CAP_ENABLE) < 1,
		string.format("%.1f s after the start", (enableAt or 0) - startedAt))
	t:Check("the point is shut", not rounds:PointsMayBeCaptured(), tostring(rounds:PointsMayBeCaptured()))

	local point = capture:Points()[1]
	local area = Tests.PointArea(capture, point)
	local owner = capture:Owner(point)
	t:Station(blue, function() return Tests.AreaSpots(area, #blue) end)
	t:Wait(SHUT_WATCH)
	t:Check("BLU on the shut point takes nothing", capture:Owner(point) == owner and WS.State() == S.STALEMATE,
		string.format("owner %d, %s", capture:Owner(point), Tests.StateName(WS.State())))
	t:Check("OnCapEnabled has not fired", Fired(logic, "OnCapEnabled") == 0, Fired(logic, "OnCapEnabled") .. " times")

	local enabled = t:WaitFor(CAP_ENABLE + 2, function() return Fired(logic, "OnCapEnabled") > 0 end)
	t:Check("OnCapEnabled fires at the cap-enable time", enabled ~= nil and math.abs(CurTime() - enableAt) < 1,
		string.format("%.1f s after it", CurTime() - enableAt))
	local flag = ents.FindByName("cap_flag")[1]
	if IsValid(flag) then t:Check("the map's OnCapEnabled shows cap_flag", not flag:IsEffectActive(EF_NODRAW), "nodraw " .. tostring(flag:IsEffectActive(EF_NODRAW))) end
	local won = t:WaitFor(CAPTURE_TIMEOUT, function() return WS.State() == S.TEAM_WIN end)
	t:Check("BLU's capture wins the round", won ~= nil and Tests.Winner() == BLUE and Reason() == Rounds.WINREASON.ALL_POINTS_CAPTURED,
		string.format("%s, winner %d, reason %d", Tests.StateName(WS.State()), Tests.Winner(), Reason()))
	t:Check("OnCapEnabled fired once", Fired(logic, "OnCapEnabled") == 1, Fired(logic, "OnCapEnabled") .. " times")
	t:Unstation()

	local again = t:WaitFor(ROUND_TIMEOUT, function() return WS.State() == S.STALEMATE end)
	t:Check("the next arena round", again ~= nil, Tests.StateName(WS.State()))
	-- RED as it is now: a win may have moved players between the teams
	local alive = {}
	for _, bot in ipairs(bots) do
		if bot:Team() == RED and bot:Alive() then alive[#alive + 1] = bot end
	end
	t:Check("both RED bots fight it", #alive == TEAM_SIZE, #alive .. " alive")
	if #alive < TEAM_SIZE then return end
	alive[1]:Kill()
	t:Wait(DEAD_WATCH)
	t:Check("a dead RED bot stays dead", not alive[1]:Alive() and WS.State() == S.STALEMATE,
		string.format("alive %s, %s", tostring(alive[1]:Alive()), Tests.StateName(WS.State())))
	alive[2]:Kill()
	local eliminated = t:WaitFor(WIN_TIMEOUT, function() return WS.State() == S.TEAM_WIN end)
	t:Check("killing the last RED hands BLU the round", eliminated ~= nil and Tests.Winner() == BLUE and Reason() == Rounds.WINREASON.OPPONENTS_DEAD,
		string.format("%s, winner %d, reason %d", Tests.StateName(WS.State()), Tests.Winner(), Reason()))

	-- A tie: mp_arena_round_time runs out with both teams alive.
	RunConsoleCommand("mp_arena_round_time", tostring(ROUND_TIME))
	local timed = t:WaitFor(ROUND_TIMEOUT, function() return WS.State() == S.STALEMATE end)
	t:Check("a timed arena round", timed ~= nil, Tests.StateName(WS.State()))
	local tied = t:WaitFor(ROUND_TIME + 3, function() return WS.State() == S.TEAM_WIN end)
	t:Check("its timer out with both teams alive is a stalemate", tied ~= nil and Tests.Winner() == WS.TEAM_UNASSIGNED
		and Reason() == Rounds.WINREASON.STALEMATE,
		string.format("%s, winner %d, reason %d", Tests.StateName(WS.State()), Tests.Winner(), Reason()))

	RunConsoleCommand("mp_arena_round_time", "0")
	RunConsoleCommand("mp_arena_override_cap_enable_time", "-1")
	RunConsoleCommand("mp_bonusroundtime", bonusBefore)
end
