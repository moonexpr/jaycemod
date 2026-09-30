-- The payload feature's controller. It owns the map's train watchers and
-- the admin's cart speed scale. When a watcher binds it chooses the payload
-- mode (CTFGameRules::Activate); it holds the round clock while any cart
-- does (CTeamplayRoundBasedRules::TimerMayExpire asks every watcher); it
-- marks a payload race for the rounds controller (tf_logic_multiple_escort,
-- CTFGameRules::SetMultipleTrains); and it publishes every cart for the
-- payload view (wetsand_cart_*). The watchers' own decisions are
-- foundation.payload's; the race's and the HUD's are its parts'.
--
-- Loaded by team_train_watcher and tf_logic_multiple_escort.
local Payload = WETSAND.require("foundation.payload")
local PayloadMode = WETSAND.require("foundation.rounds.payload")
local Race = WETSAND.require("foundation.payload.race")
local Hud = WETSAND.require("foundation.payload.hud")

local NOBODY = WETSAND.TEAM_UNASSIGNED
local PUBLISH_INTERVAL = 0.1 -- the HUD's 10 Hz
local THINK_HOOK = "wetsand_payload"
local HOLD_NAME = "payload"
local NOT_A_CAPTURE_HOLD = false -- a pushed cart holds only while pushed, with no 0.1 s buffer

local Controller = {
	rounds = WETSAND.Feature("rounds"),
	capture = WETSAND.Feature("capture"),
	cartSpeedScale = Payload.CART_SPEED_DEFAULT,
	watchers = {}, -- the bound team_train_watchers, in the order they bound
	nextPublish = 0,
}

-- Watchers and the race --------------------------------------------------------------

function Controller:BindWatcher(ent)
	self.watchers[#self.watchers + 1] = ent
	self.rounds:SetMode(PayloadMode.Mode)
end

function Controller:UnbindWatcher(ent)
	table.RemoveByValue(self.watchers, ent)
end

function Controller:BindEscort(ent)
	self.rounds:SetMultipleTrains(true)
end

function Controller:HasMultipleTrains()
	return self.rounds:HasMultipleTrains()
end

-- The Game Rules editor's cart speed: a scale on every cart's top speed,
-- kept for the rest of the map.
function Controller:CartSpeedScale()
	return self.cartSpeedScale
end

function Controller:SetCartSpeedScale(scale)
	self.cartSpeedScale = Payload.SpeedScale(scale)
	for _, watcher in ipairs(self.watchers) do watcher:ApplyMaxSpeed() end
end

-- Whether any watcher holds the round clock at zero.
function Controller:HoldsTimer()
	for _, watcher in ipairs(self.watchers) do
		if not watcher:TimerMayExpire() then return true end
	end
	return false
end

-- The cart HUD -----------------------------------------------------------------------
-- wetsand_cart_count, wetsand_cart_race, wetsand_cart_race_leader, and per cart i
-- (1-based, Hud.Order) wetsand_cart_<i>_{team,progress,speed,cappers,recede_time,
-- can_recede,alarm,cps,owners,hills}.

local function PublishCart(i, hud)
	local key = "wetsand_cart_" .. i .. "_"
	SetGlobal2Int(key .. "team", hud.team)
	SetGlobal2Float(key .. "progress", hud.progress)
	SetGlobal2Int(key .. "speed", hud.speed)
	SetGlobal2Int(key .. "cappers", hud.cappers)
	SetGlobal2Float(key .. "recede_time", hud.recedeAt)
	SetGlobal2Bool(key .. "can_recede", hud.canRecede)
	SetGlobal2Bool(key .. "alarm", hud.alarm)
	SetGlobal2String(key .. "cps", Hud.EncodeNumbers(hud.cps, Hud.POSITION_FORMAT))
	SetGlobal2String(key .. "owners", Hud.EncodeNumbers(hud.owners, Hud.OWNER_FORMAT))
	SetGlobal2String(key .. "hills", Hud.EncodeHills(hud.hills))
end

-- The enabled watchers' carts, BLU's first.
function Controller:PublishCarts()
	local active = {}
	for _, watcher in ipairs(self.watchers) do
		if watcher:IsActive() then
			local hud = watcher:HudState()
			active[#active + 1] = {
				team = hud.team,
				index = watcher:EntIndex(),
				hud = hud,
				distance = watcher:TrainDistanceAlongTrack(),
			}
		end
	end
	local distances = {}
	local carts = Hud.Order(active)
	for i, cart in ipairs(carts) do
		PublishCart(i, cart.hud)
		distances[cart.team] = cart.distance
	end
	local race = self:HasMultipleTrains()
	SetGlobal2Int("wetsand_cart_count", #carts)
	SetGlobal2Bool("wetsand_cart_race", race)
	SetGlobal2Int("wetsand_cart_race_leader", race and Race.Leader(distances) or NOBODY)
end

hook.Add("Think", THINK_HOOK, function()
	local now = CurTime()
	if not WETSAND.Active() or now < Controller.nextPublish then return end
	Controller.nextPublish = now + PUBLISH_INTERVAL
	Controller:PublishCarts()
end)

Controller.rounds:AddTimerHold(HOLD_NAME, function() return Controller:HoldsTimer() end, NOT_A_CAPTURE_HOLD)

return Controller
