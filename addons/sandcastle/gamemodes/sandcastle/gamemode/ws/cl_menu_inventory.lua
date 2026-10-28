-- Disabled for demo
if true then
	return
end

-- The spawn menu's Store tab: one grid of icon tiles, everything on sale and
-- every player model, icons first and text second, as TF2's loadout and
-- GMod's spawn icons show items. A tile carries its slot badge, its name,
-- its price (or a check once owned) and a heart; hovering it shows a
-- TF2-style item tooltip with its stats.
-- - Click a weapon to buy it (game_loadout_buy): it goes into the first empty
--   slot that takes it; the Loadout tab picks the slot.
-- - Click a model to wear it from the next spawn (cl_playermodel).
-- - Click a heart to favorite the tile: favorites come first, in the order
--   they were favorited, kept on this computer (cookie FAVORITES_COOKIE).
local Economy = gameplay.economy
local Loadout = gameplay.loadout
local E = WS.Events
local UI = WS.UI
local THEME = UI.THEME

local TAB_NAME = "Store"
local TAB_ICON = "icon16/cart.png"
local TAB_ORDER = -30 -- after Loadout (-40), ahead of Sandbox's Spawnlists (-10)

local FAVORITES_COOKIE = "sandcastle_store_favorites"
local FAVORITE_SEP = "\n"

local LAYOUT = core.constants.New("inventory layout", {
	GAP = 8,
	TILE = 112,
	BADGE = 18,
	HEART = 16,
	PAD = 4,
	TIP_W = 280,
	TIP_OFFSET = 16,
})

local COLOR = core.constants.New("inventory colors", {
	NAME_COLOR = Color(255, 215, 0), -- TF2's unique quality
	TIP_BACK = Color(43, 39, 36),
	TIP_BORDER = Color(92, 84, 76),
	TIP_TEXT = Color(235, 226, 202),
	TIP_DESC = Color(200, 191, 168),
	TIP_REFUSED = Color(255, 64, 64),
	PRICE_BACK = Color(143, 191, 74),
	PRICE_TEXT = Color(16, 20, 12),
	PRICE_DIM = Color(58, 58, 68),
	OWNED_DIM = Color(255, 255, 255, 140),
	UNAFFORDABLE = Color(120, 120, 120, 140),
	HEART_OFF = Color(255, 255, 255, 110),
})

local KIND_TYPE = {
	[Loadout.KIND_PRIMARY] = "Primary weapon",
	[Loadout.KIND_SECONDARY] = "Secondary weapon",
	[Loadout.KIND_MELEE] = "Melee weapon",
	[Loadout.KIND_SUPPORT] = "Support item",
}

local function Money()
	return LocalPlayer():GetNW2Int("ws_money", 0)
end

local function Favorites()
	local list = {}
	for key in string.gmatch(cookie.GetString(FAVORITES_COOKIE, ""), "[^" .. FAVORITE_SEP .. "]+") do list[#list + 1] = key end
	return list
end

local function ToggleFavorite(key)
	local list, found = Favorites(), false
	for i = #list, 1, -1 do
		if list[i] == key then
			table.remove(list, i)
			found = true
		end
	end
	if not found then list[#list + 1] = key end
	cookie.Set(FAVORITES_COOKIE, table.concat(list, FAVORITE_SEP))
end

-- A weapon's stat lines for its tooltip.
local function StatLines(weapon)
	local lines = {}
	local stats = WS.WeaponStats[weapon.class]
	if stats then
		local per = stats.pellets > 1 and (" per pellet, " .. stats.pellets .. " pellets") or " per hit"
		lines[#lines + 1] = "Damage: " .. stats.damage .. per
	end
	local details = WS.WeaponDetails[weapon.class]
	if details and details.clip then
		lines[#lines + 1] = "Ammo: " .. details.clip .. " + " .. details.clip * Loadout.RESERVE_CLIPS
	end
	return lines
end

-- Every tile: { key, name, kind (nil for a model), weapon or model }.
local function Items()
	local items = {}
	for _, k in ipairs(Loadout.KINDS) do
		for _, weapon in ipairs(WS.LoadoutCatalog:OfKind(k.kind)) do
			items[#items + 1] = {
				key = "weapon:" .. weapon.class,
				name = weapon.name,
				kind = k.kind,
				weapon = weapon,
			}
		end
	end
	for name, path in SortedPairs(player_manager.AllValidModels()) do
		items[#items + 1] = {
			key = "model:" .. name,
			name = name,
			model = name,
			path = path,
		}
	end
	return items
end

-- Favorites first, in the order favorited; the rest in catalog order.
local function Sorted(items)
	local rank = {}
	for i, key in ipairs(Favorites()) do rank[key] = i end
	local order = {}
	for i, item in ipairs(items) do order[item] = i end
	table.sort(items, function(a, b)
		local ra, rb = rank[a.key] or math.huge, rank[b.key] or math.huge
		if ra ~= rb then return ra < rb end
		return order[a] < order[b]
	end)
	for _, item in ipairs(items) do item.favorite = rank[item.key] ~= nil end
	return items
end

-- The tooltip: drawn on top, beside the hovered tile.
UI.Define("StoreTip", "DPanel", {
	Init = function(self)
		self:SetDrawOnTop(true)
		self:SetMouseInputEnabled(false)
		self:SetVisible(false)
		self:SetWide(LAYOUT.TIP_W)
	end,
	Show = function(self, lines, x, y)
		self.lines = lines
		surface.SetFont(THEME.bodyFont)
		local h = THEME.padding * 2
		for _, line in ipairs(lines) do h = h + (line.gap or 0) + select(2, surface.GetTextSize(line.text)) end
		self:SetTall(h)
		local sx = x + LAYOUT.TIP_OFFSET
		if sx + LAYOUT.TIP_W > ScrW() then sx = x - LAYOUT.TIP_OFFSET - LAYOUT.TIP_W end
		self:SetPos(sx, math.min(y, ScrH() - h))
		self:SetVisible(true)
	end,
	Paint = function(self, w, h)
		surface.SetDrawColor(COLOR.TIP_BORDER)
		surface.DrawRect(0, 0, w, h)
		surface.SetDrawColor(COLOR.TIP_BACK)
		surface.DrawRect(2, 2, w - 4, h - 4)
		local y = THEME.padding
		for _, line in ipairs(self.lines or {}) do
			y = y + (line.gap or 0)
			local x = THEME.padding
			if line.badge then
				UI.SlotBadge(line.badge, x, y + 1, LAYOUT.BADGE - 4, line.color, COLOR.TIP_BACK)
				x = x + LAYOUT.BADGE
			end
			local _, th = draw.SimpleText(line.text, line.font or THEME.bodyFont, x, y, line.color)
			y = y + th
		end
	end,
})

UI.Define("StoreTile", "DButton", {
	Init = function(self)
		self:SetText("")
		self:SetSize(LAYOUT.TILE, LAYOUT.TILE)
		self.heart = vgui.Create("DImageButton", self)
		self.heart:SetImage("icon16/heart.png")
		self.heart:SetSize(LAYOUT.HEART, LAYOUT.HEART)
	end,
	PerformLayout = function(self, w, h)
		self.heart:SetPos(w - LAYOUT.HEART - LAYOUT.PAD, h - LAYOUT.HEART - LAYOUT.PAD)
		if IsValid(self.icon) then self.icon:SetSize(w, h) end
	end,
	SetItem = function(self, item, owned, affordable, onFavorite)
		self.item, self.owned, self.affordable = item, owned, affordable
		if IsValid(self.icon) then self.icon:Remove() end
		if item.weapon then
			self.icon = WS.WeaponIcon(self, item.weapon, LAYOUT.TILE)
			self.icon:SetImageColor(owned and COLOR.OWNED_DIM or (affordable and color_white or COLOR.UNAFFORDABLE))
		else
			self.icon = vgui.Create("SpawnIcon", self)
			self.icon:SetModel(item.path)
		end
		self.icon:SetMouseInputEnabled(false)
		self.icon:SetPos(0, 0)
		self.icon:SetSize(LAYOUT.TILE, LAYOUT.TILE)
		self.icon:MoveToBack()
		self.heart:SetColor(item.favorite and color_white or COLOR.HEART_OFF)
		self.heart.DoClick = onFavorite
	end,
	Paint = function(self, w, h)
		surface.SetDrawColor(THEME.border)
		surface.DrawRect(0, 0, w, h)
		surface.SetDrawColor(THEME.background)
		surface.DrawRect(2, 2, w - 4, h - 4)
	end,
	PaintOver = function(self, w, h)
		local item = self.item
		if self:IsHovered() or self.heart:IsHovered() then
			surface.SetDrawColor(THEME.border)
			surface.DrawOutlinedRect(0, 0, w, h, 2)
		end
		if item.kind then UI.SlotBadge(item.kind, LAYOUT.PAD, LAYOUT.PAD, LAYOUT.BADGE, color_white, THEME.background) end
		draw.SimpleTextOutlined(item.name, THEME.bodyFont, LAYOUT.PAD + 2, h - LAYOUT.PAD, color_white, TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM, 1, color_black)
		if not item.weapon then return end
		if self.owned then
			draw.SimpleText("✓", THEME.titleFont, w - LAYOUT.PAD - 2, LAYOUT.PAD, color_white, TEXT_ALIGN_RIGHT)
			return
		end
		local price = Economy.Format(item.weapon.price)
		surface.SetFont(THEME.bodyFont)
		local tw, th = surface.GetTextSize(price)
		surface.SetDrawColor(self.affordable and COLOR.PRICE_BACK or COLOR.PRICE_DIM)
		surface.DrawRect(w - tw - LAYOUT.PAD * 3, LAYOUT.PAD, tw + LAYOUT.PAD * 2, th)
		draw.SimpleText(price, THEME.bodyFont, w - LAYOUT.PAD * 2, LAYOUT.PAD, self.affordable and COLOR.PRICE_TEXT or THEME.muted, TEXT_ALIGN_RIGHT)
	end,
})

UI.Define("StoreMenu", "DPanel", {
	Init = function(self)
		self:DockPadding(LAYOUT.GAP, LAYOUT.GAP, LAYOUT.GAP, LAYOUT.GAP)
		self.balance = UI.Title(self, "")
		self.scroll = vgui.Create("DScrollPanel", self)
		self.scroll:Dock(FILL)
		self.grid = self.scroll:Add("DIconLayout")
		self.grid:Dock(TOP)
		self.grid:SetSpaceX(LAYOUT.GAP)
		self.grid:SetSpaceY(LAYOUT.GAP)
		self.tip = vgui.Create(UI.Name("StoreTip"))
		hook.Add("WSLoadoutChanged", self, function() self:Refresh() end)
		self:Refresh()
	end,

	OnRemove = function(self)
		if IsValid(self.tip) then self.tip:Remove() end
	end,

	Paint = function(self, w, h)
		surface.SetDrawColor(THEME.background)
		surface.DrawRect(0, 0, w, h)
	end,

	Think = function(self)
		if IsValid(LocalPlayer()) and Money() ~= self.money then self:Refresh() end
		local hovered = vgui.GetHoveredPanel()
		while IsValid(hovered) and hovered.item == nil do hovered = hovered:GetParent() end
		if not (IsValid(hovered) and hovered:IsVisible() and self:IsVisible() and hovered:GetParent() == self.grid) then
			self.tip:SetVisible(false)
			return
		end
		local x, y = input.GetCursorPos()
		self.tip:Show(self:TipLines(hovered), x, y)
	end,

	TipLines = function(self, tile)
		local item = tile.item
		local lines = {
			{
				text = item.name,
				font = THEME.titleFont,
				color = COLOR.NAME_COLOR,
			},
		}
		if not item.weapon then
			lines[#lines + 1] = { text = "Player model · Free", color = THEME.muted }
			lines[#lines + 1] = {
				text = "Click to wear it from your next spawn.",
				color = COLOR.TIP_TEXT,
				gap = LAYOUT.GAP,
			}
			return lines
		end
		local weapon = item.weapon
		lines[#lines + 1] = {
			text = KIND_TYPE[item.kind] .. " · " .. (tile.owned and "Owned" or "Cost: " .. Economy.Format(weapon.price)),
			color = THEME.muted,
			badge = item.kind,
		}
		for i, stat in ipairs(StatLines(weapon)) do
			lines[#lines + 1] = {
				text = stat,
				color = COLOR.TIP_TEXT,
				gap = i == 1 and LAYOUT.GAP or 0,
			}
		end
		local details = WS.WeaponDetails[weapon.class]
		if details then
			lines[#lines + 1] = {
				text = details.description,
				color = COLOR.TIP_DESC,
				gap = LAYOUT.GAP,
			}
		end
		local action, color = "Click to buy · ♥ to keep it first", COLOR.TIP_TEXT
		if tile.owned then
			action = "Owned. Equip it in Loadout."
		elseif not tile.affordable then
			action, color = "Not enough money.", COLOR.TIP_REFUSED
		end
		lines[#lines + 1] = {
			text = action,
			color = color,
			gap = LAYOUT.GAP,
		}
		return lines
	end,

	Refresh = function(self)
		self.money = IsValid(LocalPlayer()) and Money() or 0
		self.balance:SetText(Economy.Format(self.money))
		self.grid:Clear()
		local loadout = WS.LocalLoadout()
		for _, item in ipairs(Sorted(Items())) do
			local tile = self.grid:Add(UI.Name("StoreTile"))
			local owned = item.weapon and loadout:Owns(item.weapon)
			local affordable = item.weapon and WS.Affords(self.money, item.weapon.price)
			tile:SetItem(item, owned, affordable, function()
				ToggleFavorite(item.key)
				self:Refresh()
			end)
			tile.DoClick = function()
				if item.weapon then
					if not owned then WS.LoadoutRequest("game_loadout_buy", { weapon = item.weapon.class }) end
					return
				end
				RunConsoleCommand("cl_playermodel", item.model)
				notification.AddLegacy("Your model changes at your next spawn.", NOTIFY_GENERIC, 3)
			end
		end
		self.grid:InvalidateLayout(true)
	end,
})

spawnmenu.AddCreationTab(TAB_NAME, function()
	return vgui.Create(UI.Name("StoreMenu"))
end, TAB_ICON, TAB_ORDER)
WS.EconomyTabs[TAB_NAME] = true
