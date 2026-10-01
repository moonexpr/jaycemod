-- The npc feature's view: the boss health bar (TF2's monster resource
-- meter), drawn from the wetsand_boss_health Global2 the npc controller
-- networks (0 hides it); the bosses' cues; the bomb heads' bombs; and
-- Merasmus's body effects (C_Merasmus). The particle files are sh.lua's, in
-- both realms.
local BOSS_HEALTH = "wetsand_boss_health"

-- Under the round timer (cl_hud.lua), centred.
local BAR_TOP = 0.17 -- of the screen height
local BAR_WIDTH = 0.3 -- of the screen width
local BAR_HEIGHT = 16
local BAR_PADDING = 4
local BAR_CORNER = 4
local BAR_BACK = Color(0, 0, 0, 170)
local BAR_FILL = Color(118, 196, 52)

local View = {}

function View:DrawBossHealth(w, h)
	local fraction = GetGlobal2Float(BOSS_HEALTH, 0)
	if fraction <= 0 then return end
	local width = math.floor(w * BAR_WIDTH)
	local x, y = math.floor((w - width) / 2), math.floor(h * BAR_TOP)
	draw.RoundedBox(BAR_CORNER, x - BAR_PADDING, y - BAR_PADDING, width + 2 * BAR_PADDING, BAR_HEIGHT + 2 * BAR_PADDING, BAR_BACK)
	surface.SetDrawColor(BAR_FILL)
	surface.DrawRect(x, y, math.floor(width * fraction), BAR_HEIGHT)
end

hook.Add("HUDPaint", "wetsand_boss_health_bar", function()
	View:DrawBossHealth(ScrW(), ScrH())
end)

-- The bosses' game events, as ClientModeTFNormal::FireGameEvent takes
-- them: the cue's sound on the local player (the Horsemann's and
-- MONOCULUS's music and lines), and its line in the chat.
local BossEvents = WETSAND.require("foundation.npc.boss_events")

function View:PlayBossCue(name, fields)
	local cue = BossEvents.Cue(name, fields)
	local ply = LocalPlayer()
	if IsValid(ply) and cue.sound then ply:EmitSound(cue.sound) end
	local color = cue.color and Color(cue.color.r, cue.color.g, cue.color.b) or color_white
	chat.AddText(color, cue.text)
end

for _, name in ipairs(BossEvents.NAMES) do
	WETSAND.Events.Listen(name, "wetsand_npc_view", function(fields)
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

WETSAND.Events.Listen(BossEvents.HALLOWEEN_BOMB_HEAD, "wetsand_npc_view", function(fields)
	View:SetBombHead(fields.player, fields.duration)
end)

hook.Add("PostPlayerDraw", "wetsand_bomb_heads", function(ply)
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
	ent.wetsandEffects = ent.wetsandEffects or {}
	local running = ent.wetsandEffects
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
