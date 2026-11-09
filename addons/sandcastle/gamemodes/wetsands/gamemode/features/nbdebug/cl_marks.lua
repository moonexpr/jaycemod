-- Part of the nbdebug view (cl.lua): the MARKS layer, each time the system
-- stepped in on the selected NPC's movement (game_nb_debug_mark): a post
-- where it was, an arrow to where it was sent, and the mark's words above,
-- fading out over Debug.MARK_SECONDS. The server words it in the console too.
local view = ...
local Debug = WS.require("features.nbdebug.model")

local MARK_COLOR = Color(255, 70, 200)
local MARK_LIFT = Vector(0, 0, 40) -- the arrow at chest height
local MARK_LABEL_LIFT = Vector(0, 0, 80)
local MARK_POST = Vector(0, 0, 72) -- the post standing where it was
local MARK_HEAD = 16 -- the arrowhead's length
local UP = Vector(0, 0, 1)

WS.Events.Listen("game_nb_debug_mark", "ws_nbdebug_view", function(fields)
	view.marks[#view.marks + 1] = {
		line = Debug.MarkLine(fields),
		from = fields.from,
		to = fields.to,
		at = CurTime(),
	}
end)

local function MarkColor(alpha)
	return Color(MARK_COLOR.r, MARK_COLOR.g, MARK_COLOR.b, math.floor(255 * alpha))
end

-- The marks still drawn at now, each with its alpha; the expired dropped.
local function Live(now)
	local live = {}
	for _, mark in ipairs(view.marks) do
		local alpha = Debug.MarkAlpha(now - mark.at)
		if alpha then
			mark.alpha = alpha
			live[#live + 1] = mark
		end
	end
	view.marks = live
	return live
end

-- The 3D pass: posts and arrows.
local function Draw(now)
	for _, mark in ipairs(Live(now)) do
		local color = MarkColor(mark.alpha)
		render.DrawLine(mark.from, mark.from + MARK_POST, color, false)
		if mark.to then
			local a, b = mark.from + MARK_LIFT, mark.to + MARK_LIFT
			render.DrawLine(a, b, color, false)
			local back = (a - b):GetNormalized() * MARK_HEAD
			local side = back:Cross(UP):GetNormalized() * (MARK_HEAD / 2)
			render.DrawLine(b, b + back + side, color, false)
			render.DrawLine(b, b + back - side, color, false)
		end
	end
end

-- The HUD pass: each mark's words above its post, with the view's Label.
local function DrawLabels(Label)
	for _, mark in ipairs(view.marks) do
		if mark.alpha then Label(mark.from + MARK_LABEL_LIFT, mark.line, MarkColor(mark.alpha)) end
	end
end

return {
	Draw = Draw,
	DrawLabels = DrawLabels,
}
