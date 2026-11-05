-- The world feature's controller: the map's own state, which the game's
-- controllers ask to change and do not manage. For now, its doors
-- (features.world.doors): opened by kind as the map itself opens them, held
-- open while asked (a stopped game, a win's humiliation, sudden death), and
-- shut again for the next round. The rounds controller asks; this keeps them.
--   OpenDoors(now, kinds): kinds a list of Doors.KIND; SETUP is the timers'
--   (the rounds' FinishSetup fires their OnSetupFinished)
--   CloseDoors(): what was held open, shut, its triggers back as the map left them
--   Each(class, fn): fn(ent) for each entity of class, as the rounds' EachPlayer
local Doors = WS.require("features.world.doors")

local Overlap = math.box.Overlaps

-- How often held doors are told again to open, as a map may shut them.
local HOLD_INTERVAL = 2

local Controller = {
	KIND = Doors.KIND,
	held = nil, -- the doors held open, or nil
	heldTriggers = nil, -- the guarded doors' triggers turned off: trigger -> true
	triggerHold = nil, -- which of them come back on (Doors.Hold)
	switchingTriggers = false, -- our own Enable/Disable, not the map's
	nextHold = 0,
}

-- fn(ent) for each of the map's entities of class (a Source wildcard, "func_door*", too).
local function Each(class, fn)
	for _, ent in ipairs(ents.FindByClass(class)) do fn(ent) end
end
Controller.Each = Each

-- The doors a team's trigger stands at ({ key = the door, name }), and those
-- triggers: func_doors overlapped by a trigger_multiple whose filter is a
-- filter_activator_tfteam.
local function Guarded()
	local triggers = {}
	Each("trigger_multiple", function(trigger)
		local filter = trigger:GetInternalVariable("m_hFilter")
		if IsValid(filter) and filter:GetClass() == "filter_activator_tfteam" then
			local mins, maxs = trigger:WorldSpaceAABB()
			triggers[#triggers + 1] = { ent = trigger, mins = mins, maxs = maxs }
		end
	end)
	local doors, doorTriggers = {}, {}
	Each("func_door*", function(door)
		local mins, maxs = door:WorldSpaceAABB()
		local found = false
		for _, trigger in ipairs(triggers) do
			if Overlap(mins, maxs, trigger.mins, trigger.maxs) then
				found = true
				doorTriggers[trigger.ent] = true
			end
		end
		if found then doors[#doors + 1] = { key = door, name = door:GetName() } end
	end)
	return doors, doorTriggers
end

local function Openers()
	local openers = {}
	for _, class in ipairs(Doors.OpenerClasses()) do
		Each(class, function(ent)
			openers[#openers + 1] = { ent = ent, class = class, outputs = WS.KeyValues(ent).outputs }
		end)
	end
	return openers
end

local function IsDoor(ent) return string.find(ent:GetClass(), "^func_door") ~= nil end

-- Holds a guarded door's triggers off so none shuts it, remembering those
-- that were on, with what the map does to them meanwhile.
function Controller:HoldTriggers(triggers)
	if self.triggerHold then return end
	local on = {}
	for trigger in pairs(triggers) do
		if not trigger:GetInternalVariable("m_bDisabled") then on[#on + 1] = trigger end
	end
	self.heldTriggers, self.triggerHold = triggers, Doors.Hold(on)
	self.switchingTriggers = true
	for _, trigger in ipairs(on) do trigger:Input("Disable") end
	self.switchingTriggers = false
end

-- The doors of these kinds opened: the map's own connections that open them
-- fired as the map would (a door's own OnOpen then does the rest, a bullet
-- blocker turned off), then the guarded spawn doors none of them opens, by
-- hand; all held open until CloseDoors or the next map reset.
function Controller:OpenDoors(now, kinds)
	local guarded, triggers = Guarded()
	local plan = Doors.Plan(Openers(), guarded, kinds)
	local held = self.held or {}
	for _, connection in ipairs(plan.fire) do
		local output = connection.output
		for _, target in ipairs(WS.MapIO:FindByName(output.target)) do
			target:Fire(output.input, output.param, output.delay)
			if IsDoor(target) then held[target] = true end
		end
	end
	if #plan.open > 0 then self:HoldTriggers(triggers) end
	for _, door in ipairs(plan.open) do
		door.key:Fire("Unlock")
		door.key:Fire("Open")
		held[door.key] = true
	end
	self.held, self.nextHold = held, now + HOLD_INTERVAL
end

-- The next round (a stage of a multi-stage map has no map reset): the
-- triggers that were on, on again unless the map has since turned them off,
-- with those it turned on, and the doors held open closed for them to open.
function Controller:CloseDoors()
	if self.triggerHold then
		self.switchingTriggers = true
		for _, trigger in ipairs(self.triggerHold:ToEnable()) do
			if IsValid(trigger) then trigger:Input("Enable") end
		end
		self.switchingTriggers = false
	end
	for door in pairs(self.held or {}) do
		if IsValid(door) then door:Fire("Close") end
	end
	self.held, self.heldTriggers, self.triggerHold = nil, nil, nil
end

-- The doors held open stay so, told again every HOLD_INTERVAL.
function Controller:KeepDoorsOpen(now)
	if not self.held or now < self.nextHold then return end
	self.nextHold = now + HOLD_INTERVAL
	for door in pairs(self.held) do
		if IsValid(door) then door:Fire("Open") end
	end
end

hook.Add("Think", "ws_world_doors", function() Controller:KeepDoorsOpen(CurTime()) end)

-- A cleanup makes the map's doors and triggers anew, shut and on: nothing is held.
hook.Add("PreCleanupMap", "ws_world_doors", function()
	Controller.held, Controller.heldTriggers, Controller.triggerHold = nil, nil, nil
end)

-- The map's own Enable and Disable of a held trigger: a stage's handover in
-- the bonus time (pl_goldrush's cap_a_capture_relay) outlasts the hold.
hook.Add("AcceptInput", "ws_world_doors", function(ent, input)
	local self = Controller
	if self.switchingTriggers or not (self.heldTriggers and self.heldTriggers[ent]) then return end
	self.triggerHold:MapInput(ent, string.lower(input))
end)

return Controller
