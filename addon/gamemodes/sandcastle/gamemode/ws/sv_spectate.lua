-- What a player sees and does while dead, and the spectator team, on TF2 maps
-- (CTFPlayer's DYING and OBSERVER states, tf_player.cpp).
--
-- A player who dies watches their body (deathcam), then the killer (freezecam),
-- then living teammates, until the respawn wave (tf_gamerules) spawns them.
-- Spectators (team 1) watch anyone, NPCs too, roam freely, or use the map's
-- info_observer_points. An admin may spectate an NPC from its right-click
-- (ws_spectate_npc) while in play, and Reload brings them back. The model of each observer lives in `observing[ply]`;
-- Apply() makes the engine's observer mode and target match it every tick.
-- The rules themselves are in foundation/spectate.lua.
local Spec = WS.require("foundation.spectate")

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
	return ply:Team() == WS.TEAM_SPECTATOR
end

-- A player in play watching an NPC (ws_spectate_npc) observes as a
-- spectator does: anyone, in any mode.
local function ObservesAsSpectator(ply)
	local st = observing[ply]
	return IsSpectator(ply) or (st ~= nil and st.watch ~= nil)
end

-- Descriptors for foundation.spectate -----------------------------------------

local function Rules()
	return {
		forcecamera = forcecamera:GetInt(),
		teamWin = WS.State() == WS.STATE.TEAM_WIN,
		now = CurTime(),
	}
end

local function Kind(ent)
	if not IsValid(ent) then return nil end
	if ent:IsPlayer() then return "player" end
	if ent:GetClass() == "info_observer_point" then return "point" end
	if ent:IsNPC() or ent:IsNextBot() then return "npc" end
	return "entity"
end

-- CObserverPoint::CanUseObserverPoint compares the viewer's team with the
-- associated entity's; every installed map associates a team_control_point.
local function AssociatedTeam(point)
	local ent = point:AssociatedEntity()
	if not IsValid(ent) or ent:GetClass() ~= "team_control_point" then return nil end
	return WS.Feature("capture"):Owner(ent)
end

local function Describe(ent)
	local kind = Kind(ent)
	if kind == "player" then
		local st = observing[ent]
		return { 
			id = ent,
			kind = kind,
			team = ent:Team(),
			alive = WS.IsAliveInGame(ent),
			deathTime = st and st.deathTime 
		}
	elseif kind == "npc" then
		return {
			id = ent,
			kind = kind,
			team = WS.TeamNumber(ent),
			alive = ent:Health() > 0,
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
		team = WS.TEAM_UNASSIGNED,
		train = ent:GetClass() == "func_tracktrain"
	}
end

local function Validator(ply)
	local team = ObservesAsSpectator(ply) and WS.TEAM_SPECTATOR or ply:Team()
	local viewer, rules = { id = ply, team = team }, Rules()
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

local function ByIndex(a, b)
	return a:EntIndex() < b:EntIndex()
end

-- Observer points, then players by index, then NPCs by index, then trains
-- that a watcher follows.
local function Observables()
	local list = ents.FindByClass("info_observer_point")
	local players = player.GetAll()
	table.sort(players, ByIndex)
	for _, ply in ipairs(players) do list[#list + 1] = ply end
	local npcs = {}
	for _, ent in ents.Iterator() do
		if ent:IsNPC() or ent:IsNextBot() then npcs[#npcs + 1] = ent end
	end
	table.sort(npcs, ByIndex)
	for _, npc in ipairs(npcs) do list[#list + 1] = npc end
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
		if ObservesAsSpectator(ply) or other:Team() == ply:Team() then candidates[#candidates + 1] = other end
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
	-- the NPC watched died or went: roam on from where its camera was
	local camera = st.npcCamera
	if camera then
		st.npcCamera = nil
		st.mode, st.target = "roaming", nil
		ply:SetPos(camera.origin - ply:GetViewOffset())
		ply:SetEyeAngles(camera.angles)
		return false
	end
	if st.mode == "roaming" then
		st.target = nil
		return false
	end
	local old = st.target
	if IsValid(old) and old:GetClass() == "func_tracktrain" 
		and WS.State() == WS.STATE.TEAM_WIN then
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
	-- Resolve may turn an observer whose NPC died to roaming, so the mode is read after it
	local pinned = Resolve(ply, st)
	local mode = st.mode
	-- TF2 re-targets a roaming observer to the required target every frame,
	-- which pins them there; show it as the camera instead.
	if pinned and mode == "roaming" then mode = "chase" end
	local view = Spec.ViewMode(mode, Kind(st.target))
	-- where the camera on a watched NPC is (WS.NpcCamera), to roam from if it dies
	if Kind(st.target) == "npc" and (view == "in_eye" or view == "chase") then
		local origin, angles = WS.NpcCamera(st.target, view == "in_eye", ply:EyeAngles())
		st.npcCamera = {
			origin = origin,
			angles = angles,
		}
	else
		st.npcCamera = nil
	end
	return OBS[view], st.target
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
function WS.StartObserving(ply)
	ply:StripWeapons()
	local st = { aborted = false }
	st.target = InitialTarget(ply)
	Begin(ply, st)
end

-- Leave observer mode. The engine needs the player spawned (or killed)
-- afterwards to be solid and damageable again (Player:UnSpectate's caveat);
-- GM:PlayerSpawn also unspectates, so a respawn alone is enough.
function WS.StopObserving(ply)
	local st = observing[ply]
	observing[ply] = nil
	if st and st.wasAtPoint then ply:SetFOV(0, 0) end
	ply:UnSpectate()
end

-- CTFGameRulesProxy::InputSetRequiredObserverTarget: "" clears it.
function WS.SetRequiredObserverTarget(name)
	required = WS.FindByName(name)
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

hook.Add("PlayerDeath", "ws_spectate", function(victim, inflictor, attacker)
	killers[victim] = Killer(victim, attacker)
end)

-- PostPlayerDeath follows every death, KillSilent included.
hook.Add("PostPlayerDeath", "ws_spectate", function(ply)
	if not WS.Active() then return end
	local killer = killers[ply]
	killers[ply] = nil
	if IsSpectator(ply) then
		WS.StartObserving(ply)
		return
	end
	Begin(ply, { deathTime = CurTime(), killer = killer, aborted = false })
end)

-- Spawning ends observing. A spectator is put straight back (tf_gamerules
-- spawns everyone at round start), skipping Sandbox's loadout.
hook.Add("PlayerSpawn", "ws_spectate", function(ply)
	if not WS.Active() then return end
	if IsSpectator(ply) then
		WS.StartObserving(ply)
		return true
	end
	-- Base's PlayerSpawn unspectates too, but a hook of another addon that
	-- returns first would skip it; WS.IsAliveInGame needs OBS_MODE_NONE.
	WS.StopObserving(ply)
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
	st.mode = Spec.NextMode(st.mode, ObservesAsSpectator(ply))
	if st.mode == "roaming" and IsValid(st.target) and Kind(st.target) ~= "point" then JumpBehind(ply, st.target) end
end

-- Spectating an NPC (ws_spectate_npc) ------------------------------------------

-- Where a player in play stood, and what they carried, to come back to.
local function Whereabouts(ply)
	local weapons = {}
	for i, weapon in ipairs(ply:GetWeapons()) do weapons[i] = weapon:GetClass() end
	local active = ply:GetActiveWeapon()
	return {
		pos = ply:GetPos(),
		ang = ply:EyeAngles(),
		weapons = weapons,
		active = IsValid(active) and active:GetClass() or nil,
		health = ply:Health(),
		armor = ply:Armor(),
	}
end

-- An observer turns to the NPC; a player in play starts observing it.
function WS.SpectateNpc(ply, npc)
	local st = observing[ply]
	if st then
		SetTarget(ply, st, npc)
		Apply(ply, st)
		return
	end
	local back = Whereabouts(ply)
	ply:StripWeapons()
	Begin(ply, {
		aborted = false,
		watch = back,
		target = npc,
	})
	ply:ChatPrint("Spectating #" .. npc:EntIndex() .. ": attack and attack2 for the next or previous, jump for the view, "
		.. "reload to come back")
end

-- Back where they stood, as they were (the engine needs a spawn to make them
-- solid again: Player:UnSpectate).
local function StopWatching(ply, st)
	local back = st.watch
	WS.StopObserving(ply)
	ply:Spawn()
	ply:SetPos(back.pos)
	ply:SetEyeAngles(back.ang)
	ply:StripWeapons()
	for _, class in ipairs(back.weapons) do ply:Give(class) end
	if back.active then ply:SelectWeapon(back.active) end
	ply:SetHealth(back.health)
	ply:SetArmor(back.armor)
end

-- Each returns true when the player no longer observes.
local KEYS = {
	[IN_ATTACK] = function(ply, st) CycleTarget(ply, st, false) end,
	[IN_ATTACK2] = function(ply, st) CycleTarget(ply, st, true) end,
	[IN_JUMP] = CycleMode,
	[IN_RELOAD] = function(ply, st)
		if not st.watch then return false end
		StopWatching(ply, st)
		return true
	end,
}

concommand.Add("ws_spectate_npc", function(ply, _, args)
	if not IsValid(ply) or not ply:IsAdmin() then return end
	local npc = Entity(tonumber(args[1] or "") or -1)
	if not (IsValid(npc) and (npc:IsNPC() or npc:IsNextBot()) and npc:Health() > 0) then
		ply:ChatPrint("ws_spectate_npc: no living NPC #" .. tostring(args[1]))
		return
	end
	WS.SpectateNpc(ply, npc)
end, nil, "Spectate the NPC with this entity index (admins); in play, reload brings you back")

hook.Add("KeyPress", "ws_spectate", function(ply, key)
	local st = observing[ply]
	local handler = KEYS[key]
	if not st or not handler then return end
	local phase = Phase(st)
	if phase == "freezecam" then
		-- CTFPlayer::AttemptToExitFreezeCam
		if Spec.CanAbortFreezeCam(CurTime(), st.deathTime) then st.aborted = true end
	elseif phase == "observer" then
		if not handler(ply, st) then Apply(ply, st) end
	end
end)

-- Every tick -------------------------------------------------------------------------

hook.Add("Think", "ws_spectate", function()
	for ply, st in pairs(observing) do
		if IsValid(ply) then Apply(ply, st) end
	end
end)

-- The observer stands where it died (or roams); the watched entity's area
-- must still reach the client for chase, in-eye and the killer cams.
hook.Add("SetupPlayerVisibility", "ws_spectate", function(ply)
	local st = observing[ply]
	if st and IsValid(st.appliedTarget) and Kind(st.appliedTarget) ~= "point" then
		AddOriginToPVS(st.appliedTarget:GetPos())
	end
end)
