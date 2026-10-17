-- The spells feature's view: TF2's spell HUD (CHudSpellMenu). It draws the
-- local player's spellbook as its weapon networks it (the spells
-- controller's ws_spell_* NW2 values): the spell's icon, its charges
-- and the key that casts it. While a spell rolls it cycles the icons, each
-- tick a little slower, with alternating tick sounds; a new spell plays the
-- set sound. Casting is TF2's +use_action_slot_item: with no key bound the
-- HUD says "bind h +use_action_slot_item".
local Spells = WS.require("foundation.spells")
local SpellSet = WS.require("foundation.spells.halloween")

local WEAPON = "tf_weapon_spellbook"
local CAST_COMMAND = "+use_action_slot_item"
local BIND_HINT = "bind h " .. CAST_COMMAND

-- What the spells controller networks on the weapon.
local NW_SELECTED = "ws_spell_selected"
local NW_CHARGES = "ws_spell_charges"

-- UpdateSpellText's roll: the first tick gap and how much each adds.
local ROLL_FIRST_GAP = 0.01
local ROLL_GAP_STEP = 0.015
local TICK_SOUNDS = {
	"Halloween.spelltick_a",
	"Halloween.spelltick_b",
}
local SET_SOUND = "Halloween.spelltick_set"
local NO_CHARGES_TEXT = "..."
local ROLLING_TEXT = "?"
local CHARGES_FORMAT = "x%d"

local FONT = "Sandcastle.SpellHud"
local FONT_SIZE = 24
local ICON_SIZE = 64
local PADDING = 8
local MARGIN_RIGHT = 0.02 -- of the screen width
local MARGIN_BOTTOM = 0.22 -- of the screen height, above the ammo
local BACK = Color(0, 0, 0, 170)
local TEXT = Color(236, 227, 203)
local CORNER = 6

surface.CreateFont(FONT, {
	font = "TF2 Build",
	size = FONT_SIZE,
	weight = 500,
})

local View = {
	materials = {},
	nextRollAt = 0,
	rollGap = ROLL_FIRST_GAP,
	rollIcon = 0,
	tickSound = 1,
	previous = Spells.EMPTY,
	icon = SpellSet.ICON_NONE,
	text = NO_CHARGES_TEXT,
	showKey = false,
}

function View:Material(path)
	self.materials[path] = self.materials[path] or Material(path)
	return self.materials[path]
end

local function ResetRoll(self)
	self.rollGap = ROLL_FIRST_GAP
	self.nextRollAt = 0
end

-- CHudSpellMenu::UpdateSpellText, for the local player.
function View:Update(ply, selected, charges, now)
	if selected == Spells.EMPTY or (charges <= 0 and selected ~= Spells.UNKNOWN) then
		self.text, self.icon, self.showKey = NO_CHARGES_TEXT, SpellSet.ICON_NONE, false
		ResetRoll(self)
		return
	end
	if selected == Spells.UNKNOWN then
		if self.nextRollAt > now then return end
		self.nextRollAt = now + self.rollGap
		self.rollGap = self.rollGap + ROLL_GAP_STEP
		self.rollIcon = (self.rollIcon + 1) % SpellSet.COUNT
		self.text, self.icon, self.showKey = ROLLING_TEXT, SpellSet.Definition(self.rollIcon).icon, false
		ply:EmitSound(TICK_SOUNDS[self.tickSound])
		self.tickSound = #TICK_SOUNDS + 1 - self.tickSound
		self.previous = Spells.UNKNOWN
		return
	end
	ResetRoll(self)
	self.text = string.format(CHARGES_FORMAT, charges)
	self.icon = SpellSet.Definition(selected).icon
	self.showKey = true
	if self.previous ~= selected then ply:EmitSound(SET_SOUND) end
	self.previous = selected
end

local function KeyText()
	local key = input.LookupBinding(CAST_COMMAND)
	if key then return string.upper(key) end
	return BIND_HINT
end

function View:Draw(w, h)
	surface.SetFont(FONT)
	local key = KeyText()
	local keyWidth = surface.GetTextSize(key)
	local width = math.max(ICON_SIZE, keyWidth) + 2 * PADDING
	local height = ICON_SIZE + 2 * FONT_SIZE + 2 * PADDING
	local x = math.floor(w * (1 - MARGIN_RIGHT)) - width
	local y = math.floor(h * (1 - MARGIN_BOTTOM)) - height
	draw.RoundedBox(CORNER, x, y, width, height, BACK)
	surface.SetDrawColor(255, 255, 255, 255)
	surface.SetMaterial(self:Material(self.icon))
	surface.DrawTexturedRect(x + (width - ICON_SIZE) / 2, y + PADDING, ICON_SIZE, ICON_SIZE)
	draw.SimpleText(self.text, FONT, x + width / 2, y + PADDING + ICON_SIZE, TEXT, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
	if self.showKey then
		draw.SimpleText(key, FONT, x + width / 2, y + PADDING + ICON_SIZE + FONT_SIZE, TEXT, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
	end
end

-- ShouldDraw: a living player holding a spellbook (only while spells are
-- on does anyone hold one).
hook.Add("HUDPaint", "ws_spell_hud", function()
	local ply = LocalPlayer()
	if not (IsValid(ply) and ply:Alive()) then return end
	local weapon = ply:GetWeapon(WEAPON)
	if not IsValid(weapon) then return end
	View:Update(ply, weapon:GetNW2Int(NW_SELECTED, Spells.EMPTY), weapon:GetNW2Int(NW_CHARGES, 0), CurTime())
	View:Draw(ScrW(), ScrH())
end)

return View
