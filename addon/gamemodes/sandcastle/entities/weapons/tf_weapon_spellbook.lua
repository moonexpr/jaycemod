-- tf_weapon_spellbook (CTFSpellBook): a thin weapon that stands for a
-- player's spellbook. The spells controller hands it out while spells are
-- on, owns the book behind it (foundation.spells) and networks the book on
-- it for the spell HUD. Equipped any other way (the spawn menu), it asks the
-- controller for a book, which goes when the weapon is dropped or removed.
-- Attacking with it casts, as TF2's action key (+use_action_slot_item) does
-- from any weapon.
AddCSLuaFile()

SWEP.PrintName = "Spellbook"
SWEP.Spawnable = true
SWEP.Slot = 5
SWEP.SlotPos = 1
SWEP.DrawAmmo = false
SWEP.DrawCrosshair = false
SWEP.ViewModel = ""
SWEP.WorldModel = "models/player/items/all_class/hwn_spellbook_complete.mdl"
SWEP.HoldType = "slam"

SWEP.Primary = {
	ClipSize = -1,
	DefaultClip = -1,
	Automatic = false,
	Ammo = "none",
}
SWEP.Secondary = {
	ClipSize = -1,
	DefaultClip = -1,
	Automatic = false,
	Ammo = "none",
}

function SWEP:Initialize()
	self:SetHoldType(self.HoldType)
end

-- Server only. The holder is kept, since the owner is gone by OnDrop.
function SWEP:Equip(owner)
	self.bookHolder = owner
	WS.Feature("spells"):Arm(owner)
end

function SWEP:LetGoOfBook()
	if SERVER and self.bookHolder then
		WS.Feature("spells"):Disarm(self.bookHolder)
		self.bookHolder = nil
	end
end

function SWEP:OnDrop()
	self:LetGoOfBook()
end

function SWEP:OnRemove()
	self:LetGoOfBook()
end

function SWEP:PrimaryAttack()
	if CLIENT then return end
	WS.Feature("spells"):Cast(self:GetOwner())
end

function SWEP:SecondaryAttack()
end
