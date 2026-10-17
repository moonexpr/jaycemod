-- The spawn-room triggers held off while every spawn door stands open (a
-- halt, a win's humiliation), and which come back on after: those that were
-- on, as the map has since left them. A stage's handover lands in the bonus
-- time (pl_goldrush's cap_a_capture_relay turns RED's old spawn trigger off
-- and BLU's on as the room changes hands), and the next stage keeps it.
-- Triggers are opaque keys.
local pairs, setmetatable = pairs, setmetatable
module(...)

local HoldModel = {}
HoldModel.__index = HoldModel

-- on: the triggers that were on, now turned off.
function New(on)
	local wanted = {}
	for _, trigger in pairs(on) do wanted[trigger] = true end
	return setmetatable({ wanted = wanted }, HoldModel)
end

local MAP_INPUTS = {
	enable = true,
	disable = false,
}

-- The map's own input to a trigger while it is held (name lower-cased).
function HoldModel:MapInput(trigger, name)
	local on = MAP_INPUTS[name]
	if on == nil then return end
	self.wanted[trigger] = on or nil
end

-- The triggers to turn back on.
function HoldModel:ToEnable()
	local list = {}
	for trigger in pairs(self.wanted) do list[#list + 1] = trigger end
	return list
end
