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
	T.eq(AiWar.FactionTeam("wetsand_drg_combine"), RED, "Combine soldier")
	T.eq(AiWar.FactionTeam("wetsand_drg_rebel"), BLUE, "Resistance fighter")
	T.eq(AiWar.FactionTeam("npc_combine_s"), nil, "HL2's own NPCs take no part")
	T.eq(AiWar.FactionTeam("npc_zombie"), nil, "no side")
end)

T.test("sides stand by their team and fight the other; the losers of a round fear their enemies", function()
	T.eq(AiWar.Relation(RED, RED), AiWar.ALLY, "teammates")
	T.eq(AiWar.Relation(RED, BLUE), AiWar.ENEMY_OF, "enemies")
	T.eq(AiWar.Relation(RED, Teams.UNASSIGNED), AiWar.NEUTRAL, "the unassigned")
	local losers = AiWar.LosersOf(BLUE)
	T.eq(losers, RED, "BLU won, RED lost")
	T.eq(AiWar.Relation(RED, BLUE, losers), AiWar.FEAR, "the losers fear the winners")
	T.eq(AiWar.Relation(BLUE, RED, losers), AiWar.ENEMY_OF, "the winners hunt the losers")
	T.eq(AiWar.Relation(RED, RED, losers), AiWar.ALLY, "the losers still stand together")
	T.eq(AiWar.LosersOf(Teams.UNASSIGNED), nil, "a stalemate humiliates nobody")
end)

T.test("each recruit of a faction is one of its members", function()
	for team, faction in pairs(AiWar.FACTIONS) do
		T.eq(faction.team, team, faction.name .. " team")
		for i, recruit in ipairs(faction.recruits) do
			T.eq(AiWar.FactionTeam(recruit.class), team, faction.name .. " recruit " .. i)
		end
	end
end)

T.test("drafts cycle through the recruits", function()
	local war = AiWar.War.New()
	local recruits = AiWar.FACTIONS[RED].recruits
	T.eq(war:Draft(RED).recruit, recruits[1], "first recruit")
	for _ = 2, #recruits do war:Draft(RED) end
	T.eq(war:Draft(RED).recruit, recruits[1], "the cycle restarts")
end)

-- Fire teams ---------------------------------------------------------------

T.test("soldiers of a role form fire teams of FIRE_TEAM_SIZE, each its own squad", function()
	local war = AiWar.War.New()
	war:Assign({ [BLUE] = true })
	local defenders = {}
	for i = 1, 20 do
		local member = war:Enlist("red" .. i, RED, true)
		if member.role == AiWar.DEFEND then defenders[#defenders + 1] = member end
	end
	local teams, squads = {}, {}
	for _, member in ipairs(defenders) do
		T.eq(member.fireTeam.role, AiWar.DEFEND, "a defenders' team")
		teams[member.fireTeam] = (teams[member.fireTeam] or 0) + 1
		squads[member.fireTeam.squad] = true
	end
	local count = 0
	for fireTeam, n in pairs(teams) do
		count = count + 1
		T.eq(n <= AiWar.FIRE_TEAM_SIZE, true, "no more than FIRE_TEAM_SIZE")
	end
	T.eq(count, math.ceil(#defenders / AiWar.FIRE_TEAM_SIZE), "as few teams as fit")
	local squadCount = 0
	for _ in pairs(squads) do squadCount = squadCount + 1 end
	T.eq(squadCount, count, "one squad per team")
end)

T.test("members take places 0 up in their team, and a place freed is taken again", function()
	local war = AiWar.War.New()
	war:Assign({ [BLUE] = true })
	local first = war:Enlist("a", BLUE, true)
	local fireTeam = first.fireTeam
	local mates = {}
	for i = 1, 20 do
		local member = war:Enlist("b" .. i, BLUE, true)
		if member.fireTeam == fireTeam then mates[#mates + 1] = member end
	end
	T.eq(first.place, 0, "the first place")
	T.eq(#war:FireTeamMembers(fireTeam), AiWar.FIRE_TEAM_SIZE, "full")
	local leaving = mates[1]
	local place = leaving.place
	war:Discharge(leaving.handle)
	T.eq(fireTeam.members[place], nil, "the place is free")
	local newcomer
	repeat newcomer = war:Enlist("c" .. math.random(1e9), BLUE, true) until newcomer.role == fireTeam.role
	T.eq(newcomer.fireTeam, fireTeam, "joins the open team")
	T.eq(newcomer.place, place, "in the freed place")
end)

T.test("a team emptied goes, and teams never cross sides", function()
	local war = AiWar.War.New()
	war:Assign({ [BLUE] = true })
	local red = war:Enlist("r", RED, true)
	local blue = war:Enlist("b", BLUE, true)
	T.eq(red.fireTeam ~= blue.fireTeam, true, "separate sides")
	local fireTeam = red.fireTeam
	war:Discharge("r")
	local still = false
	for _, other in ipairs(war.fireTeams) do still = still or other == fireTeam end
	T.eq(still, false, "gone once empty")
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

T.test("a cart near its checkpoint throws more of the defenders at it, fewest changed", function()
	local war = AiWar.War.New()
	war:Assign({ [BLUE] = true })
	for i = 1, 10 do war:Enlist("r" .. i, RED, true) end
	local function Count(role)
		local n = 0
		for _, member in ipairs(war:Members()) do
			if member.team == RED and member.role == role then n = n + 1 end
		end
		return n
	end
	T.eq(Count(AiWar.BLOCK), 3, "three blockers while the cart is far")
	local before = {}
	for _, member in ipairs(war:Members()) do before[member] = member.role end
	war:Assign({ [BLUE] = { close = true } })
	T.eq(Count(AiWar.BLOCK), 6, "six once it is close")
	local changed = 0
	for member, role in pairs(before) do
		if member.role ~= role then changed = changed + 1 end
		T.eq(member.fireTeam.role, member.role, "in a fire team of its new role")
	end
	T.eq(changed, 3, "only three defenders turned blocker")
	war:Assign({ [BLUE] = { close = false } })
	T.eq(Count(AiWar.BLOCK), 3, "back to three when it is pushed back")
end)

T.test("a cart is close within CLOSE_RANGE, and stays close a little past it", function()
	T.eq(AiWar.CartClose(false, AiWar.CLOSE_RANGE), true, "at the range")
	T.eq(AiWar.CartClose(false, AiWar.CLOSE_RANGE + 1), false, "past it")
	T.eq(AiWar.CartClose(true, AiWar.CLOSE_RANGE + AiWar.CLOSE_HYSTERESIS), true, "still close, once close")
	T.eq(AiWar.CartClose(true, AiWar.CLOSE_RANGE + AiWar.CLOSE_HYSTERESIS + 1), false, "far again")
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
