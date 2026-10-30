-- CS:S's weapons in GMod (gameplay.css_weapons): CS:S's ammo types, and
-- what each weapon's SWEP takes from its weapon (WS.CSSWeapon), for
-- entities/weapons/weapon_css_base.lua, weapon_knife.lua,
-- weapon_css_grenade_base.lua and the weapons on them.
local Css = gameplay.css_weapons

for _, name in ipairs({
	"BULLET_PLAYER_50AE", "BULLET_PLAYER_762MM", "BULLET_PLAYER_556MM", "BULLET_PLAYER_556MM_BOX",
	"BULLET_PLAYER_338MAG", "BULLET_PLAYER_9MM", "BULLET_PLAYER_BUCKSHOT", "BULLET_PLAYER_45ACP",
	"BULLET_PLAYER_357SIG", "BULLET_PLAYER_57MM",
}) do
	game.AddAmmoType({ name = name, dmgtype = DMG_BULLET, tracer = TRACER_LINE_AND_WHIZ, maxcarry = Css.AMMO[name].max })
end

WS.CSS_CATEGORY = "Counter-Strike: Source"
WS.CSS_VIEWMODEL_FOV = 54 -- what GMod's cstrike c_ models are framed for

-- Fills a SWEP table from CS:S's weapon class: its name, slot, models,
-- hold type and clip. The SWEP keeps its class (CSSClass) and reads the
-- weapon from gameplay.css_weapons, never a copy of it.
function WS.CSSWeapon(SWEP, class)
	local w = Css.WEAPONS[class]
	if not w then error("no CS:S weapon " .. tostring(class), 2) end
	SWEP.CSSClass = class
	SWEP.PrintName = w.name
	SWEP.Category = WS.CSS_CATEGORY
	SWEP.Spawnable = true
	SWEP.Slot, SWEP.SlotPos = w.slot, w.slotPos
	SWEP.ViewModel, SWEP.WorldModel = w.viewModel, w.worldModel
	SWEP.ViewModelFOV, SWEP.ViewModelFlip, SWEP.UseHands = WS.CSS_VIEWMODEL_FOV, false, true
	SWEP.HoldType = w.hold
	SWEP.DrawCrosshair = w.type ~= "SniperRifle"
	SWEP.Primary = {
		ClipSize = w.clip or -1,
		DefaultClip = w.clip or -1,
		Automatic = w.kind == Css.GUN and w.fullAuto or w.kind == Css.KNIFE,
		Ammo = w.ammo or "none",
	}
	SWEP.Secondary = { ClipSize = -1, DefaultClip = -1, Automatic = w.kind == Css.KNIFE, Ammo = "none" }
end
