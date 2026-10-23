-- features.aiwar.reserve: the fallen soldiers a respawn wave revives
-- instead of spawning new ones.
local T = dofile("tests/harness.lua")
local Reserve = T.require("features.aiwar.reserve")
local Teams = gameplay.teams

local RED, BLUE = Teams.RED, Teams.BLUE
local NEXT_WAVE = 10 -- any finite wave length

T.test("only a drafted soldier, with revives on and respawn waves running, is kept", function()
	T.eq(Reserve.Keeps(true, true, NEXT_WAVE), true, "drafted, waves on")
	T.eq(Reserve.Keeps(true, true, 0), true, "a setup wave respawns at once")
	T.eq(Reserve.Keeps(false, true, NEXT_WAVE), false, "revives off")
	T.eq(Reserve.Keeps(true, false, NEXT_WAVE), false, "an admin's or a player's soldier")
	T.eq(Reserve.Keeps(true, true, math.huge), false, "respawns stopped: no wave will come")
end)

T.test("a wave revives the oldest kept body of the team and class, as a scenario", function()
	local reserve = Reserve.New()
	reserve:Keep("combine_a", RED, "ws_drg_combine")
	reserve:Keep("rebel_a", BLUE, "ws_drg_rebel")
	reserve:Keep("combine_b", RED, "ws_drg_combine")
	T.eq(reserve:Count(RED), 2, "two kept for red")
	T.eq(reserve:Take(RED, "ws_drg_combine"), "combine_a", "oldest first")
	T.eq(reserve:Take(RED, "ws_drg_combine"), "combine_b", "then the next")
	T.eq(reserve:Take(RED, "ws_drg_combine"), nil, "none left: spawn one")
	T.eq(reserve:Take(RED, "ws_drg_rebel"), nil, "another team's class is not red's")
	T.eq(reserve:Take(BLUE, "ws_drg_rebel"), "rebel_a", "blue's own")
end)

T.test("a class the wave does not draft stays kept", function()
	local reserve = Reserve.New()
	reserve:Keep("vort", BLUE, "ws_drg_vortigaunt")
	T.eq(reserve:Take(BLUE, "ws_drg_rebel"), nil, "no rebel kept")
	T.eq(reserve:Count(BLUE), 1, "the vortigaunt waits for a medic's draft")
end)

T.test("a body removed while kept is forgotten", function()
	local reserve = Reserve.New()
	reserve:Keep("gone", RED, "ws_drg_combine")
	reserve:Keep("here", RED, "ws_drg_combine")
	reserve:Forget("gone")
	T.eq(reserve:Take(RED, "ws_drg_combine"), "here", "the removed one is skipped")
	reserve:Forget("never kept")
end)

T.test("keeping a body twice keeps it once", function()
	local reserve = Reserve.New()
	reserve:Keep("twice", RED, "ws_drg_combine")
	reserve:Keep("twice", RED, "ws_drg_combine")
	T.eq(reserve:Count(RED), 1, "once")
end)

T.test("draining hands back every kept body and leaves none", function()
	local reserve = Reserve.New()
	reserve:Keep("a", RED, "ws_drg_combine")
	reserve:Keep("b", BLUE, "ws_drg_rebel")
	local drained = reserve:Drain()
	table.sort(drained)
	T.eq(table.concat(drained, ","), "a,b", "both")
	T.eq(reserve:Count(RED) + reserve:Count(BLUE), 0, "empty")
end)

T.finish()
