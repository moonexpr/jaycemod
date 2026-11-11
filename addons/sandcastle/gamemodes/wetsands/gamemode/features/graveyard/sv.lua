-- The graveyard feature's controller: graveyard.nut, which GMod cannot run,
-- played in Lua (the map's logic_script loads it). It owns the rules
-- (features.graveyard.model), turns the dead into ghosts who heal their team,
-- and carries out the last player's announcement and the round's end.
local Model = WS.require ("features.graveyard.model")
local Rounds = gameplay.rounds
local C = gameplay.players.COND

local RED, BLUE, UNASSIGNED = WS.TEAM_RED, WS.TEAM_BLUE, WS.TEAM_UNASSIGNED

local HOOK = "ws_graveyard"
local GHOST_MODELS =
{
	[RED] = "models/props_graveyard/ghost_healing_red.mdl",
	[BLUE] = "models/props_graveyard/ghost_healing.mdl"
}
local GHOST_SCALE = 0.3
local FOREVER = -1
local HEAL_INTERVAL = 1
local BECOME_GHOST = "YOU DIED! As a GHOST, heal your team!"
local LAST_PLAYER = "%s is the LAST PLAYER STANDING!"

local Controller =
{
	rounds = WS.Feature ("rounds"),
	game = Model.New (),
	ghosts = {}, -- player -> true
	lastMen = {}, -- team -> its last player alive
	nextHeal = 0
}

-- The script turns random crits off while the map runs.
local criticals = GetConVar ("tf_weapon_criticals")
local criticalsBefore = criticals:GetString ()
criticals:SetBool (false)
hook.Add ("ShutDown", HOOK, function () criticals:SetString (criticalsBefore) end)

-- living, members: team -> how many.
function Controller:Counts ()
	local living, members = { [RED] = 0, [BLUE] = 0 }, { [RED] = 0, [BLUE] = 0 }
	for _, ply in ipairs (player.GetAll ()) do
		local team = ply:Team ()
		if members [team] then
			members [team] = members [team] + 1
			if ply:Alive () and not self.ghosts [ply] then living [team] = living [team] + 1 end
		end
	end
	return living, members
end

local function LastAlive (self, side)
	for _, ply in ipairs (team.GetPlayers (side)) do
		if ply:Alive () and not self.ghosts [ply] then return ply end
	end
end

local ANSWERS =
{
	[Model.LAST_MAN] = function (self, e)
		local ply = LastAlive (self, e.team)
		self.lastMen [e.team] = ply
		WS.AddCondition (ply, C.OFFENSEBUFF, FOREVER)
		WS.BroadcastText (UNASSIGNED, string.format (LAST_PLAYER, ply:Nick ()))
		WS.BroadcastSoundscape (e.team,              "Graveyard.LastManAlly")
		WS.BroadcastSoundscape (WS.EnemyOf (e.team), "Graveyard.LastManEnemy")
	end,
	[Model.WIN] = function (self, e)
		self.rounds:SetWinningTeam (e.team, Rounds.WINREASON.OPPONENTS_DEAD, true, false)
	end,
	[Model.STALEMATE] = function (self)
		self.rounds:SetStalemate (Rounds.STALEMATE.TIMER, true, false)
	end
}

function Controller:Check ()
	local living, members = self:Counts ()
	SetGlobal2Int ("ws_graveyard_alive_" .. RED,  living [RED])
	SetGlobal2Int ("ws_graveyard_alive_" .. BLUE, living [BLUE])
	for _, event in ipairs (self.game:Check (living, members)) do ANSWERS [event.kind] (self, event) end
end

-- A death or a departure counts from the next tick, when the player is gone.
local function CheckSoon ()
	timer.Simple (0, function () Controller:Check () end)
end

-- becomeGhost, in what GMod has: unarmed, small and floating, passing through
-- players, unharmed (EntityTakeDamage) and unseen by NPCs.
function Controller:MakeGhost (ply)
	self.ghosts [ply] = true
	WS.AddCondition (ply, C.HALLOWEEN_GHOST_MODE, FOREVER)
	ply:StripWeapons ()
	ply:SetModel (GHOST_MODELS [ply:Team ()])
	ply:SetModelScale (GHOST_SCALE, 0)
	ply:SetMoveType (MOVETYPE_FLY)
	ply:SetCollisionGroup (COLLISION_GROUP_WORLD)
	ply:SetNoTarget (true)
	ply:ChatPrint (BECOME_GHOST)
end

function Controller:ClearGhost (ply)
	if not self.ghosts [ply] then return end
	self.ghosts [ply] = nil
	WS.RemoveCondition (ply, C.HALLOWEEN_GHOST_MODE)
	ply:SetModelScale (1, 0)
	ply:SetMoveType (MOVETYPE_WALK)
	ply:SetCollisionGroup (COLLISION_GROUP_PLAYER)
	ply:SetNoTarget (false)
end

function Controller:Spawned (ply)
	self:ClearGhost (ply)
	if self.game:GhostOnSpawn (ply:Team ()) then self:MakeGhost (ply) end
	self:Check ()
end

-- A bot's outfit and loadout can arrive after it became a ghost.
local function KeepGhost (ply)
	local model = GHOST_MODELS [ply:Team ()]
	if ply:GetModel () ~= model then ply:SetModel (model) end
	if #ply:GetWeapons () > 0 then ply:StripWeapons () end
end

-- Each ghost is a dispenser for its team; the last player keeps their buff
-- through a resupply, as the script's think does.
function Controller:Heal ()
	local radius = Model.HEAL_RADIUS * Model.HEAL_RADIUS
	for ghost in pairs (self.ghosts) do
		KeepGhost (ghost)
		local from = ghost:GetPos ()
		for _, ply in ipairs (team.GetPlayers (ghost:Team ())) do
			if ply:Alive () and not self.ghosts [ply] and ply:GetPos ():DistToSqr (from) <= radius then
				ply:SetHealth (Model.Healed (ply:Health (), ply:GetMaxHealth (), HEAL_INTERVAL))
			end
		end
	end
	for _, ply in pairs (self.lastMen) do
		if IsValid (ply) and ply:Alive () and not WS.InCondition (ply, C.OFFENSEBUFF) then
			WS.AddCondition (ply, C.OFFENSEBUFF, FOREVER)
		end
	end
end

-- The map's RunScriptCode (logic_script).
function Controller:RunScriptCode (code)
	local text = Model.CODE [code]
	if text then WS.BroadcastText (UNASSIGNED, text) end
end

-- A new round starts the script over, as the map reset does in TF2.
Controller.rounds:AddRoundListener (Rounds.PHASE_SPAWN, Rounds.LISTEN_LOGIC, function ()
	local self = Controller
	self.game, self.ghosts, self.lastMen = Model.New (), {}, {}
	WS.Rules:Fire ("SetRedTeamRespawnWaveTime",  "0")
	WS.Rules:Fire ("SetBlueTeamRespawnWaveTime", "0")
end)

-- A stopped game ends setup too, and plays no round.
hook.Add ("WSSetup", HOOK, function (on)
	if on or WS.GameplayStopped () then return end
	Controller.game:FinishSetup ()
	Controller:Check ()
end)

-- Its loadout and model are set after this hook: a tick on they are final.
hook.Add ("PlayerSpawn", HOOK, function (ply)
	timer.Simple (0, function ()
		if IsValid (ply) and ply:Alive () then Controller:Spawned (ply) end
	end)
end)

hook.Add ("PlayerDeath", HOOK, function (victim)
	if not Controller.game.setupFinished then return end
	WS.PlaySoundTo (victim, victim, "Graveyard.YouDied")
	CheckSoon ()
end)

hook.Add ("PlayerDisconnected", HOOK, function (ply)
	Controller.ghosts [ply] = nil
	CheckSoon ()
end)

hook.Add ("EntityTakeDamage", HOOK, function (target, damage)
	if Controller.ghosts [target] or Controller.ghosts [damage:GetAttacker ()] then return true end
end)

hook.Add ("PlayerCanPickupWeapon", HOOK, function (ply)
	if Controller.ghosts [ply] then return false end
end)

hook.Add ("Think", HOOK, function ()
	local now = CurTime ()
	if now < Controller.nextHeal then return end
	Controller.nextHeal = now + HEAL_INTERVAL
	Controller:Heal ()
end)

return Controller
