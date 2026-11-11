-- The game builder's helpers under stubbed GMod globals: their real files, loaded
-- as GMod loads a folder entity, and helpers on them whose getters and setters
-- read and write a plain table.
local T = dofile ("tests/harness.lua")
local ENTITIES = "addons/sandcastle/gamemodes/sandcastle/entities/"

CLIENT, SERVER = false, true
AddCSLuaFile = function () end
CurTime = function () return 0 end
WS = WS or {}
WS.require = T.require
WS.TEAM_UNASSIGNED, WS.TEAM_RED, WS.TEAM_BLUE = 0, 2, 3
Color = function (r, g, b) return { r = r, g = g, b = b } end
Vector = function (x, y, z) return { x = x or 0, y = y or 0, z = z or 0 } end
Angle = function (p, y, r) return { p = p or 0, y = y or 0, r = r or 0 } end
vector_origin, angle_zero = Vector (), Angle ()
COLLISION_GROUP_DEBRIS = 1
IsValid = function (v) return v ~= nil end
timer = { Simple = function (_, fn) fn () end }
GetGlobal2Bool = function () return true end
hook = hook or { Add = function () end, Run = function () end }

local Fake = { classes = {}, registered = {} }
duplicator = { RegisterEntityClass = function (class) Fake.registered [class] = true end }
scripted_ents = { GetStored = function (class) return { t = Fake.classes [class] } end }

-- As GMod: the folder's init.lua, in which ENT is global only as it runs.
local function LoadClass (class)
	local ENT = {}
	local folder = ENTITIES .. "entities/" .. class .. "/"
	local env = setmetatable ({ ENT = ENT }, { __index = _G })
	env.include = function (file)
		local chunk = assert (loadfile (folder .. file))
		setfenv (chunk, env)
		chunk ()
	end
	env.include ("init.lua")
	env.ENT = nil
	Fake.classes [class] = ENT
	return ENT
end

local Builder = T.require ("features.builder.model")
Fake.Builder = Builder
Fake.base = LoadClass ("base_gameplay_piece")
for _, kind in ipairs (Builder.KINDS) do Fake.classes [kind] = LoadClass (Builder.CLASSES [kind]) end

-- A helper of the kind. fields: props (its properties), team, capTime,
-- returnTime, position (the keys tests care for most), node, pos, mins, maxs, ang.
function Fake.Piece (id, kind, fields)
	local class = Fake.classes [kind]
	local vars = { PieceId = id, NodeId = 0, BoxMaxs = vector_origin, BoxMins = vector_origin, BodyModel = "" }
	for _, prop in ipairs (class.Properties) do vars [prop.name] = prop.default end
	local piece = setmetatable ({ props = vars }, { __index = function (_, key)
		if key == "BaseClass" then return Fake.base end
		if class [key] ~= nil then return class [key] end
		if Fake.base [key] ~= nil then return Fake.base [key] end
		if key:match ("^%l") or key == "EntityMods" or key == "Inputs" or key == "Outputs" then return nil end
		local get = key:match ("^Get(.+)")
		if get then
			if class.Properties and get == "TeamNum" and vars.TeamNum == nil then return nil end
			return function () return vars [get] end
		end
		local set = key:match ("^Set(.+)")
		if set then return function (_, v) vars [set] = v end end
		return function () end
	end })
	fields = fields or {}
	piece.GetPos = function () return fields.pos or Vector (id * 100, 0, 0) end
	piece.GetAngles = function () return fields.ang or Angle () end
	for name, value in pairs (fields.props or {}) do vars [name] = value end
	if fields.team then vars [kind == Builder.POINT and "DefaultOwner" or "TeamNum"] = fields.team end
	if fields.capTime then vars.TimeToCap = fields.capTime end
	if fields.returnTime then vars.ReturnTime = fields.returnTime end
	if fields.position then vars.PointIndex = fields.position end
	if fields.node then vars.NodeId = fields.node end
	if fields.mins then vars.BoxMins, vars.BoxMaxs = fields.mins, fields.maxs end
	return piece, vars
end

return Fake
