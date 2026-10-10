-- The Player/Robot Destruction stand-in (foundation.rounds.destruction):
-- CTFGameRules::Activate settles the game type in order, the destruction
-- logics after the train watchers and KOTH, arena last. pd_watergate's UFO
-- rides a team_train_watcher, but the map is Player Destruction: not
-- payload, so no cart HUD. Sandcastle plays no PD scoring yet, so the
-- round limits decide its rounds (an objective-less mode).
local T = dofile("tests/harness.lua")
local Rounds = T.require("foundation.rounds")
local Destruction = T.require("foundation.rounds.destruction")
local Payload = T.require("foundation.rounds.payload")
local Koth = T.require("foundation.rounds.koth")
local Arena = T.require("foundation.rounds.arena")
local Limits = T.require("foundation.rounds.limits")

local function Settings()
	return {
		respawnWaveTime = 10, bonusRoundTime = 15, enableRoundWaitTime = 1, stalemateEnable = false,
		stalemateTimelimit = 240, winlimit = 0, maxrounds = 0, timelimit = 0, matchEndAtTimelimit = false,
		chattime = 10, mapResetTime = 0,
	}
end

T.test("a destruction logic outranks the train watchers and KOTH, whichever spawned first", function()
	for _, first in ipairs({ Payload.Mode, Koth.Mode }) do
		local round = Rounds.New(Settings())
		round:SetMode(first)
		round:SetMode(Destruction.Mode)
		T.eq(round:Mode(), Destruction.Mode, first.NAME .. " then destruction")
		round = Rounds.New(Settings())
		round:SetMode(Destruction.Mode)
		round:SetMode(first)
		T.eq(round:Mode(), Destruction.Mode, "destruction then " .. first.NAME)
	end
end)

T.test("arena still outranks it", function()
	local round = Rounds.New(Settings())
	round:SetMode(Destruction.Mode)
	round:SetMode(Arena.Mode)
	T.eq(round:Mode(), Arena.Mode, "arena")
end)

T.test("it shows no objective HUD and plays to the round limits", function()
	T.eq(Destruction.Mode.HUD, Rounds.HUD_NONE, "no cart or point HUD")
	local limits = Limits.Of(Destruction.Mode, 30, 10000)
	T.eq(limits.frags, 30, "the frag limit")
	T.eq(limits.cash, 10000, "the cash limit")
end)

T.finish()
