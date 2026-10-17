-- Part of the AI war controller (sv.lua): the reserve (features.aiwar.reserve).
-- With mp_aiwar_revive_enabled on, a drafted soldier that falls while
-- respawn waves run lies dormant (ws_drg_soldier's NSRest) and a later wave
-- revives it (NSRevive) instead of spawning a new entity. Off, or for any
-- other soldier, death removes the body as before.
local Controller = ...
local Reserve = WS.require("features.aiwar.reserve")

local REVIVE = CreateConVar("mp_aiwar_revive_enabled", "0", { FCVAR_ARCHIVE, FCVAR_NOTIFY },
	"A respawn wave revives the war's fallen soldiers instead of spawning new ones", 0, 1)

function Controller:Reserve()
	self.reserve = self.reserve or Reserve.New()
	return self.reserve
end

-- As a soldier falls (OnNPCKilled, before its discharge): kept when the
-- reserve takes it. waveLength is its team's next wave (WaveLength).
function Controller:Retire(ent, waveLength)
	local member = self.war:Member(ent)
	local entry = self.soldiers[ent]
	if not (member and entry and ent.NSRest) then return end
	if not Reserve.Keeps(REVIVE:GetBool(), member.drafted == true, waveLength) then return end
	ent.NSDormant = true
	self:Reserve():Keep(ent, entry.soldier.team, ent:GetClass())
end

-- A kept body of the team and class revived at pos, or nil.
function Controller:Revive(team, class, pos, ang)
	local reserve = self:Reserve()
	local ent = reserve:Take(team, class)
	while ent ~= nil and not IsValid(ent) do ent = reserve:Take(team, class) end
	if ent == nil then return nil end
	ent:NSRevive(pos, ang)
	return ent
end

-- Every kept body goes: a new round's fresh wave, the war's end, revives
-- turned off.
function Controller:DisbandReserve()
	for _, ent in ipairs(self:Reserve():Drain()) do
		if IsValid(ent) then ent:Remove() end
	end
end

cvars.AddChangeCallback("mp_aiwar_revive_enabled", function(_, _, value)
	if value == "0" then Controller:DisbandReserve() end
end, "ws_aiwar_reserve")

hook.Add("EntityRemoved", "ws_aiwar_reserve", function(ent)
	if Controller.reserve then Controller.reserve:Forget(ent) end
end)
