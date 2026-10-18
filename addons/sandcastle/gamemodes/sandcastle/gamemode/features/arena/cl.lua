-- The arena feature's view (CHudArenaCapPointCountdown): while the arena
-- round waits for its cap-enable time (ws_arena_cap_enable_time), the last
-- five seconds spoken, then the cap-enabled line. The countdown itself is
-- on the round timer (the rounds view's, as POINT UNLOCKS).
WS.Feature("rounds")
local Arena = WS.require("foundation.rounds.arena")

local View = {
	enableAt = 0, -- the cap-enable time the countdown is armed for
	armed = {}, -- second -> whether its line is still to play
	zeroArmed = false,
}

local function EnableAt()
	return GetGlobal2Float("ws_arena_cap_enable_time", 0)
end

local function Play(name)
	local ply = LocalPlayer()
	if IsValid(ply) then ply:EmitSound(name, SNDLVL_100dB, 100, CHAN_VOICE2) end
end

-- CHudArenaCapPointCountdown::OnTick: armed afresh for each new time.
function View:CountdownThink()
	local now, at = CurTime(), EnableAt()
	if at ~= self.enableAt then
		self.enableAt = at
		self.zeroArmed = at > now
		for s in pairs(Arena.COUNTDOWN_LINES) do self.armed[s] = at - now >= s end
	end
	if WS.State() ~= WS.STATE.STALEMATE then return end
	local left = math.ceil(at - now)
	if left <= 0 then
		if self.zeroArmed then Play(Arena.CAP_ENABLED_LINE) end
		self.zeroArmed = false
	elseif self.armed[left] then
		self.armed[left] = false
		Play(Arena.COUNTDOWN_LINES[left])
	end
end

hook.Add("Think", "ws_arena_announcer", function() View:CountdownThink() end)

return View
