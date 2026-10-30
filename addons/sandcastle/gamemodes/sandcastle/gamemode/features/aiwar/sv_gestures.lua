-- Part of the AI war controller (sv.lua): its soldiers' gestures
-- (nextsoldier.gestures), each soldier's memory of them in its entry. A
-- NextBot soldier plays one on a layer of its own at the gesture's rate; a
-- bot player as a player taunts (the animation event every client plays),
-- at the model's own rate. A model without the act (a vortigaunt) plays
-- nothing. A taunt (nextsoldier.gestures' Still) holds the soldier still
-- while it plays. A soldier nods at a teammate's kill or capture near it, and
-- celebrates once calm after wiping out a squad; the greetings, the battle
-- stance (sv_speech.lua) and the grenades (sv_gadgets.lua) gesture too.
local Controller = ...
local Gestures = nextsoldier.gestures
local Speech = nextsoldier.speech

local function Memory(entry)
	if not entry.gestures then entry.gestures = Gestures.Memory() end
	return entry.gestures
end

function Controller:Gesture(ent, occasion, now)
	local entry = self.soldiers[ent]
	if not (entry and entry.soldier:IsAlive()) then return end
	local name, rate = Memory(entry):Play(occasion, now, math.random)
	if not name then return end
	local act = _G[name]
	local sequence = ent:SelectWeightedSequence(act)
	if sequence < 0 then return end
	-- a taunt is the whole body's: it stands still while it plays
	if Gestures.Still(name) then
		local playing = ent:IsPlayer() and 1 or rate
		entry.soldier:HoldStill(ent:SequenceDuration(sequence) / playing)
	end
	if ent:IsPlayer() then
		ent:DoAnimationEvent(act)
		return
	end
	ent:SetLayerPlaybackRate(ent:AddGesture(act, true), rate)
end

-- The living soldier of team nearest pos within Speech.ALLY_DOWN_RANGE,
-- other than except; or nil.
local function NearestWitness(team, pos, except)
	local witness, nearest = nil, math.huge
	for ent, entry in pairs(Controller.soldiers) do
		if ent ~= except and IsValid(ent) and entry.soldier.team == team and entry.soldier:IsAlive() then
			local distance = ent:GetPos():Distance(pos)
			if distance < nearest and Speech.WitnessesFall(distance) then witness, nearest = ent, distance end
		end
	end
	return witness
end

-- A kill by a soldier or a player: the killer, if a soldier, counts it
-- toward a squad wiped out, and the nearest teammate of the killer that saw
-- it nods. Anything else (a grenade, the world) is no one's teammate.
local function Killed(victim, attacker)
	if not Controller.war or not IsValid(attacker) or attacker == victim then return end
	local now = CurTime()
	local killer = Controller.soldiers[attacker]
	if killer then Memory(killer):Killed(now)
	elseif not attacker:IsPlayer() then return end
	local team = killer and killer.soldier.team or attacker:Team()
	local witness = NearestWitness(team, victim:GetPos(), attacker)
	if witness then Controller:Gesture(witness, Gestures.AGREE, now) end
end

hook.Add("OnNPCKilled", "ws_aiwar_gestures", Killed)
hook.Add("PlayerDeath", "ws_aiwar_gestures", function(victim, _, attacker) Killed(victim, attacker) end)

-- A capture: the nearest soldier of the capturing team nods.
hook.Add("WSPointCaptured", "ws_aiwar_gestures", function(point, team)
	if not Controller.war or not IsValid(point) then return end
	local witness = NearestWitness(team, point:GetPos())
	if witness then Controller:Gesture(witness, Gestures.AGREE, CurTime()) end
end)

hook.Add("WSFlagCaptured", "ws_aiwar_gestures", function(flag, team, activator)
	if not Controller.war then return end
	local at = IsValid(activator) and activator or flag
	if not IsValid(at) then return end
	local witness = NearestWitness(team, at:GetPos(), activator)
	if witness then Controller:Gesture(witness, Gestures.AGREE, CurTime()) end
end)

-- Every CALM_INTERVAL, each soldier out of a fight that wiped out a squad
-- in it (Gestures' Calm) celebrates.
local CALM_INTERVAL = 0.5
local nextCalm = 0

hook.Add("Think", "ws_aiwar_celebrations", function()
	local now = CurTime()
	if not Controller.war or now < nextCalm then return end
	nextCalm = now + CALM_INTERVAL
	for ent, entry in pairs(Controller.soldiers) do
		if IsValid(ent) and entry.gestures and entry.soldier:IsAlive() and not entry.soldier:HasEnemy()
			and entry.gestures:Calm(now) then
			Controller:Gesture(ent, Gestures.CELEBRATE, now)
		end
	end
end)
