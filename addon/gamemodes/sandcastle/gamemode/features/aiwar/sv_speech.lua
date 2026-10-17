-- Part of the AI war controller (sv.lua): its soldiers speak the concepts
-- a cart's watcher raises (WSCartConcept: team_train_watcher, as TF2's has
-- its players speak them), by the response rules of foundation.aiwar.speech.
-- The cart's own team is on offense, its enemy on defense; a concept for
-- the pushers goes to the soldiers in the cart's capture area. A soldier
-- speaks one line at a time, and waits SPEECH_DELAY after it (TF2's
-- defaultdelay); every soldier shares the groups' repeats, as TF2's players
-- do. ns_speech_debug prints each line and the rule that chose it (print
-- lines are placeholders, heard only so).
local Controller = ...
local Response = WS.require("foundation.core.response")
local Speech = WS.require("foundation.aiwar.speech")
local Payload = WS.require("foundation.payload")

local DEBUG = CreateConVar("ns_speech_debug", "0", { FCVAR_ARCHIVE },
	"1: print each AI war soldier's line for a cart concept, and the rule that chose it", 0, 1)

local SPEECH_DELAY = 3
local SPEECH_LEVEL = 80 -- SNDLVL_TALKING

local system = Speech.System()
local memory = Response.Memory()

-- The soldier's speaker: its contexts, and when it may speak again.
local function Speaker(entry)
	entry.speaker = entry.speaker or { memory = memory, contexts = Response.Contexts(), busyUntil = 0 }
	return entry.speaker
end

-- The soldier speaks concept in role, if a rule has it say something and
-- it is not still speaking.
function Controller:SpeakConcept(ent, concept, role, blocked, now)
	local entry = self.soldiers[ent]
	-- an enlisted NPC that is no DrGBase soldier has no voice
	local voice = ent.NSVoiceLines and ent.NSVoiceLines.name
	if not (voice and entry.soldier:IsAlive()) or ent.NSDormant then return end
	local speaker = Speaker(entry)
	if now < speaker.busyUntil then return end
	local said = system:Speak(speaker, concept, Speech.Criteria(role, voice, math.random(0, 100), blocked), math.random, now)
	if not said then return end
	local line, length = said.response, 0
	if line.kind == "speak" then
		ent:EmitSound(line.value, SPEECH_LEVEL)
		length = SoundDuration(line.value)
	end
	speaker.busyUntil = now + length + SPEECH_DELAY
	if DEBUG:GetBool() then
		print(string.format("[ns speech] #%d %s on %s, %s%s: %s %s (%s)", ent:EntIndex(), voice, role, concept,
			blocked and " (cut off)" or "", line.kind, line.value, said.rule))
	end
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
