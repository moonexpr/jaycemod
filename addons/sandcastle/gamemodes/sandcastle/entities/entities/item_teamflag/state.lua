-- A flag's state and the rules of carrying it (CCaptureFlag,
-- entity_capture_flag.cpp), held by item_teamflag.
--
-- A flag is at HOME, CARRIED or DROPPED. Each change returns events
-- { kind, team }: PICKUP and DROP name the carrier's team, CAPTURE the
-- capturing team, RETURN the flag's own.
local RED, BLUE, NOBODY = TEAM_RED, TEAM_BLUE, TF_TEAM_UNASSIGNED

local HOME, CARRIED, DROPPED = "home", "carried", "dropped"
local PICKUP, DROP, CAPTURE, RETURN = "pickup", "drop", "capture", "return"

-- item_teamflag's ReturnTime default (the FGD's).
local RETURN_TIME_DEFAULT = 60

-- CCaptureFlag::PickUp's team check: a neutral flag goes to anyone; a
-- team's to its enemies, or in MvM (ownersCarry) to its own team only.
local function MayCarry (flagTeam, carrierTeam, ownersCarry)
	if carrierTeam ~= RED and carrierTeam ~= BLUE then return false end
	if flagTeam == NOBODY then return true end
	if ownersCarry then return flagTeam == carrierTeam end
	return flagTeam ~= carrierTeam
end

-- CFuncRespawnRoom::RespawnRoomTouch: a carrier running into its own
-- team's respawn room (roomTeam) drops the flag, unless the room is the
-- invaders' (MvM's TF_TEAM_PVE_INVADERS; nil in other modes).
local function DropsIn (roomTeam, carrierTeam, invaders)
	return roomTeam == carrierTeam and roomTeam ~= invaders
end

local Flag = {}
Flag.__index = Flag

-- t = { team, returnTime (seconds), disabled }.
local function New (t)
	return setmetatable (
		{
			team = t.team,
			returnTime = t.returnTime or RETURN_TIME_DEFAULT,
			enabled = not t.disabled,
			state = HOME,
			carrier = nil,
			carrierTeam = NOBODY,
			returnAt = 0
		}, Flag)
end

function Flag:State () return self.state end
function Flag:Team () return self.team end
function Flag:Enabled () return self.enabled end
function Flag:Carrier () return self.carrier end
function Flag:CarrierTeam () return self.carrierTeam end
function Flag:ReturnTime () return self.returnTime end
function Flag:ReturnAt () return self.returnAt end

function Flag:SetTeam (team) self.team = team end
-- No number: ReturnTime's default.
function Flag:SetReturnTime (seconds) self.returnTime = seconds or RETURN_TIME_DEFAULT end

function Flag:MayCarry (carrierTeam, ownersCarry)
	return MayCarry (self.team, carrierTeam, ownersCarry)
end

local function Event (kind, team)
	return
	{
		{
			kind = kind,
			team = team
		}
	}
end

local function SendHome (self)
	self.state, self.carrier, self.carrierTeam = HOME, nil, NOBODY
end

-- q = { ownersCarry, mayBeCapped }.
function Flag:PickUp (carrier, carrierTeam, q)
	if not self.enabled or self.state == CARRIED or not q.mayBeCapped then return {} end
	if not self:MayCarry (carrierTeam, q.ownersCarry) then return {} end
	self.state, self.carrier, self.carrierTeam = CARRIED, carrier, carrierTeam
	return Event (PICKUP, carrierTeam)
end

-- The carrier died, left or was made to drop it (ForceDrop). Dropped in a
-- func_respawnflag zone (inResetZone), it is reset at once
-- (CCaptureFlag::Drop's PointInRespawnFlagZone): DROP, then RETURN.
function Flag:Drop (now, inResetZone)
	if self.state ~= CARRIED then return {} end
	local team = self.carrierTeam
	self.state, self.carrier, self.carrierTeam = DROPPED, nil, NOBODY
	self.returnAt = now + self.returnTime
	local events = Event (DROP, team)
	if inResetZone then events [2] = self:Reset (false) [1] end
	return events
end

-- A dropped flag returns home once its ReturnTime has passed.
function Flag:Think (now)
	if self.state ~= DROPPED or now < self.returnAt then return {} end
	return self:Reset (false)
end

-- ForceReset, or ForceResetSilent: home, announced unless silent.
function Flag:Reset (silent)
	if self.state == HOME then return {} end
	SendHome (self)
	if silent then return {} end
	return Event (RETURN, self.team)
end

-- Its carrier stands in a zone that takes it (func_capturezone decides).
function Flag:Capture ()
	if self.state ~= CARRIED then return {} end
	local team = self.carrierTeam
	SendHome (self)
	return Event (CAPTURE, team)
end

-- Enable and Disable: a disabled flag goes home silently.
function Flag:SetEnabled (on)
	self.enabled = on
	if on then return {} end
	return self:Reset (true)
end

return
{
	New = New,
	MayCarry = MayCarry,
	DropsIn = DropsIn,
	HOME = HOME,
	CARRIED = CARRIED,
	DROPPED = DROPPED,
	PICKUP = PICKUP,
	DROP = DROP,
	CAPTURE = CAPTURE,
	RETURN = RETURN,
	RETURN_TIME_DEFAULT = RETURN_TIME_DEFAULT
}
