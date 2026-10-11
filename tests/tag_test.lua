local T = dofile("tests/harness.lua")
local Tag = T.require("features.tag.model")
local Teams = T.require("foundation.teams")
local Holiday = T.require("foundation.holiday")
local Halloween = T.require("foundation.holiday.halloween")

-- The tag model's world: the holiday controller's HolidayActive and Mode
-- (backed here by a real foundation.holiday model), and players' teams and
-- lives.
local function World(mapHoliday)
	local holiday = Holiday.New({
		mapHoliday = mapHoliday,
		forced = Holiday.NONE,
		spellsForced = false,
		modes = { Halloween },
	})
	return {
		HolidayActive = function(_, h) return holiday:Active(h) end,
		Mode = function() return holiday:Mode() end,
		IsAlive = function(_, p) return p.alive end,
		TeamOf = function(_, p) return p.team end,
	}
end

local function Player(name, team)
	return {
		name = name,
		team = team,
		alive = true,
	}
end

-- The notices of one kind, as { player, sound or text } pairs.
local function Of(notices, kind)
	local found = {}
	for _, n in ipairs(notices) do
		if n.kind == kind then found[#found + 1] = n end
	end
	return found
end

T.test("nobody is IT at first, and Set makes a player IT", function()
	local tag = Tag.New(World(Holiday.HALLOWEEN))
	local red = Player("red", Teams.RED)
	T.eq(tag:Get(), nil, "nobody")
	tag:Set(red)
	T.eq(tag:Get(), red, "red is IT")
	T.eq(tag:IsIT(red), true, "IsIT")
	tag:Set(nil)
	T.eq(tag:Get(), nil, "nobody again")
end)

-- CTFGameRules::SetIT
T.test("on Halloween the new IT is warned and screams, and the old IT is told", function()
	local tag = Tag.New(World(Holiday.HALLOWEEN))
	local red, blue = Player("red", Teams.RED), Player("blue", Teams.BLUE)
	local first = tag:Set(red)
	T.eq(Of(first, Tag.SOUND_TO)[1].player, red, "you are IT: to red")
	T.eq(Of(first, Tag.SOUND_TO)[1].sound, Tag.YOU_ARE_IT_SOUND, "you are IT sound")
	T.eq(Of(first, Tag.SOUND_FROM)[1].sound, Tag.SCREAM_SOUND, "red screams")
	T.eq(Of(first, Tag.PRINT_CENTER)[1].text, Tag.WARN_VICTIM, "centre warning")
	T.eq(Of(first, Tag.PRINT_TALK)[1].text, Tag.WARN_VICTIM, "chat warning")
	T.eq(#first, 4, "nothing for an old IT")

	local second = tag:Set(blue)
	local toRed = {}
	for _, n in ipairs(second) do
		if n.player == red then toRed[#toRed + 1] = n end
	end
	T.eq(#toRed, 3, "red hears and reads that it is safe")
	T.eq(Of(toRed, Tag.SOUND_TO)[1].sound, Tag.TAGGED_OTHER_SOUND, "tagged other sound")
	T.eq(Of(toRed, Tag.PRINT_CENTER)[1].text, Tag.LOST_AGGRO, "no longer IT")
end)

T.test("setting the same IT again warns nobody, and a dead old IT is not told", function()
	local tag = Tag.New(World(Holiday.HALLOWEEN))
	local red, blue = Player("red", Teams.RED), Player("blue", Teams.BLUE)
	tag:Set(red)
	T.eq(#tag:Set(red), 0, "same IT")
	red.alive = false
	local notices = tag:Set(blue)
	for _, n in ipairs(notices) do T.eq(n.player, blue, "only the new IT") end
end)

T.test("outside Halloween IT changes hands silently", function()
	for _, h in ipairs({ Holiday.NONE, Holiday.CHRISTMAS }) do
		local tag = Tag.New(World(h))
		local red, blue = Player("red", Teams.RED), Player("blue", Teams.BLUE)
		T.eq(#tag:Set(red), 0, "new IT")
		T.eq(#tag:Set(blue), 0, "old IT")
		T.eq(#tag:Warn(blue), 0, "no warning")
		T.eq(tag:Get(), blue, "still IT")
	end
end)

T.test("the Horsemann's repeated warning is a centre print to IT, on Halloween only", function()
	local tag = Tag.New(World(Holiday.HALLOWEEN))
	local red = Player("red", Teams.RED)
	local notices = tag:Warn(red)
	T.eq(#notices, 1, "one notice")
	T.eq(notices[1].kind, Tag.PRINT_CENTER, "centre")
	T.eq(notices[1].player, red, "to IT")
	T.eq(notices[1].text, Tag.WARN_VICTIM, "the warning")
end)

-- CTFWeaponBaseMelee::OnSwingHit
T.test("IT passes by a melee hit on an enemy, and everyone hears who tagged whom", function()
	local tag = Tag.New(World(Holiday.HALLOWEEN))
	local red, blue, red2 = Player("red", Teams.RED), Player("blue", Teams.BLUE), Player("red2", Teams.RED)
	tag:Set(red)
	T.eq(#tag:OnMeleeHit(red, red2), 0, "a teammate is not tagged")
	T.eq(tag:Get(), red, "red still IT")
	T.eq(#tag:OnMeleeHit(blue, red), 0, "hitting IT does not tag")
	T.eq(tag:Get(), red, "red still IT")
	local notices = tag:OnMeleeHit(red, blue)
	T.eq(tag:Get(), blue, "blue is IT")
	local all = Of(notices, Tag.PRINT_ALL)
	T.eq(#all, 1, "one announcement")
	T.eq(all[1].text, Tag.ANNOUNCE_TAG, "tagged text")
	T.eq(all[1].subjects[1], red, "tagger")
	T.eq(all[1].subjects[2], blue, "tagged")
	T.eq(notices[#notices], all[1], "announced after the IT change")
end)

T.test("the tag announcement plays outside Halloween too, as TF2's melee code does", function()
	local tag = Tag.New(World(Holiday.NONE))
	local red, blue = Player("red", Teams.RED), Player("blue", Teams.BLUE)
	tag:Set(red)
	local notices = tag:OnMeleeHit(red, blue)
	T.eq(#notices, 1, "only the announcement")
	T.eq(notices[1].kind, Tag.PRINT_ALL, "print all")
end)

-- CTFPlayer::Event_Killed
T.test("IT passes to whoever kills IT; other deaths change nothing", function()
	local tag = Tag.New(World(Holiday.HALLOWEEN))
	local red, blue, other = Player("red", Teams.RED), Player("blue", Teams.BLUE), Player("other", Teams.BLUE)
	tag:Set(red)
	tag:OnDeath(other, blue)
	T.eq(tag:Get(), red, "not IT's death")
	tag:OnDeath(red, nil)
	T.eq(tag:Get(), red, "no player killer")
	local notices = tag:OnDeath(red, blue)
	T.eq(tag:Get(), blue, "the killer is IT")
	T.eq(Of(notices, Tag.SOUND_TO)[1].player, blue, "the killer is warned")
end)

T.finish()
