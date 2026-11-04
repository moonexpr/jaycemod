-- What the game builder's helpers share (entities/entities/base_gameplay_piece and
-- its classes each hold their own properties, ports and rules): which maps it
-- runs on, the Hammer keyvalues of a property list, the game helpers make together,
-- and the Wire commands they name.
local error, format, ipairs, setmetatable, sort, sub, tostring, type =
	error, string.format, ipairs, setmetatable, table.sort, string.sub, tostring, type
local scripted_ents = scripted_ents
local Teams = gameplay.teams
module(...)

local NOBODY, RED, BLUE = Teams.UNASSIGNED, Teams.RED, Teams.BLUE
local WIRE_PREFIX = "gmod_wire_"

SPAWN, ROOM, LOCKER, NODE, CART, POINT, FLAG, ZONE, SIGN, SCENARIO =
	"spawn", "room", "locker", "node", "cart", "point", "flag", "zone", "sign", "scenario"
-- In the order a game makes them: each entity before those that name it.
KINDS = { SPAWN, ROOM, LOCKER, NODE, CART, POINT, SCENARIO, FLAG, ZONE, SIGN }

CLASSES = { [SCENARIO] = "edit_scenario" }
for _, kind in ipairs(KINDS) do CLASSES[kind] = CLASSES[kind] or "ent_gameplay_" .. kind end

NETWORK_TYPES = { Bool = "Bool", Int = "Int", Float = "Float", String = "String" }

-- What makes a map a scenario's: an objective of its own, which the builder
-- leaves alone.
SCENARIO_CLASSES = {
	"team_control_point_master",
	"team_control_point",
	"trigger_capture_area",
	"team_train_watcher",
	"tf_logic_koth",
	"tf_logic_arena",
	"item_teamflag",
	"func_capturezone",
	"func_bomb_target",
	"func_hostage_rescue",
	"hostage_entity",
}

function IsScenarioMap(holds)
	for _, class in ipairs(SCENARIO_CLASSES) do
		if holds(class) then return true end
	end
	return false
end

-- The entity a helper's Wire inputs reach is named for it.
function Name(id)
	return "build_" .. id
end

function PartName(id, part)
	return Name(id) .. "_" .. part
end

function AreaName(id)
	return PartName(id, "area")
end

CART_AREA_NAME = "build_cart_area"
-- RED holds the track: whose a new checkpoint helper is.
CHECKPOINT_OWNER = RED

function EnemyOf(team)
	return team == RED and BLUE or RED
end

function OnPass(target, input, param)
	return { key = "OnPass", value = format("%s,%s,%s,0,-1", target, input, param) }
end

function Text(value)
	if type(value) == "boolean" then return value and "1" or "0" end
	return tostring(value)
end

-- The Hammer keyvalues of properties on the entity of target, read(name) giving
-- each value. auto: a value setting no key.
function Keys(properties, read, target)
	local keys = {}
	for _, prop in ipairs(properties) do
		local value = read(prop.name)
		if prop.key and prop.target == target and value ~= prop.auto then keys[prop.key] = Text(value) end
	end
	return keys
end

-- The game: what the helpers make together. A spec: { class, name, pos, ang,
-- model, keys, outputs, mins, maxs, parent, onParent, hidden }.
local Game = {}
Game.__index = Game

function Game:Add(spec)
	self.specs[#self.specs + 1] = spec
end

function Game:ProblemOnce(text)
	if self.told[text] then return end
	self.told[text] = true
	self.problems[#self.problems + 1] = text
end

-- Each of teams takes the point after the one before it: TF2's order on a map
-- that sets it, as its base point cannot give one here. The first names itself:
-- open from the start.
function ControlPoint(game, name, pos, index, keys, before, teams)
	keys.point_index = tostring(index)
	for _, team in ipairs(teams) do keys["team_previouspoint_" .. team .. "_0"] = before or name end
	game:Add({ class = "team_control_point", name = name, pos = pos, keys = keys })
end

local POINT_PLATE = "models/props_gameplay/cap_point_base.mdl"

function PointPlate(game, id, pos)
	game:Add({ class = "prop_dynamic", name = PartName(id, "base"), pos = pos, model = POINT_PLATE, keys = {} })
end

local function ById(a, b) return a:Id() < b:Id() end

local TEAM_NAMES = { [RED] = "RED", [BLUE] = "BLU" }

local function CheckSpawns(game)
	local by = game.by
	if #by[NODE] + #by[CART] + #by[POINT] + #by[FLAG] == 0 then return end
	local has = {}
	for _, spawn in ipairs(by[SPAWN]) do has[spawn:GetTeamNum()] = true end
	for _, team in ipairs({ RED, BLUE }) do
		if not has[team] then game:ProblemOnce(TEAM_NAMES[team] .. " has no spawn") end
	end
end

-- The helpers' game: its entities' specs, in an order that has each before those
-- that name it, the inputs for the gamerules, and what the layout lacks. What
-- cannot work is told and left out; the rest still plays. A class takes its kind
-- whole with CompileAll, or each helper its own with Compile.
function Compile(pieces)
	local game = setmetatable({ specs = {}, problems = {}, told = {}, rules = {}, by = {}, helperOf = {}, pointIndex = 0 }, Game)
	for _, kind in ipairs(KINDS) do game.by[kind] = {} end
	for _, piece in ipairs(pieces) do
		local list = game.by[piece.Kind]
		list[#list + 1] = piece
	end
	for _, kind in ipairs(KINDS) do sort(game.by[kind], ById) end
	for _, point in ipairs(game.by[POINT]) do
		if point:GetNodeId() ~= 0 then game.helperOf[point:GetNodeId()] = point end
	end
	CheckSpawns(game)
	for _, kind in ipairs(KINDS) do
		local class = scripted_ents.GetStored(CLASSES[kind]).t
		if class.CompileAll then
			class.CompileAll(game.by[kind], game)
		else
			for _, piece in ipairs(game.by[kind]) do piece:Compile(game) end
		end
	end
	return { specs = game.specs, problems = game.problems, rules = game.rules }
end

-- What a Wire input asks for: fire input (with param) at the helper's entity, or
-- call own(param) on the helper itself. NOTHING: the wire asks nothing.
NOTHING = {}

function WireSwitch(on, off)
	return function(value) return { input = value ~= 0 and on or off } end
end

function WireValue(input)
	return function(value) return { input = input, param = tostring(value) } end
end

function WirePulse(input)
	return function(value)
		if value == 0 then return NOTHING end
		return { input = input }
	end
end

function WireOwn(method)
	return function(value) return { own = method, param = value } end
end

-- Which of the classes are Wire's own (gates, constants, screens), to last
-- through a round's cleanup as the helpers they are wired to do.
function WireClasses(classes)
	local kept = {}
	for _, class in ipairs(classes) do
		if sub(class, 1, #WIRE_PREFIX) == WIRE_PREFIX then kept[#kept + 1] = class end
	end
	return kept
end

-- What a tool's convars say.
function PlayingTeam(value)
	return value == BLUE and BLUE or RED
end

local NEXT_OWNER = { [NOBODY] = RED, [RED] = BLUE, [BLUE] = NOBODY }

function NextOwner(team)
	return NEXT_OWNER[team]
end

-- What a spawner may show as while building, the first by default.
SPAWN_MODELS = {
	"models/editor/playerstart.mdl",
	"models/player/scout.mdl",
	"models/player/soldier.mdl",
	"models/player/heavy.mdl",
	"models/player/engineer.mdl",
}

function SpawnModel(text)
	for _, model in ipairs(SPAWN_MODELS) do
		if model == text then return model end
	end
	return SPAWN_MODELS[1]
end

-- A pasted helper keeps its id unless another has it; taken holds those in use.
function PastedId(saved, taken, nextId)
	return taken[saved] and nextId or saved
end

-- A second click on a placed helper within this long updates it.
DOUBLE_CLICK_TIME = 0.5

function IsDoubleClick(last, now)
	return last ~= nil and now - last <= DOUBLE_CLICK_TIME
end
