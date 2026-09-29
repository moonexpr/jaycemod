-- foundation.aiwar: who fights for whom, what each soldier is for, when
-- reinforcements come, and what the round state allows; and
-- foundation.aiwar.track, the cart's path as geometry.
local T = dofile("tests/harness.lua")
local AiWar = T.require("foundation.aiwar")
local Track = T.require("foundation.aiwar.track")
local Teams = T.require("foundation.teams")
local STATE = T.require("foundation.rounds.state")

local RED, BLUE = Teams.RED, Teams.BLUE

local function Roles(war, team)
	local list = {}
	for _, member in ipairs(war:Members()) do
		if member.team == team then list[#list + 1] = member.role .. member.slot end
	end
	return table.concat(list, " ")
end

-- Factions ---------------------------------------------------------------

T.test("the Combine fight for RED and the Resistance for BLU", function()
	T.eq(AiWar.FactionTeam("npc_combine_s"), RED, "soldier")
	T.eq(AiWar.FactionTeam("npc_metropolice"), RED, "civil protection")
	T.eq(AiWar.FactionTeam("npc_hunter"), RED, "hunter")
	T.eq(AiWar.FactionTeam("npc_citizen"), BLUE, "rebel")
	T.eq(AiWar.FactionTeam("npc_alyx"), BLUE, "Alyx")
	T.eq(AiWar.FactionTeam("npc_vortigaunt"), BLUE, "vortigaunt")
	T.eq(AiWar.FactionTeam("npc_zombie"), nil, "no side")
	T.eq(AiWar.FactionTeam("npc_manhack"), nil, "fliers take no orders")
end)

T.test("each recruit of a faction is one of its members", function()
	for team, faction in pairs(AiWar.FACTIONS) do
		T.eq(faction.team, team, faction.name .. " team")
		for i, recruit in ipairs(faction.recruits) do
			T.eq(AiWar.FactionTeam(recruit.class), team, faction.name .. " recruit " .. i)
			T.eq(type(recruit.weapon), "string", faction.name .. " recruit " .. i .. " weapon")
		end
	end
end)

T.test("drafts cycle through the recruits and fill squads of SQUAD_SIZE", function()
	local war = AiWar.War.New()
	local recruits = AiWar.FACTIONS[RED].recruits
	local first = war:Draft(RED)
	T.eq(first.recruit, recruits[1], "first recruit")
	for _ = 2, #recruits do war:Draft(RED) end
	T.eq(war:Draft(RED).recruit, recruits[1], "the cycle restarts")
	for _ = #recruits + 2, AiWar.SQUAD_SIZE do war:Draft(RED) end
	local next = war:Draft(RED)
	T.eq(first.squad ~= next.squad, true, "a new squad after SQUAD_SIZE")
	T.eq(war:Draft(BLUE).squad ~= first.squad, true, "teams never share a squad")
end)

-- Roles --------------------------------------------------------------------

T.test("the pushing team splits between pushing and escorting the cart", function()
	local war = AiWar.War.New()
	war:Assign({ [BLUE] = true })
	for i = 1, 4 do war:Enlist("b" .. i, BLUE, true) end
	T.eq(Roles(war, BLUE), "push0 escort0 push1 escort1", "alternating")
end)

T.test("the defending team mostly holds the track ahead and sends some to block the cart", function()
	local war = AiWar.War.New()
	war:Assign({ [BLUE] = true })
	for i = 1, 5 do war:Enlist("r" .. i, RED, true) end
	T.eq(Roles(war, RED), "defend0 block0 defend1 defend2 defend3", "7 to 3, ties to the first role")
end)

T.test("on a race map each side pushes its cart, blocks the other and escorts", function()
	local war = AiWar.War.New()
	war:Assign({ [BLUE] = true, [RED] = true })
	for i = 1, 3 do war:Enlist("r" .. i, RED, true) end
	T.eq(Roles(war, RED), "push0 block0 escort0", "one of each")
end)

T.test("without a cart nobody has a role", function()
	local war = AiWar.War.New()
	war:Assign({})
	T.eq(war:Enlist("x", RED, true).role, nil, "no role")
end)

T.test("a freed slot is taken by the next soldier of that role", function()
	local war = AiWar.War.New()
	war:Assign({ [BLUE] = true })
	for i = 1, 4 do war:Enlist("b" .. i, BLUE, true) end
	war:Discharge("b1")
	local member = war:Enlist("b5", BLUE, false)
	T.eq(member.role .. member.slot, "push0", "push0 again")
end)

T.test("a change of stance reassigns the team's roles, oldest first", function()
	local war = AiWar.War.New()
	war:Assign({ [BLUE] = true })
	for i = 1, 3 do war:Enlist("r" .. i, RED, true) end
	war:Assign({ [BLUE] = true, [RED] = true })
	T.eq(Roles(war, RED), "push0 block0 escort0", "race roles")
	war:Assign({ [BLUE] = true, [RED] = true })
	T.eq(Roles(war, RED), "push0 block0 escort0", "unchanged stance keeps them")
end)

-- Reinforcements ---------------------------------------------------------------

local function WaveOf(seconds)
	return function() return seconds end
end

T.test("the first wave fills both teams at once", function()
	local war = AiWar.War.New()
	local wave = war:Reinforcements(0, 6, WaveOf(10))
	T.eq(wave[RED], 6, "RED")
	T.eq(wave[BLUE], 6, "BLU")
end)

T.test("the dead come back only with the team's next wave", function()
	local war = AiWar.War.New()
	war:Reinforcements(0, 2, WaveOf(10))
	war:Enlist("r1", RED, true)
	war:Enlist("r2", RED, true)
	war:Discharge("r1")
	T.eq(war:Reinforcements(5, 2, WaveOf(10))[RED], nil, "mid-wave")
	T.eq(war:Reinforcements(10, 2, WaveOf(10))[RED], 1, "at the wave")
end)

T.test("soldiers the player adds do not count against the team's size", function()
	local war = AiWar.War.New()
	war:Enlist("mine", RED, false)
	T.eq(war:Reinforcements(0, 2, WaveOf(10))[RED], 2, "still two drafted")
end)

T.test("with no wave time the dead come back at once, and a reset starts the waves over", function()
	local war = AiWar.War.New()
	war:Reinforcements(0, 1, WaveOf(0))
	T.eq(war:Reinforcements(0.1, 1, WaveOf(0))[RED], 1, "at once")
	war:Reinforcements(1, 1, WaveOf(30))
	T.eq(war:Reinforcements(2, 1, WaveOf(30))[RED], nil, "waiting")
	war:ResetWaves()
	T.eq(war:Reinforcements(2, 1, WaveOf(30))[RED], 1, "reset")
end)

-- Phases -------------------------------------------------------------------------

T.test("the round state decides whether soldiers reinforce and take orders", function()
	local function Phase(active, state) return AiWar.PhaseOf(active, state).name end
	T.eq(Phase(false, STATE.INIT), "running", "a map without gamerules")
	T.eq(Phase(true, STATE.PREGAME), "waiting", "pregame")
	T.eq(Phase(true, STATE.PREROUND), "frozen", "pre-round")
	T.eq(Phase(true, STATE.RND_RUNNING), "running", "running")
	T.eq(Phase(true, STATE.STALEMATE), "suddenDeath", "sudden death")
	T.eq(Phase(true, STATE.TEAM_WIN), "over", "won")
	local frozen, running = AiWar.PhaseOf(true, STATE.PREROUND), AiWar.PhaseOf(true, STATE.RND_RUNNING)
	T.eq(frozen.reinforce and not frozen.orders, true, "the frozen reinforce but stand")
	T.eq(running.reinforce and running.orders, true, "the running do both")
	local sudden = AiWar.PhaseOf(true, STATE.STALEMATE)
	T.eq(sudden.orders and not sudden.reinforce, true, "no respawns in sudden death")
end)

-- Track -------------------------------------------------------------------------

local function P(x, y, z) return { x = x, y = y, z = z or 0 } end

T.test("a track measures along its points and clamps to its ends", function()
	local track = Track.New({ P(0, 0), P(100, 0), P(100, 50) })
	T.eq(track:Length(), 150, "length")
	local mid = track:PointAt(125)
	T.eq(mid.x .. "," .. mid.y, "100,25", "on the second leg")
	local before, after = track:PointAt(-10), track:PointAt(999)
	T.eq(before.x .. "," .. before.y, "0,0", "clamped to the start")
	T.eq(after.x .. "," .. after.y, "100,50", "clamped to the end")
end)

T.test("an offset goes sideways from the direction of travel, left positive", function()
	local track = Track.New({ P(0, 0), P(100, 0) })
	local left = track:Offset(50, 20)
	T.eq(left.x .. "," .. left.y, "50,20", "left of +x is +y")
	local right = track:Offset(50, -20)
	T.eq(right.x .. "," .. right.y, "50,-20", "right")
end)

T.test("a track of one point is that point everywhere", function()
	local track = Track.New({ P(5, 6, 7) })
	T.eq(track:Length(), 0, "no length")
	local p = track:Offset(100, 30)
	T.eq(p.x .. "," .. p.y .. "," .. p.z, "5,6,7", "the point")
end)

T.test("a point projects onto the track as the distance along it of its nearest point", function()
	local track = Track.New({ P(0, 0), P(100, 0), P(100, 100) })
	T.near(track:DistanceOf(P(40, 30)), 40, 1e-9, "beside the first leg")
	T.near(track:DistanceOf(P(130, 60)), 160, 1e-9, "beside the second leg")
	T.near(track:DistanceOf(P(-50, 0)), 0, 1e-9, "before the start")
	T.near(track:DistanceOf(P(100, 500)), 200, 1e-9, "past the end")
end)

T.finish()
