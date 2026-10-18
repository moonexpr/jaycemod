-- TF2's HUD look on the client (ws.tf_hud has its layouts): its fonts at a
-- 480-tall size scaled to the screen, its images, its scalable borders and
-- its labels' drop shadow, for the views that draw TF2's panels.
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

-- A color_panel image drawn as TF2's scalable borders draw it.
function TFHud.DrawPanel(path, r, unit)
	local mat = Mat(path)
	surface.SetDrawColor(255, 255, 255, 255)
	surface.SetMaterial(mat)
	for _, p in ipairs(Hud.Slices(r.x, r.y, r.w, r.h, mat:Width(), mat:Height(), Hud.PANEL_SRC_CORNER, Hud.PANEL_DRAW_CORNER * unit)) do
		surface.DrawTexturedRectUV(p.x, p.y, p.w, p.h, p.u0, p.v0, p.u1, p.v1)
	end
end

-- A line centred on y, in TanLight (or color), over its drop shadow.
function TFHud.Shadowed(text, font, x, y, alignX, color)
	draw.SimpleText(text, font, x + 1, y + 1, color_black, alignX, TEXT_ALIGN_CENTER)
	draw.SimpleText(text, font, x, y, color or TAN_LIGHT, alignX, TEXT_ALIGN_CENTER)
end
