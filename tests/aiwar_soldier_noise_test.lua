-- A soldier's body noises (sh_war_soldier.lua's NoticeNoise) are told every bot in
-- earshot: from one source at most once a NOTICE_INTERVAL, unless louder than the last
-- let through, so a crowd's steps are not an O(N^2) fan-out each tick (ARCHITECTURE
-- §7.4 #4 in nextsoldier).
local T = dofile ("tests/harness.lua")

local now = 0

local function SoldierClass (bots)
	local ENT = {}
	local env = setmetatable (
		{
			SERVER = true,
			CLIENT = false,
			CurTime = function () return now end,
			IsValid = function (value) return value ~= nil end,
			FindMetaTable = function () return {} end,
			nextsoldier = setmetatable ({ bots = bots }, { __index = nextsoldier }),
			WS = { require = function (name) return T.require (name) end }
		}, { __index = _G })
	setfenv (assert (loadfile (T.ROOT .. "sh_war_soldier.lua")), env) ()
	env.WS.WarSoldier (ENT)
	return ENT
end

local function Listener ()
	local bot = { heard = 0 }
	function bot:IsAIDisabled () return false end
	function bot:IsDeaf () return false end
	function bot:GetHearingCoefficient () return 1 end
	function bot:GetRangeTo () return 10 end
	function bot:VisibleVec () return true end
	function bot:Timer () self.heard = self.heard + 1 end
	return bot
end

T.test ("one source's noises reach the others at most once an interval, unless louder", function ()
	local listener = Listener ()
	local ENT = SoldierClass ({ [listener] = true })
	local soldier = setmetatable ({}, { __index = ENT })
	function soldier:GetPos () return { x = 0, y = 0, z = 0 } end
	now = 10
	soldier:NoticeNoise (75, 1)
	T.eq (listener.heard, 1, "its first step heard")
	now = 10.1
	soldier:NoticeNoise (75, 1)
	T.eq (listener.heard, 1, "the next, within the interval, not told")
	soldier:NoticeNoise (90, 1)
	T.eq (listener.heard, 2, "a louder noise is")
	now = 11
	soldier:NoticeNoise (75, 1)
	T.eq (listener.heard, 3, "and a step once the interval is out")
end)

T.finish ()
