-- Part of the AI war controller (sv.lua): its soldiers speak the concepts
-- a cart's watcher raises (WSCartConcept: team_train_watcher, as TF2's has
-- its players speak them), by the response rules of the responserules
-- addon (addons/responserules: its ResponseRules service, and its rules by
-- the speaker model's affiliation). The cart's own team is on offense, its
-- enemy on defense; a concept for the pushers goes to the soldiers in the
-- cart's capture area. A soldier speaks one line at a time and waits,
-- after it, the delay its rule's group sets; the group sets how loud it is
-- too. A soldier also says it is ready in its battle stance, calls out an
-- enemy it has just spotted, calls for a medic when hurt, and greets a
-- teammate player walking past, heard by that player alone. And the squad
-- chatters (Speech.CONCEPT_ENEMY_KILLED and the rest): a kill, a teammate
-- down, an enemy slipped out of sight, the radio between fights.
local Controller = ...
local Speech = WS.require("games.nextsoldier.speech")
local Payload = WS.require("features.payload.model")
local Teams = WS.require("games.gameplay.teams")

-- The AI war needs the responserules addon, as it needs DrGBase.
local Rules = ResponseRules or error("the AI war's speech needs the responserules addon (addons/responserules)")

-- The soldier's speaker: its contexts, and when it may speak again.
local function Speaker(entry)
	if not entry.speaker then
		entry.speaker = Rules:Speaker()
		entry.speaker.busyUntil = 0
	end
	return entry.speaker
end

-- The soldier speaks concept in role, if a rule has it say something and
-- it is not still speaking; to listener alone when given (a greeting).
function Controller:SpeakConcept(ent, concept, role, blocked, now, listener)
	local entry = self.soldiers[ent]
	-- an enlisted NPC that is no DrGBase soldier, or a model with no voice, says nothing
	local voice = ent.NSVoiceLines
	if not (voice and voice.name and entry.soldier:IsAlive()) or ent.NSDormant then return end
	local speaker = Speaker(entry)
	if now < speaker.busyUntil then return end
	local criteria = Speech.Criteria(voice, role, math.random(0, 100), blocked)
	local said = Rules:Speak(speaker, concept, criteria, now, string.format("#%d %s %s on %s", ent:EntIndex(), voice.affiliation, voice.name, role))
	if not said then return end
	local line, length = said.response, 0
	if line.kind == "speak" then
		local filter
		if listener then
			filter = RecipientFilter()
			filter:AddPlayer(listener)
		end
		ent:EmitSound(line.value, said.soundLevel, 100, 1, CHAN_VOICE, 0, 0, filter)
		length = SoundDuration(line.value)
	end
	speaker.busyUntil = now + length + said.delay
end

-- A soldier's team is on offense when it has a cart, as for the cart's lines.
function Controller:RoleOf(entry)
	local field = self.war and self.war:Field()
	return field and field.carts and field.carts[entry.soldier.team] and Speech.OFFENSE or Speech.DEFENSE
end

-- A soldier settled into its battle stance (Soldier:Pose, in setup) may say
-- it is ready.
function Controller:AnnounceStance(ent)
	local entry = self.soldiers[ent]
	if not entry then return end
	self:SpeakConcept(ent, Speech.CONCEPT_BATTLE_STANCE, self:RoleOf(entry), false, CurTime())
end

-- A hurt soldier calling for a medic (the soldier port's CallMedic) says
-- so, to all near.
function Controller:CallMedicLine(ent)
	local entry = self.soldiers[ent]
	if not entry then return end
	self:SpeakConcept(ent, Speech.CONCEPT_CALL_MEDIC, self:RoleOf(entry), false, CurTime())
end

-- A soldier calling out what it is doing (the soldier port's Announce:
-- falling back to cover, going for health) says so, to all near.
function Controller:AnnounceLine(ent, concept)
	local entry = self.soldiers[ent]
	if not entry then return end
	self:SpeakConcept(ent, concept, self:RoleOf(entry), false, CurTime())
end

-- A soldier that has just spotted a new enemy (ws_drg_soldier's
-- OnNewEnemy) may call it out, to all near.
hook.Add("WSSoldierContact", "ws_aiwar_speech", function(ent)
	if not Controller.war then return end
	local entry = Controller.soldiers[ent]
	if not entry then return end
	Controller:SpeakConcept(ent, Speech.CONCEPT_ENEMY_SPOTTED, Controller:RoleOf(entry), false, CurTime())
end)

-- Every GREET_INTERVAL, each soldier out of a fight that a living teammate
-- player is passing (Speech.Passes) may greet that player, heard by them alone.
local GREET_INTERVAL = 0.5
local nextGreet = 0

hook.Add("Think", "ws_aiwar_greetings", function()
	local now = CurTime()
	if not Controller.war or now < nextGreet then return end
	nextGreet = now + GREET_INTERVAL
	for _, ply in ipairs(player.GetHumans()) do
		if ply:Alive() then
			local team, pos, speed = WS.TeamOf(ply), ply:GetPos(), ply:GetVelocity():Length2D()
			for ent, entry in pairs(Controller.soldiers) do
				if IsValid(ent) and entry.soldier.team == team and not entry.soldier:HasEnemy()
					and Speech.Passes(ent:GetPos():Distance(pos), speed) then
					Controller:SpeakConcept(ent, Speech.CONCEPT_PLAYER_PASSING, Controller:RoleOf(entry), false, now, ply)
				end
			end
		end
	end
end)

hook.Add("WSCartConcept", "ws_aiwar_speech", function(watcher, concept, audience, blocked)
	if not Controller.war then return end
	local area = nil
	if audience == Payload.AUDIENCE_PUSHERS then
		area = watcher:CartArea()
		if not IsValid(area) then return end
	end
	local mins, maxs
	if area then mins, maxs = area:WorldSpaceAABB() end
	local now = CurTime()
	for ent, entry in pairs(Controller.soldiers) do
		if IsValid(ent) and (not area or ent:WorldSpaceCenter():WithinAABox(mins, maxs)) then
			local role = entry.soldier.team == watcher.team and Speech.OFFENSE or Speech.DEFENSE
			Controller:SpeakConcept(ent, concept, role, blocked, now)
		end
	end
end)

local function Alive(ent)
	if ent:IsPlayer() then return ent:Alive() end
	return ent:Health() > 0
end

-- Someone of a team fell: a soldier that killed them (an enemy) says so, and
-- the nearest living soldier of their team that saw it fall
-- (Speech.WitnessesFall) calls the loss.
local function Fell(victim, attacker)
	if not Controller.war then return end
	local team, now = WS.LastTeamNumber(victim), CurTime()
	local killer = IsValid(attacker) and Controller.soldiers[attacker]
	if killer and Teams.EnemyOf(killer.soldier.team) == team then
		Controller:SpeakConcept(attacker, Speech.CONCEPT_ENEMY_KILLED, Controller:RoleOf(killer), false, now)
	end
	local pos, witness, nearest = victim:GetPos(), nil, math.huge
	for ent, entry in pairs(Controller.soldiers) do
		if ent ~= victim and IsValid(ent) and entry.soldier.team == team and entry.soldier:IsAlive() then
			local distance = ent:GetPos():Distance(pos)
			if distance < nearest and Speech.WitnessesFall(distance) then witness, nearest = ent, distance end
		end
	end
	if witness then Controller:SpeakConcept(witness, Speech.CONCEPT_ALLY_DOWN, Controller:RoleOf(Controller.soldiers[witness]), false, now) end
end

hook.Add("OnNPCKilled", "ws_aiwar_speech", Fell)
hook.Add("PlayerDeath", "ws_aiwar_speech", function(victim, _, attacker) Fell(victim, attacker) end)

-- A soldier whose last enemy slipped out of sight still alive (not one it
-- killed) may say it lost contact.
hook.Add("WSSoldierContactLost", "ws_aiwar_speech", function(ent, enemy)
	if not Controller.war or not (IsValid(enemy) and Alive(enemy)) then return end
	local entry = Controller.soldiers[ent]
	if not entry then return end
	Controller:SpeakConcept(ent, Speech.CONCEPT_CONTACT_LOST, Controller:RoleOf(entry), false, CurTime())
end)

-- Every Speech.IDLE_INTERVAL, one soldier of each team out of a fight, drawn
-- at random, may talk on the radio.
local nextIdle = 0

hook.Add("Think", "ws_aiwar_idle_chatter", function()
	local now = CurTime()
	if not Controller.war or now < nextIdle then return end
	nextIdle = now + Speech.IDLE_INTERVAL
	local calm = {}
	for ent, entry in pairs(Controller.soldiers) do
		if IsValid(ent) and not ent.NSDormant and entry.soldier:IsAlive() and not entry.soldier:HasEnemy() then
			local team = entry.soldier.team
			calm[team] = calm[team] or {}
			calm[team][#calm[team] + 1] = ent
		end
	end
	for _, soldiers in pairs(calm) do
		local ent = soldiers[math.random(#soldiers)]
		Controller:SpeakConcept(ent, Speech.CONCEPT_IDLE, Controller:RoleOf(Controller.soldiers[ent]), false, now)
	end
end)
