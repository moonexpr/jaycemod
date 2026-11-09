-- The map's doors by kind, as the map itself opens them:
--   SPAWN: a team's way out of its spawn, opened as play starts (an arena's
--     round start) or guarded by a team's trigger (a door that opens for
--     its team alone);
--   SETUP: a setup gate, opened as setup finishes: by each team_round_timer's
--     own OnSetupFinished (the rounds' FinishSetup), never here, as a map may
--     give a timer those connections at runtime (AddOutput) where no
--     keyvalue shows them;
--   ROUND: one opened later in the round (an arena's point unlocking).
-- Plan(openers, guarded, kinds) says how to open the kinds asked for: the
-- map's own connections that open them (fired as the map would, so a door's
-- own OnOpen does the rest, a bullet blocker turned off), then the guarded
-- spawn doors no connection opens, by hand. Hold(on) keeps the spawn-room
-- triggers held off while the doors stand open, and which come back on after:
-- those that were on, as the map has since left them. A stage's handover
-- lands in the bonus time (pl_goldrush's cap_a_capture_relay turns RED's old
-- spawn trigger off and BLU's on as the room changes hands), and the next
-- stage keeps it. Triggers and doors' keys are opaque.
local Enum = core.enum
local Names = nextsoldier.world.doors
local ipairs, pairs, setmetatable = ipairs, pairs, setmetatable
local lower = string.lower
module(...)

KIND = Enum.New("DoorKind", 1, { "SPAWN", "SETUP", "ROUND" })

-- The doors held open while the game is stopped; setup gates are the timers'.
HALTED = { KIND.SPAWN, KIND.ROUND }

-- What opens each kind: an output of a class, by the output's name.
local OPENERS = {
	tf_logic_arena = { OnArenaRoundStart = KIND.SPAWN, OnCapEnabled = KIND.ROUND },
}

-- The inputs that open a door; a toggle may as well shut one.
local OPENING = { Open = true, Unlock = true }

-- Source's names are case-free: both looked up lower-cased.
local function Lowered(set)
	local lowered = {}
	for name, value in pairs(set) do lowered[lower(name)] = value end
	return lowered
end

local OPENER_OUTPUTS = {}
for class, outputs in pairs(OPENERS) do OPENER_OUTPUTS[class] = Lowered(outputs) end
local OPENING_INPUTS = Lowered(OPENING)

-- The classes whose outputs open doors.
function OpenerClasses()
	local classes = {}
	for class in pairs(OPENERS) do classes[#classes + 1] = class end
	return classes
end

-- openers: { class, outputs }s; guarded: { key, name }s, the doors a team's
-- trigger stands at; kinds: a list of KIND. -> { fire = { kind, output }s,
-- open = the guarded doors to open by hand }.
function Plan(openers, guarded, kinds)
	local wanted = {}
	for _, kind in ipairs(kinds) do wanted[kind] = true end
	local fire, opened = {}, {}
	for _, opener in ipairs(openers) do
		local names = OPENER_OUTPUTS[opener.class]
		for _, output in ipairs(names and opener.outputs or {}) do
			local kind = names[lower(output.name)]
			if kind and OPENING_INPUTS[lower(output.input)] then
				opened[#opened + 1] = output
				if wanted[kind] then fire[#fire + 1] = { kind = kind, output = output } end
			end
		end
	end
	local open = {}
	if wanted[KIND.SPAWN] then
		for _, door in ipairs(guarded) do
			if not Names.Opens(opened, door.name) then open[#open + 1] = door end
		end
	end
	return { fire = fire, open = open }
end

local HoldModel = {}
HoldModel.__index = HoldModel

-- on: the triggers that were on, now turned off.
function Hold(on)
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
