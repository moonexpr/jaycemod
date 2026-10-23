-- TF2's HUD look on the client, as cooler-hud draws it (ws.tf_hud has its
-- layouts): its fonts at a 480-tall size scaled to the screen, its images,
-- its scalable borders, the timer's outline and progress pie, the boss
-- meter's frame and its labels' drop shadow, for the views that draw TF2's
-- panels.
local Hud = WS.require("ws.tf_hud")

local TAN_LIGHT = Color(Hud.TAN_LIGHT.r, Hud.TAN_LIGHT.g, Hud.TAN_LIGHT.b)

local TFHud = { TAN_LIGHT = TAN_LIGHT }
WS.TFHud = TFHud

local fonts = {}

-- The font face at tall (a 480-tall screen's), made once per size.
function TFHud.Font(face, tall, unit)
	local size = math.max(1, math.Round(tall * unit))
	local name = "Sandcastle.TF." .. face .. "." .. size
	if not fonts[name] then
		surface.CreateFont(name, { font = face, size = size, weight = 500, antialias = true })
		fonts[name] = true
	end
	return name
end

local materials = {}

local function Mat(path)
	materials[path] = materials[path] or Material(path)
	return materials[path]
end

-- An image stretched over the rect, tinted by alpha (255 when nil).
function TFHud.DrawImage(path, r, alpha)
	surface.SetDrawColor(255, 255, 255, alpha or 255)
	surface.SetMaterial(Mat(path))
	surface.DrawTexturedRect(r.x, r.y, r.w, r.h)
end

-- An image drawn as TF2's scalable_image borders draw it: corners srcCorner
-- pixels of the image, drawn drawCorner HUD units.
function TFHud.DrawBorder(path, r, unit, srcCorner, drawCorner)
	local mat = Mat(path)
	surface.SetDrawColor(255, 255, 255, 255)
	surface.SetMaterial(mat)
	for _, p in ipairs(Hud.Slices(r.x, r.y, r.w, r.h, mat:Width(), mat:Height(), srcCorner, drawCorner * unit)) do
		surface.DrawTexturedRectUV(p.x, p.y, p.w, p.h, p.u0, p.v0, p.u1, p.v1)
	end
end

-- A color_panel image, as the TFFatLineBorder* borders draw it.
function TFHud.DrawPanel(path, r, unit)
	TFHud.DrawBorder(path, r, unit, Hud.PANEL_SRC_CORNER, Hud.PANEL_DRAW_CORNER)
end

-- Cooler-hud's timer outline (ws.tf_hud's TIMER_OUTLINE), built from TF2's
-- own textures as its material is.
local outlineKeys = {}
for key, value in pairs(Hud.TIMER_OUTLINE) do outlineKeys[key] = tostring(value) end
local TIMER_OUTLINE = CreateMaterial("Sandcastle.TFHud.TimerOutline", "UnlitGeneric", outlineKeys)

-- A time panel's background in the team's colour (alpha: 255 when nil), its
-- outline over it.
function TFHud.DrawTimerBackground(panel, team, alpha)
	TFHud.DrawImage(Hud.TimerBackground(team), panel.bg, alpha)
	surface.SetDrawColor(255, 255, 255, alpha or 255)
	surface.SetMaterial(TIMER_OUTLINE)
	surface.DrawTexturedRect(panel.bg.x, panel.bg.y, panel.bg.w, panel.bg.h)
end

-- The progress pie (CTFProgressBar) in its rect, elapsed (0 to 1) of the
-- timer gone: the image in the inactive colour, the time left over it.
function TFHud.DrawPie(r, elapsed)
	local mat = Mat(Hud.TIMER_PIE)
	surface.SetMaterial(mat)
	local off = Hud.PIE_INACTIVE
	surface.SetDrawColor(off.r, off.g, off.b, 255)
	surface.DrawTexturedRect(r.x, r.y, r.w, r.h)
	local wedge = Hud.PieWedge(1 - elapsed)
	if #wedge < 3 then return end
	local poly = {}
	for i, p in ipairs(wedge) do poly[i] = { x = r.x + p.x * r.w, y = r.y + p.y * r.h, u = p.x, v = p.y } end
	local on = Hud.PieColor(elapsed)
	surface.SetDrawColor(on.r, on.g, on.b, 255)
	surface.DrawPoly(poly)
end

local function Fill(r, c)
	surface.SetDrawColor(c.r, c.g, c.b, c.a)
	surface.DrawRect(r.x, r.y, r.w, r.h)
end

-- The boss meter's frame (ws.tf_hud's BossMeter): the dark band round the
-- tan line, nothing drawn inside the line.
function TFHud.DrawBossFrame(frame, unit)
	local band, line = frame.band, frame.line
	local c = Hud.BOSS_BAND_COLOR
	Fill({ x = band.x, y = band.y, w = band.w, h = line.y - band.y }, c)
	Fill({ x = band.x, y = line.y + line.h, w = band.w, h = band.y + band.h - line.y - line.h }, c)
	Fill({ x = band.x, y = line.y, w = line.x - band.x, h = line.h }, c)
	Fill({ x = line.x + line.w, y = line.y, w = band.x + band.w - line.x - line.w, h = line.h }, c)
	local t = Hud.BOSS_LINE_COLOR
	surface.SetDrawColor(t.r, t.g, t.b, t.a)
	surface.DrawOutlinedRect(math.Round(line.x), math.Round(line.y), math.Round(line.w), math.Round(line.h),
		math.max(1, math.Round(Hud.BOSS_LINE_THICK * unit)))
end

-- A line centred on y, in TanLight (or color), over its drop shadow.
function TFHud.Shadowed(text, font, x, y, alignX, color)
	draw.SimpleText(text, font, x + 1, y + 1, color_black, alignX, TEXT_ALIGN_CENTER)
	draw.SimpleText(text, font, x, y, color or TAN_LIGHT, alignX, TEXT_ALIGN_CENTER)
end
