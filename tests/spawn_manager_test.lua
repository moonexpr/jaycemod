-- foundation.spawn_manager: the one gate players spawn through. A lock
-- (the nav mesh being generated) holds everyone back: nobody picks a team,
-- a player who would spawn watches, the dead stay down, and a respawn wave
-- brings nobody; lifting the last lock releases all of them. Shared, it
-- also says why a player is not spawning, in TF2's words.
local T = dofile("tests/harness.lua")
local S = T.require("foundation.spawn_manager")

local function Names(players)
	local names = {}
	for i, p in ipairs(players) do names[i] = p.name end
	return table.concat(names, ",")
end

T.test("unlocked, everyone spawns, respawns and picks a team", function()
	local m, ann = S.New(), { name = "ann" }
	T.eq(m:LockedBy(), nil)
	T.eq(m:MayChooseTeam(), true)
	T.eq(m:Admit(ann), true)
	T.eq(m:MayRespawn(ann), true)
	T.eq(Names(m:Spawnable({ ann })), "ann")
end)

T.test("locked, nobody picks a team, spawns or respawns, and each is held", function()
	local m = S.New()
	local ann, bob, cy = { name = "ann" }, { name = "bob" }, { name = "cy" }
	m:Lock("nav")
	T.eq(m:LockedBy(), "nav")
	T.eq(m:MayChooseTeam(), false)
	T.eq(m:Admit(ann), false, "watches")
	T.eq(m:MayRespawn(bob), false, "stays down")
	T.eq(Names(m:Spawnable({ cy })), "", "the wave brings nobody")
	T.eq(Names(m:Unlock("nav")), "ann,bob,cy", "all released, in the order held")
	T.eq(m:LockedBy(), nil)
	T.eq(m:Admit(ann), true, "spawns again")
end)

T.test("a player held twice is released once", function()
	local m, ann = S.New(), { name = "ann" }
	m:Lock("nav")
	m:Admit(ann)
	m:MayRespawn(ann)
	T.eq(Names(m:Unlock("nav")), "ann")
end)

T.test("unlocking what is not locked releases nobody", function()
	local m, ann = S.New(), { name = "ann" }
	T.eq(Names(m:Unlock("nav")), "")
	m:Admit(ann)
	T.eq(Names(m:Unlock("nav")), "", "ann was never held")
end)

T.test("a lock not in the vocabulary is our bug", function()
	local ok = pcall(function() S.New():Lock("lunch") end)
	T.eq(ok, false)
end)

T.test("why a player is not spawning, in TF2's words", function()
	T.eq(S.Message(S.WAVE, 4.2), "Respawn in: 5 seconds")
	T.eq(S.Message(S.WAVE, 0.5), "Respawn in: 1 second")
	T.eq(S.Message(S.WAVE, 0), "Prepare to respawn")
	T.eq(S.Message(S.SUDDEN_DEATH, 0), "No respawning in Sudden Death")
	T.eq(S.Message(S.ARENA, 0), "No respawning in Arena Mode")
	T.eq(S.Message(S.NEXT_ROUND, 0), "Respawn in: Wait for next round")
	T.eq(S.Message(S.NONE, 0), nil, "nothing to say")
end)

T.test("held, the lock says why", function()
	T.eq(S.Message(S.HELD, 0, "nav"), "No respawning allowed during map navigation processing")
end)

T.finish()
