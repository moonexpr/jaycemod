-- TF2's medic effects on the AI war's soldiers: a medic's heal beam to its
-- patient ("WSHealing", set by the controller while it heals) is TF2's
-- medigun beam in the medic's team colour, and a soldier calling for a
-- medic (ws_medic_call_end, the soldier port's CallMedic) shows TF2's
-- speech bubble over its head to its teammates, as TF2 shows a player's
-- "MEDIC!".
local BEAM_FILE, BUBBLE_FILE = "particles/medicgun_beam.pcf", "particles/speechbubbles.pcf"
local BEAMS = { [WS.TEAM_RED] = "medicgun_beam_red", [WS.TEAM_BLUE] = "medicgun_beam_blue" }
local BUBBLE = "speech_mediccall"
game.AddParticles(BEAM_FILE)
game.AddParticles(BUBBLE_FILE)
for _, name in pairs(BEAMS) do PrecacheParticleSystem(name) end
PrecacheParticleSystem(BUBBLE)

-- The beam leaves the medic's chest height and lands on the patient's
-- centre; the bubble floats BUBBLE_LIFT over the head.
local BEAM_LIFT, BUBBLE_LIFT = Vector(0, 0, 16), 16

local beams = setmetatable({}, { __mode = "k" }) -- medic -> { patient, effect }
local bubbles = setmetatable({}, { __mode = "k" }) -- soldier -> effect

local function Team(ent) return ent:GetNW2Int("ws_team", WS.TEAM_UNASSIGNED) end

local function Stop(effect)
	if effect and effect:IsValid() then effect:StopEmission() end
end

local function Head(ent)
	return ent:GetPos() + Vector(0, 0, ent:OBBMaxs().z + BUBBLE_LIFT)
end

hook.Add("Think", "ws_medic_effects", function()
	local soldiers, now = ents.FindByClass("ws_drg_*"), CurTime()
	local seen = {}
	for _, ent in ipairs(soldiers) do
		seen[ent] = true
		-- the heal beam
		local patient, beam = ent:GetNW2Entity("WSHealing"), beams[ent]
		local name = BEAMS[Team(ent)]
		if IsValid(patient) and name then
			if not beam or beam.patient ~= patient or not beam.effect:IsValid() then
				if beam then Stop(beam.effect) end
				beam = { patient = patient, effect = CreateParticleSystemNoEntity(name, ent:WorldSpaceCenter() + BEAM_LIFT) }
				beams[ent] = beam
			end
			beam.effect:SetControlPoint(0, ent:WorldSpaceCenter() + BEAM_LIFT)
			beam.effect:SetControlPoint(1, patient:WorldSpaceCenter())
		elseif beam then
			Stop(beam.effect)
			beams[ent] = nil
		end
		-- the call for a medic, to its teammates
		local calling = now < ent:GetNW2Float("ws_medic_call_end", 0) and Team(ent) == LocalPlayer():Team()
		local bubble = bubbles[ent]
		if calling then
			if not (bubble and bubble:IsValid()) then
				bubble = CreateParticleSystemNoEntity(BUBBLE, Head(ent))
				bubbles[ent] = bubble
			end
			bubble:SetControlPoint(0, Head(ent))
		elseif bubble then
			Stop(bubble)
			bubbles[ent] = nil
		end
	end
	-- soldiers gone (dead, removed) take their effects with them
	for ent, beam in pairs(beams) do
		if not seen[ent] then Stop(beam.effect) beams[ent] = nil end
	end
	for ent, bubble in pairs(bubbles) do
		if not seen[ent] then Stop(bubble) bubbles[ent] = nil end
	end
end)
