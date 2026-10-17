-- Part of the AI war controller (sv.lua): its soldiers speak the concepts
-- a cart's watcher raises (WSCartConcept: team_train_watcher, as TF2's has
-- its players speak them), by the response rules of the responserules
-- addon (addons/responserules: its ResponseRules service, and its rules by
-- the speaker model's affiliation). The cart's own team is on offense, its
-- enemy on defense; a concept for the pushers goes to the soldiers in the
-- cart's capture area. A soldier speaks one line at a time and waits,
-- after it, the delay its rule's group sets; the group sets how loud it is
-- too.
local Controller = ...
local Speech = WS.require("foundation.aiwar.speech")
local Payload = WS.require("foundation.payload")

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
-- it is not still speaking.
function Controller:SpeakConcept(ent, concept, role, blocked, now)
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
		ent:EmitSound(line.value, said.soundLevel)
		length = SoundDuration(line.value)
	end
	speaker.busyUntil = now + length + said.delay
end

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
