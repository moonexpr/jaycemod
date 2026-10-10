-- WS.UI (ws/cl_ui.lua): Sandcastle's TF2-styled panels as derma
-- prototypes. UI.Define(name, base, proto) registers "WS<name>" on base (a
-- UI name, else a derma class); a panel derives from one and overrides only
-- what differs. Run against a fake derma.
local T = dofile("tests/harness.lua")

local function Load()
	local defined = {}
	local env = setmetatable({
		WS = {},
		derma = { DefineControl = function(name, help, proto, base) defined[name] = { proto = proto, base = base } return proto end },
		surface = { CreateFont = function() end, SetDrawColor = function() end, DrawRect = function() end, DrawOutlinedRect = function() end },
		Color = function(r, g, b, a) return { r = r, g = g, b = b, a = a or 255 } end,
		ScrW = function() return 1920 end,
		ScrH = function() return 1080 end,
		vgui = { Register = function() end },
	}, { __index = _G })
	setfenv(assert(loadfile("addon/gamemodes/sandcastle/gamemode/ws/cl_ui.lua")), env)()
	return env.WS.UI, defined
end

T.test("the theme: a dark box, a white border, white text", function()
	local UI = Load()
	T.eq(UI.THEME.background.r, 24)
	T.eq(UI.THEME.border.r, 255)
	T.eq(UI.THEME.text.r, 255)
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

T.finish()
