-- What a player sees and does while dead, and the spectator team, on TF2 maps
-- (CTFPlayer's DYING and OBSERVER states, tf_player.cpp).
--
-- A player who dies watches their body (deathcam), then the killer (freezecam),
-- then living teammates, until the respawn wave (tf_gamerules) spawns them.
-- Spectators (team 1) watch anyone, roam freely, or use the map's
-- info_observer_points. The model of each observer lives in `observing[ply]`;
-- Apply() makes the engine's observer mode and target match it every tick.
-- The rules themselves are in foundation/spectate.lua.
local Spec = WETSAND.require("foundation.spectate")

local OBS = {
	fixed = OBS_MODE_FIXED,
	in_eye = OBS_MODE_IN_EYE,
	chase = OBS_MODE_CHASE,
	roaming = OBS_MODE_ROAMING,
}

-- The engine's own convar (gamevars_shared.cpp, TF2 default 1: dead players
-- watch their own team only); created here in case GMod's engine lacks it.
local forcecamera = GetConVar("mp_forcecamera")
	or CreateConVar("mp_forcecamera", "1", FCVAR_REPLICATED, "Restricts spectator modes for dead players")

local observing = setmetatable({}, { __mode = "k" })
local killers = setmetatable({}, { __mode = "k" })
local required = NULL

local function IsSpectator(ply)
	return ply:Team() == WETSAND.TEAM_SPECTATOR
end

-- Descriptors for foundation.spectate -----------------------------------------

local function Rules()
	return {
		forcecamera = forcecamera:GetInt(),
		teamWin = WETSAND.State() == WETSAND.STATE.TEAM_WIN,
		now = CurTime(),
	}
end

local function Kind(ent)
	if not IsValid(ent) then return nil end
	if ent:IsPlayer() then return "player" end
	if ent:GetClass() == "info_observer_point" then return "point" end
	return "entity"
end

-- CObserverPoint::CanUseObserverPoint compares the viewer's team with the
-- associated entity's; every installed map associates a team_control_point.
local function AssociatedTeam(point)
	local ent = point:AssociatedEntity()
	if not IsValid(ent) or ent:GetClass() ~= "team_control_point" then return nil end
	return WETSAND.Feature("capture"):Owner(ent)
end

local function Describe(ent)
	local kind = Kind(ent)
	if kind == "player" then
		local st = observing[ent]
		return { 
			id = ent,
			kind = kind,
			team = ent:Team(),
			alive = WETSAND.IsAliveInGame(ent),
			deathTime = st and st.deathTime 
		}
	elseif kind == "point" then
		return { 
			id = ent, 
			kind = kind,
			team = ent:TeamNum(),
			enabled = ent:IsEnabled(),
			associatedTeam = AssociatedTeam(ent),
			welcome = ent:IsDefaultWelcome() 
		}
	end
	return { 
		id = ent,
		kind = kind,
		team = WETSAND.TEAM_UNASSIGNED,
		train = ent:GetClass() == "func_tracktrain"
	}
end

local function Validator(ply)
	local viewer, rules = { id = ply, team = ply:Team() }, Rules()
	return function(desc) return Spec.IsValidTarget(viewer, desc, rules) end
end

local function IsValidTarget(ply, ent)
	return IsValid(ent) and Validator(ply)(Describe(ent))
end

-- The observable list (CTFPlayer::BuildObservableEntityList) -------------------

local function Watched(train)
	for _, watcher in ipairs(ents.FindByClass("team_train_watcher")) do
		if watcher:IsWatching(train) then return true end
	end
	return false
end

-- Observer points, then players by index, then trains that a watcher follows.
local function Observables()
	local list = ents.FindByClass("info_observer_point")
	local players = player.GetAll()
	table.sort(players, function(a, b) return a:EntIndex() < b:EntIndex() end)
	for _, ply in ipairs(players) do list[#list + 1] = ply end
	for _, train in ipairs(ents.FindByClass("func_tracktrain")) do
		if Watched(train) then list[#list + 1] = train end
	end
	return list
end

local function Descriptors(list, origin)
	local descs = {}
	for i, ent in ipairs(list) do
		descs[i] = Describe(ent)
		if origin then descs[i].dist = ent:GetPos():DistToSqr(origin) end
	end
	return descs
end

-- Target choice ------------------------------------------------------------------

-- CTFPlayer::FindNearestObservableTarget: team players look among their own
-- team, spectators among everyone.
local function NearestPlayer(ply)
	local candidates = {}
	for _, other in ipairs(player.GetAll()) do
		if IsSpectator(ply) or other:Team() == ply:Team() then candidates[#candidates + 1] = other end
	end
	local i = Spec.Nearest(Descriptors(candidates, ply:GetPos()), Validator(ply))
	return candidates[i]
end

local function WelcomePoint(ply)
	local points = ents.FindByClass("info_observer_point")
	return points[Spec.WelcomePoint(Descriptors(points), Validator(ply))]
end

-- CTFPlayer::FindInitialObserverTarget (without the contested-point views);
-- a spectator's first view is the map's welcome point (PickWelcomeObserverPoint).
local function InitialTarget(ply)
	if IsSpectator(ply) then return WelcomePoint(ply) or NearestPlayer(ply) end
	return NearestPlayer(ply)
end

local function NextTarget(ply, current, reverse)
	local list = Observables()
	local index = current and table.KeyFromValue(list, current)
	return list[Spec.FindNext(Descriptors(list), index, reverse, Validator(ply))]
end

-- CheckObserverSettings: the payload is no target during a team win, so
-- watch the observer point nearest to where it stopped.
local function PointNearest(ply, pos)
	local points = ents.FindByClass("info_observer_point")
	local descs = Descriptors(points, pos)
	return points[Spec.Nearest(descs, Validator(ply))]
end

-- CBasePlayer::SetObserverTarget in roaming mode: move just behind the
-- target's eyes, looking where it looks.
local DUCK_MINS, DUCK_MAXS = Vector(-16, -16, 0), Vector(16, 16, 36)
local function JumpBehind(ply, target)
	local ang = target:EyeAngles()
	ang.r = 0
	local start = target:EyePos()
	local tr = util.TraceHull({
		start = start, endpos = start - ang:Forward() * 64,
		mins = DUCK_MINS, maxs = DUCK_MAXS, mask = MASK_PLAYERSOLID, filter = target,
	})
	ply:SetPos(tr.HitPos)
	ply:SetEyeAngles(ang)
end

local function SetTarget(ply, st, target)
	st.target = target
	if st.mode == "roaming" and IsValid(target) and Kind(target) ~= "point" then JumpBehind(ply, target) end
end

-- CTFPlayer::CheckObserverSettings / ValidateCurrentObserverTarget: the
-- required target wins (returns true then); an invalid target is replaced,
-- except that roaming just drops it.
local function Resolve(ply, st)
	if IsValidTarget(ply, required) then
		st.target = required
		return true
	end
	if IsValidTarget(ply, st.target) then return false end
	if st.mode == "roaming" then
		st.target = nil
		return false
	end
	local old = st.target
	if IsValid(old) and old:GetClass() == "func_tracktrain" 
		and WETSAND.State() == WETSAND.STATE.TEAM_WIN then
		st.target = PointNearest(ply, old:GetPos())
	else
		st.target = nil
	end
	st.target = st.target or InitialTarget(ply) or NextTarget(ply, nil, false)
	return false
end

-- Engine state -------------------------------------------------------------------

local function Phase(st)
	return Spec.DeathPhase(CurTime(), st.deathTime, IsValid(st.killer), st.aborted)
end

-- The engine observer mode and target this model shows now.
local function View(ply, st)
	local phase = Phase(st)
	if phase == "deathcam" then return OBS_MODE_DEATHCAM, st.killer end
	if phase == "freezecam" then return OBS_MODE_FREEZECAM, st.killer end
	local mode = st.mode
	-- TF2 re-targets a roaming observer to the required target every frame,
	-- which pins them there; show it as the camera instead.
	if Resolve(ply, st) and mode == "roaming" then mode = "chase" end
	return OBS[Spec.ViewMode(mode, Kind(st.target))], st.target
end

-- CTFPlayer::SetObserverTarget on an observer point: jump to it, take its
-- angles and fov. A point parented to the cart is followed every tick.
local function FollowPoint(ply, point, snap)
	ply:SetPos(point:GetPos())
	if snap or IsValid(point:GetParent()) then ply:SetEyeAngles(point:GetAngles()) end
end

-- Only changes are sent to the engine, so the player's own camera
-- movement is not reset every tick.
local function Apply(ply, st)
	local mode, target = View(ply, st)
	local targetChanged = st.appliedTarget ~= target
	if st.appliedMode ~= mode then
		ply:Spectate(mode)
		st.appliedMode = mode
	end
	if targetChanged then
		ply:SpectateEntity(IsValid(target) and target or nil)
		st.appliedTarget = target
	end
	-- Spectate and SpectateEntity reset the fov (CBasePlayer::SetObserverMode,
	-- SetObserverTarget), so a point's fov is set after them.
	local atPoint = mode == OBS_MODE_FIXED and Kind(target) == "point"
	local entering = atPoint and (targetChanged or not st.wasAtPoint)
	if entering then ply:SetFOV(target:FOV(), 0) end
	if atPoint then
		FollowPoint(ply, target, entering)
	elseif st.wasAtPoint then
		ply:SetFOV(0, 0)
	end
	st.wasAtPoint = atPoint
end

local function Begin(ply, st)
	st.mode = "chase" -- StateEnterOBSERVER: every session starts in chase mode
	observing[ply] = st
	Apply(ply, st)
end

-- Interface ------------------------------------------------------------------------

-- Put a player straight into observing: the spectator team, or a dead player
-- skipping the deathcam. Weapons go, as in GM:PlayerSpawnAsSpectator.
function WETSAND.StartObserving(ply)
	ply:StripWeapons()
	local st = { aborted = false }
	st.target = InitialTarget(ply)
	Begin(ply, st)
end

-- Leave observer mode. The engine needs the player spawned (or killed)
-- afterwards to be solid and damageable again (Player:UnSpectate's caveat);
-- GM:PlayerSpawn also unspectates, so a respawn alone is enough.
function WETSAND.StopObserving(ply)
	local st = observing[ply]
	observing[ply] = nil
	if st and st.wasAtPoint then ply:SetFOV(0, 0) end
	ply:UnSpectate()
end

-- CTFGameRulesProxy::InputSetRequiredObserverTarget: "" clears it.
function WETSAND.SetRequiredObserverTarget(name)
	required = WETSAND.FindByName(name)
end

-- Death --------------------------------------------------------------------------

-- CTFPlayer::Event_Killed: the deathcam looks at the killer (a vehicle's
-- driver for a vehicle); suicide and world deaths have none.
local function Killer(victim, attacker)
	if not IsValid(attacker) then return nil end
	if attacker:IsVehicle() and IsValid(attacker:GetDriver()) then attacker = attacker:GetDriver() end
	if attacker == victim or not (attacker:IsPlayer() or attacker:IsNPC()) then return nil end
	return attacker
end

hook.Add("PlayerDeath", "wetsand_spectate", function(victim, inflictor, attacker)
	killers[victim] = Killer(victim, attacker)
end)

-- PostPlayerDeath follows every death, KillSilent included.
hook.Add("PostPlayerDeath", "wetsand_spectate", function(ply)
	if not WETSAND.Active() then return end
	local killer = killers[ply]
	killers[ply] = nil
	if IsSpectator(ply) then
		WETSAND.StartObserving(ply)
		return
	end
	Begin(ply, { deathTime = CurTime(), killer = killer, aborted = false })
end)

-- Spawning ends observing. A spectator is put straight back (tf_gamerules
-- spawns everyone at round start), skipping Sandbox's loadout.
hook.Add("PlayerSpawn", "wetsand_spectate", function(ply)
	if not WETSAND.Active() then return end
	if IsSpectator(ply) then
		WETSAND.StartObserving(ply)
		return true
	end
	-- Base's PlayerSpawn unspectates too, but a hook of another addon that
	-- returns first would skip it; WETSAND.IsAliveInGame needs OBS_MODE_NONE.
	WETSAND.StopObserving(ply)
end)

-- Input (spec_next / spec_prev / spec_mode) --------------------------------------

-- ClientModeShared::HandleSpectatorKeyInput binds attack to spec_next,
-- attack2 to spec_prev and jump to spec_mode.
local function CycleTarget(ply, st, reverse)
	local target = NextTarget(ply, st.target, reverse)
	if target then SetTarget(ply, st, target) end
end

-- CBasePlayer::SetObserverMode into roaming re-targets, which jumps behind
-- the target (a point's camera is already where the player stands).
local function CycleMode(ply, st)
	st.mode = Spec.NextMode(st.mode, IsSpectator(ply))
	if st.mode == "roaming" and IsValid(st.target) and Kind(st.target) ~= "point" then JumpBehind(ply, st.target) end
end

local KEYS = {
	[IN_ATTACK] = function(ply, st) CycleTarget(ply, st, false) end,
	[IN_ATTACK2] = function(ply, st) CycleTarget(ply, st, true) end,
	[IN_JUMP] = CycleMode,
}

hook.Add("KeyPress", "wetsand_spectate", function(ply, key)
	local st = observing[ply]
	local handler = KEYS[key]
	if not st or not handler then return end
	local phase = Phase(st)
	if phase == "freezecam" then
		-- CTFPlayer::AttemptToExitFreezeCam
		if Spec.CanAbortFreezeCam(CurTime(), st.deathTime) then st.aborted = true end
	elseif phase == "observer" then
		handler(ply, st)
		Apply(ply, st)
	end
end)

-- Every tick -------------------------------------------------------------------------

hook.Add("Think", "wetsand_spectate", function()
	for ply, st in pairs(observing) do
		if IsValid(ply) then Apply(ply, st) end
	end
end)

-- The observer stands where it died (or roams); the watched entity's area
-- must still reach the client for chase, in-eye and the killer cams.
hook.Add("SetupPlayerVisibility", "wetsand_spectate", function(ply)
	local st = observing[ply]
	if st and IsValid(st.appliedTarget) and Kind(st.appliedTarget) ~= "point" then
		AddOriginToPVS(st.appliedTarget:GetPos())
	end
end)
