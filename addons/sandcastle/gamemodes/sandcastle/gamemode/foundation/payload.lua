-- The team_train_watcher's decisions, from team_train_watcher.cpp, as pure
-- functions: how fast the cart goes, which speed arrows the HUD shows, when
-- it recedes, how far it has come, and when the announcer and the capture
-- alarm sound. The entity feeds them what it reads from the world.
local ipairs, math = ipairs, math
module(...)

HILL_NONE, HILL_UP, HILL_DOWN = 0, 1, 2
-- InternalSetNumTrainCappers(-1): the enemy is on the cart, which stands still.
CAPPERS_BLOCKED = -1
-- m_iTrainSpeedLevel while the cart rolls back.
SPEED_LEVEL_BACKWARDS = -1

ALERT_DISTANCE = 750           -- TEAM_TRAIN_ALERT_DISTANCE: the announcer's warning
ALARM_DISTANCE = 200           -- TEAM_TRAIN_ALARM_DISTANCE: the looping alarm at the point
MAX_ALARM_TIME_NO_RECEDE = 18  -- loop length when the train cannot recede
ALARM_SINGLE_INTERVAL = 8      -- TW_ALARM_THINK_INTERVAL

local RECEDE_SPEED = -0.1
local PUSH_SPEED = { 0.55, 0.77, 1.0 }

local function PushSpeed(numCappers, hill)
	if hill == HILL_DOWN then return 1.0 end
	return PUSH_SPEED[math.min(numCappers, #PUSH_SPEED)]
end

local function IdleSpeed(s)
	if s.currentSpeed > 0 then
		return s.hill == HILL_DOWN and 1.0 or 0
	end
	if s.hill == HILL_UP then return -1.0 end
	return s.receding and RECEDE_SPEED or 0
end

-- HandleTrainMovement. s = { numCappers, hill, currentSpeed, receding }.
-- Returns the speed fraction to set and the new receding flag.
function TrainSpeed(s, startReceding)
	local speed, receding = 0, s.receding
	if startReceding then
		speed, receding = RECEDE_SPEED, true
	elseif s.numCappers > 0 then
		speed, receding = PushSpeed(s.numCappers, s.hill), false
	elseif s.numCappers == CAPPERS_BLOCKED then
		-- a blocked cart stands still unless it is rolling downhill
		speed = s.hill == HILL_DOWN and 1.0 or 0
	else
		speed = IdleSpeed(s)
	end
	if speed ~= s.currentSpeed and speed >= 0 then receding = false end
	return speed, receding
end

-- WatcherThink's m_iTrainSpeedLevel: backwards (0 once stopped at a dead
-- end), else 0..3 by the hud_min_speed_level_1..3 thresholds.
function SpeedLevel(desiredSpeed, currentSpeed, levels)
	if desiredSpeed < 0 then return currentSpeed == 0 and 0 or SPEED_LEVEL_BACKWARDS end
	for level = 3, 1, -1 do
		if desiredSpeed > levels[level] then return level end
	end
	return 0
end

-- WatcherThink's concepts (TF2's response rules: scripts/talker): a cart
-- that stops has everyone speak TLK_CART_STOP, one that starts back from
-- standing TLK_CART_MOVING_BACKWARD (either lets the pushers speak again at
-- once), and one going forward has the players on its capture area speak
-- TLK_CART_MOVING_FORWARD, at most every FORWARD_CONCEPT_INTERVAL.
CONCEPT_CART_STOP = "TLK_CART_STOP"
CONCEPT_CART_MOVING_BACKWARD = "TLK_CART_MOVING_BACKWARD"
CONCEPT_CART_MOVING_FORWARD = "TLK_CART_MOVING_FORWARD"
AUDIENCE_ALL, AUDIENCE_PUSHERS = "all", "pushers"
FORWARD_CONCEPT_INTERVAL = 3

-- From the speed level before and now, and when the pushers may next speak
-- (nextForward): the concepts to speak, each { concept, audience }, and the
-- new nextForward.
function SpeedConcepts(oldLevel, level, nextForward, now)
	local said = {}
	if level ~= oldLevel then
		if level == 0 and oldLevel ~= 0 then
			said[#said + 1] = { concept = CONCEPT_CART_STOP, audience = AUDIENCE_ALL }
			nextForward = 0
		elseif level < 0 and oldLevel == 0 then
			said[#said + 1] = { concept = CONCEPT_CART_MOVING_BACKWARD, audience = AUDIENCE_ALL }
			nextForward = 0
		end
	end
	if level > 0 and nextForward < now then
		said[#said + 1] = { concept = CONCEPT_CART_MOVING_FORWARD, audience = AUDIENCE_PUSHERS }
		nextForward = now + FORWARD_CONCEPT_INTERVAL
	end
	return said, nextForward
end

-- InternalSetNumTrainCappers: seconds until an unpushed cart recedes.
function RecedeDelay(overtime, trainRecedeTime, recedeTime, overtimeRecedeTime)
	if overtime then return overtimeRecedeTime end
	if trainRecedeTime > 0 then return trainRecedeTime end
	return recedeTime
end

-- InputOnStartOvertime: a pending recede longer than the overtime length is cut to it.
function OvertimeRecedeAt(recedeAt, now, overtimeLen)
	if recedeAt - now > overtimeLen then return now + overtimeLen end
	return recedeAt
end

-- CTeamTrainWatcher::TimerMayExpire, plus CTFGameRules::TimerMayExpire's
-- hold while a point is being captured, for the cart's own area, so the
-- round clock holds in overtime while the cart is pushed, blocked, or
-- waiting to recede. q = { disabled, waitingToRecede, capBlocked, areaCapturing }.
function TimerMayExpire(q)
	if q.disabled then return true end
	if q.waitingToRecede or q.capBlocked then return false end
	return not q.areaCapturing
end

-- The path node the train is heading for, given the index of its current
-- node (func_tracktrain's m_ppath): the next one, or its own when reversing.
function TargetIndex(pathIndex, speed, count)
	if speed < 0 then return pathIndex end
	return math.min(pathIndex + 1, count)
end

-- The train's current node after it passes node `index`: CFuncTrackTrain
-- fires OnPass on the new node going forward, and on the node it leaves
-- going backward.
function PassedIndex(index, speed)
	if speed >= 0 then return index end
	return math.max(index - 1, 1)
end

-- distanceAt[i] is the path length from the start node to node i.
function DistanceToGoal(total, distanceAt, targetIndex, straight)
	return straight + total - distanceAt[targetIndex]
end

function Progress(total, distanceToGoal)
	return math.min(math.max(1 - distanceToGoal / total, 0), 1)
end

-- Approach alerts. links = { { distance, alerted }, ... }, updated in place;
-- returns the indices whose alert should play now.
function AlertsDue(links, trainDistance, canRecede)
	local due = {}
	for i, link in ipairs(links) do
		if trainDistance < link.distance - ALERT_DISTANCE then
			-- re-arm after backing off twice the distance, or for a train
			-- that rolled back down a hill although it never recedes
			if trainDistance < link.distance - 2 * ALERT_DISTANCE or not canRecede then
				link.alerted = false
			end
		elseif trainDistance < link.distance and not link.alerted then
			link.alerted = true
			due[#due + 1] = i
		end
	end
	return due
end

-- The capture alarm: a loop at the final point while the train is within
-- ALARM_DISTANCE of the goal. Actions: "start" (loop), "stop" (loop and
-- singles), "single" (one Cart.WarningSingle).
local NO_END = -1 -- endAt of an alarm that is not looping

function NewAlarm()
	return { playing = false, played = false, endAt = NO_END, nextSingle = nil }
end

-- StopCaptureAlarm
local function StopAlarmInto(a, out)
	if a.playing or a.nextSingle then out[#out + 1] = "stop" end
	a.playing, a.endAt, a.nextSingle = false, NO_END, nil
end

-- StopCaptureAlarm on its own (RoundActivate, Enable, Disable); returns the actions.
function StopAlarm(a)
	local out = {}
	StopAlarmInto(a, out)
	return out
end

-- One WatcherThink (and WatcherAlarmThink) step.
function AlarmStep(a, distanceToGoal, running, canRecede, hasLinks, now)
	local out = {}
	if a.nextSingle and now >= a.nextSingle then
		out[#out + 1] = "single"
		a.nextSingle = a.nextSingle + ALARM_SINGLE_INTERVAL
	end
	if not running then StopAlarmInto(a, out) end
	if distanceToGoal > ALARM_DISTANCE then
		StopAlarmInto(a, out)
		a.played = false
	elseif running then
		if not a.playing then
			-- played: on maps where the train does not recede, the loop
			-- plays once and then only singles
			if hasLinks and not a.played then
				out[#out + 1] = "start"
				a.playing, a.played, a.endAt = true, true, now + MAX_ALARM_TIME_NO_RECEDE
			end
		elseif not canRecede and a.endAt > 0 and a.endAt < now then
			StopAlarmInto(a, out)
			a.nextSingle = now + ALARM_SINGLE_INTERVAL
		end
	end
	return out
end

-- WatcherActivate's hill data for the HUD. nodes[i] = { distance, hill } from
-- the start node to the goal; returns { { from, to, down }, ... } as
-- fractions of the path, pulled 0.005 inward so a train stopped at the foot
-- or top of a hill does not show as on it.
function HillSegments(nodes, total)
	local marks, down = {}, {}
	local onHill, hillStart, current = false, nil, HILL_NONE
	local function StartHill(i, distance)
		marks[#marks + 1] = distance
		onHill, hillStart = true, i
		down[#down + 1] = nodes[i].hill == HILL_DOWN
	end
	for i = 2, #nodes do
		local node = nodes[i]
		if node.hill ~= current then
			if not onHill then
				StartHill(i, node.distance)
			else
				-- the previous node ended the hill, unless the hill was that one node
				local length = node.distance - nodes[i - 1].distance
				marks[#marks + 1] = hillStart == i - 1 and node.distance or node.distance - length
				if node.hill ~= HILL_NONE then
					StartHill(i, node.distance)
				else
					onHill, hillStart = false, nil
				end
			end
			current = node.hill
		end
	end
	if #marks % 2 ~= 0 then marks[#marks + 1] = total end
	local hills = {}
	if total <= 0 then return hills end
	for k = 1, #marks, 2 do
		hills[#hills + 1] = { from = marks[k] / total + 0.005, to = marks[k + 1] / total - 0.005, down = down[(k + 1) / 2] }
	end
	return hills
end

-- Admin controls (the Game Rules editor) --------------------------------------------

-- The cart's top speed scale an admin may set.
CART_SPEED_MIN, CART_SPEED_MAX = 0.1, 4
CART_SPEED_DEFAULT = 1 -- the map's own speed

-- The scale an admin asked for, within the editor's range.
function SpeedScale(scale)
	return math.min(math.max(scale, CART_SPEED_MIN), CART_SPEED_MAX)
end

-- links: the watcher's checkpoints in path order, { distance, index }.
-- The first one farther along the path than `distance`, or nil.
function NextCheckpoint(links, distance)
	for _, link in ipairs(links) do
		if link.distance > distance then return link end
	end
	return nil
end

-- The Game Rules editor's retract. A cart at most RETRACT_NEAR past the last
-- point it took gives that point back (uncap), the attackers gain
-- RETRACT_SLACK seconds for it, and the cart goes to the checkpoint before
-- (to; nil is the start of the track); farther on, it only goes back to the
-- last point (to), giving nothing back. links in path order, as above.
RETRACT_NEAR = 200
RETRACT_SLACK = 300

function RetractPlan(links, distance)
	local last
	for i, link in ipairs(links) do
		if link.distance <= distance then last = i end
	end
	if not last then return { uncap = nil, to = nil } end
	if distance - links[last].distance <= RETRACT_NEAR then
		return { uncap = links[last], to = links[last - 1] }
	end
	return { uncap = nil, to = links[last] }
end

-- Whether the watcher sets the train's speed: with handle_train_movement
-- always; on a map that drives its own cart (pl_goldrush's capture area ->
-- logic_case), only while an admin advances it.
function WatcherDrives(handleMovement, advancing)
	return handleMovement or advancing
end

-- Whether a cart `distance` along its watcher's track (negative: short of
-- its start) is on it: a stage's cart stops a little short of the start;
-- farther back it is still riding there (pl_goldrush's lift) and an admin's
-- advance would drive it into the ride.
ON_TRACK_SLACK = 64

function OnTrack(distance)
	return distance >= -ON_TRACK_SLACK
end

-- The Game Rules editor's advance: the node (an index into the path) to
-- teleport the cart to, as a retract does: the one before the checkpoint, so
-- the cart rolls the last stretch at the map's speed and passes the
-- checkpoint (its OnPass is the map's stop, capture relay, a stage's lift).
-- nil when the cart (on the node pathIndex, or past it) is already on that
-- stretch.
function AdvanceFrom(pathIndex, checkpointIndex)
	local from = checkpointIndex - 1
	if pathIndex >= from then return nil end
	return from
end

-- A cart an admin advances does not recede on the way (OnTrainStartRecede).
function MayRecede(advancing)
	return not advancing
end

-- The train's m_maxSpeed for the map's top speed `base`.
function MaxSpeed(base, scale)
	return base * SpeedScale(scale)
end
