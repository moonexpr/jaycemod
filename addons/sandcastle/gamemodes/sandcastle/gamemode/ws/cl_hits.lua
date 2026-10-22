-- What an attacking player sees and hears of its own hits
-- (game_combat_text, ws/sv_hits.lua): TF2's damage numbers rising from the
-- victim (hud_combattext, games.gameplay.combat.combat_text), its hit sound
-- (tf_dingalingaling, games.gameplay.combat.hit_sound), and the crit text over
-- the victim (crit.pcf's crit_text, minicrit_text). TF2's console
-- variables set them, from the spawn menu's Options > Client > Gameplay
-- Effects.
local P = WS.PlayerRules
local CombatText = WS.require("games.gameplay.combat.combat_text")
local HitSound = WS.require("games.gameplay.combat.hit_sound")
local E = WS.Events

local COMBAT_TEXT = CreateClientConVar("hud_combattext", "1", true, false, "1: show the damage you deal as numbers over your victims", 0, 1)
local BATCHING = CreateClientConVar("hud_combattext_batching", "0", true, false, "1: hits on one victim close together show as one number", 0, 1)
local BATCHING_WINDOW = CreateClientConVar("hud_combattext_batching_window", "0.2", true, false, "Seconds within which hits on one victim add into one number", 0.1, 2)
local DINGALING = CreateClientConVar("tf_dingalingaling", "1", true, false, "1: play a sound when you hit an enemy", 0, 1)
local EFFECT = CreateClientConVar("tf_dingalingaling_effect", "0", true, false, "The hit sound: 0 Default, 1 Electro, 2 Notes, 3 Percussion, 4 Retro, 5 Space, 6 Beepo, 7 Vortex, 8 Squasher", 0, #HitSound.EFFECTS - 1)
local VOLUME = CreateClientConVar("tf_dingaling_volume", "0.6", true, false, "The hit sound's volume", 0, 1)
local PITCH_LOW = CreateClientConVar("tf_dingaling_pitchmindmg", "100", true, false, "The hit sound's pitch for the least damage", 1, 255)
local PITCH_HIGH = CreateClientConVar("tf_dingaling_pitchmaxdmg", "100", true, false, "The hit sound's pitch for the most damage", 1, 255)
local REPEAT_DELAY = CreateClientConVar("tf_dingalingaling_repeat_delay", "0", true, false, "Least seconds between two hit sounds; 0 plays one for every hit", 0, 1)
local WAV_OVERRIDE = CreateClientConVar("tf_dingaling_wav_override", "", true, false, "A sound under sound/ played as the hit sound instead (e.g. ui/hitsound_beepo.wav); empty for the chosen one")

local CRIT_FILE = "particles/crit.pcf"
local CRIT_TEXTS = {
	[P.HIT_CRIT] = "crit_text",
	[P.HIT_MINICRIT] = "minicrit_text",
}
game.AddParticles(CRIT_FILE)
for _, name in pairs(CRIT_TEXTS) do PrecacheParticleSystem(name) end

-- TF2's 480-tall units; hud_combattext_red/green/blue's default.
local TEXT_TALL = 12
local TEXT_FONT = "WS.CombatText"
local TEXT_COLOR = Color(255, 0, 0)
local OUTLINE_COLOR = Color(0, 0, 0)

local fontFor

local function Font(unit)
	if fontFor == unit then return end
	surface.CreateFont(TEXT_FONT, { font = "TF2 Build", size = math.Round(TEXT_TALL * unit), weight = 500 })
	fontFor = unit
end

local function Window()
	return BATCHING:GetBool() and BATCHING_WINDOW:GetFloat() or 0
end

local texts = CombatText.New(Window())
local function Rebatch() texts = CombatText.New(Window()) end
cvars.AddChangeCallback(BATCHING:GetName(), Rebatch, "ws_hits")
cvars.AddChangeCallback(BATCHING_WINDOW:GetName(), Rebatch, "ws_hits")

-- The hit sound for damage: heard by the attacker alone, from nowhere.
local function Ding(damage)
	local sound = HitSound.Sound(EFFECT:GetInt(), WAV_OVERRIDE:GetString())
	local pitch = HitSound.Pitch(damage, PITCH_LOW:GetFloat(), PITCH_HIGH:GetFloat())
	LocalPlayer():EmitSound(sound, 0, pitch, VOLUME:GetFloat(), CHAN_STATIC)
end

local lastDing

E.Listen("game_combat_text", "ws_hits", function(fields)
	local now = CurTime()
	if COMBAT_TEXT:GetBool() then texts:Add(fields.victim, fields.amount, fields.kind, fields.pos, now) end
	if DINGALING:GetBool() and HitSound.Ready(lastDing, now, REPEAT_DELAY:GetFloat()) then
		lastDing = now
		Ding(fields.amount)
	end
	local crit = CRIT_TEXTS[fields.kind]
	if crit then CreateParticleSystemNoEntity(crit, fields.pos, angle_zero) end
end)

WS.HUD:Add("player.hits", WS.HUD_ORDER.WORLD, function()
	local shown = texts:Live(CurTime())
	if #shown == 0 then return end
	Font(ScrH() / 480)
	for _, text in ipairs(shown) do
		local screen = (text.pos + Vector(0, 0, text.rise)):ToScreen()
		if screen.visible then
			local alpha = 255 * text.alpha
			TEXT_COLOR.a, OUTLINE_COLOR.a = alpha, alpha
			draw.SimpleTextOutlined(text.text, TEXT_FONT, screen.x, screen.y, TEXT_COLOR, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM, 1, OUTLINE_COLOR)
		end
	end
end)

-- Kept in the client's data folder, across games and servers.
WS.PersistClientConVars("gameplay_effects", {
	COMBAT_TEXT, BATCHING, BATCHING_WINDOW, DINGALING, EFFECT, VOLUME, PITCH_LOW, PITCH_HIGH, REPEAT_DELAY, WAV_OVERRIDE,
})

-- Options > Client > Gameplay Effects: TF2's Advanced Options for these.
local PREVIEW_DAMAGE = 50

local function Help(panel, convar)
	panel:ControlHelp(convar:GetHelpText())
end

local function BuildPanel(panel)
	panel:ClearControls()
	panel:Help("Damage numbers")
	panel:CheckBox("Show damage numbers", COMBAT_TEXT:GetName())
	panel:CheckBox("Add up quick hits on one victim", BATCHING:GetName())
	panel:NumSlider("Adding-up window (seconds)", BATCHING_WINDOW:GetName(), 0.1, 2, 2)
	panel:Help("Hit sounds")
	panel:CheckBox("Play a sound when I hit an enemy", DINGALING:GetName())
	local effect = panel:ComboBox("Hit sound", EFFECT:GetName())
	for i, choice in ipairs(HitSound.EFFECTS) do effect:AddChoice(choice.label, i - 1) end
	panel:NumSlider("Volume", VOLUME:GetName(), 0, 1, 2)
	panel:NumSlider("Pitch at low damage", PITCH_LOW:GetName(), 1, 255, 0)
	panel:NumSlider("Pitch at high damage", PITCH_HIGH:GetName(), 1, 255, 0)
	panel:NumSlider("Least time between sounds", REPEAT_DELAY:GetName(), 0, 1, 2)
	Help(panel, REPEAT_DELAY)
	panel:TextEntry("Custom sound file", WAV_OVERRIDE:GetName())
	Help(panel, WAV_OVERRIDE)
	panel:Button("Play the hit sound").DoClick = function() Ding(PREVIEW_DAMAGE) end
end

hook.Add("PopulateToolMenu", "ws_hits", function()
	spawnmenu.AddToolMenuOption("Options", "Client", "ws_gameplay_effects", "Gameplay Effects", "", "", BuildPanel)
end)
