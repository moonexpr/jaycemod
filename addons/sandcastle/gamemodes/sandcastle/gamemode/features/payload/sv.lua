-- The payload feature's controller. It owns the map's train watchers and
-- the admin's cart speed scale. A watcher that is part of the payload's
-- logic (linking a path_track to a control point: team_train_watcher's
-- IsObjective) chooses the payload mode; one watching a train that is
-- scenery (ctf_turbine_winter's minecart) does not. It holds the round clock while any cart
-- does (CTeamplayRoundBasedRules::TimerMayExpire asks every watcher); it
-- marks a payload race for the rounds controller (tf_logic_multiple_escort,
-- CTFGameRules::SetMultipleTrains); and it publishes every cart for the
-- payload view (ws_cart_*). The watchers' own decisions are
-- features.payload.model's; the race's and the HUD's are its parts'.
--
-- Loaded by team_train_watcher and tf_logic_multiple_escort.
local Payload = WS.require("features.payload.model")
local PayloadMode = WS.require("features.payload.round")
local Race = WS.require("features.payload.race")
local Hud = WS.require("features.payload.hud")

local NOBODY = WS.TEAM_UNASSIGNED
local PUBLISH_INTERVAL = 0.1 -- the HUD's 10 Hz
local THINK_HOOK = "ws_payload"
local HOLD_NAME = "payload"
local NOT_A_CAPTURE_HOLD = false -- a pushed cart holds only while pushed, with no 0.1 s buffer

local Controller = {
	rounds = WS.Feature("rounds"),
	capture = WS.Feature("capture"),
	cartSpeedScale = Payload.CART_SPEED_DEFAULT,
	watchers = {}, -- the bound team_train_watchers, in the order they bound
	nextPublish = 0,
}

-- Watchers and the race --------------------------------------------------------------

function Controller:BindWatcher(ent)
	self.watchers[#self.watchers + 1] = ent
end

-- A watcher of the payload's logic makes the game payload (CTFGameRules::Activate's escort).
function Controller:ChooseMode()
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
-- ws_cart_count, ws_cart_race, ws_cart_race_leader, and per cart i
-- (1-based, Hud.Order) ws_cart_<i>_{team,progress,speed,cappers,recede_time,
-- can_recede,alarm,cps,owners,hills}.

local function PublishCart(i, hud)
	local key = "ws_cart_" .. i .. "_"
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

-- Each cart and each of its checkpoints has a proxy (WS.Proxy, kind
-- "cart") for its watcher, the box an admin right-clicks for its entries
-- (ws/sh_editors_cart.lua): one riding the train, one at each point,
-- made again when a cleanup removes them. The cart's body, a prop the map
-- ties to the train with a constraint (phys_constraint and the rest), names
-- the cart's proxy (ws_proxy), as GMod's right-click hits it first,
-- and so do the props of a checkpoint's base (WS.ProxyBodies).
local CART_MINS, CART_MAXS = Vector(-40, -40, 0), Vector(40, 40, 80)
local POINT_MINS, POINT_MAXS = Vector(-48, -48, -8), Vector(48, 48, 64)
local function KeepProxies(watcher)
	local train = watcher:Train()
	if IsValid(train) then
		local proxy, made = WS.Proxy(train, "cart", watcher, CART_MINS, CART_MAXS, train)
		if made then
			for _, body in ipairs(WS.TiedTo(train)) do body:SetNW2Entity("ws_proxy", proxy) end
		end
	end
	for _, point in ipairs(watcher:Checkpoints()) do
		if IsValid(point) then
			local proxy, made = WS.Proxy(point, "cart", watcher, POINT_MINS, POINT_MAXS)
			if made then WS.ProxyBodies(proxy, point:GetPos()) end
		end
	end
end

-- The enabled watchers' carts, BLU's first; none on a map another mode won
-- (TF2 shows the escort HUD for the payload game type only: pd_watergate's
-- UFO rides a watcher on a Player Destruction map).
function Controller:PublishCarts()
	local active = {}
	local payload = self.rounds:Mode() == PayloadMode.Mode
	for _, watcher in ipairs(self.watchers) do
		if payload and watcher:IsActive() then
			KeepProxies(watcher)
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
	SetGlobal2Int("ws_cart_count", #carts)
	SetGlobal2Bool("ws_cart_race", race)
	SetGlobal2Int("ws_cart_race_leader", race and Race.Leader(distances) or NOBODY)
end

hook.Add("Think", THINK_HOOK, function()
	local now = CurTime()
	if not WS.Active() or now < Controller.nextPublish then return end
	Controller.nextPublish = now + PUBLISH_INTERVAL
	Controller:PublishCarts()
end)

Controller.rounds:AddTimerHold(HOLD_NAME, function() return Controller:HoldsTimer() end, NOT_A_CAPTURE_HOLD)

return Controller
