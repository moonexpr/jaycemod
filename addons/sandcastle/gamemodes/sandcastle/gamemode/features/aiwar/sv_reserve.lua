-- Part of the AI war controller (sv.lua): the reserve (features.aiwar.reserve).
-- A drafted soldier that falls while respawn waves run lies dormant
-- (ws_drg_soldier's NSRest) and a later wave revives it (NSRevive) instead
-- of spawning a new entity. With ns_use_regular_spawns on (the classical
-- pattern, kept to compare against), or for any other soldier, death removes
-- the body and a wave spawns a new one.
local Controller = ...
local Reserve = WS.require("features.aiwar.reserve")

local REGULAR_SPAWNS = CreateConVar("ns_use_regular_spawns", "0", { FCVAR_ARCHIVE, FCVAR_NOTIFY },
	"1: a fallen AI war soldier is removed and a respawn wave spawns a new one; 0: the wave revives it", 0, 1)

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
	if not Reserve.Keeps(not REGULAR_SPAWNS:GetBool(), member.drafted == true, waveLength) then return end
	ent.NSDormant = true
	self:Reserve():Keep(ent, entry.soldier.team, WS.SoldierKind(ent))
end

-- A kept body of the team and kind (WS.SoldierKind) revived at pos, or nil.
function Controller:Revive(team, kind, pos, ang)
	local reserve = self:Reserve()
	local ent = reserve:Take(team, kind)
	while ent ~= nil and not IsValid(ent) do ent = reserve:Take(team, kind) end
	if ent == nil then return nil end
	ent:NSRevive(pos, ang)
	return ent
end

-- Every kept body goes: a new round's fresh wave, the war's end, regular
-- spawns turned on.
function Controller:DisbandReserve()
	for _, ent in ipairs(self:Reserve():Drain()) do
		if IsValid(ent) then ent:Remove() end
	end
end

cvars.AddChangeCallback("ns_use_regular_spawns", function(_, _, value)
	if value == "1" then Controller:DisbandReserve() end
end, "ws_aiwar_reserve")

hook.Add("EntityRemoved", "ws_aiwar_reserve", function(ent)
	if Controller.reserve then Controller.reserve:Forget(ent) end
end)
