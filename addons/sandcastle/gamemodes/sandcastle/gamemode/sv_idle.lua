-- Whether the server is idle (games.system.idle): once it has had no players
-- for sv_idle_delay seconds, counted from the last one leaving or from an
-- empty map's start, it is, and hook WSServerIdle says so; a player joining
-- calls the countdown off, or makes an idle server active again
-- (WSServerActive). WS.ServerIdle() asks. While it is idle, a map without a
-- nav mesh has one generated (ws/sv_nav.lua) and the AI war stands still
-- (features/aiwar/sv_war.lua); the rounds run on, so the maps rotate.
local Idle = system.idle

local DELAY = CreateConVar("sv_idle_delay", "300", FCVAR_ARCHIVE,
	"Seconds an empty server waits before it is idle", 0)
local CHECK_SECONDS = 1
local TIMER = "ws_idle"

local CLOCK = { Now = function() return CurTime() end }
local watch = Idle.New(CLOCK, DELAY:GetFloat())

-- a new delay applies to the countdown under way
cvars.AddChangeCallback("sv_idle_delay", function()
	watch:SetDelay(DELAY:GetFloat())
end, "ws_idle")

local HOOKS = {
	[Idle.IDLE] = "WSServerIdle",
	[Idle.ACTIVE] = "WSServerActive",
}

function WS.ServerIdle()
	return watch:IsIdle()
end

local function Check()
	local change = watch:Update(#player.GetHumans())
	if not change then return end
	print(change == Idle.IDLE and "Server: empty for " .. DELAY:GetFloat() .. " seconds, idle" or "Server: a player joined, active")
	hook.Run(HOOKS[change])
end

timer.Create(TIMER, CHECK_SECONDS, 0, Check)
-- a joining player wakes an idle server at once; a leaving one is still
-- counted until the next check
hook.Add("PlayerInitialSpawn", "ws_idle", function(ply)
	if not ply:IsBot() then Check() end
end)
