-- foundation.aiwar: who fights for whom, what each soldier is for, when
-- reinforcements come, and what the round state allows; and
-- foundation.aiwar.track, the cart's path as geometry.
local T = dofile("tests/harness.lua")
local AiWar = T.require("foundation.aiwar")
local Squad = T.require("foundation.aiwar.squad")
local Track = T.require("foundation.core.structs.polyline")
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

T.test("the Combine's home is BLU and the Resistance's RED", function()
	T.eq(AiWar.FactionTeam("ws_drg_combine"), BLUE, "Combine soldier")
	T.eq(AiWar.FactionTeam("ws_drg_rebel"), RED, "Resistance fighter")
	T.eq(AiWar.FactionOf("ws_drg_vortigaunt").id, AiWar.RESISTANCE, "a vortigaunt is the Resistance's")
	T.eq(AiWar.HomeFaction(BLUE).id, AiWar.COMBINE, "BLU's home faction")
	T.eq(AiWar.HomeFaction(Teams.UNASSIGNED), nil, "nobody's home")
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
	for id, faction in pairs(AiWar.FACTIONS) do
		T.eq(faction.id, id, faction.name .. " id")
		for i, recruit in ipairs(faction.recruits) do
			T.eq(AiWar.FactionTeam(recruit.class), faction.home, faction.name .. " recruit " .. i)
		end
	end
end)

T.test("drafts cycle through the recruits", function()
	local war = AiWar.War.New()
	local recruits = AiWar.HomeFaction(RED).recruits
	T.eq(war:Draft(RED).recruit, recruits[1], "first recruit")
	for _ = 2, #recruits do war:Draft(RED) end
	T.eq(war:Draft(RED).recruit, recruits[1], "the cycle restarts")
end)

T.test("a war starts each faction on its home and swaps them: the Combine fight for RED, the Resistance for BLU", function()
	local war = AiWar.War.New()
	T.eq(war:Faction(BLUE).name, "Combine", "the Combine start on BLU")
	T.eq(war:FactionTeam("ws_drg_combine"), BLUE)
	T.eq(war:TeamOf(AiWar.COMBINE), BLUE, "the Combine's team")
	war:SwapFactions()
	T.eq(war:Faction(BLUE).name, "Resistance", "the Resistance on BLU")
	T.eq(war:Faction(RED).name, "Combine", "the Combine on RED")
	T.eq(war:TeamOf(AiWar.COMBINE), RED, "the Combine's team now")
	T.eq(war:FactionTeam("ws_drg_combine"), RED, "a Combine soldier joins RED")
	T.eq(war:FactionTeam("ws_drg_vortigaunt"), BLUE, "a vortigaunt joins BLU")
	T.eq(war:FactionTeam("npc_zombie"), nil, "no side")
	T.eq(war:Draft(RED).recruit.class, "ws_drg_combine", "RED drafts the Combine")
	war:SwapFactions()
	T.eq(war:Faction(BLUE).name, "Combine", "and back")
end)

T.test("clients read every faction's team from the Combine's", function()
	local sides = AiWar.Sides(RED)
	T.eq(sides[AiWar.COMBINE], RED, "the Combine")
	T.eq(sides[AiWar.RESISTANCE], BLUE, "the Resistance, their enemy")
end)

T.test("a defender's win: held to the time limit, or won without a cart against one", function()
	local CART = {}
	T.eq(AiWar.DefenderWon(RED, true, {}), true, "held until the time limit")
	T.eq(AiWar.DefenderWon(RED, false, { [BLUE] = CART }), true, "payload: the side without the cart")
	T.eq(AiWar.DefenderWon(BLUE, false, { [BLUE] = CART }), false, "the attackers pushed it home")
	T.eq(AiWar.DefenderWon(RED, false, { [RED] = CART, [BLUE] = CART }), false, "a race has no defenders")
	T.eq(AiWar.DefenderWon(RED, false, {}), false, "a symmetric map")
	T.eq(AiWar.DefenderWon(Teams.UNASSIGNED, true, {}), false, "a stalemate")
end)

-- Fire teams ---------------------------------------------------------------

-- The fire team mechanics, with as many squads as the soldiers fill
-- (AiWar.SQUADS_MAX_DEFAULT and SQUADS_MIN_DEFAULT aside).
local function UncappedWar()
	local war = AiWar.War.New()
	war:SetSquadsMax(math.huge)
	war:SetSquadsMin(1)
	return war
end

T.test("soldiers of a role form fire teams of FIRE_TEAM_SIZE, each its own squad", function()
	local war = UncappedWar()
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

-- For now (operator, 2026-10-10) the war gives only the roles that work the
-- objective, and exploring: no raiders, assault squads, support or escorts.
T.test("the war gives only the objective's roles: no raid, assault, support or escort", function()
	for role in pairs({ [AiWar.RAID] = true, [AiWar.ASSAULT] = true, [AiWar.SUPPORT] = true, [AiWar.ESCORT] = true }) do
		T.eq(AiWar.OFF_ROLES[role], true, role .. " off")
	end
	for _, role in ipairs({ AiWar.CAPTURE, AiWar.HOLD, AiWar.DEFEND, AiWar.PUSH, AiWar.BLOCK, AiWar.EXPLORE }) do
		T.eq(AiWar.OFF_ROLES[role], nil, role .. " on")
	end
	local war = AiWar.War.New()
	local stance = {
		{ role = AiWar.CAPTURE, weight = 4 },
		{ role = AiWar.ASSAULT, weight = 3 },
		{ role = AiWar.RAID, weight = 2 },
		{ role = AiWar.SUPPORT, weight = 1 },
	}
	war:AssignStances({ [RED] = stance }, { [RED] = 0 })
	for i = 1, 10 do
		local member = war:Enlist("red" .. i, RED, true)
		T.eq(member.role, AiWar.CAPTURE, member.handle .. " captures")
	end
	local applied = war.stances[RED]
	war:AssignStances({ [RED] = stance }, { [RED] = 0 })
	T.eq(war.stances[RED], applied, "the same stance again is the same table: no rebalance")
end)

-- ns_squads_max: fewer, bigger squads, so fewer soldiers wander off alone.
T.test("a team forms at most its squads' max; past it a soldier joins its role's smallest squad, or goes solo", function()
	T.eq(AiWar.SQUADS_MAX_DEFAULT, 3, "three by default")
	local war = AiWar.War.New()
	war:SetSquadsMin(1)
	war:SetSquadsMax(2)
	war:AssignStances({ [RED] = { { role = AiWar.CAPTURE, weight = 1 } } }, { [RED] = 0 })
	for i = 1, 12 do war:Enlist("red" .. i, RED, true) end
	local squads, sizes = {}, {}
	for _, member in ipairs(war:Members()) do
		T.eq(member.fireTeam ~= nil, true, member.handle .. " in a squad")
		squads[member.fireTeam] = true
	end
	local count = 0
	for fireTeam in pairs(squads) do
		count = count + 1
		local n = 0
		for _ in pairs(fireTeam.members) do n = n + 1 end
		sizes[#sizes + 1] = n
	end
	T.eq(count, 2, "two squads")
	table.sort(sizes)
	T.eq(sizes[1] + sizes[2], 12, "everyone in them")
	T.eq(sizes[2] - sizes[1] <= 1, true, "the overflow spread evenly")
	-- a role with no squad once the cap is reached fights solo
	local blue = AiWar.War.New()
	blue:SetSquadsMin(1)
	blue:SetSquadsMax(1)
	blue:AssignStances({ [BLUE] = { { role = AiWar.CAPTURE, weight = 1 }, { role = AiWar.DEFEND, weight = 1 } } }, { [BLUE] = 0 })
	local first, second = blue:Enlist("b1", BLUE, true), blue:Enlist("b2", BLUE, true)
	T.eq(first.fireTeam ~= nil, true, "the first squad")
	T.eq(second.role ~= first.role, true, "another role")
	T.eq(second.fireTeam, nil, "no squad left for it: solo")
end)

-- ns_squads_min: a team splits into at least that many squads, so its
-- explorers come at the map from more than one place.
T.test("a team forms at least its squads' min, and its soldiers join their role's smallest open squad", function()
	T.eq(AiWar.SQUADS_MIN_DEFAULT, 3, "three by default")
	local war = AiWar.War.New()
	war:SetFireTeamSize(8)
	war:SetSquadsMin(3)
	war:SetSquadsMax(3)
	war:AssignStances({ [BLUE] = { { role = AiWar.EXPLORE, weight = 1 } } }, { [BLUE] = 0 })
	war:Enlist("medic", BLUE, true, AiWar.MEDIC)
	for i = 1, 7 do war:Enlist("blue" .. i, BLUE, true) end
	local sizes = {}
	for _, fireTeam in ipairs(war.fireTeams) do
		if fireTeam.role == AiWar.EXPLORE then
			local n = 0
			for _ in pairs(fireTeam.members) do n = n + 1 end
			sizes[#sizes + 1] = n
		end
	end
	T.eq(#war.fireTeams, 3, "three squads")
	T.eq(#sizes, 2, "two of explorers, the medics' the third")
	table.sort(sizes)
	T.eq(sizes[1] .. "+" .. sizes[2], "3+4", "split evenly")
end)

-- The squad investigates a member's death: it goes for its killer, so it
-- engages the enemy rather than walking on.
T.test("a member that falls leaves its squad investigating: its killer's place, else where it fell", function()
	local Tactics = T.require("foundation.wartactics")
	local war = UncappedWar()
	war:Assign({ [BLUE] = true })
	for i = 1, 4 do war:Enlist("red" .. i, RED, true) end
	local fallen = war:Member("red1")
	local fireTeam = fallen.fireTeam
	war:Fallen("red1", { x = 100, y = 0, z = 0 }, { x = 400, y = 50, z = 0 }, 20)
	war:Discharge("red1")
	T.eq(Tactics.Contact(fireTeam, 20).pos.x, 400, "its killer")
	for i = 1, 4 do war:Enlist("blue" .. i, BLUE, true) end
	local other = war:Member("blue1").fireTeam
	war:Fallen("blue1", { x = -100, y = 0, z = 0 }, nil, 20)
	T.eq(Tactics.Contact(other, 20).pos.x, -100, "no killer known: where it fell")
	local alone = war:Enlist("solo", RED, true)
	alone.fireTeam = nil
	war:Fallen("solo", { x = 0, y = 0, z = 0 }, nil, 20)
	T.eq(war:Member("solo") ~= nil, true, "a soldier without a squad tells nobody")
end)

T.test("members take places 0 up in their team, and a place freed is taken again", function()
	local war = UncappedWar()
	war:AssignStances({ [RED] = { { role = AiWar.DEFEND, weight = 1 } } }, { [RED] = 0 })
	local first = war:Enlist("a", RED, true)
	local fireTeam = first.fireTeam
	local mates = {}
	for i = 1, AiWar.FIRE_TEAM_SIZE - 1 do mates[i] = war:Enlist("b" .. i, RED, true) end
	T.eq(first.place, 0, "the first place")
	T.eq(#war:FireTeamMembers(fireTeam), AiWar.FIRE_TEAM_SIZE, "full")
	local leaving = mates[1]
	local place = leaving.place
	war:Discharge(leaving.handle)
	T.eq(fireTeam.members[place], nil, "the place is free")
	local newcomer = war:Enlist("c", RED, true)
	T.eq(newcomer.fireTeam, fireTeam, "joins the open team")
	T.eq(newcomer.place, place, "in the freed place")
end)

T.test("a team emptied goes, and teams never cross sides", function()
	local war = UncappedWar()
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

-- Squads by hand (ns_squads_*) -------------------------------------------------

-- A war with n BLU soldiers enlisted, attacking a cart.
local function Enlisted(n, war)
	war = war or AiWar.War.New()
	war:Assign({ [BLUE] = true })
	local members = {}
	for i = 1, n do members[i] = war:Enlist("b" .. i, BLUE, true) end
	return war, members
end

local function InAnySquad(members)
	for _, member in ipairs(members) do
		if member.fireTeam then return true end
	end
	return false
end

T.test("with automatic squads off, soldiers stay out of squads, and turning them on groups them", function()
	local war = UncappedWar()
	war:SetAutoSquads(false)
	local _, members = Enlisted(6, war)
	T.eq(InAnySquad(members), false, "nobody grouped")
	T.eq(members[1].role ~= nil, true, "still given jobs")
	war:SetAutoSquads(true)
	for _, member in ipairs(members) do T.eq(member.fireTeam ~= nil, true, member.handle .. " grouped") end
end)

T.test("dissolving puts everyone out of their squads; with automatic squads on they regroup at once", function()
	local war, members = Enlisted(6)
	war:SetAutoSquads(false)
	war:DissolveSquads()
	T.eq(InAnySquad(members), false, "all solo")
	T.eq(#war.fireTeams, 0, "no fire teams left")
	war:SetAutoSquads(true)
	war:DissolveSquads()
	T.eq(members[1].fireTeam ~= nil, true, "regrouped")
end)

T.test("a squad formed by hand is led by the soldier it was formed for, and grows past FIRE_TEAM_SIZE", function()
	local war, members = Enlisted(10)
	war:SetAutoSquads(false)
	war:DissolveSquads()
	local leader = members[10]
	local squad = war:FormSquad(leader)
	T.eq(squad.manual, true, "by hand")
	T.eq(Squad.Leader(squad), leader, "led by its founder, the newest")
	for i = 1, 9 do T.eq(war:JoinSquad(members[i], squad), true, "joined " .. i) end
	T.eq(#war:FireTeamMembers(squad), 10, "ten in one squad")
	T.eq(Squad.Leader(squad), leader, "still its founder, over the longest serving")
	for i = 1, 9 do
		T.eq(members[i].role, leader.role, "the leader's job")
		T.eq(Squad.Kind(members[i]), "member", "follows")
	end
	local places = {}
	for _, member in ipairs(war:FireTeamMembers(squad)) do places[#places + 1] = member.place end
	T.eq(table.concat(places, " "), "0 1 2 3 4 5 6 7 8 9", "places in order")
end)

T.test("the war leaves a squad by hand alone: no rebalance or new stance moves its soldiers", function()
	local war, members = Enlisted(8)
	local leader = members[1]
	local squad = war:FormSquad(leader)
	for i = 2, 8 do war:JoinSquad(members[i], squad) end
	local role = leader.role
	war:Assign({ [BLUE] = { progress = 0.9 } })
	war:Assign({})
	for _, member in ipairs(members) do
		T.eq(member.fireTeam, squad, member.handle .. " still in it")
		T.eq(member.role, role, member.handle .. " still on its job")
	end
	local newcomer = war:Enlist("new", BLUE, true)
	T.eq(newcomer.fireTeam ~= squad, true, "the war's own squads never fill it")
end)

-- Attach: a soldier the war seats in another's squad (MvM's medic with the
-- bomb's carrier) keeps its own job, never leads it, and leaves the squad
-- the war's own; Detach puts it back.
T.test("an attached soldier joins its host's squad beside its job, never leads it, and goes back when detached", function()
	local Squad = T.require("foundation.aiwar.squad")
	local war, members = Enlisted(4)
	local medic, host = members[1], members[4]
	local job = medic.role
	local squad = war:Attach(medic, host)
	T.eq(squad, host.fireTeam, "the host's squad")
	T.eq(medic.fireTeam, host.fireTeam, "seated in it")
	T.eq(medic.role, job, "its own job kept")
	T.eq(squad.manual ~= true, true, "still the war's")
	T.eq(Squad.Leader(squad) ~= medic, true, "the oldest soldier, attached, does not lead")
	T.eq(war:Attach(medic, host), squad, "attaching again changes nothing")
	war:Detach(medic)
	T.eq(medic.attached, nil, "detached")
	T.eq(medic.fireTeam ~= nil, true, "regrouped with automatic squads on")
	war:SetAutoSquads(false)
	war:DissolveSquads()
	local own = war:Attach(medic, host)
	T.eq(own ~= nil and host.fireTeam == own and medic.fireTeam == own, true, "a solo host gets a squad of its own")
	T.eq(Squad.Leader(own), host, "which it leads")
	war:Detach(medic)
	T.eq(medic.fireTeam, nil, "solo again with automatic squads off")
end)

T.test("joining an automatic squad makes it a squad by hand; one soldier can't join the other side's", function()
	local war, members = Enlisted(3)
	local red = war:Enlist("red", RED, true)
	local squad = members[1].fireTeam
	T.eq(war:JoinSquad(red, squad), false, "not across sides")
	T.eq(war:JoinSquad(members[3], squad), true, "joined")
	T.eq(squad.manual, true, "now by hand")
end)

T.test("leaving a squad by hand leaves its soldier solo, or regrouped with automatic squads on; an empty squad goes", function()
	local war, members = Enlisted(2)
	war:SetAutoSquads(false)
	war:DissolveSquads()
	local squad = war:FormSquad(members[1])
	war:JoinSquad(members[2], squad)
	war:LeaveSquad(members[2])
	T.eq(members[2].fireTeam, nil, "solo")
	war:SetAutoSquads(true)
	war:LeaveSquad(members[1])
	T.eq(members[1].fireTeam ~= nil and members[1].fireTeam ~= squad, true, "back in the war's squads")
	local still = false
	for _, other in ipairs(war.fireTeams) do still = still or other == squad end
	T.eq(still, false, "the empty squad is gone")
end)

-- Jobs by hand (ns_soldiers_job) ----------------------------------------------------

T.test("a soldier given a job by hand keeps it: no rebalance or new stance moves it", function()
	local war, members = Enlisted(4)
	local member = members[1]
	war:SetRole(member, AiWar.RAID)
	T.eq(member.role, AiWar.RAID, "raids")
	T.eq(member.fireTeam.role, AiWar.RAID, "in a raiders' squad")
	war:Assign({ [BLUE] = { progress = 0.9 } })
	war:Assign({})
	T.eq(member.role, AiWar.RAID, "kept")
end)

T.test("a job given to a soldier in a squad by hand is the whole squad's", function()
	local war, members = Enlisted(3)
	local squad = war:FormSquad(members[1])
	war:JoinSquad(members[2], squad)
	war:SetRole(members[2], AiWar.SUPPORT)
	T.eq(members[1].role .. " " .. members[2].role .. " " .. squad.role, "support support support", "all of it")
	T.eq(members[2].fireTeam, squad, "still together")
end)

T.test("a medic's job can't be changed; a job handed back is the war's to give again", function()
	local war, members = Enlisted(2)
	local medic = war:Enlist("vort", BLUE, true, AiWar.MEDIC)
	local ok, why = war:SetRole(medic, AiWar.RAID)
	T.eq(ok, false, "refused")
	T.eq(why, "vort only ever does medic", "why")
	war:SetRole(members[1], AiWar.RAID)
	war:ReleaseRole(members[1])
	T.eq(members[1].roleByHand, nil, "the war's again")
	T.eq(members[1].role ~= nil, true, "given a job by the war")
end)

T.test("a medic joining a squad by hand keeps healing", function()
	local war, members = Enlisted(1)
	local medic = war:Enlist("vort", BLUE, true, AiWar.MEDIC)
	local squad = war:FormSquad(members[1])
	war:JoinSquad(medic, squad)
	T.eq(medic.role, AiWar.MEDIC, "its fixed job")
	T.eq(medic.fireTeam, squad, "in the squad")
end)

-- Roles --------------------------------------------------------------------

T.test("the pushing team splits between pushing, escorting, raiding and support", function()
	local war = UncappedWar()
	war:Assign({ [BLUE] = true })
	for i = 1, 6 do war:Enlist("b" .. i, BLUE, true) end
	T.eq(Roles(war, BLUE), "push0 escort0 raid0 push1 escort1 support0", "4:3:2:1")
end)

T.test("the defending team mostly holds the track ahead and sends some to block the cart", function()
	local war = UncappedWar()
	war:Assign({ [BLUE] = true })
	for i = 1, 6 do war:Enlist("r" .. i, RED, true) end
	T.eq(Roles(war, RED), "defend0 block0 raid0 defend1 defend2 support0", "5:2:2:1, ties to the first role")
end)

T.test("on an even race each side both defends against the other's cart and pushes its own", function()
	local war = AiWar.War.New()
	war:Assign({ [BLUE] = true, [RED] = true })
	for i = 1, 3 do war:Enlist("r" .. i, RED, true) end
	T.eq(Roles(war, RED), "defend0 push0 raid0", "one of each work first")
	T.eq(war.defense[RED], 0.5, "an even share")
end)

T.test("a team's defense share: all offense or all defense with one cart, leaning with the race", function()
	T.eq(AiWar.DefenseShare(RED, { [RED] = true }), 0, "only its own cart")
	T.eq(AiWar.DefenseShare(RED, { [BLUE] = true }), 1, "only the enemy's")
	T.eq(AiWar.DefenseShare(RED, {}), nil, "no cart")
	local function Race(red, blue) return AiWar.DefenseShare(RED, { [RED] = red, [BLUE] = blue }) end
	T.eq(Race({ progress = 0.3 }, { progress = 0.3 }), 0.5, "level")
	T.eq(Race({ progress = 0.2 }, { progress = 0.4 }), 0.8, "the enemy 0.2 ahead: more defense")
	T.eq(Race({ progress = 0.5 }, { progress = 0.4 }), 0.4, "ahead: less")
	T.eq(Race({ progress = 0.3 }, { progress = 0.3, close = true }), 0.7, "the enemy's cart close to its checkpoint")
	T.eq(Race({ progress = 0.3, close = true }, { progress = 0.3 }), 0.3, "its own close")
	T.eq(Race({ progress = 0 }, { progress = 1 }), AiWar.DEFENSE_MAX, "never all defense in a race")
	T.eq(Race({ progress = 1 }, { progress = 0 }), AiWar.DEFENSE_MIN, "nor all offense")
end)

T.test("the field a war is given carries each team's defense share, which the orders read as they are", function()
	local war = AiWar.War.New()
	local field = {}
	war:SetField(field)
	T.eq(type(field.defense), "table", "filled before any assignment")
	local carts = {
		[RED] = { progress = 0.3 },
		[BLUE] = { progress = 0.5 },
	}
	war:Assign(carts)
	T.eq(field.defense[RED], AiWar.DefenseShare(RED, carts), "RED's share")
	T.eq(field.defense[BLUE], AiWar.DefenseShare(BLUE, carts), "BLU's share")
end)

T.test("a race turning moves as few soldiers as it can from one cart to the other", function()
	local war = AiWar.War.New()
	war:Assign({ [RED] = { progress = 0.3 }, [BLUE] = { progress = 0.3 } })
	for i = 1, 10 do war:Enlist("r" .. i, RED, true) end
	local function Split()
		local offense, defense, changed = 0, 0, 0
		for _, member in ipairs(war:Members()) do
			if member.role == AiWar.PUSH or member.role == AiWar.ESCORT then offense = offense + 1 end
			if member.role == AiWar.DEFEND or member.role == AiWar.BLOCK then defense = defense + 1 end
		end
		return offense, defense
	end
	local offense, defense = Split()
	T.eq(offense + defense, 7, "seven on the carts")
	local before = {}
	for _, member in ipairs(war:Members()) do before[member] = member.role end
	war:Assign({ [RED] = { progress = 0.3 }, [BLUE] = { progress = 0.5 } })
	T.eq(war.defense[RED], 0.8, "BLU pulled ahead")
	local offense2, defense2 = Split()
	T.eq(defense2 > defense and offense2 < offense, true, "more on BLU's cart, fewer on RED's own")
	local changed = 0
	for member, role in pairs(before) do
		if member.role ~= role then changed = changed + 1 end
	end
	T.eq(changed, defense2 - defense, "only those that had to")
end)

T.test("without a cart nobody has a role", function()
	local war = AiWar.War.New()
	war:Assign({})
	T.eq(war:Enlist("x", RED, true).role, nil, "no role")
end)

T.test("a freed slot is taken by the next soldier of that role", function()
	local war = UncappedWar()
	war:Assign({ [BLUE] = true })
	for i = 1, 4 do war:Enlist("b" .. i, BLUE, true) end
	war:Discharge("b1")
	local member = war:Enlist("b5", BLUE, false)
	T.eq(member.role .. member.slot, "push0", "push0 again")
end)

T.test("a change of stance reassigns the team's roles, oldest first", function()
	local war = UncappedWar()
	war:Assign({ [BLUE] = true })
	for i = 1, 3 do war:Enlist("r" .. i, RED, true) end
	war:Assign({ [BLUE] = true, [RED] = true })
	T.eq(Roles(war, RED), "defend0 push0 raid0", "race roles")
	war:Assign({ [BLUE] = true, [RED] = true })
	T.eq(Roles(war, RED), "defend0 push0 raid0", "unchanged stance keeps them")
end)

T.test("a cart near its checkpoint throws more of the defenders at it, fewest changed", function()
	local war = UncappedWar()
	war:Assign({ [BLUE] = true })
	for i = 1, 10 do war:Enlist("r" .. i, RED, true) end
	local function Count(role)
		local n = 0
		for _, member in ipairs(war:Members()) do
			if member.team == RED and member.role == role then n = n + 1 end
		end
		return n
	end
	T.eq(Count(AiWar.BLOCK), 2, "two blockers while the cart is far")
	local before = {}
	for _, member in ipairs(war:Members()) do before[member] = member.role end
	war:Assign({ [BLUE] = { close = true } })
	T.eq(Count(AiWar.BLOCK), 5, "five once it is close")
	local changed = 0
	for member, role in pairs(before) do
		if member.role ~= role then changed = changed + 1 end
		T.eq(member.fireTeam.role, member.role, "in a fire team of its new role")
	end
	T.eq(changed, 3, "only three defenders turned blocker")
	T.eq(Count(AiWar.RAID), 2, "the raiders left alone")
	war:Assign({ [BLUE] = { close = false } })
	T.eq(Count(AiWar.BLOCK), 2, "back to two when it is pushed back")
end)

-- Stances a scenario hands the war (foundation.aiwar.scenario)

local function Share(role, weight)
	return {
		role = role,
		weight = weight,
	}
end

local ATTACKING = {
	Share(AiWar.CAPTURE, 4),
	Share(AiWar.ASSAULT, 3),
	Share(AiWar.RAID, 2),
	Share(AiWar.SUPPORT, 1),
}
local DEFENDING = {
	Share(AiWar.HOLD, 4),
	Share(AiWar.DEFEND, 3),
	Share(AiWar.RAID, 2),
	Share(AiWar.SUPPORT, 1),
}

local function RolesOf(war, team)
	local roles = {}
	for _, member in ipairs(war:Members()) do
		if member.team == team then roles[member.handle] = member.role end
	end
	return roles
end

T.test("the point jobs are named once", function()
	T.eq(AiWar.CAPTURE, "capture", "capture")
	T.eq(AiWar.ASSAULT, "assault", "assault")
	T.eq(AiWar.HOLD, "hold", "hold")
end)

-- The stance mechanics, with every role on (AiWar.OFF_ROLES aside).
local function AllRolesWar()
	local war = UncappedWar()
	war:SetOffRoles({})
	return war
end

T.test("a team with no stance yet is assigned its scenario's stance from scratch, oldest first", function()
	local war = AllRolesWar()
	for i = 1, 4 do war:Enlist("r" .. i, RED, true) end
	war:AssignStances({ [RED] = ATTACKING }, { [RED] = 0 })
	T.eq(Roles(war, RED), "capture0 assault0 raid0 capture1", "by the shares, in enlistment order")
	T.eq(war.defense[RED], 0, "its defense share")
	T.eq(war.stances[BLUE], nil, "BLU given nothing")
end)

T.test("a team moving to a stance whose roles differ keeps the members of the roles both share", function()
	local war = AllRolesWar()
	for i = 1, 8 do war:Enlist("r" .. i, RED, true) end
	war:AssignStances({ [RED] = ATTACKING }, { [RED] = 0 })
	local before = RolesOf(war, RED)
	war:AssignStances({ [RED] = DEFENDING }, { [RED] = 1 })
	local after = RolesOf(war, RED)
	local moved = 0
	for handle, role in pairs(before) do
		if role == AiWar.RAID or role == AiWar.SUPPORT then
			T.eq(after[handle], role, handle .. " kept " .. role)
		else
			T.eq(after[handle] == AiWar.HOLD or after[handle] == AiWar.DEFEND, true, handle .. " from " .. role .. " to a defense job")
			moved = moved + 1
		end
	end
	T.eq(moved, 5, "only the capture and assault members moved")
	T.eq(war.defense[RED], 1, "the new share")
	for _, member in ipairs(war:Members()) do T.eq(member.fireTeam.role, member.role, "in a fire team of its new role") end
end)

T.test("a nil stance leaves the team as it is", function()
	local war = AllRolesWar()
	for i = 1, 3 do war:Enlist("r" .. i, RED, true) end
	war:AssignStances({ [RED] = ATTACKING }, { [RED] = 0 })
	local before = Roles(war, RED)
	war:AssignStances({}, {})
	T.eq(Roles(war, RED), before, "unchanged")
	T.eq(war.stances[RED], ATTACKING, "the stance kept")
	T.eq(war.defense[RED], 0, "and its share")
end)

T.test("a cart is close within CLOSE_RANGE, and stays close a little past it", function()
	T.eq(AiWar.CartClose(false, AiWar.CLOSE_RANGE), true, "at the range")
	T.eq(AiWar.CartClose(false, AiWar.CLOSE_RANGE + 1), false, "past it")
	T.eq(AiWar.CartClose(true, AiWar.CLOSE_RANGE + AiWar.CLOSE_HYSTERESIS), true, "still close, once close")
	T.eq(AiWar.CartClose(true, AiWar.CLOSE_RANGE + AiWar.CLOSE_HYSTERESIS + 1), false, "far again")
end)

-- Both teams' sizes, for Reinforcements.
local function Sizes(red, blue)
	return {
		[RED] = red,
		[BLUE] = blue or red,
	}
end

T.test("medics: a few per side, drafted first while short, and never moved to another job", function()
	T.eq(AiWar.MedicsFor(3), 0, "too few soldiers for one")
	T.eq(AiWar.MedicsFor(8), 1, "one for eight")
	T.eq(AiWar.MedicsFor(16), 2, "two for sixteen")
	T.eq(AiWar.FixedRole("ws_drg_vortigaunt"), AiWar.MEDIC, "a vortigaunt only heals")
	T.eq(AiWar.FactionTeam("ws_drg_vortigaunt"), RED, "for the Resistance, at home on RED")
	T.eq(AiWar.FixedRole("ws_drg_rebel"), nil, "a rebel does any job")
	local war = UncappedWar()
	war:Assign({ [RED] = true })
	war:Reinforcements(0, Sizes(8), function() return 0 end)
	local draft = war:Draft(RED)
	T.eq(draft.role, AiWar.MEDIC, "a medic first")
	T.eq(draft.recruit.class, "ws_drg_vortigaunt", "a vortigaunt")
	local medic = war:Enlist("vort", RED, true, draft.role)
	T.eq(medic.role, AiWar.MEDIC, "enlisted a medic")
	T.eq(war:Draft(RED).role, nil, "then soldiers")
	T.eq(war:Draft(BLUE).recruit.class, "ws_drg_combine", "the Combine's medic is a soldier in a medic's kit")
	for i = 1, 6 do war:Enlist("r" .. i, RED, true) end
	war:Assign({ [RED] = { progress = 0.2 }, [BLUE] = { progress = 0.9 } })
	T.eq(medic.role, AiWar.MEDIC, "a turning race does not move it")
end)

-- Reinforcements ---------------------------------------------------------------

local function WaveOf(seconds)
	return function() return seconds end
end

T.test("the first wave fills both teams at once", function()
	local war = AiWar.War.New()
	local wave = war:Reinforcements(0, Sizes(6), WaveOf(10))
	T.eq(wave[RED], 6, "RED")
	T.eq(wave[BLUE], 6, "BLU")
end)

T.test("the dead come back only with the team's next wave", function()
	local war = AiWar.War.New()
	war:Reinforcements(0, Sizes(2), WaveOf(10))
	war:Enlist("r1", RED, true)
	war:Enlist("r2", RED, true)
	war:Discharge("r1")
	T.eq(war:Reinforcements(5, Sizes(2), WaveOf(10))[RED], nil, "mid-wave")
	T.eq(war:Reinforcements(10, Sizes(2), WaveOf(10))[RED], 1, "at the wave")
end)

T.test("soldiers the player adds do not count against the team's size", function()
	local war = AiWar.War.New()
	war:Enlist("mine", RED, false)
	T.eq(war:Reinforcements(0, Sizes(2), WaveOf(10))[RED], 2, "still two drafted")
end)

T.test("with no wave time the dead come back at once, and a reset starts the waves over", function()
	local war = AiWar.War.New()
	war:Reinforcements(0, Sizes(1), WaveOf(0))
	T.eq(war:Reinforcements(0.1, Sizes(1), WaveOf(0))[RED], 1, "at once")
	war:Reinforcements(1, Sizes(1), WaveOf(30))
	T.eq(war:Reinforcements(2, Sizes(1), WaveOf(30))[RED], nil, "waiting")
	war:ResetWaves()
	T.eq(war:Reinforcements(2, Sizes(1), WaveOf(30))[RED], 1, "reset")
end)

T.test("each team is filled to its own size: one side alone, or none", function()
	local war = AiWar.War.New()
	local wave = war:Reinforcements(0, Sizes(3, 0), WaveOf(10))
	T.eq(wave[RED], 3, "RED's three")
	T.eq(wave[BLUE], nil, "BLU none")
end)

T.test("medics are counted against each team's own size", function()
	local war = UncappedWar()
	war:Assign({ [BLUE] = true })
	war:Reinforcements(0, Sizes(3, 8), WaveOf(10))
	T.eq(war:Draft(RED).role, nil, "three are too few for a medic")
	T.eq(war:Draft(BLUE).role, AiWar.MEDIC, "eight have one")
end)

T.test("a team's wave can be called at once, leaving the other's waiting", function()
	local war = AiWar.War.New()
	war:Reinforcements(0, Sizes(1), WaveOf(30))
	war:CallWave(RED)
	local wave = war:Reinforcements(1, Sizes(2), WaveOf(30))
	T.eq(wave[RED], 2, "RED now")
	T.eq(wave[BLUE], nil, "BLU at its wave")
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

T.test("a round won by a team is its humiliation of the losers; a stalemate is simply over", function()
	local humiliation = AiWar.PhaseOf(true, STATE.TEAM_WIN, BLUE)
	T.eq(humiliation, AiWar.PHASES.humiliation, "BLU won")
	T.eq(AiWar.PhaseOf(true, STATE.TEAM_WIN, RED), AiWar.PHASES.humiliation, "RED won")
	T.eq(humiliation.orders and humiliation.hunt and not humiliation.reinforce, true, "orders and the hunt, no reinforcements")
	T.eq(AiWar.PhaseOf(true, STATE.TEAM_WIN, nil), AiWar.PHASES.over, "no winner")
	T.eq(AiWar.PhaseOf(true, STATE.TEAM_WIN, Teams.UNASSIGNED), AiWar.PHASES.over, "a stalemate")
	T.eq(AiWar.PhaseOf(true, STATE.GAME_OVER, RED), AiWar.PHASES.humiliation, "the match's winners hunt too")
	T.eq(AiWar.PhaseOf(true, STATE.GAME_OVER, nil), AiWar.PHASES.over, "a match over with no winner")
	T.eq(AiWar.PhaseOf(true, STATE.RND_RUNNING, BLUE), AiWar.PHASES.running, "a winner outside TEAM_WIN changes nothing")
	for name, phase in pairs(AiWar.PHASES) do T.eq(type(phase.hunt), "boolean", name .. " says whether winners hunt") end
	for name, phase in pairs(AiWar.PHASES) do
		if phase ~= AiWar.PHASES.humiliation and phase ~= AiWar.PHASES.suddenDeath then
			T.eq(phase.hunt, false, name .. " has no hunt")
		end
	end
	local sudden = AiWar.PHASES.suddenDeath
	T.eq(sudden.hunt and sudden.everyoneHunts and sudden.sightAll, true, "sudden death: both sides hunt, seeing every enemy")
	T.eq(humiliation.everyoneHunts or humiliation.sightAll, false, "a round won: the winners hunt what they see")
end)

T.test("a war keeps a board of the hunt's sightings", function()
	T.eq(type(AiWar.War.New().hunt.Report), "function", "war.hunt")
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

-- The observer's stranded watch (features/aiwar/sv_posts.lua): a soldier
-- trying to move that gets nowhere for STRANDED_TIME is put back. A
-- soldier fighting stands still on purpose.

local function Stranded(fields)
	local q = { travelling = true, fighting = false, moved = false, since = 0, now = AiWar.STRANDED_TIME }
	for k, v in pairs(fields or {}) do q[k] = v end
	return AiWar.StrandedWatch(q)
end

T.test("a soldier trying to move that gets nowhere for long enough is stranded", function()
	T.defined(AiWar.STRANDED_TIME, "AiWar.STRANDED_TIME")
	T.eq(Stranded(), AiWar.STRANDED, "stranded")
	T.eq(Stranded({ now = AiWar.STRANDED_TIME - 1 }), AiWar.WATCHING, "not yet")
end)

T.test("the watch starts over for a soldier that got somewhere, has nowhere to go, or is fighting", function()
	T.eq(Stranded({ moved = true }), AiWar.WATCH_AGAIN, "it got somewhere")
	T.eq(Stranded({ travelling = false }), AiWar.WATCH_AGAIN, "nowhere to go")
	T.eq(Stranded({ fighting = true }), AiWar.WATCH_AGAIN, "standing to fight an enemy it sees")
end)

T.finish()
