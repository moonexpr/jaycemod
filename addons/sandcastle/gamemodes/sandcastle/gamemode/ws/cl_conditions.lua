-- What players see of the conditions the server networks on players and
-- the AI war's soldiers (ws_cond_<number>, ws/sv_teams_conditions.lua), as
-- TF2's client shows them (games.gameplay.players.condition_effects): a crit
-- boost's glow on the weapon and its hum, the burning player's flames,
-- Jarate's and Mad Milk's drips, the holder's screen overlay (Jarate's, a
-- fire's, a bleed's), the mark for death over the head, the speed boost's
-- trail, the uber's material.
local Effects = WS.require("games.gameplay.players.condition_effects")
-- The local player, asked of the engine until there is one (it is NULL
-- while the client loads), then kept.
local me = NULL
local function Me()
	if not IsValid(me) then me = LocalPlayer() end
	return me
end

for _, path in ipairs(Effects.FILES) do game.AddParticles(path) end
for _, effect in ipairs(Effects.EFFECTS) do
	if effect.particle then
		for _, name in pairs(effect.particle) do PrecacheParticleSystem(name) end
	end
end

local SCAN_INTERVAL = 0.1

-- holder -> effect name -> what shows it: particle (and its owner), sound,
-- material
local showing = setmetatable({}, { __mode = "k" })
-- holder -> the effects it showed when last scanned, for its corpse
local lastShown = setmetatable({}, { __mode = "k" })

local function EndsOf(ent)
	return function(cond) return ent:GetNW2Float("ws_cond_" .. cond, 0) end
end

local function Holders()
	local holders = player.GetAll()
	for _, soldier in ipairs(ents.FindByClass("npc_nextsoldier")) do holders[#holders + 1] = soldier end
	return holders
end

local function Showing(ent)
	return ent:IsPlayer() and ent:Alive() or not ent:IsPlayer()
end

local function FirstPerson(ent)
	return ent == Me() and not ent:ShouldDrawLocalPlayer()
end

-- Where an effect's particle sits on its owner: an OVERHEAD one above its
-- eyes (C_TFPlayer::GetOverheadEffectPosition), any other at its origin.
local function Offset(owner, effect)
	if effect.on ~= Effects.OVERHEAD then return nil end
	return Vector(0, 0, owner:EyePos().z - owner:GetPos().z + effect.above)
end

-- What an effect's particle plays on: a WEAPON effect's on the holder's view
-- model in first person; none for a thirdPersonOnly one there, nor ever for
-- an othersOnly one on its holder.
local function Owner(ent, effect)
	if effect.othersOnly and ent == Me() then return NULL end
	if effect.thirdPersonOnly and FirstPerson(ent) then return NULL end
	if effect.on == Effects.BODY or effect.on == Effects.OVERHEAD then return ent end
	if FirstPerson(ent) then return ent:GetViewModel() end
	return ent.GetActiveWeapon and ent:GetActiveWeapon() or NULL
end

local function SetMaterial(ent, material)
	ent:SetMaterial(material)
	local weapon = ent.GetActiveWeapon and ent:GetActiveWeapon()
	if IsValid(weapon) then weapon:SetMaterial(material) end
end

local function Stop(ent, shown)
	if shown.particle and shown.particle:IsValid() then shown.particle:StopEmission() end
	if shown.sound then shown.sound:Stop() end
	if shown.material and IsValid(ent) then SetMaterial(ent, "") end
end

local function Show(ent, effect, shown)
	-- a soldier's team is its ws_team (WS.SetTeamMember)
	local team = ent:IsPlayer() and ent:Team() or ent:GetNW2Int("ws_team", WS.TEAM_UNASSIGNED)
	local name = Effects.Particle(effect, team)
	if name then
		local owner = Owner(ent, effect)
		if owner ~= shown.owner or not (shown.particle and shown.particle:IsValid()) then
			if shown.particle and shown.particle:IsValid() then shown.particle:StopEmission() end
			shown.owner = owner
			shown.particle = IsValid(owner) and owner:CreateParticleEffect(name, {
				{ entity = owner, attachtype = PATTACH_ABSORIGIN_FOLLOW, position = Offset(owner, effect) },
			}) or nil
		end
	end
	if effect.loop and not shown.sound then
		shown.sound = CreateSound(ent, effect.loop)
		shown.sound:Play()
	end
	local material = Effects.Material(effect, team)
	if material then
		shown.material = material
		SetMaterial(ent, material)
	end
end

local nextScan = 0
hook.Add("Think", "ws_condition_effects", function()
	local now = CurTime()
	if now < nextScan then return end
	nextScan = now + SCAN_INTERVAL
	for ent, effects in pairs(showing) do
		if not IsValid(ent) then
			for _, shown in pairs(effects) do Stop(ent, shown) end
			showing[ent] = nil
		end
	end
	for _, ent in ipairs(Holders()) do
		local wanted = {}
		if Showing(ent) then
			for _, effect in ipairs(Effects.Shown(EndsOf(ent), now)) do wanted[effect.name] = effect end
		end
		if next(wanted) then lastShown[ent] = { at = now, effects = wanted } end
		local effects = showing[ent] or {}
		for name, shown in pairs(effects) do
			if not wanted[name] then
				Stop(ent, shown)
				effects[name] = nil
			end
		end
		for name, effect in pairs(wanted) do
			effects[name] = effects[name] or {}
			Show(ent, effect, effects[name])
		end
		showing[ent] = next(effects) and effects or nil
	end
end)

-- One who dies holding an effect with a corpse particle (burning) leaves a
-- ragdoll that burns on for CORPSE_SECONDS, as C_TFRagdoll's does; the
-- holder was last scanned within CORPSE_GRACE of its death. Players' and
-- engine ragdolls come through CreateClientsideRagdoll, the NPC ragdolls
-- this gamemode builds through ws/cl_npc_ragdolls.lua.
local CORPSE_SECONDS, CORPSE_GRACE = 10, 0.5

function WS.CorpseEffects(body, ragdoll)
	local last = lastShown[body]
	if not (last and CurTime() - last.at <= CORPSE_GRACE) then return end
	for _, effect in pairs(last.effects) do
		if effect.corpse then
			local particle = ragdoll:CreateParticleEffect(effect.corpse, {
				{ entity = ragdoll, attachtype = PATTACH_ABSORIGIN_FOLLOW },
			})
			timer.Simple(CORPSE_SECONDS, function()
				if particle:IsValid() then particle:StopEmission() end
			end)
		end
	end
end

hook.Add("CreateClientsideRagdoll", "ws_condition_effects", WS.CorpseEffects)

-- The holder's own screen: Jarate's yellow, a fire's heat, a bleed's red.
hook.Add("RenderScreenspaceEffects", "ws_condition_effects", function()
	local ply = Me()
	if not (IsValid(ply) and ply:Alive()) then return end
	for _, effect in ipairs(Effects.Shown(EndsOf(ply), CurTime())) do
		if effect.overlay then DrawMaterialOverlay(effect.overlay, 0) end
	end
end)
