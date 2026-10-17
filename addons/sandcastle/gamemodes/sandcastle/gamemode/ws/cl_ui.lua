-- WS.UI: Sandcastle's TF2-styled panels, one look (THEME: a dark box,
-- a white border, white text) as derma prototypes. UI.Define(name, base,
-- proto) registers "WS<name>" on base, a UI name ("Dialog") or any derma
-- class ("DFrame"); a new panel derives from one and overrides only what
-- differs (derma copies the base's methods under the proto's). The library's
-- own: Panel (the box), Label (theme text), Progress (a bar, full to its
-- fraction, or a moving band while it has none), Button, Title (a box's
-- heading) and Dialog (a Panel with a title and a line, kept in the middle
-- of the screen).
local UI = {}
WS.UI = UI

UI.THEME = {
	background = Color(24, 24, 28),
	border = Color(255, 255, 255),
	text = Color(255, 255, 255),
	muted = Color(220, 220, 225),
	borderWidth = 2,
	padding = 12,
	titleFont = "WSTitle",
	bodyFont = "WSBody",
}

surface.CreateFont("WSTitle", { font = "Verdana", size = 18, weight = 800 })
surface.CreateFont("WSBody", { font = "Verdana", size = 15, weight = 500 })

local PREFIX = "WS"

function UI.Name(name) return PREFIX .. name end

-- base: a UI name when the library has defined it, else a derma class.
local defined = {}
function UI.Define(name, base, proto)
	defined[name] = true
	return derma.DefineControl(UI.Name(name), "Sandcastle " .. name, proto, defined[base] and UI.Name(base) or base)
end

function UI.Center(panel)
	local w, h = panel:GetSize()
	panel:SetPos((ScrW() - w) / 2, (ScrH() - h) / 2)
end

local THEME = UI.THEME

-- The box: the theme's background, inside its border.
local function Box(w, h)
	surface.SetDrawColor(THEME.border)
	surface.DrawRect(0, 0, w, h)
	local b = THEME.borderWidth
	surface.SetDrawColor(THEME.background)
	surface.DrawRect(b, b, w - b * 2, h - b * 2)
end

UI.Define("Panel", "DPanel", {
	Init = function(self)
		local p = THEME.padding
		self:DockPadding(p, p, p, p)
	end,
	Paint = function(self, w, h) Box(w, h) end,
})

UI.Define("Label", "DLabel", {
	Init = function(self)
		self:SetFont(THEME.bodyFont)
		self:SetTextColor(THEME.text)
		self:SetContentAlignment(5)
	end,
})

-- fraction: 0..1, or nil for a band that moves while the work runs.
local BAND, BAND_SPEED = 0.25, 0.6

UI.Define("Progress", "DPanel", {
	SetFraction = function(self, fraction) self.fraction = fraction end,
	Paint = function(self, w, h)
		Box(w, h)
		local b = THEME.borderWidth * 2
		local inner = w - b * 2
		surface.SetDrawColor(THEME.border)
		if self.fraction then
			surface.DrawRect(b, b, inner * self.fraction, h - b * 2)
		else
			local at = (CurTime() * BAND_SPEED) % (1 + BAND) - BAND
			local from, to = math.max(at, 0), math.min(at + BAND, 1)
			surface.DrawRect(b + inner * from, b, inner * (to - from), h - b * 2)
		end
	end,
})

-- A box's heading: title text, docked along its top.
local TITLE_HEIGHT = 24

function UI.Title(parent, text)
	local label = vgui.Create(UI.Name("Label"), parent)
	label:SetFont(THEME.titleFont)
	label:SetContentAlignment(4)
	label:SetText(text)
	label:SetTall(TITLE_HEIGHT)
	label:Dock(TOP)
	return label
end

-- A button: the box, filled with the border's colour while hovered or
-- selected (its text turns dark), dimmed while disabled.
local DISABLED_ALPHA = 90

UI.Define("Button", "DButton", {
	Init = function(self)
		self:SetFont(THEME.bodyFont)
		self:SetTextColor(THEME.text)
	end,
	SetSelected = function(self, selected) self.selected = selected end,
	Paint = function(self, w, h)
		local lit = self:IsEnabled() and (self.selected or self:IsHovered())
		surface.SetAlphaMultiplier(self:IsEnabled() and 1 or DISABLED_ALPHA / 255)
		if lit then
			surface.SetDrawColor(THEME.border)
			surface.DrawRect(0, 0, w, h)
		else
			Box(w, h)
		end
		surface.SetAlphaMultiplier(1)
		self:SetTextColor(lit and THEME.background or THEME.text)
	end,
})

UI.Define("Dialog", "Panel", {
	Init = function(self)
		self.title = vgui.Create(UI.Name("Label"), self)
		self.title:SetFont(THEME.titleFont)
		self.title:Dock(TOP)
		self.body = vgui.Create(UI.Name("Label"), self)
		self.body:SetTextColor(THEME.muted)
		self.body:Dock(TOP)
		self.body:DockMargin(0, 6, 0, 0)
	end,
	SetTitle = function(self, text) self.title:SetText(text) end,
	SetBody = function(self, text) self.body:SetText(text) end,
	PerformLayout = function(self) UI.Center(self) end,
})

-- Slot badges: a solid shape, its corners bevelled, with its glyph knocked
-- out: Primary 1 in a triangle, Secondary 2 in a square, Melee 3 in a
-- circle, Support S in a star. Drawn rather than loaded, so they stay sharp
-- at any size. Shapes are in units of the badge's size, clockwise (as
-- surface.DrawPoly needs) on the screen, y down.
local Loadout = WS.require("foundation.loadout")

local BEVEL = 0.16 -- of each edge, cut from each end of a corner
local CIRCLE_SEGMENTS = 24
local STAR_INNER = 0.45 -- the star's inner points, of its outer radius
local BADGE_SMALL = 20 -- below this size, the small glyph font

surface.CreateFont("WSBadge", { font = "Verdana", size = 15, weight = 900 })
surface.CreateFont("WSBadgeSmall", { font = "Verdana", size = 10, weight = 900 })

local function Lerp2(a, b, t)
	return { x = a.x + (b.x - a.x) * t, y = a.y + (b.y - a.y) * t }
end

-- A convex polygon with every corner cut.
local function Bevelled(corners)
	local out = {}
	for i, c in ipairs(corners) do
		local prev = corners[(i - 2) % #corners + 1]
		local nextCorner = corners[i % #corners + 1]
		out[#out + 1] = Lerp2(c, prev, BEVEL)
		out[#out + 1] = Lerp2(c, nextCorner, BEVEL)
	end
	return out
end

local function Ring(radius, count, startDeg)
	local points = {}
	for i = 0, count - 1 do
		local a = math.rad(startDeg + i * 360 / count)
		points[#points + 1] = { x = 0.5 + radius * math.cos(a), y = 0.5 + radius * math.sin(a) }
	end
	return points
end

-- The star as a fan of triangles from its centre: DrawPoly takes only convex shapes.
local function StarFan()
	local outer, inner = Ring(0.48, 5, -90), Ring(0.48 * STAR_INNER, 5, -54)
	local rim = {}
	for i = 1, 5 do
		rim[#rim + 1] = outer[i]
		rim[#rim + 1] = inner[i]
	end
	local fan, centre = {}, { x = 0.5, y = 0.53 }
	for i = 1, #rim do fan[#fan + 1] = { centre, rim[i], rim[i % #rim + 1] } end
	return fan
end

local BADGES = {
	[Loadout.KIND_PRIMARY] = {
		glyph = "1",
		glyphY = 0.64,
		polys = { Bevelled({ { x = 0.5, y = 0.04 }, { x = 0.98, y = 0.92 }, { x = 0.02, y = 0.92 } }) },
	},
	[Loadout.KIND_SECONDARY] = {
		glyph = "2",
		glyphY = 0.5,
		polys = { Bevelled({ { x = 0.08, y = 0.08 }, { x = 0.92, y = 0.08 }, { x = 0.92, y = 0.92 }, { x = 0.08, y = 0.92 } }) },
	},
	[Loadout.KIND_MELEE] = {
		glyph = "3",
		glyphY = 0.5,
		polys = { Ring(0.47, CIRCLE_SEGMENTS, -90) },
	},
	[Loadout.KIND_SUPPORT] = {
		glyph = "S",
		glyphY = 0.55,
		small = true,
		polys = StarFan(),
	},
}

-- Draws kind's badge at x, y, size pixels square, in color, its glyph in
-- behind (the colour under the badge; the theme's background if nil).
function UI.SlotBadge(kind, x, y, size, color, behind)
	local badge = BADGES[kind]
	draw.NoTexture()
	surface.SetDrawColor(color)
	for _, poly in ipairs(badge.polys) do
		local scaled = {}
		for i, p in ipairs(poly) do scaled[i] = { x = x + p.x * size, y = y + p.y * size } end
		surface.DrawPoly(scaled)
	end
	local font = (badge.small or size < BADGE_SMALL) and "WSBadgeSmall" or "WSBadge"
	draw.SimpleText(badge.glyph, font, x + size / 2, y + size * badge.glyphY, behind or THEME.background,
		TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end
