-- luadev_show (ulx_luadev's): what !print of one of easylua's relative names draws for its
-- caller, for sv_luadev_output_overlay seconds: a box around each entity (me, this, we, wep, veh,
-- phys's) with lines describing it, a line from the caller's eye to each position (there, here),
-- along the aim (dir), and along a trace with a box around what it hit. Drawn by this module on
-- the caller's own client, which needs no developer convar, as debugoverlay does.
--   RELATIVES -> the names shown
--   Describe(ent, opts) -> its lines: name, class, rounded position and angles; for an NPC or a
--     NextBot its activity, animation and target; for an NPC its schedule (a scripted NPC's own,
--     an engine NPC's by opts.schedules, id -> SCHED_ name); then opts.more(ent, lines)'s
--   Shapes(name, value, eye, opts) -> { kind = "box", pos, ang, mins, maxs, lines } and
--     { kind = "line", from, to, lines } for what name holds; none for nothing
--   Show(ply, name, value) -> sends ply the shapes, other addons' lines from the hook
--     ULXLuaDevDescribe(ent, lines) (server)
local SERVER, CLIENT, IsValid, GetConVar, CurTime = SERVER, CLIENT, IsValid, GetConVar, CurTime
local hook, net, util, render, draw = hook, net, util, render, draw
local Vector, Angle, Color = Vector, Angle, Color
local _G, ipairs, pairs, tostring, type = _G, ipairs, pairs, tostring, type
local floor, sqrt, format, remove = math.floor, math.sqrt, string.format, table.remove
module(...)

RELATIVES = { me = true, this = true, we = true, wep = true, veh = true, phys = true, there = true, here = true,
	dir = true, trace = true }
-- How far along the aim dir's line runs.
DIR_LENGTH = 128

local NET = "luadev_show"
local HOOK = "ULXLuaDevDescribe"

local function Round(n) return floor(n + 0.5) end
local function Point(p) return format("%d %d %d", Round(p.x), Round(p.y), Round(p.z)) end

-- An entity by a name a reader knows it by: a player's nick, its targetname, else its class and index.
local function Named(ent)
	if ent:IsPlayer() then return ent:Nick() end
	local name = ent:GetName()
	if name ~= "" then return name end
	return ent:GetClass() .. "#" .. ent:EntIndex()
end

local function Valid(ent) return ent ~= nil and type(ent.IsValid) == "function" and ent:IsValid() end

function Describe(ent, opts)
	local ang = ent:GetAngles()
	local lines = {
		"name: " .. Named(ent),
		"class: " .. ent:GetClass(),
		"pos: " .. Point(ent:GetPos()),
		format("ang: %d %d %d", Round(ang.p), Round(ang.y), Round(ang.r)),
	}
	if ent:IsNPC() or ent:IsNextBot() then
		local sequence = ent:GetSequence()
		lines[#lines + 1] = "activity: " .. tostring(ent:GetSequenceActivityName(sequence))
		lines[#lines + 1] = "animation: " .. tostring(ent:GetSequenceName(sequence))
		local enemy = ent.GetEnemy and ent:GetEnemy()
		lines[#lines + 1] = "target: " .. (Valid(enemy) and Named(enemy) or "none")
	end
	if type(ent.CurrentSchedule) == "table" then
		lines[#lines + 1] = "schedule: " .. tostring(ent.CurrentSchedule.DebugName or ent.CurrentSchedule.Name)
	elseif ent:IsNPC() then
		local id = ent:GetCurrentSchedule()
		lines[#lines + 1] = "schedule: " .. tostring((opts.schedules or {})[id] or id)
	end
	if opts.more then opts.more(ent, lines) end
	return lines
end

local function Box(ent, opts)
	return { kind = "box", pos = ent:GetPos(), ang = ent:GetAngles(), mins = ent:OBBMins(), maxs = ent:OBBMaxs(),
		lines = Describe(ent, opts) }
end

local function Distance(a, b)
	local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
	return sqrt(dx * dx + dy * dy + dz * dz)
end

function Shapes(name, value, eye, opts)
	if value == nil then return {} end
	if name == "trace" then
		local shapes = { { kind = "line", from = value.StartPos, to = value.HitPos,
			lines = { "hit: " .. Point(value.HitPos), "length: " .. Round(Distance(value.StartPos, value.HitPos)) } } }
		if Valid(value.Entity) then shapes[2] = Box(value.Entity, opts) end
		return shapes
	end
	if name == "dir" then
		local to = { x = eye.x + value.x * DIR_LENGTH, y = eye.y + value.y * DIR_LENGTH, z = eye.z + value.z * DIR_LENGTH }
		return { { kind = "line", from = eye, to = to, lines = { "dir: " .. format("%.2f %.2f %.2f", value.x, value.y, value.z) } } }
	end
	if name == "phys" then
		local ent = value.GetEntity and value:GetEntity()
		return Valid(ent) and { Box(ent, opts) } or {}
	end
	if name == "we" then
		local shapes = {}
		for _, ent in ipairs(value) do
			if Valid(ent) then shapes[#shapes + 1] = Box(ent, opts) end
		end
		return shapes
	end
	if type(value.GetClass) == "function" then return Valid(value) and { Box(value, opts) } or {} end
	if type(value.x) == "number" then
		return { { kind = "line", from = eye, to = value, lines = { name .. ": " .. Point(value), "distance: " .. Round(Distance(eye, value)) } } }
	end
	return {}
end

if SERVER then
	util.AddNetworkString(NET)

	-- The engine's schedules by id, SCHED_ names, read once.
	local schedules
	local function Schedules()
		if schedules then return schedules end
		schedules = {}
		for key, value in pairs(_G) do
			if type(key) == "string" and key:sub(1, 6) == "SCHED_" and type(value) == "number" then schedules[value] = key end
		end
		return schedules
	end

	local function More(ent, lines) hook.Run(HOOK, ent, lines) end

	function Show(ply, name, value)
		local overlay = GetConVar("sv_luadev_output_overlay")
		local seconds = overlay and overlay:GetFloat() or 0
		if not IsValid(ply) or seconds <= 0 then return end
		net.Start(NET)
		net.WriteFloat(seconds)
		net.WriteTable(Shapes(name, value, ply:EyePos(), { schedules = Schedules(), more = More }))
		net.Send(ply)
	end
end

if CLIENT then
	local BOX_COLOR, LINE_COLOR, TEXT_COLOR = Color(80, 220, 255), Color(255, 220, 60), Color(255, 255, 255)
	local OUTLINE, LINE_HEIGHT = Color(0, 0, 0), 14
	local shown = {}

	net.Receive(NET, function()
		local seconds = net.ReadFloat()
		for _, shape in ipairs(net.ReadTable()) do
			shape.untilTime = CurTime() + seconds
			shown[#shown + 1] = shape
		end
	end)

	local function Vect3(p) return Vector(p.x, p.y, p.z) end

	-- Where a shape's lines are written: above a box, at a line's end.
	local function Anchor(shape)
		if shape.kind == "box" then return Vect3(shape.pos) + Vector(0, 0, shape.maxs.z + 8) end
		return Vect3(shape.to)
	end

	local function Expire()
		local now = CurTime()
		for i = #shown, 1, -1 do
			if shown[i].untilTime < now then remove(shown, i) end
		end
	end

	hook.Add("PostDrawTranslucentRenderables", NET, function(_, sky)
		if sky then return end
		Expire()
		for _, shape in ipairs(shown) do
			if shape.kind == "box" then
				render.DrawWireframeBox(Vect3(shape.pos), Angle(shape.ang.p, shape.ang.y, shape.ang.r), Vect3(shape.mins), Vect3(shape.maxs), BOX_COLOR, false)
			else
				render.DrawLine(Vect3(shape.from), Vect3(shape.to), LINE_COLOR, false)
				render.DrawWireframeSphere(Vect3(shape.to), 4, 6, 6, LINE_COLOR, false)
			end
		end
	end)

	hook.Add("HUDPaint", NET, function()
		for _, shape in ipairs(shown) do
			local at = Anchor(shape):ToScreen()
			if at.visible then
				for i, line in ipairs(shape.lines) do
					draw.SimpleTextOutlined(line, "DermaDefault", at.x, at.y + (i - #shape.lines) * LINE_HEIGHT, TEXT_COLOR,
						1, 1, 1, OUTLINE)
				end
			end
		end
	end)
end
