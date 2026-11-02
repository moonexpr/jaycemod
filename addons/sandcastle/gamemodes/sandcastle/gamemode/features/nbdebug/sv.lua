-- The nbdebug feature's controller: the NextBot debug layer for admins,
-- after the engine's nb_select, nb_debug and nb_debug_filter, drawing what
-- the engine's cannot: our Lua Behaviors, our path strategies' costs, and
-- routes searched in Lua. The rules are features.nbdebug.model's; this file
-- keeps one Subscription per admin, finds the NPCs through the hook
-- WSNbDebugNpcs (the npc and aiwar controllers answer it), asks the npc
-- controller to watch the path searches of the NPCs someone draws, watches
-- their Behaviors, and sends each admin only what they asked for. The AIWAR
-- layer is the AI war's own soldier overlay: its controller sends it to the
-- players whose ply.wsAiwarDebug this file sets.
--
-- Loaded by the first ws_nb_* command (ws/sv_nbdebug.lua) or
-- ws_aiwar_debug; its client part (cl.lua) is the one view for all of it.
local Debug = WS.require("features.nbdebug.model")

-- The game events it fires are sh.lua's.
local MAX_POINTS, MAX_NPCS, MAX_LINES = Debug.MAX_POINTS, Debug.MAX_NPCS, Debug.MAX_LINES
local NO_SELECTION = Debug.NO_SELECTION

local TICK_INTERVAL = 0.25
local NAV_INTERVAL = 0.5
local NAV_STEP_DOWN, NAV_STEP_UP = 200, 200 -- navmesh.Find's reach below and above the NPC
local NW, NE, SE, SW = 0, 1, 2, 3 -- CNavArea::GetCorner's NavCornerType

local NPCS_HOOK = "WSNbDebugNpcs"

local function NextSoldierNpc(ent)
	return {
		variant = { _NAME = ent:GetClass() },
		Stack = function()
			return ent:NSDebugStack()
		end,
		Watch = function(_, log)
			ent:NSDebugWatch(log)
		end,
	}
end

-- Where the NAV layer takes an area's attribute names: :Of(area) -> list.
-- GMod's nav mesh has no TF2 attributes (TF_NAV_*); they will come from a
-- sidecar written beside the converted mesh, through a source like this.
local NoAttributes = {}
function NoAttributes:Of(area) return {} end

local Clock = {}
function Clock:Now() return CurTime() end

local Controller = {
	subscriptions = {}, -- player -> features.nbdebug.model Subscription
	bots = {}, -- entity -> bot, as features.nbdebug.model sees an NPC, from the last collection
	npcs = {}, -- entity -> its games.npc.nextbot Npc, from the last collection
	pathWatches = {}, -- entity -> { costs }, as last given to the npc controller
	reports = {}, -- entity -> its last path report, while watched
	logs = {}, -- entity -> its BehaviorLog, while watched
	nextTick = 0,
	nextNav = 0,
	navAttributes = NoAttributes,
}

local function Tell(ply, text)
	ply:ChatPrint(text)
end

function Controller:SubscriptionOf(ply)
	local sub = self.subscriptions[ply]
	if not sub then
		sub = Debug.NewSubscription()
		self.subscriptions[ply] = sub
	end
	return sub
end

-- The subscriptions of players still here.
function Controller:Subscriptions()
	local list = {}
	for ply, sub in pairs(self.subscriptions) do
		if IsValid(ply) then
			list[#list + 1] = sub
		else
			self.subscriptions[ply] = nil
		end
	end
	return list
end

-- The NPCs every system offers (entity -> Npc), as bots.
function Controller:Collect()
	local found = {}
	hook.Run(NPCS_HOOK, found)
	for ent in pairs(WS.NextSoldierBots or {}) do
		if IsValid(ent) and found[ent] == nil then found[ent] = NextSoldierNpc(ent) end
	end
	local bots = {}
	for ent, npc in pairs(found) do
		bots[ent] = {
			key = ent,
			index = ent:EntIndex(),
			class = ent:GetClass(),
			variant = npc.variant._NAME,
		}
	end
	self.bots, self.npcs = bots, found
end

local function SameWatch(a, b)
	if a == nil or b == nil then return a == b end
	return a.costs == b.costs
end

function Controller:SetPathWatch(ent, index, watch)
	if SameWatch(self.pathWatches[ent], watch) then return end
	WS.Feature("npc"):WatchPaths(index, watch)
	if ent.IsNextSoldier then ent.NSDebugPathWatch = watch end
	self.pathWatches[ent] = watch
	if watch == nil then self.reports[ent] = nil end
end

function Controller:SetBehaviorWatch(ent, npc, on)
	local log = self.logs[ent]
	if on and not log then
		log = Debug.NewBehaviorLog(Clock, Debug.BEHAVIOR_LOG_SIZE)
		self.logs[ent] = log
		npc:Watch(log)
	elseif not on and log then
		npc:Watch(nil)
		self.logs[ent] = nil
	end
end

-- Watches what the subscriptions want of each NPC, and nothing more.
function Controller:ApplyWatches(subs)
	for ent, bot in pairs(self.bots) do
		self:SetPathWatch(ent, bot.index, Debug.PathWatch(subs, bot))
		self:SetBehaviorWatch(ent, self.npcs[ent], Debug.WatchesBehavior(subs, bot))
	end
end

function Controller:Forget(ent)
	if self.pathWatches[ent] then WS.Feature("npc"):WatchPaths(ent:EntIndex(), nil) end
	if IsValid(ent) and ent.IsNextSoldier then ent.NSDebugPathWatch = nil end
	self.pathWatches[ent], self.reports[ent], self.logs[ent] = nil, nil, nil
	self.bots[ent], self.npcs[ent] = nil, nil
	for _, sub in pairs(self.subscriptions) do sub:Forget(ent) end
end

-------------------------------------------------------------------------------
-- Sending

local function Recipients(self, bot, layer)
	local list = {}
	for ply, sub in pairs(self.subscriptions) do
		if IsValid(ply) and sub:Wants(bot, layer) then list[#list + 1] = ply end
	end
	return list
end

local function Corners(area)
	local corners = {}
	for corner = NW, SW do corners[#corners + 1] = area:GetCorner(corner) end
	return corners
end

function Controller:SendState(ply, sub)
	local selected = sub.selected
	WS.Events.Fire("game_nb_debug_state", {
		layers = Debug.LayerNames(sub.layers),
		selected = IsValid(selected) and selected:EntIndex() or NO_SELECTION,
	}, ply)
end

function Controller:SendPath(recipients, bot, report)
	if #recipients == 0 then return end
	local points = {}
	for i = 1, math.min(#report.points, MAX_POINTS) do
		points[i] = {
			pos = report.points[i].pos,
			move = report.points[i].move,
		}
	end
	WS.Events.Fire("game_nb_debug_path", {
		index = bot.index,
		strategy = report.strategy,
		source = report.source,
		found = report.found,
		total_cost = report.totalCost,
		microseconds = report.microseconds,
		nodes_expanded = report.nodesExpanded,
		computed_at = report.computedAt,
		goal = report.goal,
		points = points,
	}, recipients)
end

-- The explored areas, decimated to fit one message; none when this search's
-- costs were not recorded (the NPC was selected after it began).
function Controller:SendCost(recipients, bot, report)
	if #recipients == 0 or report.explored == nil then return end
	local kept = Debug.Decimate(report.explored, report.areaIds, Debug.MAX_COST_AREAS)
	local areas = {}
	for _, explored in ipairs(kept) do
		local area = navmesh.GetNavAreaByID(explored.id)
		if IsValid(area) then
			areas[#areas + 1] = {
				id = explored.id,
				cost = explored.cost,
				impassable = explored.impassable,
				corners = Corners(area),
			}
		end
	end
	WS.Events.Fire("game_nb_debug_cost", {
		index = bot.index,
		total = #report.explored,
		areas = areas,
	}, recipients)
end

-- What the server already knows, to a player whose view just changed.
function Controller:Resend(ply)
	local sub = self.subscriptions[ply]
	for ent, report in pairs(self.reports) do
		local bot = self.bots[ent]
		if bot and sub:Wants(bot, Debug.PATH) then self:SendPath({ ply }, bot, report) end
		if bot and sub:Wants(bot, Debug.COST) then self:SendCost({ ply }, bot, report) end
	end
end

function Controller:SendBehavior(ply, sub, now)
	local items = {}
	for ent, bot in pairs(self.bots) do
		local log = self.logs[ent]
		if log and sub:Wants(bot, Debug.BEHAVIOR) and #items < MAX_NPCS then
			local name, frames = self.npcs[ent]:Stack()
			local all, lines = Debug.BehaviorLines(name, frames, log:Entries(), now), {}
			for i = 1, math.min(#all, MAX_LINES) do lines[i] = all[i] end
			items[#items + 1] = {
				index = bot.index,
				lines = lines,
			}
		end
	end
	WS.Events.Fire("game_nb_debug_behavior", { npcs = items }, ply)
end

function Controller:SendNav(ply, sub)
	local ent = sub.selected
	local pos = ent:GetPos()
	local items = {}
	for _, area in ipairs(navmesh.Find(pos, Debug.NAV_RADIUS, NAV_STEP_DOWN, NAV_STEP_UP)) do
		items[#items + 1] = {
			area = area,
			distance = area:GetCenter():DistToSqr(pos),
		}
	end
	local areas = {}
	for i, item in ipairs(Debug.NearestFirst(items, Debug.MAX_NAV_AREAS)) do
		areas[i] = {
			id = item.area:GetID(),
			corners = Corners(item.area),
			attributes = self.navAttributes:Of(item.area),
		}
	end
	WS.Events.Fire("game_nb_debug_nav", { areas = areas }, ply)
end

-------------------------------------------------------------------------------
-- The tick and the hooks

function Controller:Tick(now)
	if now < self.nextTick then return end
	self.nextTick = now + TICK_INTERVAL
	local subs = self:Subscriptions()
	local anyActive = false
	for _, sub in ipairs(subs) do anyActive = anyActive or sub:IsActive() end
	if not anyActive and next(self.pathWatches) == nil and next(self.logs) == nil then return end
	self:Collect()
	self:ApplyWatches(subs)
	local sendNav = now >= self.nextNav
	if sendNav then self.nextNav = now + NAV_INTERVAL end
	for ply, sub in pairs(self.subscriptions) do
		if sub:Shows(Debug.BEHAVIOR) then self:SendBehavior(ply, sub, now) end
		if sendNav and sub:Shows(Debug.NAV) and IsValid(sub.selected) then self:SendNav(ply, sub) end
	end
end

-- A watched NPC's search is done (the npc controller's report).
function Controller:OnPathComputed(ent, report)
	local bot = self.bots[ent]
	if not bot then return end
	self.reports[ent] = report
	self:SendPath(Recipients(self, bot, Debug.PATH), bot, report)
	self:SendCost(Recipients(self, bot, Debug.COST), bot, report)
end

function Controller:OnRemoved(ent)
	if not self.bots[ent] then return end
	local index = ent:EntIndex()
	self:Forget(ent)
	local viewers = {}
	for ply, sub in pairs(self.subscriptions) do
		if IsValid(ply) and sub:IsActive() then viewers[#viewers + 1] = ply end
	end
	if #viewers == 0 then return end
	WS.Events.Fire("game_nb_debug_npc_removed", { index = index }, viewers)
end

hook.Add("Think", "ws_nbdebug", function()
	Controller:Tick(CurTime())
end)

hook.Add("WSNpcPathComputed", "ws_nbdebug", function(ent, report)
	Controller:OnPathComputed(ent, report)
end)

hook.Add("EntityRemoved", "ws_nbdebug", function(ent)
	Controller:OnRemoved(ent)
end)

-- The system stepped in on an NPC's movement (WSNpcMark, the AI war's
-- soldiers'): to whoever shows MARKS for it, drawn where it happened and
-- worded in their console.
function Controller:OnMark(ent, kind, detail, from, to)
	local bot = self.bots[ent]
	if not bot then return end
	local recipients = Recipients(self, bot, Debug.MARKS)
	if #recipients == 0 then return end
	local mark = { index = bot.index, kind = kind, detail = detail, from = from, to = to }
	WS.Events.Fire("game_nb_debug_mark", mark, recipients)
	local line = string.format("[MARKS %.1f] %s", CurTime(), Debug.MarkLine(mark))
	for _, ply in ipairs(recipients) do ply:PrintMessage(HUD_PRINTCONSOLE, line) end
end

hook.Add("WSNpcMark", "ws_nbdebug", function(ent, kind, detail, from, to)
	Controller:OnMark(ent, kind, detail, from, to)
end)

-------------------------------------------------------------------------------
-- Commands (registered by ws/sv_nbdebug.lua, which checks who may run them)

-- After a change to what a player sees: watch accordingly, tell their view,
-- and send what is already known.
function Controller:Changed(ply, sub)
	ply.wsAiwarDebug = sub:Shows(Debug.AIWAR) or nil
	self:Collect()
	self:ApplyWatches(self:Subscriptions())
	self:SendState(ply, sub)
	self:Resend(ply)
end

local COMMANDS = {}

-- The bot under the crosshair, or nil.
function Controller:Aimed(ply)
	local candidates = {}
	for ent, bot in pairs(self.bots) do
		candidates[#candidates + 1] = {
			bot = bot,
			center = ent:WorldSpaceCenter(),
			alive = ent:Health() > 0,
		}
	end
	local pick = Debug.Pick(ply:EyePos(), ply:GetAimVector(), candidates)
	return pick and pick.bot
end

-- The bot a command's entity index names (the context menu's), else the
-- fallback's; ok is false, after telling the player why, when the index
-- names no NPC the layer shows. NO_SELECTION names none.
function Controller:Target(ply, command, args, Fallback)
	self:Collect()
	local index, invalid = Debug.ParseIndex(args)
	if invalid then
		Tell(ply, string.format("%s: '%s' is no entity index", command, invalid))
		return nil, false
	end
	if index == nil then return Fallback(), true end
	if index == NO_SELECTION then return nil, true end
	local bot = Debug.BotAt(self.bots, index)
	if bot == nil then Tell(ply, string.format("%s: #%d is no NPC the debug layer shows", command, index)) end
	return bot, bot ~= nil
end

-- nb_select: the NPC with the given entity index (0: none), else the one
-- under the crosshair, or none.
COMMANDS.ws_nb_select = function(self, ply, sub, args)
	local bot, ok = self:Target(ply, "ws_nb_select", args, function() return self:Aimed(ply) end)
	if not ok then return end
	sub:Select(bot and bot.key)
	if bot then
		Tell(ply, string.format("ws_nb_select: %s #%d (%s)", bot.class, bot.index, bot.variant))
	else
		Tell(ply, "ws_nb_select: selection cleared")
	end
	self:Changed(ply, sub)
end

COMMANDS.ws_nb_debug = function(self, ply, sub, args)
	for _, token in ipairs(sub:SetLayers(args)) do
		Tell(ply, string.format("ws_nb_debug: invalid layer '%s' (%s, ALL or OFF)", token, table.concat(Debug.LAYERS, ", ")))
	end
	Tell(ply, "ws_nb_debug: " .. Debug.DescribeLayers(sub.layers))
	if (sub:Shows(Debug.COST) or sub:Shows(Debug.NAV)) and sub.selected == nil then
		Tell(ply, "ws_nb_debug: COST and NAV draw the selected NPC only; aim at one and run ws_nb_select")
	end
	self:Changed(ply, sub)
end

COMMANDS.ws_nb_debug_filter = function(self, ply, sub, args)
	sub:SetFilter(args)
	Tell(ply, "ws_nb_debug_filter: " .. Debug.DescribeFilter(sub.filter))
	self:Changed(ply, sub)
end

COMMANDS.ws_nb_dump = function(self, ply, sub)
	local ent = sub.selected
	if not IsValid(ent) then
		Tell(ply, "ws_nb_dump: select an NPC first (ws_nb_select)")
		return
	end
	local report, bot = self.reports[ent], self.bots[ent]
	if not report then
		Tell(ply, string.format("ws_nb_dump: #%d has not searched for a path since it was selected; try again once it repaths", ent:EntIndex()))
		return
	end
	local map = game.GetMap()
	local doc = Debug.DumpDocument({
		map = map,
		index = bot.index,
		class = bot.class,
		variant = bot.variant,
	}, report)
	local path = Debug.DumpPath(map, bot.index, os.time())
	file.CreateDir(Debug.DUMP_DIR)
	file.Write(path, util.TableToJSON(doc, true))
	Tell(ply, "ws_nb_dump: wrote garrysmod/data/" .. path .. (report.explored and "" or " (no costs: the search began before the selection)"))
end

-- An NPC's behavior (the one with the given entity index, else the
-- selected one), as the BEHAVIOR layer draws it and in both notations
-- (features.nbdebug.model's Tdbn and Obn), in the player's console.
COMMANDS.ws_nb_behavior_print = function(self, ply, sub, args)
	local bot, ok = self:Target(ply, "ws_nb_behavior_print", args, function() return self.bots[sub.selected] end)
	if not ok then return end
	if bot == nil then
		Tell(ply, "ws_nb_behavior_print: select an NPC first (ws_nb_select), or give its entity index")
		return
	end
	local ent = bot.key
	local log = self.logs[ent]
	local name, frames = self.npcs[ent]:Stack()
	local title = string.format("%s #%d (%s)", bot.class, bot.index, bot.variant)
	local now = CurTime()
	for _, line in ipairs(Debug.BehaviorReport(title, name, frames, log and log:Entries(), now)) do
		ply:PrintMessage(HUD_PRINTCONSOLE, line)
	end
	Tell(ply, "ws_nb_behavior_print: printed #" .. bot.index .. "'s behavior to your console")
end

function Controller:Command(name, ply, args)
	COMMANDS[name](self, ply, self:SubscriptionOf(ply), args)
end

-- Toggles one layer, as ws_nb_debug <layer> does (ws_aiwar_debug).
function Controller:ToggleLayer(ply, layer)
	self:Command("ws_nb_debug", ply, { layer })
end

return Controller
