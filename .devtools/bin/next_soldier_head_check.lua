-- How a bot player's head goes with its feet, each tick, as data: how far its eyes are off
-- the way it moves, how they swing, how fast it goes and how it stalls.
--   (next_soldier_round_check.lua first: this watches NSRoundCheck.bot)
--   dt gmod lua_run instance=N code="$(cat .devtools/bin/next_soldier_head_check.lua)"
--   dt gmod lua_run instance=N code='return NSHeadCheck.Report()'
local MOVING = 50
local STALL = 30
local bot = NSRoundCheck.bot
local report =
{
	ticks = 0,
	off = { [15] = 0, [45] = 0, [90] = 0, [180] = 0 },
	speed = 0,
	swing = 0,
	bigSwings = 0,
	reversals = 0,
	stalls = {}
}
local lastYaw, lastTurn, stalledSince, stalledAt

local function Normal (a)
	a = a % 360
	if a > 180 then a = a - 360 end
	return a
end

hook.Add ("Tick", "ns_head_check", function ()
	if not IsValid (bot) or not bot:Alive () or WS.GameplayStopped () or WS.State () ~= 4 then
		lastYaw = nil
		return
	end
	local velocity = bot:GetVelocity ()
	local speed = velocity:Length2D ()
	local yaw = bot:EyeAngles ().y
	if speed >= MOVING then
		report.ticks = report.ticks + 1
		report.speed = report.speed + speed
		local off = math.abs (Normal (yaw - math.deg (math.atan2 (velocity.y, velocity.x))))
		for _, band in ipairs ({ 15, 45, 90, 180 }) do
			if off <= band then
				report.off [band] = report.off [band] + 1
				break
			end
		end
		if lastYaw then
			local turn = Normal (yaw - lastYaw)
			report.swing = report.swing + math.abs (turn)
			if math.abs (turn) >= 5 then report.bigSwings = report.bigSwings + 1 end
			if lastTurn and turn * lastTurn < 0 and math.abs (turn) >= 1 then report.reversals = report.reversals + 1 end
			if math.abs (turn) >= 0.01 then lastTurn = turn end
		end
	end
	lastYaw = yaw
	if speed < STALL and bot:OnGround () then
		stalledSince = stalledSince or CurTime ()
		stalledAt = bot:GetPos ()
	elseif stalledSince then
		local held = CurTime () - stalledSince
		if held >= 0.25 then
			report.stalls [#report.stalls + 1] = string.format ("%.1f s at %.0f,%.0f,%.0f", held, stalledAt.x, stalledAt.y, stalledAt.z)
		end
		stalledSince = nil
	end
end)

NSHeadCheck = {}

function NSHeadCheck.Report ()
	local ticks = math.max (report.ticks, 1)
	local seconds = ticks * engine.TickInterval ()
	return util.TableToJSON (
		{
			moving_seconds = seconds,
			mean_speed = report.speed / ticks,
			eyes_off_within_15 = report.off [15] / ticks,
			eyes_off_within_45 = report.off [45] / ticks,
			eyes_off_within_90 = report.off [90] / ticks,
			eyes_off_past_90 = report.off [180] / ticks,
			degrees_a_second = report.swing / seconds,
			big_swings_a_second = report.bigSwings / seconds,
			reversals_a_second = report.reversals / seconds,
			stalls = report.stalls
		}
	)
end

return "watching"
