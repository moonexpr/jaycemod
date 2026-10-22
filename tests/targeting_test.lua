local T = dofile("tests/harness.lua")
local Targeting = T.require("games.npc.targeting")
local Players = T.require("games.gameplay.players")
local Teams = T.require("games.gameplay.teams")

local C = Players.COND

-- A player's conditions as the predicate the rules take.
local function Conds(list)
	local set = {}
	for _, cond in ipairs(list) do set[cond] = true end
	return function(cond) return set[cond] == true end
end

-- The condition and stun numbers keep tf_shareddefs.h's.

T.test("the Halloween conditions and the trigger stun keep TF2's numbers", function()
	T.eq(C.DISGUISED, 3, "disguised")
	T.eq(C.STEALTHED, 4, "stealthed")
	T.eq(C.STEALTHED_BLINK, 9, "stealth blink")
	T.eq(C.INVULNERABLE_HIDE_UNLESS_DAMAGED, 51, "hidden invulnerable")
	T.eq(C.INVULNERABLE_USER_BUFF, 52, "invulnerable buff")
	T.eq(C.INVULNERABLE_CARD_EFFECT, 57, "card invulnerable")
	T.eq(C.STEALTHED_USER_BUFF, 64, "stealth buff")
	T.eq(C.STEALTHED_USER_BUFF_FADING, 66, "stealth buff fading")
	T.eq(C.HALLOWEEN_SPEED_BOOST, 72, "halloween speed boost")
	T.eq(C.HALLOWEEN_TINY, 75, "halloween tiny")
	T.eq(C.HALLOWEEN_GHOST_MODE, 77, "ghost mode")
	T.eq(Players.STUN.BY_TRIGGER, 128, "stun by trigger")
end)

-- IsHiddenFromNPC (CZombieAttack::SelectVictim, CEyeballBoss::FindClosestVisibleVictim)

T.test("a visible player is not hidden", function()
	T.eq(Targeting.IsHiddenFromNPC(Conds({})), false, "no conditions")
	T.eq(Targeting.IsHiddenFromNPC(Conds({ C.BURNING })), false, "burning, not stealthed")
end)

T.test("every kind of stealth hides a player", function()
	T.eq(Targeting.IsHiddenFromNPC(Conds({ C.STEALTHED })), true, "cloaked")
	T.eq(Targeting.IsHiddenFromNPC(Conds({ C.STEALTHED_USER_BUFF })), true, "stealth buff")
	T.eq(Targeting.IsHiddenFromNPC(Conds({ C.STEALTHED_USER_BUFF_FADING })), true, "fading stealth buff")
end)

T.test("a stealthed player who is burning, jarated, blinking or bleeding is seen", function()
	T.eq(Targeting.IsHiddenFromNPC(Conds({ C.STEALTHED, C.BURNING })), false, "burning")
	T.eq(Targeting.IsHiddenFromNPC(Conds({ C.STEALTHED, C.URINE })), false, "jarated")
	T.eq(Targeting.IsHiddenFromNPC(Conds({ C.STEALTHED, C.STEALTHED_BLINK })), false, "blinking")
	T.eq(Targeting.IsHiddenFromNPC(Conds({ C.STEALTHED_USER_BUFF, C.BLEEDING })), false, "bleeding")
end)

T.test("a ghost is hidden whatever else it has", function()
	T.eq(Targeting.IsHiddenFromNPC(Conds({ C.HALLOWEEN_GHOST_MODE })), true, "ghost")
	T.eq(Targeting.IsHiddenFromNPC(Conds({ C.HALLOWEEN_GHOST_MODE, C.BURNING })), true, "burning ghost")
end)

-- IsInvulnerable (CTFPlayerShared::IsInvulnerable)

T.test("the four invulnerability conditions make a player invulnerable", function()
	T.eq(Targeting.IsInvulnerable(Conds({})), false, "none")
	T.eq(Targeting.IsInvulnerable(Conds({ C.CRITBOOSTED })), false, "crit boost is not invulnerability")
	T.eq(Targeting.IsInvulnerable(Conds({ C.INVULNERABLE })), true, "uber")
	T.eq(Targeting.IsInvulnerable(Conds({ C.INVULNERABLE_USER_BUFF })), true, "buff")
	T.eq(Targeting.IsInvulnerable(Conds({ C.INVULNERABLE_HIDE_UNLESS_DAMAGED })), true, "hidden")
	T.eq(Targeting.IsInvulnerable(Conds({ C.INVULNERABLE_CARD_EFFECT })), true, "card")
end)

-- EnemyTeamsOf

local function Names(teams)
	local names = {}
	for i, team in ipairs(teams) do names[i] = tostring(team) end
	return table.concat(names, ",")
end

T.test("RED and BLU fight each other; everyone else fights both", function()
	T.eq(Names(Targeting.EnemyTeamsOf(Teams.RED)), Names({ Teams.BLUE }), "red")
	T.eq(Names(Targeting.EnemyTeamsOf(Teams.BLUE)), Names({ Teams.RED }), "blue")
	T.eq(Names(Targeting.EnemyTeamsOf(Teams.HALLOWEEN)), Names({ Teams.RED, Teams.BLUE }), "halloween")
	T.eq(Names(Targeting.EnemyTeamsOf(Teams.UNASSIGNED)), Names({ Teams.RED, Teams.BLUE }), "unassigned")
	T.eq(Names(Targeting.EnemyTeamsOf(Teams.SPECTATOR)), Names({ Teams.RED, Teams.BLUE }), "spectator")
end)

T.test("a caller cannot change the enemy lists", function()
	Targeting.EnemyTeamsOf(Teams.HALLOWEEN)[1] = Teams.HALLOWEEN
	T.eq(Names(Targeting.EnemyTeamsOf(Teams.HALLOWEEN)), Names({ Teams.RED, Teams.BLUE }), "fresh list")
end)

T.finish()
