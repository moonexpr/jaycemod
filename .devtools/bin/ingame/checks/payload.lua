-- Payload (docs/pass4-koth-cp.md §9.1 "Payload regression"): after setup,
-- BLU bots beside the cart, inside the capture area that rides it, push it:
-- it moves along its track and the HUD's progress rises, and pushing on
-- captures the first checkpoint.
-- args: { team_size = n pushers (default 3) }
local Tests = WETSAND_TESTS
local S = WETSAND.STATE
local BLUE = WETSAND.TEAM_BLUE
local DEFAULT_TEAM_SIZE = 3
local SETUP_TIMEOUT = 100
local MOVE_SAMPLE = 10 -- seconds of pushing before the first reading
local MIN_DISTANCE = 50 -- units the cart must have moved
local CHECKPOINT_TIMEOUT = 240

-- Pushers stand in a row beside the train, just clear of its own bounds
-- (a player overlapping the train's brush blocks it, and the bots are put
-- back every 0.2 s), and still within reach of the area riding it.
local PLAYER_HALF_WIDTH = 16
local CLEARANCE = 4

local function SideSpots(train, count)
	local mins, maxs = train:OBBMins(), train:OBBMaxs()
	local middle = (mins + maxs) * 0.5
	local spots = {}
	for i = 1, count do
		local x = mins.x + (maxs.x - mins.x) * i / (count + 1)
		spots[i] = Tests.FloorUnder(train, Vector(x, maxs.y + PLAYER_HALF_WIDTH + CLEARANCE, middle.z))
	end
	return spots
end

return function(t)
	local capture, rounds = t:Feature("capture"), t:Feature("rounds")
	if not (capture and rounds and t:Loaded("payload")) then return t:Skip("payload, capture or rounds not loaded") end
	local watcher = ents.FindByClass("team_train_watcher")[1]
	local train = IsValid(watcher) and watcher.train
	t:Check("a team_train_watcher with its train", IsValid(train), tostring(train))
	if not IsValid(train) then return end
	local area
	for _, a in ipairs(ents.FindByClass("trigger_capture_area")) do
		if a:GetParent() == train then area = a end
	end
	t:Check("a capture area rides the train", IsValid(area), tostring(area))
	if not IsValid(area) then return end

	local open, waited = t:WaitFor(SETUP_TIMEOUT, function()
		return WETSAND.State() == S.RND_RUNNING and rounds:PointsMayBeCaptured()
	end)
	t:Check("setup over, points may be captured", open ~= nil,
		string.format("%s after %.1f s", Tests.StateName(WETSAND.State()), waited))
	if not open then return end

	local ownedBefore = {}
	for _, point in ipairs(capture:Points()) do ownedBefore[point] = capture:Owner(point) end
	t:Info("points_at_start", Tests.DescribePoints(capture, BLUE))

	local bots = {}
	for _, ply in ipairs(player.GetBots()) do
		if ply:Team() == BLUE and #bots < (t.args.team_size or DEFAULT_TEAM_SIZE) then bots[#bots + 1] = ply end
	end
	local startPos, startProgress = train:GetPos(), GetGlobal2Float("wetsand_cart_1_progress", 0)
	t:Station(bots, function() return SideSpots(train, #bots) end)
	-- What the cart did each second, to tell a stuck cart from a slow one.
	local samples = {}
	for second = 1, MOVE_SAMPLE do
		t:Wait(1)
		samples[#samples + 1] = string.format("%ds: moved %.0f, m_flSpeed %.1f, hud speed %d, hud cappers %d, inside %d",
			second, train:GetPos():Distance(startPos), train:GetInternalVariable("m_flSpeed") or -1,
			GetGlobal2Int("wetsand_cart_1_speed", 0), GetGlobal2Int("wetsand_cart_1_cappers", 0),
			#WETSAND.PlayersInside(area))
	end
	t:Info("push_samples", samples)
	local models = {}
	for _, child in ipairs(train:GetChildren()) do
		local model = child:GetModel()
		if model and not string.StartWith(model, "*") then
			models[#models + 1] = model .. (util.IsValidModel(model) and "" or " (missing on this server)")
		end
	end
	t:Info("cart_models", models)
	local pushers = #WETSAND.PlayersInside(area)
	local moved = train:GetPos():Distance(startPos)
	local progress = GetGlobal2Float("wetsand_cart_1_progress", 0)
	t:Info("pushers_inside", pushers)
	t:Check("BLU bots stand in the cart's area", pushers > 0, pushers .. " of " .. #bots)
	t:Check("the cart moves with BLU pushing", moved > MIN_DISTANCE,
		string.format("%.0f units in %d s", moved, MOVE_SAMPLE))
	t:Check("the cart's progress rises", progress > startProgress,
		string.format("%.3f -> %.3f", startProgress, progress))

	local taken, took = t:WaitFor(CHECKPOINT_TIMEOUT, function()
		for point, owner in pairs(ownedBefore) do
			if IsValid(point) and owner ~= BLUE and capture:Owner(point) == BLUE then return Tests.PointName(capture, point) end
		end
	end)
	t:Unstation()
	t:Check("pushing captures the first checkpoint", taken ~= nil,
		string.format("%s after %.0f s more, progress %.3f", tostring(taken), took, GetGlobal2Float("wetsand_cart_1_progress", 0)))
	t:Info("points_at_end", Tests.DescribePoints(capture, BLUE))
	t:Info("state_at_end", Tests.StateName(WETSAND.State()))
end
