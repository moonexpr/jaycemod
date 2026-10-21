-- tf_gamerules: TF2's gamerules proxy (CTFGameRulesProxy), bound to the
-- rounds feature, which runs the rounds (features/rounds/sv.lua and
-- foundation.rounds). It survives round cleanups, as the gamerules do in
-- TF2. Its methods forward to the controller, for init.lua, the editors, the
-- gameplay modes and the AI war.
ENT.Type = "point"
ENT.Base = "base_point"

local function Rounds()
	return WS.Feature("rounds")
end

function ENT:KeyValue(key, value)
	if string.sub(key, 1, 2) == "On" or string.sub(key, 1, 4) == "Team" then self:StoreOutput(key, value) end
end

function ENT:Initialize()
	Rounds():BindProxy(self)
end

-- The gamerules outlive every round; only a map change ends them. A map
-- cleanup that did not keep them (another addon's) is expected: the rounds
-- controller makes them again after it (AfterCleanup). Removed any other
-- way (a map's Kill), the rounds stop: that is our bug, raised with who
-- removed it and the last input.
local shuttingDown, cleaningUp = false, false
hook.Add("ShutDown", "ws_tf_gamerules", function() shuttingDown = true end)
hook.Add("PreCleanupMap", "ws_tf_gamerules", function() cleaningUp = true end)
hook.Add("PostCleanupMap", "ws_tf_gamerules", function() cleaningUp = false end)

function ENT:OnRemove()
	Rounds():UnbindProxy(self)
	if not (shuttingDown or cleaningUp) then
		ErrorNoHaltWithStack(string.format("tf_gamerules %s removed outside a map change; last input: %s\n",
			tostring(self), self.wsLastInput or "none"))
	end
end

function ENT:UpdateTransmitState()
	return TRANSMIT_NEVER
end

function ENT:AcceptInput(name, activator, caller, value)
	self.wsLastInput = string.format("%s(%s) from %s at %.2f", name, tostring(value), tostring(caller), CurTime())
	return Rounds():ProxyInput(string.lower(name), value)
end

function ENT:OnPlayerDeath(ply) Rounds():OnPlayerDeath(ply) end
function ENT:Halt() Rounds():Halt() end
function ENT:Unhalt() Rounds():Unhalt() end
function ENT:Halted() return Rounds():Halted() end
function ENT:RestartRound() Rounds():RestartRound() end
function ENT:StateGet() return Rounds():State() end
function ENT:InSetup() return Rounds():InSetup() end
function ENT:PointsMayBeCaptured() return Rounds():PointsMayBeCaptured() end
function ENT:AddPlayedRound(name) Rounds():AddPlayedRound(name) end
function ENT:RespawnsDisabled() return Rounds():RespawnsDisabled() end
function ENT:SetRespawnsDisabled(disabled) Rounds():SetRespawnsDisabled(disabled) end
function ENT:SetAdminRespawnWaveTime(team, seconds) Rounds():SetAdminRespawnWaveTime(team, seconds) end
function ENT:TeamRespawnWaveTime(team) return Rounds():TeamRespawnWaveTime(team) end
function ENT:GetRespawnWaveMaxLength(team, scale) return Rounds():GetRespawnWaveMaxLength(team, scale) end

function ENT:SetWinningTeam(winner, reason, forceMapReset, switchTeams, dontAddScore)
	Rounds():SetWinningTeam(winner, reason, forceMapReset, switchTeams, dontAddScore)
end

function ENT:SetStalemate(reason, forceMapReset, switchTeams)
	Rounds():SetStalemate(reason, forceMapReset, switchTeams)
end
