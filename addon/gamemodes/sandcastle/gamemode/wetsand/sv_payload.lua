-- Server side of payload: loads the pure libraries the payload entities use,
-- answers the round questions they ask (payload race), holds the round
-- timers while a cart is pushed, publishes every cart for the HUD (hiding
-- the carts' points from the point HUD), and plays the payload race
-- stage-outcome lines. Point questions go to the capture feature.

WETSAND.Payload = WETSAND.require("foundation.payload")
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

-- CTeamplayRoundBasedRules::TimerMayExpire asks every train watcher: a
-- pushed cart holds the clock. Registered once, by the first watcher.
local holdingTimers = false

function WETSAND.HoldTimersForWatchers()
	if holdingTimers then return end
	holdingTimers = true
	WETSAND.Feature("rounds"):AddTimerHold("payload", function()
		for _, watcher in ipairs(ents.FindByClass("team_train_watcher")) do
			if not watcher:TimerMayExpire() then return true end
		end
		return false
	end, false)
end

-- HUD publishing --------------------------------------------------------------------
-- wetsand_cart_count, wetsand_cart_race, wetsand_cart_race_leader, and per cart i (1-based)
-- wetsand_cart_<i>_{team,progress,speed,cappers,recede_time,can_recede,alarm,cps,owners,hills}.

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
	-- The capture feature draws the points now; cl_hud's old capture boxes
	-- stay empty until package R's cl_hud edit removes them (delete then).
	SetGlobal2Int("wetsand_capture_count", 0)
end

local nextPublish = 0
hook.Add("Think", "wetsand_payload_hud", function()
	if not WETSAND.Active() or CurTime() < nextPublish then return end
	nextPublish = CurTime() + 0.1
	PublishCarts()
end)

-- CTeamTrainWatcherMaster::FireGameEvent("teamplay_round_win"): on a race map
-- each side hears its stage outcome; full_round is a win that resets the map.
hook.Add("WetsandRoundWin", "wetsand_payload_race", function(winner)
	if not WETSAND.HasMultipleTrains() then return end
	for team, line in pairs(R.OutcomeLines(winner, WETSAND.Rules.forceMapReset)) do
		WETSAND.BroadcastSound(team, line)
	end
end)
