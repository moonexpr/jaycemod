-- The spawn menu's Inventory tab, by section:
-- - Weapons: the store (ws/sh_loadout.lua's catalog), a row a slot kind,
--   each weapon with its price and a Buy button, paid from the money on the
--   scoreboard. A weapon bought fills the first empty slot that takes it;
--   the Player tab equips the rest.
-- - Player models: every valid one; a click sets cl_playermodel, which
--   Sandbox puts on at the next spawn.
-- - Map & server items: a stub until maps and servers can offer them.
local Economy = WS.require("foundation.economy")
local Loadout = WS.require("foundation.loadout")
local E = WS.Events
local UI = WS.UI
local THEME = UI.THEME

local TAB_NAME = "Inventory"
local TAB_ICON = "icon16/basket.png"
local TAB_ORDER = 301 -- after the Player tab
local NO_ITEMS = "This map and server offer no items yet."

local GAP = 8
local TILE_WIDTH = 220
local TILE_HEIGHT = 64
local BUY_WIDTH = 72
local MODEL_ICON = 64

local function Money()
	return LocalPlayer():GetNW2Int("ws_money", 0)
end

local function Layout(parent)
	local layout = vgui.Create("DIconLayout", parent)
	layout:Dock(TOP)
	layout:DockMargin(GAP, GAP, GAP, GAP)
	layout:SetSpaceX(GAP)
	layout:SetSpaceY(GAP)
	return layout
end

local function WeaponTile(parent, weapon, loadout, money)
	local tile = parent:Add(UI.Name("Panel"))
	tile:SetSize(TILE_WIDTH, TILE_HEIGHT)
	tile:DockPadding(GAP, GAP, GAP, GAP)
	WS.WeaponIcon(tile, weapon, TILE_HEIGHT - GAP * 2):Dock(LEFT)
	local buy = vgui.Create(UI.Name("Button"), tile)
	buy:Dock(RIGHT)
	buy:SetWide(BUY_WIDTH)
	local owned = loadout:Owns(weapon)
	buy:SetText(owned and "Owned" or "Buy")
	buy:SetEnabled(not owned and money >= weapon.price)
	buy.DoClick = function() E.Request("loadout_buy", { weapon = weapon.class }) end
	local name = vgui.Create(UI.Name("Label"), tile)
	name:SetContentAlignment(4)
	name:SetText(weapon.name .. "\n" .. Economy.Format(weapon.price))
	name:Dock(FILL)
	name:DockMargin(GAP, 0, 0, 0)
end

UI.Define("InventoryMenu", "DCategoryList", {
	Init = function(self)
		self.weapons = self:Add("Weapons")
		self.store = vgui.Create("DPanel")
		self.store:SetPaintBackground(false)
		self.store.PerformLayout = function(store) store:SizeToChildren(false, true) end
		self.weapons:SetContents(self.store)

		local models = self:Add("Player models")
		local modelGrid = Layout()
		models:SetContents(modelGrid)
		for name, path in SortedPairs(player_manager.AllValidModels()) do
			local icon = modelGrid:Add("SpawnIcon")
			icon:SetSize(MODEL_ICON, MODEL_ICON)
			icon:SetModel(path)
			icon:SetTooltip(name)
			icon.DoClick = function()
				RunConsoleCommand("cl_playermodel", name)
				notification.AddLegacy("Your model changes at your next spawn.", NOTIFY_GENERIC, 3)
			end
		end

		local items = self:Add("Map & server items")
		local none = vgui.Create("DLabel")
		none:SetText(NO_ITEMS)
		none:SetDark(true)
		none:DockMargin(GAP, GAP, GAP, GAP)
		items:SetContents(none)

		hook.Add("WSLoadoutChanged", self, function() self:RefreshStore() end)
		self:RefreshStore()
	end,

	Think = function(self)
		if IsValid(LocalPlayer()) and Money() ~= self.money then self:RefreshStore() end
	end,

	-- A row of tiles a slot kind, under the kind's name and the money held.
	RefreshStore = function(self)
		self.money = IsValid(LocalPlayer()) and Money() or 0
		self.weapons:SetLabel("Weapons: " .. Economy.Format(self.money) .. " to spend")
		self.store:Clear()
		local loadout = WS.LocalLoadout()
		for _, k in ipairs(Loadout.KINDS) do
			local heading = vgui.Create("DLabel", self.store)
			heading:SetText(k.name)
			heading:SetFont(THEME.titleFont)
			heading:SetDark(true)
			heading:Dock(TOP)
			heading:DockMargin(GAP, GAP, GAP, 0)
			heading:SizeToContentsY()
			local row = Layout(self.store)
			for _, weapon in ipairs(WS.LoadoutCatalog:OfKind(k.kind)) do WeaponTile(row, weapon, loadout, self.money) end
		end
		self.store:InvalidateLayout()
	end,
})

spawnmenu.AddCreationTab(TAB_NAME, function()
	return vgui.Create(UI.Name("InventoryMenu"))
end, TAB_ICON, TAB_ORDER)
