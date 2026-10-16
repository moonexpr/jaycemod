-- foundation.play_mode: the one mode every rule keys on, built from the
-- replicated facts. A stopped game is Sandbox mode even while an AI war is
-- set up; otherwise an AI war or an arena names the kind of Gameplay mode.
local T = dofile("tests/harness.lua")
local PlayMode = T.require("foundation.play_mode")

local function Facts(over)
	local facts = {
		roundsActive = true,
		gameplayStopped = false,
		aiwar = false,
		arena = false,
	}
	for k, v in pairs(over or {}) do facts[k] = v end
	return facts
end

T.test("no rounds is Sandbox mode", function()
	T.eq(PlayMode.Of(Facts({ roundsActive = false })), PlayMode.SANDBOX)
end)

T.test("a stopped game is Sandbox mode, even with an AI war set up", function()
	T.eq(PlayMode.Of(Facts({ gameplayStopped = true, aiwar = true })), PlayMode.SANDBOX)
end)

T.test("running rounds are Gameplay mode, or the AI war's or the arena's", function()
	T.eq(PlayMode.Of(Facts()), PlayMode.GAMEPLAY)
	T.eq(PlayMode.Of(Facts({ aiwar = true })), PlayMode.AIWAR)
	T.eq(PlayMode.Of(Facts({ arena = true })), PlayMode.ARENA)
	T.eq(PlayMode.Of(Facts({ aiwar = true, arena = true })), PlayMode.AIWAR, "the AI war names the mode first")
end)

T.test("only Sandbox mode is Sandbox", function()
	T.eq(PlayMode.IsSandbox(PlayMode.SANDBOX), true)
	for _, mode in ipairs({ PlayMode.GAMEPLAY, PlayMode.AIWAR, PlayMode.ARENA }) do
		T.eq(PlayMode.IsSandbox(mode), false, mode)
	end
end)

T.test("a fact left out is our bug, not a guess", function()
	local facts = Facts()
	facts.arena = nil
	T.eq(pcall(PlayMode.Of, facts), false)
end)

T.finish()
