-- foundation.aiwar.squad: who leads a fire team, and the claims soldiers
-- put on spots.
local T = dofile("tests/harness.lua")
local Squad = T.require("foundation.aiwar.squad")
local Lease = T.require("foundation.core.lease")

local function Team(...)
	local fireTeam = { members = {} }
	for place, member in ipairs({ ... }) do
		member.place, member.fireTeam = place - 1, fireTeam
		fireTeam.members[place - 1] = member
	end
	return fireTeam
end

T.test("the member longest in the war leads, and keeps leading until it leaves", function()
	local old, young = { seq = 1 }, { seq = 5 }
	local fireTeam = Team(young, old)
	T.eq(Squad.Leader(fireTeam), old, "the oldest")
	T.eq(Squad.Kind(old), "leader", "leads")
	T.eq(Squad.Kind(young), "member", "follows")
	fireTeam.members[old.place], old.fireTeam = nil, nil
	T.eq(Squad.Leader(fireTeam), young, "the next once it leaves")
	T.eq(Squad.Kind(old), "solo", "in no squad")
end)

T.test("a hero always leads, and the oldest again once it goes", function()
	local old, hero = { seq = 1 }, { seq = 9, hero = true }
	local fireTeam = Team(old)
	T.eq(Squad.Leader(fireTeam), old, "the oldest, before the hero")
	hero.place, hero.fireTeam = 1, fireTeam
	fireTeam.members[1] = hero
	T.eq(Squad.Leader(fireTeam), hero, "the hero takes over")
	fireTeam.members[1], hero.fireTeam = nil, nil
	T.eq(Squad.Leader(fireTeam), old, "the oldest again")
end)

T.test("a soldier in a slot pinned to lead leads, over a hero and an older member", function()
	local old, hero, pinned = { seq = 1 }, { seq = 2, hero = true }, { seq = 9, pin = Squad.LEADER }
	local fireTeam = Team(old, hero, pinned)
	T.eq(Squad.Leader(fireTeam), pinned, "the pinned leader")
end)

T.test("a soldier in a slot pinned to follow never leads while another is in its fire team", function()
	local follower, young = { seq = 1, pin = Squad.MEMBER }, { seq = 9 }
	local fireTeam = Team(follower, young)
	T.eq(Squad.Leader(fireTeam), young, "the younger, unpinned")
	fireTeam.members[young.place], young.fireTeam = nil, nil
	T.eq(Squad.Leader(fireTeam), follower, "alone, it leads: a squad always has a leader")
end)

T.test("pinning a slot moves the lead at once: a new leader takes over, and an unpinned one gives way", function()
	local old, young = { seq = 1 }, { seq = 9 }
	local fireTeam = Team(old, young)
	T.eq(Squad.Leader(fireTeam), old, "the oldest")
	young.pin = Squad.LEADER
	T.eq(Squad.Leader(fireTeam), young, "pinned to lead")
	young.pin = nil
	old.pin = Squad.MEMBER
	T.eq(Squad.Leader(fireTeam), young, "the old one pinned to follow: the young one keeps the lead")
end)

T.test("a claim holds a grid cell for its holder until it expires or is released", function()
	local claims = Lease.New()
	local key = Squad.Key("cover", { x = 10, y = 10, z = 0 })
	T.eq(Squad.Key("cover", { x = 40, y = 20, z = 5 }), key, "a few units away: the same cell")
	T.eq(claims:Take(key, "a", 0, 20), true, "a takes it")
	T.eq(claims:Take(key, "b", 5, 20), false, "b cannot")
	T.eq(claims:FreeFor(key, "a", 5), true, "still a's own")
	T.eq(claims:Take(key, "b", 21, 20), true, "b once it expired")
	claims:Release(key, "a")
	T.eq(claims:Holder(key, 22), "b", "a cannot release b's")
	claims:ReleaseAll("b")
	T.eq(claims:Holder(key, 22), nil, "b died: free")
end)

T.finish()
