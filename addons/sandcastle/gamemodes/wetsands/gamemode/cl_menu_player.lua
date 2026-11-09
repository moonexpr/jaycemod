-- Disabled for demo
if true then
	return
end

-- The spawn menu's Loadout tab: the local player's loadout (ws/cl_loadout.lua)
-- in two columns, each slot marked with its badge (WS.UI.SlotBadge).
-- - Left: the player's model, with a box around it for each of their five
--   slots showing what it holds. Click a slot to pick it, again to unpick.
--   Under it, a row of tiles, one per player model: click one to wear it
--   from the next spawn (cl_playermodel, as the Store tab sets it); the model
--   shows the pick at once and its tile is outlined.
-- - Right: the weapons they own; while a slot is picked, every weapon it
--   takes, the ones not owned with their price. Click an owned one to equip
--   it, into the picked slot, or with none picked, where the loadout puts
--   it (Loadout:SlotFor); click one not owned to buy it into the picked slot
--   (game_loadout_buy_into).
-- The Store tab buys too. The server owns the loadout: the tab asks, and
-- redraws when it hears back.
local Loadout = gameplay.loadout
local Economy = gameplay.economy
local E = WS.Events
local UI = WS.UI
local THEME = UI.THEME

local TAB_NAME = "Loadout"
local TAB_ICON = "icon16/gun.png"
local TAB_ORDER = -40 -- first, ahead of Sandbox's Spawnlists (-10)
local NEXT_SPAWN = "Loadout changes take effect at a resupply locker or on respawn; a new model, on respawn."
local MODEL_CHANGED = "Your model changes at your next spawn."
local NOTICE_SECONDS = 3
local LAYOUT = core.constants.New("loadout tab layout", {
	BADGE = 18,
	BADGE_GAP = 6,
	GAP = 8,
	LEFT_SHARE = 0.6, -- of the tab's width, for the model and its slots
	SLOT_WIDTH = 180,
	SLOT_HEIGHT = 56,
	ROW_HEIGHT = 40,
	MODEL_FOV = 36,
	MODEL_TILE = 64,
	WORN_BORDER = 3,
})


-- Which side of the model each slot's box sits on.
local LEFT_SLOTS = { Loadout.SLOT_PRIMARY, Loadout.SLOT_SECONDARY, Loadout.SLOT_MELEE }
local RIGHT_SLOTS = { Loadout.SLOT_SUPPORT1, Loadout.SLOT_SUPPORT2 }

local MODEL_CAMERA = Vector(80, 0, 40)
local MODEL_LOOK_AT = Vector(0, 0, 36)

-- The model tiles under the stage, scrolled sideways.
local MODEL_STRIP = LAYOUT.MODEL_TILE + LAYOUT.GAP

-- A player model's tile: its spawn icon in the box, outlined thick while
-- it is the one worn (cl_playermodel).

UI.Define("ModelTile", "DButton", {
	Init = function(self)
		self:SetText("")
		self:SetSize(LAYOUT.MODEL_TILE, LAYOUT.MODEL_TILE)
	end,
	SetModelName = function(self, name, path)
		self.modelName = name
		self:SetTooltip(name)
		self.icon = vgui.Create("SpawnIcon", self)
		self.icon:SetModel(path)
		self.icon:SetMouseInputEnabled(false)
		local b = THEME.borderWidth
		self.icon:SetPos(b, b)
		self.icon:SetSize(LAYOUT.MODEL_TILE - b * 2, LAYOUT.MODEL_TILE - b * 2)
	end,
	Paint = function(self, w, h) UI.Box(w, h) end,
	-- over the icon, which covers the box's inside
	PaintOver = function(self, w, h)
		if GetConVar("cl_playermodel"):GetString() ~= self.modelName then return end
		surface.SetDrawColor(THEME.border)
		surface.DrawOutlinedRect(0, 0, w, h, LAYOUT.WORN_BORDER)
	end,
})

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
		UI.SlotBadge(self.kind, THEME.padding, h / 2 - LAYOUT.BADGE, LAYOUT.BADGE, color, lit and THEME.border or THEME.background)
		draw.SimpleText(self.caption, THEME.bodyFont, THEME.padding + LAYOUT.BADGE + LAYOUT.BADGE_GAP, h / 2, color, TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM)
		draw.SimpleText(self.weaponName, THEME.titleFont, THEME.padding, h / 2, color, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
	end,
})

UI.Define("PlayerMenu", "DPanel", {
	Init = function(self)
		self.loadoutBox = vgui.Create(UI.Name("Panel"), self)
		UI.Title(self.loadoutBox, "Loadout")
		self.models = vgui.Create("DHorizontalScroller", self.loadoutBox)
		self.models:SetTall(MODEL_STRIP)
		self.models:SetOverlap(-LAYOUT.GAP / 2)
		self.models:Dock(BOTTOM)
		self.models:DockMargin(0, LAYOUT.GAP, 0, 0)
		for name, path in SortedPairs(player_manager.AllValidModels()) do
			local tile = vgui.Create(UI.Name("ModelTile"), self.models)
			tile:SetModelName(name, path)
			tile.DoClick = function()
				RunConsoleCommand("cl_playermodel", name)
				notification.AddLegacy(MODEL_CHANGED, NOTIFY_GENERIC, NOTICE_SECONDS)
			end
			self.models:AddPanel(tile)
		end
		self.stage = vgui.Create("DPanel", self.loadoutBox)
		self.stage:SetPaintBackground(false)
		self.stage:Dock(FILL)
		self.stage.PerformLayout = function(stage, w, h) self:LayoutStage(w, h) end
		self.model = vgui.Create("DModelPanel", self.stage)
		self.model:SetFOV(LAYOUT.MODEL_FOV)
		self.model:SetCamPos(MODEL_CAMERA)
		self.model:SetLookAt(MODEL_LOOK_AT)
		self.slotBoxes = {}
		for _, s in ipairs(Loadout.SLOTS) do
			local box = vgui.Create(UI.Name("WeaponBox"), self.stage)
			box:SetSize(LAYOUT.SLOT_WIDTH, LAYOUT.SLOT_HEIGHT)
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
		local left = math.floor(w * LAYOUT.LEFT_SHARE)
		self.loadoutBox:SetPos(0, 0)
		self.loadoutBox:SetSize(left - LAYOUT.GAP / 2, h)
		self.weaponsBox:SetPos(left + LAYOUT.GAP / 2, 0)
		self.weaponsBox:SetSize(w - left - LAYOUT.GAP / 2, h)
	end,

	-- The model fills the middle; the slots stand in a column either side.
	LayoutStage = function(self, w, h)
		self.model:SetPos(LAYOUT.SLOT_WIDTH + LAYOUT.GAP, 0)
		self.model:SetSize(math.max(w - (LAYOUT.SLOT_WIDTH + LAYOUT.GAP) * 2, 0), h)
		local function Column(slots, x)
			local tall = #slots * LAYOUT.SLOT_HEIGHT + (#slots - 1) * LAYOUT.GAP
			local y = (h - tall) / 2
			for i, slot in ipairs(slots) do self.slotBoxes[slot]:SetPos(x, y + (i - 1) * (LAYOUT.SLOT_HEIGHT + LAYOUT.GAP)) end
		end
		Column(LEFT_SLOTS, 0)
		Column(RIGHT_SLOTS, w - LAYOUT.SLOT_WIDTH)
	end,

	-- The model picked (cl_playermodel), which the player wears from their
	-- next spawn, so the pick shows at once.
	Think = function(self)
		local ply = LocalPlayer()
		if not IsValid(ply) then return end
		local picked = player_manager.TranslatePlayerModel(GetConVar("cl_playermodel"):GetString())
		if self.model:GetModel() == picked then return end
		self.model:SetModel(picked)
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
		-- buy: the weapon is not owned; a click buys it into the slot.
		local function Row(caption, weapon, slot, buy)
			local row = self.weapons:Add(UI.Name("WeaponBox"))
			row:SetTall(LAYOUT.ROW_HEIGHT)
			row:SetWeapon(caption, weapon, weapon and weapon.kind or Loadout.SLOTS[slot].kind)
			row:Dock(TOP)
			row:DockMargin(0, 0, 0, LAYOUT.GAP / 2)
			row:SetSelected(loadout:Holds(slot, weapon))
			if buy then row:SetEnabled(WS.Affords(LocalPlayer():GetNW2Int("ws_money", 0), weapon.price)) end
			row.DoClick = function()
				if buy then
					WS.LoadoutRequest("game_loadout_buy_into", {
						slot = slot,
						weapon = weapon.class,
					})
				elseif weapon then
					WS.LoadoutRequest("game_loadout_equip", {
						slot = slot,
						weapon = weapon.class,
					})
				else
					WS.LoadoutRequest("game_loadout_clear", { slot = slot })
				end
			end
		end
		if picked then
			local s = Loadout.SLOTS[picked]
			self.weaponsTitle:SetText(s.name .. " weapons")
			for _, weapon in ipairs(loadout:Choices(picked)) do Row(s.name, weapon, picked) end
			for _, weapon in ipairs(WS.LoadoutCatalog:OfKind(s.kind)) do
				if not loadout:Owns(weapon) then Row("Buy: " .. Economy.Format(weapon.price), weapon, picked, true) end
			end
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
WS.EconomyTabs[TAB_NAME] = true
