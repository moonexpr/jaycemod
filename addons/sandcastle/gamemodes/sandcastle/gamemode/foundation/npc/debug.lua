-- The NextBot debug layer's rules (the nbdebug feature, ws_nb_*): the
-- engine's nb_select, nb_debug and nb_debug_filter, redone for what the
-- engine cannot see: our Lua Behaviors, the costs our path strategies give
-- (foundation.npc.path), and the routes foundation.pathfinder.astar searches.
--
-- Layers: PATH (the computed path by move type, its cost and timing), COST
-- (every area the search considered, by cost so far), BEHAVIOR (the action
-- stack and its recent changes), NAV (nav areas near the NPC), AIWAR (the
-- AI war's soldier overlay: roles, squads, contacts) and MARKS (each time
-- the system stepped in on the NPC's movement: recovered, hopped, sent
-- aside..., marked where it happened). An admin's
-- Subscription holds the layers, a filter and a selection; the controller
-- watches an NPC only while some subscription wants it (PathWatch,
-- WatchesBehavior), so nothing is recorded for NPCs nobody is looking at.
local error, format, ipairs, pairs, setmetatable, tonumber, tostring, type =
	error, string.format, ipairs, pairs, setmetatable, tonumber, tostring, type
local floor, huge, sqrt = math.floor, math.huge, math.sqrt
local concat, sort = table.concat, table.sort
local find, lower, rep, sub, upper = string.find, string.lower, string.rep, string.sub, string.upper
local Npc = require("foundation.npc")
local Sets = require("foundation.map.sets")
module(...)

-------------------------------------------------------------------------------
-- Layers (nb_debug)

PATH, COST, BEHAVIOR, NAV, AIWAR, MARKS = "PATH", "COST", "BEHAVIOR", "NAV", "AIWAR", "MARKS"
LAYERS = { PATH, COST, BEHAVIOR, NAV, AIWAR, MARKS }
local LAYER = Sets.Named("ws_nb_debug layer", LAYERS)

-- Tokens beside the layers' names: nb_debug's "*" means all.
ALL_TOKEN, ALL_SHORTHAND, OFF_TOKEN = "ALL", "*", "OFF"

local function Copy(set)
	local copy = {}
	for k, v in pairs(set) do copy[k] = v end
	return copy
end

-- nb_debug's match: the token is a prefix of the name, in any case.
local function IsPrefix(token, name)
	return #token > 0 and upper(sub(name, 1, #token)) == upper(token)
end

local function LayerOf(token)
	return LAYER:Match(token)
end

-- The layers after a ws_nb_debug command: no token turns every layer
-- off; ALL (or *) turns every one on, OFF every one off; a layer's name, or
-- any prefix of it, toggles it. Returns the new set (`current` is left
-- alone) and the tokens that named no layer.
function ParseLayers(current, tokens)
	if #tokens == 0 then return {}, {} end
	local layers, unknown = Copy(current), {}
	for _, token in ipairs(tokens) do
		local layer = LayerOf(token)
		if token == ALL_SHORTHAND or upper(token) == ALL_TOKEN then
			layers = {}
			for _, each in ipairs(LAYERS) do layers[each] = true end
		elseif upper(token) == OFF_TOKEN then
			layers = {}
		elseif layer then
			layers[layer] = not layers[layer] or nil
		else
			unknown[#unknown + 1] = token
		end
	end
	return layers, unknown
end

-- The layers that are on, in LAYERS' order.
function LayerNames(layers)
	local names = {}
	for _, layer in ipairs(LAYERS) do
		if layers[layer] then names[#names + 1] = layer end
	end
	return names
end

function DescribeLayers(layers)
	local names = LayerNames(layers)
	if #names == 0 then return "off" end
	return concat(names, " ")
end

-------------------------------------------------------------------------------
-- The filter (nb_debug_filter). A bot, as the filter and the subscriptions
-- see an NPC: { key (the controller's handle), index (entity index), class,
-- variant (its model's module name) }.

function NewFilter()
	return {
		indexes = {},
		names = {},
	}
end

-- No token clears the filter; otherwise each token is added to it: a
-- positive integer as an entity index, anything else as a name.
function ParseFilter(current, tokens)
	if #tokens == 0 then return NewFilter() end
	local filter = {
		indexes = Copy(current.indexes),
		names = Copy(current.names),
	}
	for _, token in ipairs(tokens) do
		local index = tonumber(token)
		if index and index > 0 and index == floor(index) then
			filter.indexes[#filter.indexes + 1] = index
		else
			filter.names[#filter.names + 1] = lower(token)
		end
	end
	return filter
end

-- A variant's own name: the last part of its module name.
local function ShortName(variant)
	local short = variant
	local dot = find(short, ".", 1, true)
	while dot do
		short = sub(short, dot + 1)
		dot = find(short, ".", 1, true)
	end
	return short
end

local function NameMatches(name, bot)
	return IsPrefix(name, bot.class) or IsPrefix(name, bot.variant) or IsPrefix(name, ShortName(bot.variant))
end

-- NextBotManager::IsDebugFilterMatch: an empty filter matches every bot.
function FilterMatches(filter, bot)
	if #filter.indexes == 0 and #filter.names == 0 then return true end
	for _, index in ipairs(filter.indexes) do
		if index == bot.index then return true end
	end
	for _, name in ipairs(filter.names) do
		if NameMatches(name, bot) then return true end
	end
	return false
end

function DescribeFilter(filter)
	local parts = {}
	for _, index in ipairs(filter.indexes) do parts[#parts + 1] = "#" .. index end
	for _, name in ipairs(filter.names) do parts[#parts + 1] = name end
	if #parts == 0 then return "none (every NPC)" end
	return concat(parts, " ")
end

-------------------------------------------------------------------------------
-- Selection (nb_select)

-- The entity index a command's first token names (the context menu's
-- commands name their NPC): nil without a token, NO_SELECTION for 0 (no
-- NPC); for a token that is no index, nil and the token.
function ParseIndex(tokens)
	local token = tokens[1]
	if token == nil then return nil end
	local index = tonumber(token)
	if index == nil or index < 0 or index ~= floor(index) then return nil, token end
	return index
end

-- The bot (as the filter sees an NPC) with this entity index, or nil.
function BotAt(bots, index)
	for _, bot in pairs(bots) do
		if bot.index == index then return bot end
	end
	return nil
end

-- CC_SelectBot's Selector: within this cosine of the crosshair.
SELECT_MIN_DOT = 0.98

-- The nearest live candidate within the crosshair's cone, or nil.
-- candidates: { center = {x, y, z}, alive, ... }; forward is a unit vector.
function Pick(eye, forward, candidates)
	local pick, pickRange = nil, huge
	for _, candidate in ipairs(candidates) do
		if candidate.alive then
			local c = candidate.center
			local dx, dy, dz = c.x - eye.x, c.y - eye.y, c.z - eye.z
			local range = sqrt(dx * dx + dy * dy + dz * dz)
			local dot = range > 0 and (dx * forward.x + dy * forward.y + dz * forward.z) / range or 0
			if dot > SELECT_MIN_DOT and range < pickRange then
				pick, pickRange = candidate, range
			end
		end
	end
	return pick
end

-------------------------------------------------------------------------------
-- Subscriptions: one per admin

Subscription = {}
Subscription.__index = Subscription

function NewSubscription()
	return setmetatable({
		layers = {},
		filter = NewFilter(),
		selected = nil, -- a bot's key
	}, Subscription)
end

-- Returns the tokens that named no layer.
function Subscription:SetLayers(tokens)
	local layers, unknown = ParseLayers(self.layers, tokens)
	self.layers = layers
	return unknown
end

function Subscription:SetFilter(tokens)
	self.filter = ParseFilter(self.filter, tokens)
end

-- A bot's key, or nil to clear the selection.
function Subscription:Select(key)
	self.selected = key
end

-- An NPC was removed.
function Subscription:Forget(key)
	if self.selected == key then self.selected = nil end
end

function Subscription:Shows(layer)
	return self.layers[layer] == true
end

function Subscription:IsActive()
	return self.selected ~= nil or #LayerNames(self.layers) > 0
end

-- With a selection only the selected NPC is drawn, whatever the filter;
-- without one, every NPC the filter passes.
function Subscription:Draws(bot)
	if self.selected ~= nil then return bot.key == self.selected end
	return FilterMatches(self.filter, bot)
end

-- The layers drawn for the selected NPC alone.
local SELECTED_ONLY = {
	[COST] = true,
	[NAV] = true,
	[MARKS] = true,
}

-------------------------------------------------------------------------------
-- Marks (MARKS): the system stepping in on an NPC's movement, each told as
-- it happens (the hook WSNpcMark) with what happened (detail), where it was
-- (from) and, when moved, where it was put (to).

MARK_RECOVERED = "recovered" -- the observer put it back (stranded, off the mesh...)
MARK_HOP = "hop" -- carried over what stopped it, toward its waypoint
MARK_SIDESTEP = "sidestep" -- stuck: a step aside and a new route
MARK_REPATH = "repath" -- stuck: its path planned afresh from where it stands
MARK_PASS = "pass" -- let through something only NPCs collide with
MARK_DETOUR = "detour" -- round a solid entity (a cart, a prop)
MARK_GAVE_UP = "gave_up" -- stuck past every remedy: the trip ends
MARK_DOOR = "door" -- held up by a door for too long
MARK_CART = "cart" -- pulled out of a cart that drove over it
MARK_KINDS = { MARK_RECOVERED, MARK_HOP, MARK_SIDESTEP, MARK_REPATH, MARK_PASS, MARK_DETOUR, MARK_GAVE_UP, MARK_DOOR, MARK_CART }
local MARK_KIND = Sets.Named("NPC mark", MARK_KINDS)

local MARK_LABELS = {
	[MARK_RECOVERED] = "RECOVERED",
	[MARK_HOP] = "HOPPED",
	[MARK_SIDESTEP] = "STUCK: STEPPED ASIDE",
	[MARK_REPATH] = "STUCK: NEW PATH",
	[MARK_PASS] = "LET THROUGH",
	[MARK_DETOUR] = "DETOUR",
	[MARK_GAVE_UP] = "STUCK: GAVE UP",
	[MARK_DOOR] = "DOOR",
	[MARK_CART] = "PULLED OUT OF CART",
}

-- How long a mark stays drawn, fading out.
MARK_SECONDS = 15

function MarkLabel(kind)
	return MARK_LABELS[MARK_KIND:Check(kind)]
end

-- mark = { index, kind, detail }: "#195 RECOVERED: stranded".
function MarkLine(mark)
	local line = "#" .. mark.index .. " " .. MarkLabel(mark.kind)
	if mark.detail ~= "" then line = line .. ": " .. mark.detail end
	return line
end

-- How opaque a mark age seconds old is drawn, from 1 down; nil once gone.
function MarkAlpha(age)
	if age >= MARK_SECONDS then return nil end
	return 1 - age / MARK_SECONDS
end

function Subscription:Wants(bot, layer)
	if not self:Shows(layer) then return false end
	if SELECTED_ONLY[layer] then return bot.key == self.selected end
	return self:Draws(bot)
end

-- What to record of a bot's path searches: nil when no subscription draws
-- its PATH or COST or has it selected; otherwise { costs }, where costs
-- (the explored areas, for COST and ws_nb_dump) is true while some
-- subscription has it selected.
function PathWatch(subscriptions, bot)
	local watched, costs = false, false
	for _, sub in ipairs(subscriptions) do
		if sub.selected == bot.key then
			watched, costs = true, true
		elseif sub:Wants(bot, PATH) then
			watched = true
		end
	end
	if not watched then return nil end
	return { costs = costs }
end

function WatchesBehavior(subscriptions, bot)
	for _, sub in ipairs(subscriptions) do
		if sub:Wants(bot, BEHAVIOR) then return true end
	end
	return false
end

-------------------------------------------------------------------------------
-- COST: the cost recorder wraps a search's cost function while the NPC is
-- selected. A negative cost is impassable (Path.IMPASSABLE, IPathCost).

CostRecorder = {}
CostRecorder.__index = CostRecorder

function NewCostRecorder()
	return setmetatable({
		areas = {}, -- id -> { id, cost, impassable }
		order = {},
		expandedFrom = {},
		expanded = 0,
	}, CostRecorder)
end

-- One call of the cost function: the move from fromId (nil for the start)
-- into areaId cost `cost`. An area keeps its cheapest cost so far; it is
-- impassable only if every move into it was.
function CostRecorder:Record(areaId, fromId, cost)
	if fromId ~= nil and not self.expandedFrom[fromId] then
		self.expandedFrom[fromId] = true
		self.expanded = self.expanded + 1
	end
	local area = self.areas[areaId]
	if area == nil then
		area = {
			id = areaId,
			cost = cost,
			impassable = cost < 0,
		}
		self.areas[areaId] = area
		self.order[#self.order + 1] = area
	elseif cost >= 0 and (area.impassable or cost < area.cost) then
		area.cost, area.impassable = cost, false
	end
end

-- How many areas the search expanded (moved out of).
function CostRecorder:Expanded()
	return self.expanded
end

local function CheaperFirst(a, b)
	if a.impassable ~= b.impassable then return b.impassable end
	if a.cost ~= b.cost then return a.cost < b.cost end
	return a.id < b.id
end

-- The areas considered, { id, cost, impassable }, cheapest first and the
-- impassable last.
function CostRecorder:Explored()
	local explored = {}
	for i, area in ipairs(self.order) do
		explored[i] = {
			id = area.id,
			cost = area.cost,
			impassable = area.impassable,
		}
	end
	sort(explored, CheaperFirst)
	return explored
end

-- The field widths of the nbdebug feature's game events
-- (features/nbdebug/sh.lua), and the most a list of each width holds.
INDEX_BITS = 16 -- entity indexes
NO_SELECTION = 0 -- the selected index when nothing is
LAYER_COUNT_BITS = 4
POINT_COUNT_BITS = 12
MOVE_BITS = 3
AREA_COUNT_BITS = 16
TOTAL_BITS = 32
AREA_ID_BITS = 32
NPC_COUNT_BITS = 8
LINE_COUNT_BITS = 6
ATTRIBUTE_COUNT_BITS = 4
CORNER_COUNT_BITS = 3 -- a nav area's four corners
MAX_POINTS = 2 ^ POINT_COUNT_BITS - 1
MAX_NPCS = 2 ^ NPC_COUNT_BITS - 1
MAX_LINES = 2 ^ LINE_COUNT_BITS - 1

-- A snapshot must fit one net message (64 KB). An area on the wire: its id
-- (4 bytes), cost (4), impassable flag, and four corners as net vectors
-- (about 9 bytes each).
NET_BUDGET_BYTES = 48000
COST_AREA_BYTES = 45
MAX_COST_AREAS = floor(NET_BUDGET_BYTES / COST_AREA_BYTES)

-- At most `limit` of the explored areas (given cheapest first): the path's
-- own areas (keepIds), then an even spread over the rest, so every part of
-- the cost range stays in view. Returns the kept areas and how many were
-- dropped.
function Decimate(explored, keepIds, limit)
	local kept = {}
	if #explored <= limit then
		for i, area in ipairs(explored) do kept[i] = area end
		return kept, 0
	end
	local keep, rest = {}, {}
	for _, id in ipairs(keepIds) do keep[id] = true end
	for _, area in ipairs(explored) do
		if keep[area.id] and #kept < limit then
			kept[#kept + 1] = area
		else
			rest[#rest + 1] = area
		end
	end
	local room = limit - #kept
	for i = 0, room - 1 do kept[#kept + 1] = rest[floor(i * #rest / room) + 1] end
	return kept, #explored - #kept
end

-- The cost ramp, cheapest to dearest (blue, cyan, green, yellow), and red
-- for an impassable area, which no cost can reach.
COST_RAMP = {
	{ 40, 90, 255 },
	{ 0, 220, 255 },
	{ 60, 230, 90 },
	{ 255, 230, 40 },
}
IMPASSABLE_COLOR = { 255, 0, 0 }

-- The lowest and highest cost of the passable areas.
function CostRange(areas)
	local lo, hi = huge, -huge
	for _, area in ipairs(areas) do
		if not area.impassable then
			if area.cost < lo then lo = area.cost end
			if area.cost > hi then hi = area.cost end
		end
	end
	if lo > hi then return 0, 0 end
	return lo, hi
end

-- r, g, b for a cost within lo..hi.
function CostColor(cost, lo, hi)
	local t = 0
	if hi > lo then t = (cost - lo) / (hi - lo) end
	if t < 0 then t = 0 elseif t > 1 then t = 1 end
	local span = t * (#COST_RAMP - 1)
	local i = floor(span) + 1
	if i >= #COST_RAMP then
		local last = COST_RAMP[#COST_RAMP]
		return last[1], last[2], last[3]
	end
	local a, b, f = COST_RAMP[i], COST_RAMP[i + 1], span - (i - 1)
	return floor(a[1] + (b[1] - a[1]) * f + 0.5), floor(a[2] + (b[2] - a[2]) * f + 0.5), floor(a[3] + (b[3] - a[3]) * f + 0.5)
end

-------------------------------------------------------------------------------
-- PATH: what a search computed, reported by whoever ran it

-- Who searched: the engine's Path:Compute (with our cost function) for a
-- NextBot, or foundation.pathfinder.astar for an NPC that cannot use it.
SOURCE_ENGINE, SOURCE_ROUTE = "Path:Compute", "foundation.pathfinder.astar"

-- Path::SegmentType (NextBotPath.h), as GMod's path segments carry it.
SEGMENT_ON_GROUND, SEGMENT_DROP_DOWN, SEGMENT_CLIMB_UP, SEGMENT_JUMP_OVER_GAP, SEGMENT_LADDER_UP, SEGMENT_LADDER_DOWN = 0, 1, 2, 3, 4, 5

MOVE_GROUND, MOVE_DROP, MOVE_CLIMB, MOVE_JUMP, MOVE_LADDER = 0, 1, 2, 3, 4
MOVE_NAMES = {
	[MOVE_GROUND] = "ground",
	[MOVE_DROP] = "drop",
	[MOVE_CLIMB] = "climb",
	[MOVE_JUMP] = "jump",
	[MOVE_LADDER] = "ladder",
}
-- Path::Draw's colours, so ours read like the engine's.
MOVE_COLORS = {
	[MOVE_GROUND] = { 255, 77, 0 },
	[MOVE_DROP] = { 255, 0, 255 },
	[MOVE_CLIMB] = { 0, 0, 255 },
	[MOVE_JUMP] = { 0, 255, 255 },
	[MOVE_LADDER] = { 0, 255, 0 },
}

local MOVE_OF_SEGMENT = {
	[SEGMENT_ON_GROUND] = MOVE_GROUND,
	[SEGMENT_DROP_DOWN] = MOVE_DROP,
	[SEGMENT_CLIMB_UP] = MOVE_CLIMB,
	[SEGMENT_JUMP_OVER_GAP] = MOVE_JUMP,
	[SEGMENT_LADDER_UP] = MOVE_LADDER,
	[SEGMENT_LADDER_DOWN] = MOVE_LADDER,
}

function MoveOfSegment(segmentType)
	local move = MOVE_OF_SEGMENT[segmentType]
	if move == nil then error("not a path segment type: " .. tostring(segmentType), 0) end
	return move
end

-- A report's fields and their types; the optional ones may be nil.
local REPORT_FIELDS = {
	source = "string",
	strategy = "string",
	start = "vector",
	goal = "vector",
	found = "boolean",
	points = "table", -- { pos, move } from start to end
	areaIds = "table", -- the nav areas along the path
	microseconds = "number",
	computedAt = "number",
}
local REPORT_OPTIONAL = {
	limits = "table",
	totalCost = "number",
	nodesExpanded = "number",
	explored = "table", -- the cost recorder's, when costs were recorded
}

-- Whether v is a position: a { x, y, z } table, or an engine vector, which
-- GMod's type() names "Vector".
function IsVector(v)
	local kind = type(v)
	return (kind == "table" or kind == "userdata" or kind == "Vector") and type(v.x) == "number"
end

local function Checked(fields, name, kind, optional)
	local value = fields[name]
	if value == nil and optional then return nil end
	local fits = kind == "vector" and IsVector(value) or type(value) == kind
	if not fits then error(format("path report: %s should be a %s, not %s", name, kind, tostring(value)), 2) end
	return value
end

-- A path report from its reporter's fields; a missing or ill-typed field is
-- the reporter's bug, and an error.
function NewPathReport(fields)
	local report = {}
	for name, kind in pairs(REPORT_FIELDS) do report[name] = Checked(fields, name, kind, false) end
	for name, kind in pairs(REPORT_OPTIONAL) do report[name] = Checked(fields, name, kind, true) end
	return report
end

local function Round(n)
	return floor(n + 0.5)
end

local MICROSECONDS_PER_MS = 1000

-- The PATH layer's lines for a report, at time `now`.
function PathLines(report, now)
	local outcome = report.found and "Found" or "Goal out of reach, to the closest area"
	local cost = report.totalCost and tostring(Round(report.totalCost)) or "?"
	return {
		format("Path: %s (%s)", report.strategy, report.source),
		format("%s: %d points, cost %s", outcome, #report.points, cost),
		format("Search: %.2f ms, %s areas expanded", report.microseconds / MICROSECONDS_PER_MS,
			report.nodesExpanded and tostring(report.nodesExpanded) or "?"),
		format("Age: %.1f s", now - report.computedAt),
	}
end

-------------------------------------------------------------------------------
-- BEHAVIOR: a Behavior's watcher (foundation.npc Behavior:Watch) that keeps
-- the last few changes and events, worded as nb_debug BEHAVIOR prints them.

BEHAVIOR_LOG_SIZE = 6

-- ActionResultType's names (Action::GetTypeName).
RESULT_NAMES = {
	[Npc.CONTINUE] = "CONTINUE",
	[Npc.CHANGE_TO] = "CHANGE_TO",
	[Npc.SUSPEND_FOR] = "SUSPEND_FOR",
	[Npc.DONE] = "DONE",
	[Npc.SUSTAIN] = "SUSTAIN",
}

BehaviorLog = {}
BehaviorLog.__index = BehaviorLog

-- clock:Now() stamps each entry.
function NewBehaviorLog(clock, capacity)
	return setmetatable({
		clock = clock,
		capacity = capacity,
		entries = {},
	}, BehaviorLog)
end

local function Append(log, text)
	local entries, now = log.entries, log.clock:Now()
	local last = entries[#entries]
	if last and last.base == text then
		last.count = last.count + 1
		last.text = format("%s x%d", text, last.count)
		last.time = now
		return
	end
	entries[#entries + 1] = {
		base = text,
		text = text,
		count = 1,
		time = now,
	}
	while #entries > log.capacity do
		for i = 1, #entries - 1 do entries[i] = entries[i + 1] end
		entries[#entries] = nil
	end
end

function BehaviorLog:Transition(resultType, fromName, toName, reason, starting)
	local text
	if starting then
		text = "STARTING " .. fromName
	else
		text = fromName .. " " .. RESULT_NAMES[resultType]
		if toName then text = text .. " " .. toName end
		if reason then text = text .. ": " .. reason end
	end
	Append(self, text)
end

function BehaviorLog:Event(name)
	Append(self, "EVENT " .. name)
end

-- { time, text }, oldest first.
function BehaviorLog:Entries()
	local list = {}
	for i, entry in ipairs(self.entries) do
		list[i] = {
			time = entry.time,
			text = entry.text,
		}
	end
	return list
end

local INDENT = "  "

-- The BEHAVIOR layer's lines: the Behavior's name, its stack (frames from
-- Behavior:Stack, indented by depth), then the log's entries, each with
-- how long ago it was.
function BehaviorLines(name, frames, entries, now)
	local lines = { "Behavior: " .. name }
	for _, frame in ipairs(frames) do
		lines[#lines + 1] = rep(INDENT, frame.depth) .. frame.name .. (frame.suspended and " (suspended)" or "")
	end
	if #entries > 0 then lines[#lines + 1] = "Recent:" end
	for _, entry in ipairs(entries) do
		lines[#lines + 1] = format("%s%.1f s %s", INDENT, entry.time - now, entry.text)
	end
	return lines
end

-- The two notations of a stack, along its active line (each level's top
-- action, then what that one contains):
-- - OBN, Outermost Behavior Notation, Source's own order: every level,
--   outermost first, in full names. NextSoldier ( StrategyMonitor ( ... ) ).
-- - TDBN, Terminal-Directed Behavior Notation: the terminal first, then
--   back out, without the levels that only pass through to the next one; a
--   passthrough root prefixes the first level shown (NextSoldier::SquadLeader),
--   and short names stand for full ones. DefendPoint ( CPDefender ( NextSoldier::SquadLeader ) ).
-- In both, a level whose top action was suspended over others reads from
-- its bottom up, each superseded action holding the one over it:
-- DefendPoint<SquadRaid>. A superseded passthrough is shown in TDBN, as is
-- the terminal, whatever it is.

EMPTY_STACK = "(empty)"

-- The active line's levels, outermost first: each a list of frames, top
-- first, then those buried under it.
local function ActiveLevels(frames)
	local levels = {}
	local first, last = 1, #frames
	while first <= last do
		local depth, level, contained = frames[first].depth, {}, last
		for i = first, last do
			if frames[i].depth == depth then
				if #level == 1 then contained = i - 1 end
				level[#level + 1] = frames[i]
			end
		end
		levels[#levels + 1] = level
		first, last = first + 1, contained
	end
	return levels
end

local function LevelToken(level, field)
	local token = level[1][field]
	for i = 2, #level do token = level[i][field] .. "<" .. token .. ">" end
	return token
end

-- tokens, innermost (or outermost) first, as A ( B ( C ) ).
local function Nest(tokens)
	local text = tokens[#tokens]
	for i = #tokens - 1, 1, -1 do text = tokens[i] .. " ( " .. text .. " )" end
	return text
end

local function PassesThrough(level)
	return #level == 1 and level[1].passthrough
end

function Obn(frames)
	local levels = ActiveLevels(frames)
	if #levels == 0 then return EMPTY_STACK end
	local tokens = {}
	for i, level in ipairs(levels) do tokens[i] = LevelToken(level, "name") end
	return Nest(tokens)
end

function Tdbn(frames)
	local levels = ActiveLevels(frames)
	if #levels == 0 then return EMPTY_STACK end
	local shown = {}
	for i, level in ipairs(levels) do
		if i == #levels or not PassesThrough(level) then shown[#shown + 1] = i end
	end
	local tokens = {}
	for i = #shown, 1, -1 do tokens[#tokens + 1] = LevelToken(levels[shown[i]], "short") end
	if shown[1] ~= 1 then
		tokens[#tokens] = LevelToken(levels[1], "short") .. "::" .. tokens[#tokens]
	end
	return Nest(tokens)
end

-- Where the recent changes would be when nobody watches the Behavior.
UNWATCHED = "Recent: not recorded; turn the BEHAVIOR layer on to keep them"

-- ws_nb_behavior_print's lines: the NPC, both notations, then the
-- BEHAVIOR layer's lines; entries is nil while nobody watches the Behavior.
function BehaviorReport(title, name, frames, entries, now)
	local lines = {
		title,
		"TDBN: " .. Tdbn(frames),
		"OBN: " .. Obn(frames),
	}
	for _, line in ipairs(BehaviorLines(name, frames, entries or {}, now)) do lines[#lines + 1] = line end
	if entries == nil then lines[#lines + 1] = UNWATCHED end
	return lines
end

-------------------------------------------------------------------------------
-- NAV: the areas near the selected NPC

NAV_RADIUS = 600
MAX_NAV_AREAS = 48

-- The first `limit` items by distance.
function NearestFirst(items, limit)
	local sorted = {}
	for i, item in ipairs(items) do sorted[i] = item end
	sort(sorted, function(a, b) return a.distance < b.distance end)
	local nearest = {}
	for i = 1, limit < #sorted and limit or #sorted do nearest[i] = sorted[i] end
	return nearest
end

-- An area's label: its id, then its attributes' names (the controller's
-- attribute source; TF2's area attributes will come from a sidecar).
function NavLabel(id, attributes)
	if #attributes == 0 then return "#" .. id end
	return "#" .. id .. " " .. concat(attributes, " ")
end

-------------------------------------------------------------------------------
-- The dump (ws_nb_dump): the selected NPC's last search as JSON, under
-- the data folder.

DUMP_DIR = "ws_nb"

function DumpPath(map, entIndex, stamp)
	return format("%s/%s_%d_%d.json", DUMP_DIR, map, entIndex, stamp)
end

local function Point(v)
	return {
		x = v.x,
		y = v.y,
		z = v.z,
	}
end

local function PlainFields(t)
	local plain = {}
	for k, v in pairs(t or {}) do
		local kind = type(v)
		if kind == "number" or kind == "string" or kind == "boolean" then plain[k] = v end
	end
	return plain
end

-- npc: { map, index, class, variant }.
function DumpDocument(npc, report)
	local points = {}
	for i, point in ipairs(report.points) do
		local p = Point(point.pos)
		p.move = MOVE_NAMES[point.move]
		points[i] = p
	end
	local explored = {}
	for i, area in ipairs(report.explored or {}) do
		explored[i] = {
			id = area.id,
			cost = area.cost,
			impassable = area.impassable,
		}
	end
	local areaIds = {}
	for i, id in ipairs(report.areaIds) do areaIds[i] = id end
	return {
		map = npc.map,
		npc = {
			index = npc.index,
			class = npc.class,
			variant = npc.variant,
		},
		request = {
			start = Point(report.start),
			goal = Point(report.goal),
			strategy = report.strategy,
			source = report.source,
			limits = PlainFields(report.limits),
		},
		result = {
			found = report.found,
			totalCost = report.totalCost,
			points = points,
			areaIds = areaIds,
		},
		search = {
			microseconds = report.microseconds,
			nodesExpanded = report.nodesExpanded,
			costsRecorded = report.explored ~= nil,
			explored = explored,
		},
		computedAt = report.computedAt,
	}
end
