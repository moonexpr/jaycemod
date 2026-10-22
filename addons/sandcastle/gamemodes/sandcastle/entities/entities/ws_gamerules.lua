-- ws_gamerules: Sandcastle's gamerules, the rules of every map without TF2's
-- (tf_gamerules derives from them). The rounds controller makes them
-- (features/rounds/sv.lua's EnsureProxy) and runs the rounds through them
-- (features/rounds/sv.lua and games.gameplay.rounds); they run none until a
-- game begins (EnsureRules). Bound, they are WS.Rules. They survive round
-- cleanups, as the gamerules do in TF2. Their methods forward to the
-- controller, for init.lua, the editors, the gameplay modes and the AI war;
-- they take tf_gamerules' inputs, for a map's outputs aimed at them.
ENT.Type = "point"
ENT.Base = "base_point"
-- Whether these rules run rounds from the start (TF2's do).
ENT.RunsRounds = false

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
-- way (a map's Kill), that is our bug, raised with who removed them and the
-- last input; the controller replaces them at once, and the game goes on.
local shuttingDown, cleaningUp = false, false
hook.Add("ShutDown", "ws_gamerules", function() shuttingDown = true end)
hook.Add("PreCleanupMap", "ws_gamerules", function() cleaningUp = true end)
hook.Add("PostCleanupMap", "ws_gamerules", function() cleaningUp = false end)

function ENT:OnRemove()
	local expected = shuttingDown or cleaningUp
	if not expected then
		ErrorNoHaltWithStack(string.format("%s %s removed outside a map change; last input: %s\n",
			self:GetClass(), tostring(self), self.wsLastInput or "none"))
	end
	Rounds():UnbindProxy(self, not expected)
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
function ENT:CleanUp() Rounds():CleanUp() end
function ENT:BeginGame(preroundEnd) Rounds():BeginGame(preroundEnd) end
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
