-- Server side of payload: loads the pure libraries the payload entities use,
-- answers the round questions they ask (final point, capture in progress,
-- payload race), publishes every cart and timed capture for the HUD, and
-- plays the payload race stage-outcome lines.

WETSAND.Payload = WETSAND.require("foundation.payload")
WETSAND.PayloadCapture = WETSAND.require("foundation.capture")
WETSAND.PayloadRace = WETSAND.require("foundation.payload.race")

local P, R = WETSAND.Payload, WETSAND.PayloadRace

-- The Game Rules editor's cart speed: a scale on every cart's top speed,
-- kept for the rest of the map.
local cartSpeedScale = 1

function WETSAND.CartSpeedScale()
	return cartSpeedScale
end

function WETSAND.SetCartSpeedScale(scale)
	cartSpeedScale = math.Clamp(scale, P.CART_SPEED_MIN, P.CART_SPEED_MAX)
	for _, watcher in ipairs(ents.FindByClass("team_train_watcher")) do watcher:ApplyMaxSpeed() end
end

-- tf_logic_multiple_escort marks a payload race map (CTFGameRules::SetMultipleTrains).
function WETSAND.HasMultipleTrains()
	return #ents.FindByClass("tf_logic_multiple_escort") > 0
end

-- CTFGameRules::TimerMayExpire: no timer runs out while a point is being captured.
function WETSAND.CaptureInProgress()
	for _, area in ipairs(ents.FindByClass("trigger_capture_area")) do
		if area:IsCapturing() then return true end
	end
	return false
end

local function PointData(points)
	local data = {}
	for i, point in ipairs(points) do
		data[i] = { group = tonumber(WETSAND.KeyValues(point).point_group) or 0, owner = WETSAND.CapTeam(point) }
	end
	return data
end

local function IndexOf(list, value)
	for i, v in ipairs(list) do
		if v == value then return i end
	end
end

local function PlayableRounds(rounds)
	local n = 0
	for _, round in ipairs(rounds) do
		if P.IsPlayable(PointData(round:Points()), round.restrictTeam) then n = n + 1 end
	end
	return n
end

-- WatcherThink's bFinalPointInMap: would capturing `point` win the game for a
-- team that may capture it? With mini-rounds, only in the last playable round.
function WETSAND.FinalPointInMap(point)
	if #ents.FindByClass("team_control_point_master") == 0 then return false end
	local rounds = ents.FindByClass("team_control_point_round")
	local miniRounds = #rounds > 0
	local points
	if miniRounds then
		local round = WETSAND.CurrentRound()
		if not IsValid(round) then return false end
		points = round:Points()
	else
		points = ents.FindByClass("team_control_point")
	end
	local index = IndexOf(points, point)
	if not index then return false end
	local teams = {}
	for team = WETSAND.TEAM_RED, WETSAND.TEAM_BLUE do
		if WETSAND.TeamCanCapPoint(point, team) then teams[#teams + 1] = team end
	end
	return P.FinalPoint(miniRounds, miniRounds and PlayableRounds(rounds) or 0, PointData(points), index, teams)
end

-- HUD publishing --------------------------------------------------------------------
-- wetsand_cart_count, wetsand_cart_race, wetsand_cart_race_leader, and per cart i (1-based)
-- wetsand_cart_<i>_{team,progress,speed,cappers,recede_time,can_recede,alarm,cps,owners,hills};
-- wetsand_capture_count and per timed capture i
-- wetsand_capture_<i>_{index,owner,capping,progress,blocked,cappers}.

local function Joined(list, format)
	local parts = {}
	for i, v in ipairs(list) do parts[i] = string.format(format, v) end
	return table.concat(parts, ",")
end

local function HillString(hills)
	local parts = {}
	for i, h in ipairs(hills) do
		parts[i] = string.format("%.4f:%.4f:%d", h.from, h.to, h.down and 1 or 0)
	end
	return table.concat(parts, ";")
end

-- Enabled watchers, BLU's first, in a stable order.
local function ActiveWatchers()
	local list = {}
	for _, watcher in ipairs(ents.FindByClass("team_train_watcher")) do
		if watcher:IsActive() then list[#list + 1] = watcher end
	end
	table.sort(list, function(a, b)
		if a.team ~= b.team then return a.team > b.team end
		return a:EntIndex() < b:EntIndex()
	end)
	return list
end

local function PublishCart(i, hud)
	local key = "wetsand_cart_" .. i .. "_"
	SetGlobal2Int(key .. "team", hud.team)
	SetGlobal2Float(key .. "progress", hud.progress)
	SetGlobal2Int(key .. "speed", hud.speed)
	SetGlobal2Int(key .. "cappers", hud.cappers)
	SetGlobal2Float(key .. "recede_time", hud.recedeAt)
	SetGlobal2Bool(key .. "can_recede", hud.canRecede)
	SetGlobal2Bool(key .. "alarm", hud.alarm)
	SetGlobal2String(key .. "cps", Joined(hud.cps, "%.4f"))
	SetGlobal2String(key .. "owners", Joined(hud.owners, "%d"))
	SetGlobal2String(key .. "hills", HillString(hud.hills))
end

local function PublishCarts()
	local watchers = ActiveWatchers()
	local distances = {}
	for i, watcher in ipairs(watchers) do
		local hud = watcher:HudState()
		PublishCart(i, hud)
		distances[hud.team] = watcher:TrainDistanceAlongTrack()
	end
	local race = WETSAND.HasMultipleTrains()
	SetGlobal2Int("wetsand_cart_count", #watchers)
	SetGlobal2Bool("wetsand_cart_race", race)
	SetGlobal2Int("wetsand_cart_race_leader", race and R.Leader(distances) or 0)
	return watchers
end

-- An area is the cart's when a watcher heard from it or its train carries it.
local function IsCartArea(area, watchers)
	for _, watcher in ipairs(watchers) do
		if watcher:UsesArea(area) then return true end
	end
	return false
end

local function PublishCaptures(watchers)
	local n = 0
	for _, area in ipairs(ents.FindByClass("trigger_capture_area")) do
		local hud = area:HudState()
		if hud and not IsCartArea(area, watchers) then
			n = n + 1
			local key = "wetsand_capture_" .. n .. "_"
			SetGlobal2Int(key .. "index", hud.index)
			SetGlobal2Int(key .. "owner", hud.owner)
			SetGlobal2Int(key .. "capping", hud.capping)
			SetGlobal2Float(key .. "progress", hud.progress)
			SetGlobal2Bool(key .. "blocked", hud.blocked)
			SetGlobal2Int(key .. "cappers", hud.cappers)
		end
	end
	SetGlobal2Int("wetsand_capture_count", n)
end

local nextPublish = 0
hook.Add("Think", "wetsand_payload_hud", function()
	if not WETSAND.Active() or CurTime() < nextPublish then return end
	nextPublish = CurTime() + 0.1
	PublishCaptures(PublishCarts())
end)

-- CTeamTrainWatcherMaster::FireGameEvent("teamplay_round_win"): on a race map
-- each side hears its stage outcome; full_round is a win that resets the map.
hook.Add("WetsandRoundWin", "wetsand_payload_race", function(winner)
	if not WETSAND.HasMultipleTrains() then return end
	for team, line in pairs(R.OutcomeLines(winner, WETSAND.Rules.forceMapReset)) do
		WETSAND.BroadcastSound(team, line)
	end
end)
