-- WS.WeaponIcon (ws/cl_loadout.lua): a catalog weapon's spawn icon. A melee
-- weapon's leans 30 degrees counter-clockwise, as HL2's weapon selection
-- draws the crowbar; the rest stand upright. Run against a fake derma.
local T = dofile("tests/harness.lua")
local Loadout = T.require("games.gameplay.loadout")

local CATALOG = Loadout.NewCatalog({
	{ class = "smg", name = "SMG", kind = Loadout.KIND_PRIMARY, price = Loadout.PRICE, starter = true },
	{ class = "crowbar", name = "Crowbar", kind = Loadout.KIND_MELEE, price = Loadout.PRICE, starter = true },
})

local MATERIAL, TINT = {}, { r = 255, g = 255, b = 255, a = 255 }

local function Panel()
	local p = {}
	function p:SetImage(name) self.image = name end
	function p:SetSize(w, h) self.w, self.h = w, h end
	function p:SetMouseInputEnabled() end
	function p:GetMaterial() return MATERIAL end
	function p:GetImageColor() return TINT end
	return p
end

local function Load(drawn)
	local env = setmetatable({
		WS = {
			require = T.require,
			Events = { Listen = function() end },
			LoadoutCatalog = CATALOG,
		},
		vgui = { Create = function() return Panel() end },
		surface = {
			SetMaterial = function(m) drawn.material = m end,
			SetDrawColor = function(c) drawn.color = c end,
			DrawTexturedRectRotated = function(x, y, w, h, degrees)
				drawn.rect = { x = x, y = y, w = w, h = h, degrees = degrees }
			end,
		},
	}, { __index = _G })
	setfenv(assert(loadfile("addons/sandcastle/gamemodes/sandcastle/gamemode/ws/cl_loadout.lua")), env)()
	return env.WS
end

T.test("a melee weapon's icon leans 30 degrees counter-clockwise about its centre", function()
	local drawn = {}
	local WS = Load(drawn)
	local icon = WS.WeaponIcon(nil, CATALOG:Weapon("crowbar"), 64)
	T.eq(icon.image, "entities/crowbar.png")
	icon:Paint(64, 64)
	T.eq(drawn.rect.degrees, 30, "positive is counter-clockwise")
	T.eq(drawn.rect.x, 32)
	T.eq(drawn.rect.y, 32)
	T.eq(drawn.material, MATERIAL, "its own image")
	T.eq(drawn.color, TINT, "tinted as the panel is")
end)

T.test("the leaning icon is shrunk so its corners stay inside the panel", function()
	local drawn = {}
	local WS = Load(drawn)
	WS.WeaponIcon(nil, CATALOG:Weapon("crowbar"), 100):Paint(100, 100)
	local a = math.rad(drawn.rect.degrees)
	local span = drawn.rect.w * (math.cos(a) + math.sin(a))
	T.near(span, 100, 1e-9, "the rotated square just fits")
end)

T.test("any other weapon's icon stands upright, painted as a plain image", function()
	local WS = Load({})
	local icon = WS.WeaponIcon(nil, CATALOG:Weapon("smg"), 64)
	T.eq(icon.image, "entities/smg.png")
	T.eq(icon.Paint, nil, "DImage's own Paint")
end)

T.finish()
