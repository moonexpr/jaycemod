-- The npc feature's view: the boss health bar (TF2's boss meter,
-- CHudBossHealthMeter, in its own images), drawn from the ws_boss_health
-- Global2 the npc controller networks (0 hides it); the bosses' cues; the
-- bomb heads' bombs; and Merasmus's body effects (C_Merasmus). The particle
-- files are sh.lua's, in both realms.
local BOSS_HEALTH = "ws_boss_health"
local Hud = WS.require("ws.tf_hud")

-- TF2's boss meter as cooler-hud draws it (CHudBossHealthMeter; ws.tf_hud's
-- BossMeter): its bar, cut to the boss's health, under its frame.
local BAR = Material(Hud.BOSS_BAR)

local View = {}

-- ShouldDraw: while a boss has health, never in the freeze cam; OnTick:
-- lower while the player is dead or watching.
function View:DrawBossHealth(w, h)
	local fraction = GetGlobal2Float(BOSS_HEALTH, 0)
	local ply = LocalPlayer()
	if fraction <= 0 or not IsValid(ply) or ply:GetObserverMode() == OBS_MODE_FREEZECAM then return end
	local watching = not ply:Alive() or ply:GetObserverMode() ~= OBS_MODE_NONE
	local unit = Hud.Unit(h)
	local meter = Hud.BossMeter(w, unit, watching, math.min(fraction, 1))
	local bar = meter.bar
	surface.SetDrawColor(255, 255, 255, 255)
	surface.SetMaterial(BAR)
	surface.DrawTexturedRectUV(bar.x, bar.y, bar.w, bar.h, 0, 0, meter.u, 1)
	WS.TFHud.DrawBossFrame(meter.frame, unit)
end

WS.HUD:Add("game.notices.boss_health", WS.HUD_ORDER.NOTICES, function()
	View:DrawBossHealth(ScrW(), ScrH())
end)

-- The bosses' game events, as ClientModeTFNormal::FireGameEvent takes
-- them: the cue's sound on the local player (the Horsemann's and
-- MONOCULUS's music and lines), and its line in the chat. A player the
-- server named whom this client cannot see is "Someone".
local BossEvents = WS.require("features.npc.boss_events")
local UNKNOWN_PLAYER = "Someone"

local function NameOf(ply)
	return IsValid(ply) and ply:Nick() or UNKNOWN_PLAYER
end

function View:PlayBossCue(name, fields)
	local cue = BossEvents.Cue(name, fields, NameOf)
	local ply = LocalPlayer()
	if IsValid(ply) and cue.sound then ply:EmitSound(cue.sound) end
	local color = cue.color and Color(cue.color.r, cue.color.g, cue.color.b) or color_white
	chat.AddText(color, cue.text)
end

for _, name in ipairs(BossEvents.NAMES) do
	WS.Events.Listen(name, "ws_npc_view", function(fields)
		View:PlayBossCue(name, fields)
	end)
end

-------------------------------------------------------------------------------
-- Bomb heads (C_TFPlayer::HalloweenBombHeadUpdate): the bomb sits on the
-- player's head, its skin darkening as the time runs out. TF2 bone-merges
-- the hat onto its class models; GMod's player models have other bones, so
-- the hat is drawn at the head bone.

local HEAD_BONE = "ValveBiped.Bip01_Head1"
local bombHeads = {} -- player -> { ends, hat }

local function DropBomb(ply)
	local bomb = bombHeads[ply]
	if bomb == nil then return end
	if IsValid(bomb.hat) then bomb.hat:Remove() end
	bombHeads[ply] = nil
end

function View:SetBombHead(ply, duration)
	DropBomb(ply)
	if not IsValid(ply) or duration <= 0 then return end
	local hat = ClientsideModel(BossEvents.BOMB_HAT_MODEL)
	hat:SetNoDraw(true)
	bombHeads[ply] = {
		ends = CurTime() + duration,
		hat = hat,
	}
	if ply == LocalPlayer() then
		ply:PrintMessage(HUD_PRINTCENTER, BossEvents.BOMB_HEAD_TEXT)
		ply:EmitSound(BossEvents.BOMB_HEAD_SOUND)
	end
end

function View:DrawBombHead(ply)
	local bomb = bombHeads[ply]
	if bomb == nil then return end
	local left = bomb.ends - CurTime()
	if left <= 0 or not ply:Alive() then
		DropBomb(ply)
		return
	end
	local bone = ply:LookupBone(HEAD_BONE)
	local pos, ang = ply:EyePos(), ply:EyeAngles()
	if bone then pos, ang = ply:GetBonePosition(bone) end
	bomb.hat:SetPos(pos)
	bomb.hat:SetAngles(ang)
	bomb.hat:SetSkin(BossEvents.BombHeadStage(left))
	bomb.hat:DrawModel()
end

WS.Events.Listen(BossEvents.HALLOWEEN_BOMB_HEAD, "ws_npc_view", function(fields)
	View:SetBombHead(fields.player, fields.duration)
end)

hook.Add("PostPlayerDraw", "ws_bomb_heads", function(ply)
	View:DrawBombHead(ply)
end)

-------------------------------------------------------------------------------
-- Merasmus's body effects (C_Merasmus::OnDataChanged), from the state the
-- merasmus entity networks: a glow while revealed, the book in his hand
-- while he rains bombs, and stars over his head while stunned.

local MERASMUS_EFFECTS = {
	{
		key = "revealed",
		particle = "merasmus_ambient_body",
	},
	{
		key = "aoeAttack",
		particle = "merasmus_book_attack",
		attachment = "effect_hand_R",
	},
	{
		key = "stunned",
		particle = "merasmus_dazed",
		attachment = "head",
	},
}

local function StartEffect(ent, effect)
	if effect.attachment then return ent:CreateParticleEffect(effect.particle, ent:LookupAttachment(effect.attachment)) end
	return ent:CreateParticleEffect(effect.particle, {
		{
			entity = ent,
			attachtype = PATTACH_ABSORIGIN_FOLLOW,
		},
	})
end

-- state: { revealed, aoeAttack, stunned }. Each effect starts when its flag
-- turns on and stops when it turns off.
function View:UpdateMerasmus(ent, state)
	ent.wsEffects = ent.wsEffects or {}
	local running = ent.wsEffects
	for _, effect in ipairs(MERASMUS_EFFECTS) do
		local on, particles = state[effect.key], running[effect.particle]
		if on and not (particles and particles:IsValid()) then
			running[effect.particle] = StartEffect(ent, effect)
		elseif not on and particles then
			if particles:IsValid() then particles:StopEmission() end
			running[effect.particle] = nil
		end
	end
end

return View
