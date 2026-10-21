-- The wheel feature's view: the Wheel of Fate's effect on the HUD (TF2's
-- PlayerStatus_WheelOfDoom), drawn from what the wheel controller networks:
-- the effect's icon, by the player's health, blinking as it runs out.
local Wheel = WS.require("foundation.holiday.wheel")

local EFFECT = "ws_wheel_effect"
local EFFECT_START = "ws_wheel_effect_start"
local EFFECT_DURATION = "ws_wheel_effect_duration"
local NO_EFFECT = -1

local ICON_LEFT = 0.02 -- of the screen width
local ICON_TOP = 0.72 -- of the screen height
local ICON_SIZE = 64

local View = {
	icons = {}, -- material name -> Material
}

function View:Icon(skin)
	local name = Wheel.HudIcon(skin)
	self.icons[name] = self.icons[name] or Material(name)
	return self.icons[name]
end

function View:DrawEffect(w, h)
	local skin = GetGlobal2Int(EFFECT, NO_EFFECT)
	if skin == NO_EFFECT then return end
	local timeLeft = GetGlobal2Float(EFFECT_START, 0) + GetGlobal2Float(EFFECT_DURATION, 0) - CurTime()
	if timeLeft <= 0 or not Wheel.HudVisible(timeLeft) then return end
	surface.SetMaterial(self:Icon(skin))
	surface.SetDrawColor(255, 255, 255, 255)
	surface.DrawTexturedRect(math.floor(w * ICON_LEFT), math.floor(h * ICON_TOP), ICON_SIZE, ICON_SIZE)
end

WS.HUD:Add("game.notices.wheel", WS.HUD_ORDER.NOTICES, function()
	View:DrawEffect(ScrW(), ScrH())
end)

return View
