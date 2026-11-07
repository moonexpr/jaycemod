-- A squad's radio: how its members know where to go, when to move in, fall back, regroup. Its
-- leader holds the channel: it speaks to its director (DIRECTOR: Overwatch, for the Combine), to the
-- whole squad (SQUAD) or to one member; a member speaks only to its leader, and the director only to
-- the leader. CALLS are what is said, a call with %s naming who it is about.
--
-- Say(order, from, to, call, ...) -> { from, to, call, text }, kept on the order's channel; refused,
-- as our bug: an unknown call, a member speaking to any but its leader, the director to any but the
-- leader. Calls(order) -> the channel, oldest first. Line(order, from, line) -> the entry for a line
-- the leggings call out aloud (their FALL_BACK_LINE, SIGNAL_LINE, CLEAR_LINE): from its leader to the
-- squad, kept as any call; nil for a line that is no call.
local error, format, tostring, setmetatable = error, string.format, tostring, setmetatable
local pairs = pairs
module("nextsoldier.squad.comms.radio")

DIRECTOR, SQUAD = "director", "squad"

CALLS = {
	STATUS = "Status report.",
	ALL_CLEAR = "All clear.",
	CONTACT = "Contact!",
	LOST = "Lost contact with %s.",
	STACK_UP = "Stack up, prepare to move.",
	MOVE_IN = "Move in!",
	NOW = "Now!",
	FALL_BACK = "Fall back!",
	ROOM_CLEAR = "Room clear!",
	REQUEST_VACATE = "Requesting clearance to vacate.",
	TAKE_PATROL = "Take over the patrol.",
	COPY = "Copy.",
	-- the director's answers (nextsoldier.squad.interactions.director), by their kind
	VACATE = "Clear to vacate.",
	DEFEND = "Negative. Hold the location.",
	ATTACK = "Negative. Assault the next room.",
	STANDBY = "Negative. Stand by.",
}

-- Each call's words, back to the call: a line said aloud is its call.
local BY_LINE = {}
for call, words in pairs(CALLS) do BY_LINE[words] = call end

-- Each order's channel, gone with the order.
local channels = setmetatable({}, { __mode = "k" })

function Calls(order)
	local channel = channels[order]
	if not channel then
		channel = {}
		channels[order] = channel
	end
	return channel
end

function Say(order, from, to, call, ...)
	local words = CALLS[call]
	if not words then error("no squad call " .. tostring(call), 2) end
	if from ~= order.leader and to ~= order.leader then
		error(from == DIRECTOR and "the director speaks only to the squad's leader" or "a member speaks only to its leader", 2)
	end
	local entry = { from = from, to = to, call = call, text = format(words, ...) }
	local channel = Calls(order)
	channel[#channel + 1] = entry
	return entry
end

function Line(order, from, line)
	local call = BY_LINE[line]
	if not (call and order) then return nil end
	local entry = { from = from, to = SQUAD, call = call, text = line }
	local channel = Calls(order)
	channel[#channel + 1] = entry
	return entry
end
