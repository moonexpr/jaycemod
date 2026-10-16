-- The spawn menu's Loadout tab: the local player's loadout (ws/cl_loadout.lua)
-- in two columns, each slot marked with its badge (WS.UI.SlotBadge).
-- - Left: the player's model, with a box around it for each of their five
--   slots showing what it holds. Click a slot to pick it, again to unpick.
-- - Right: the weapons they own; only those the picked slot takes while one
--   is picked. Click one to equip it, into the picked slot, or with none
--   picked, where the loadout puts it (Loadout:SlotFor).
-- Weapons are bought in the Store tab. The server owns the loadout:
-- the tab asks, and redraws when it hears back.
local Loadout = WS.require("foundation.loadout")
local E = WS.Events
local UI = WS.UI
local THEME = UI.THEME

local TAB_NAME = "Loadout"
local TAB_ICON = "icon16/gun.png"
local TAB_ORDER = -40 -- first, ahead of Sandbox's Spawnlists (-10)
local NEXT_SPAWN = "Loadout changes will take effect on respawn."
local BADGE = 18
local BADGE_GAP = 6

local GAP = 8
local LEFT_SHARE = 0.6 -- of the tab's width, for the model and its slots
local SLOT_WIDTH = 180
local SLOT_HEIGHT = 56
local ROW_HEIGHT = 40

-- Which side of the model each slot's box sits on.
local LEFT_SLOTS = { Loadout.SLOT_PRIMARY, Loadout.SLOT_SECONDARY, Loadout.SLOT_MELEE }
local RIGHT_SLOTS = { Loadout.SLOT_SUPPORT1, Loadout.SLOT_SUPPORT2 }

local MODEL_FOV = 36
local MODEL_CAMERA = Vector(80, 0, 40)
local MODEL_LOOK_AT = Vector(0, 0, 36)

-- A box holding its slot's badge and name small, a weapon's name large, and
-- its icon.
UI.Define("WeaponBox", "Button", {
	Init = function(self) self:SetText("") end,
	SetWeapon = function(self, caption, weapon, kind)
		self.caption = caption
		self.kind = kind
		self.weaponName = weapon and weapon.name or "Empty"
		if IsValid(self.icon) then self.icon:Remove() end
		if weapon then self.icon = WS.WeaponIcon(self, weapon, self:GetTall() - THEME.padding) end
	end,
	PerformLayout = function(self, w, h)
		if IsValid(self.icon) then self.icon:SetPos(w - self.icon:GetWide() - THEME.padding / 2, THEME.padding / 2) end
	end,
	PaintOver = function(self, w, h)
		local color = self:GetTextColor()
		local lit = color == THEME.background
		UI.SlotBadge(self.kind, THEME.padding, h / 2 - BADGE, BADGE, color, lit and THEME.border or THEME.background)
		draw.SimpleText(self.caption, THEME.bodyFont, THEME.padding + BADGE + BADGE_GAP, h / 2, color, TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM)
		draw.SimpleText(self.weaponName, THEME.titleFont, THEME.padding, h / 2, color, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
	end,
})

UI.Define("PlayerMenu", "DPanel", {
	Init = function(self)
		self.loadoutBox = vgui.Create(UI.Name("Panel"), self)
		UI.Title(self.loadoutBox, "Loadout")
		self.stage = vgui.Create("DPanel", self.loadoutBox)
		self.stage:SetPaintBackground(false)
		self.stage:Dock(FILL)
		self.stage.PerformLayout = function(stage, w, h) self:LayoutStage(w, h) end
		self.model = vgui.Create("DModelPanel", self.stage)
		self.model:SetFOV(MODEL_FOV)
		self.model:SetCamPos(MODEL_CAMERA)
		self.model:SetLookAt(MODEL_LOOK_AT)
		self.slotBoxes = {}
		for _, s in ipairs(Loadout.SLOTS) do
			local box = vgui.Create(UI.Name("WeaponBox"), self.stage)
			box:SetSize(SLOT_WIDTH, SLOT_HEIGHT)
			box.DoClick = function()
				self.picked = self.picked ~= s.slot and s.slot or nil
				self:Refresh()
			end
			self.slotBoxes[s.slot] = box
		end

		self.weaponsBox = vgui.Create(UI.Name("Panel"), self)
		self.weaponsTitle = UI.Title(self.weaponsBox, "")
		local hint = vgui.Create(UI.Name("Label"), self.weaponsBox)
		hint:SetTextColor(THEME.muted)
		hint:SetWrap(true)
		hint:SetAutoStretchVertical(true)
		hint:SetText(NEXT_SPAWN)
		hint:Dock(BOTTOM)
		self.weapons = vgui.Create("DScrollPanel", self.weaponsBox)
		self.weapons:Dock(FILL)

		hook.Add("WSLoadoutChanged", self, function() self:Refresh() end)
		self:Refresh()
	end,

	Paint = function() end,

	PerformLayout = function(self, w, h)
		local left = math.floor(w * LEFT_SHARE)
		self.loadoutBox:SetPos(0, 0)
		self.loadoutBox:SetSize(left - GAP / 2, h)
		self.weaponsBox:SetPos(left + GAP / 2, 0)
		self.weaponsBox:SetSize(w - left - GAP / 2, h)
	end,

	-- The model fills the middle; the slots stand in a column either side.
	LayoutStage = function(self, w, h)
		self.model:SetPos(SLOT_WIDTH + GAP, 0)
		self.model:SetSize(math.max(w - (SLOT_WIDTH + GAP) * 2, 0), h)
		local function Column(slots, x)
			local tall = #slots * SLOT_HEIGHT + (#slots - 1) * GAP
			local y = (h - tall) / 2
			for i, slot in ipairs(slots) do self.slotBoxes[slot]:SetPos(x, y + (i - 1) * (SLOT_HEIGHT + GAP)) end
		end
		Column(LEFT_SLOTS, 0)
		Column(RIGHT_SLOTS, w - SLOT_WIDTH)
	end,

	Think = function(self)
		local ply = LocalPlayer()
		if not IsValid(ply) or self.model:GetModel() == ply:GetModel() then return end
		self.model:SetModel(ply:GetModel())
		local ent = self.model:GetEntity()
		if IsValid(ent) then ent.GetPlayerColor = function() return ply:GetPlayerColor() end end
	end,

	Refresh = function(self)
		local loadout = WS.LocalLoadout()
		for _, s in ipairs(Loadout.SLOTS) do
			local box = self.slotBoxes[s.slot]
			box:SetWeapon(s.name, loadout:Equipped(s.slot), s.kind)
			box:SetSelected(s.slot == self.picked)
		end
		self:RefreshWeapons(loadout)
	end,

	RefreshWeapons = function(self, loadout)
		local picked = self.picked
		self.weapons:Clear()
		local function Row(caption, weapon, slot)
			local row = self.weapons:Add(UI.Name("WeaponBox"))
			row:SetTall(ROW_HEIGHT)
			row:SetWeapon(caption, weapon, weapon and weapon.kind or Loadout.SLOTS[slot].kind)
			row:Dock(TOP)
			row:DockMargin(0, 0, 0, GAP / 2)
			row:SetSelected(loadout:Holds(slot, weapon))
			row.DoClick = function()
				if weapon then
					E.Request("loadout_equip", {
						slot = slot,
						weapon = weapon.class,
					})
				else
					E.Request("loadout_clear", { slot = slot })
				end
			end
		end
		if picked then
			local s = Loadout.SLOTS[picked]
			self.weaponsTitle:SetText(s.name .. " weapons")
			for _, weapon in ipairs(loadout:Choices(picked)) do Row(s.name, weapon, picked) end
			Row(s.name, nil, picked)
			return
		end
		self.weaponsTitle:SetText("Your weapons")
		for _, k in ipairs(Loadout.KINDS) do
			for _, weapon in ipairs(WS.LoadoutCatalog:OfKind(k.kind)) do
				if loadout:Owns(weapon) then Row(k.name, weapon, loadout:SlotFor(weapon)) end
			end
		end
	end,
})

spawnmenu.AddCreationTab(TAB_NAME, function()
	return vgui.Create(UI.Name("PlayerMenu"))
end, TAB_ICON, TAB_ORDER)
