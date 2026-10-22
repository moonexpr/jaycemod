-- WS.UI (ws/cl_ui.lua): Sandcastle's TF2-styled panels as derma
-- prototypes. UI.Define(name, base, proto) registers "WS<name>" on base (a
-- UI name, else a derma class); a panel derives from one and overrides only
-- what differs. Run against a fake derma.
local T = dofile("tests/harness.lua")

local function Load(polys, texts)
	local defined = {}
	local env = setmetatable({
		WS = { require = T.require },
		derma = { DefineControl = function(name, help, proto, base) defined[name] = { proto = proto, base = base } return proto end },
		surface = {
			CreateFont = function() end,
			SetDrawColor = function() end,
			DrawRect = function() end,
			DrawOutlinedRect = function() end,
			DrawPoly = function(poly) if polys then polys[#polys + 1] = poly end end,
		},
		draw = {
			NoTexture = function() end,
			SimpleText = function(text) if texts then texts[#texts + 1] = text end end,
		},
		TEXT_ALIGN_CENTER = 1,
		Color = function(r, g, b, a) return { r = r, g = g, b = b, a = a or 255 } end,
		ScrW = function() return 1920 end,
		ScrH = function() return 1080 end,
		vgui = { Register = function() end },
	}, { __index = _G })
	setfenv(assert(loadfile("addons/sandcastle/gamemodes/sandcastle/gamemode/ws/cl_ui.lua")), env)()
	return env.WS.UI, defined
end

-- TF2's scheme, as its nav mesh box draws it: TFDarkBrown, TanDark, TanLight.
T.test("the theme: TF2's dark brown box, edged in dark tan, light tan text and fill", function()
	local UI = Load()
	local function RGB(c) return string.format("%d %d %d", c.r, c.g, c.b) end
	T.eq(RGB(UI.THEME.background), "42 39 37", "TFDarkBrown")
	T.eq(RGB(UI.THEME.edge), "117 107 94", "TanDark")
	T.eq(RGB(UI.THEME.text), "235 226 202", "TanLight")
	T.eq(RGB(UI.THEME.border), "235 226 202", "a selection's fill: TanLight")
	T.eq(UI.THEME.borderWidth, 2)
end)

T.test("the library's own panels are defined, each on its base", function()
	local _, defined = Load()
	T.eq(defined.WSPanel.base, "DPanel")
	T.eq(defined.WSLabel.base, "DLabel")
	T.eq(defined.WSProgress.base, "DPanel")
	T.eq(defined.WSDialog.base, "WSPanel", "a dialog is a panel")
end)

T.test("a new panel derives from a UI one by its short name, or from any derma class", function()
	local UI, defined = Load()
	UI.Define("NavProgress", "Dialog", { Hello = function() return "hi" end })
	T.eq(defined.WSNavProgress.base, "WSDialog")
	UI.Define("Raw", "DFrame", {})
	T.eq(defined.WSRaw.base, "DFrame")
	T.eq(UI.Name("NavProgress"), "WSNavProgress")
end)

T.test("a dialog keeps itself in the middle of the screen", function()
	local UI = Load()
	local dialog = { w = 400, h = 100 }
	function dialog:GetSize() return self.w, self.h end
	function dialog:SetPos(x, y) self.x, self.y = x, y end
	UI.Center(dialog)
	T.eq(dialog.x, (1920 - 400) / 2)
	T.eq(dialog.y, (1080 - 100) / 2)
end)

-- surface.DrawPoly draws a convex polygon given clockwise on the screen
-- (y down), and silently nothing otherwise.
local function ClockwiseConvex(poly)
	local n = #poly
	if n < 3 then return false end
	for i = 1, n do
		local a, b, c = poly[i], poly[i % n + 1], poly[(i + 1) % n + 1]
		local cross = (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x)
		if cross < 0 then return false end
	end
	return true
end

T.test("every slot kind's badge is drawn as clockwise convex polygons, with its glyph", function()
	local Loadout = T.require("games.gameplay.loadout")
	local GLYPHS = {
		[Loadout.KIND_PRIMARY] = "1",
		[Loadout.KIND_SECONDARY] = "2",
		[Loadout.KIND_MELEE] = "3",
		[Loadout.KIND_SUPPORT] = "S",
	}
	for _, k in ipairs(Loadout.KINDS) do
		local polys, texts = {}, {}
		local UI = Load(polys, texts)
		UI.SlotBadge(k.kind, 10, 20, 18, UI.THEME.border)
		T.eq(#polys > 0, true, k.name .. " draws")
		for i, poly in ipairs(polys) do T.eq(ClockwiseConvex(poly), true, k.name .. " polygon " .. i) end
		T.eq(texts[1], GLYPHS[k.kind], k.name .. "'s glyph")
	end
end)

T.finish()
