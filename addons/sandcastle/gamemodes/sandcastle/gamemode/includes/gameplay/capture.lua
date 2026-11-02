-- The capture system: a PointSet holding every control point of a map
-- (team_control_point, team_control_point.cpp) with the rules TF2 spreads
-- over the point, the master's point list and the gamerules: owners, locks
-- and timed unlocks, capture order (CTFGameRules::TeamMayCapturePoint),
-- groups, and why a player may not capture (the HUD's capture panel).
-- Its parts: .area (a trigger_capture_area's capture) and .master (the
-- master and its mini-rounds).
--
-- New{ caplinear, points = { spec... } }. A spec is { id, index,
-- defaultOwner, startLocked, group, warnOnCap, warnSound, printName,
-- spawnflags, previous = { [team] = { id, id, id } }, sounds = { start,
-- stop, progress, interrupted }, capSounds = { [team] = name } } where id is
-- any key the caller picks (the controller uses the point entity), previous
-- holds team_previouspoint_<team>_0..2 (a slot nil when unset), sounds the
-- point_capture_*_sound keyvalues and capSounds team_capsound_<team>; an
-- unset or empty sound keeps TF2's default. A spec may carry the point's
-- current owner and locked, for a set rebuilt while its points live on (a
-- mini-round).
--
-- Methods that change a point return events, in order:
--   { kind = "owner", id, old, team, sounding, scoring, lines, cappers }:
--     sounding for a capture by players (OnOwnerChangedToTeam, the notice),
--     cappers the names of those who took it (a capture's, when they are
--     known; none otherwise), scoring
--     when HandleScoring runs, lines the sounds it plays ({ hearer, team,
--     sound }, HEAR_*);
--   { kind = "unlocked", id } (OnUnlocked); { kind = "unlock_time", id, at };
--   { kind = "round_start_owned", id, team } (OnRoundStartOwnedByTeam).
local error, ipairs, pairs, setmetatable, tostring = error, ipairs, pairs, setmetatable, tostring
local abs = math.abs
local gmatch = string.gmatch
local sort = table.sort
local tonumber = tonumber
local Teams = gameplay.teams
local Select = list.select
local Snapshot = world.snapshot
module(...)

-- A control point index or rank that names no point (the SDK's -1).
NO_POINT = -1
-- The cappers of a change of owner no one is named for.
NO_CAPPERS = {}
MAX_PREVIOUS_POINTS = 3 -- team_control_point.h

-- shareddefs.h: point_warn_on_cap
CP_WARN = {
	NORMAL = 0,
	FINALCAP = 1,
	NO_ANNOUNCEMENTS = 2,
}

-- team_control_point.h spawnflags
SF_HIDE_MODEL = 2 -- SF_CAP_POINT_HIDE_MODEL
SF_NO_CAP_SOUNDS = 8 -- SF_CAP_POINT_NO_CAP_SOUNDS

-- The point_capture_*_sound defaults (CTeamControlPoint::Spawn).
SOUND_START = "Hologram.Start"
SOUND_END = "Hologram.Stop"
SOUND_PROGRESS = "Hologram.Move"
SOUND_INTERRUPTED = "Hologram.Interrupted"

-- point_warn_sound's default (the FGD's), the contested lines
-- (C_TFObjectiveResource::SetCappingTeam) and the capture bell (the scored
-- chime of CTeamControlPoint::HandleScoring), which every capture rings for
-- everyone, spectators too.
WARN_SOUND_DEFAULT = "ControlPoint.CaptureWarn"
CONTESTED = "Announcer.ControlPointContested"
CONTESTED_NEUTRAL = "Announcer.ControlPointContested_Neutral"
CAPTURE_BELL = "Hud.EndRoundScored"
-- The client's spam guard on the final-cap warning (C_BaseTeamObjectiveResource::ClientThink).
WARN_INTERVAL = 5

-- Who hears a line { hearer, team, sound }: everyone (a broadcast filter,
-- played from the point), the team's players, or every player not on the
-- team (each client's "not my team" test, spectators included).
HEAR_EVERYONE = "everyone"
HEAR_TEAM = "team"
HEAR_OTHERS = "others"

-- Why the owner changes: a capture area's capture, a SetOwner input sent by
-- a player or by anything else, and ForceOwner (the game itself).
CAUSE_CAPTURE = "capture"
CAUSE_PLAYER_INPUT = "player_input"
CAUSE_INPUT = "input"
CAUSE_FORCE = "force"

-- The capture panel's text (CControlPointProgressBar::UpdateBarText),
-- REASON_NONE while the player's team is capping (the bar, no text).
REASON_NONE = 0
REASON_NOT_NOW = 1
REASON_BLOCKING = 2
REASON_REVERTING = 3
REASON_OWNED = 4
REASON_OWN_POINT = 5
REASON_LINEAR = 6
REASON_BLOCKED = 7
REASON_CANNOT = 8
REASON_WAITING = 9

REASON_TOKEN = {
	[REASON_NOT_NOW] = "#Team_Capture_NotNow",
	[REASON_BLOCKING] = "#Team_Blocking_Capture",
	[REASON_REVERTING] = "#Team_Reverting_Capture",
	[REASON_OWNED] = "#Team_Capture_Owned",
	[REASON_OWN_POINT] = "#Team_Capture_OwnPoint",
	[REASON_LINEAR] = "#Team_Capture_Linear",
	[REASON_BLOCKED] = "#Team_Capture_Blocked",
	[REASON_CANNOT] = "#Team_Cannot_Capture",
	[REASON_WAITING] = "#Team_Waiting_for_teammate",
}

local NOBODY, RED, BLUE = Teams.UNASSIGNED, Teams.RED, Teams.BLUE
local FIRST_GAME_TEAM = Teams.FIRST_GAME_TEAM
local ENEMY = {
	[RED] = BLUE,
	[BLUE] = RED,
}

-- Capture order (CTFGameRules::TeamMayCapturePoint) -------------------------------

-- CTeamControlPointMaster::FindControlPoints renumbers the points 0..n-1 in
-- point_index order. Returns each input's rank.
function Ranks(indices)
	local ranks = Select.Ranks(indices, function(a, b) return a < b end)
	for i, rank in ipairs(ranks) do ranks[i] = rank - 1 end
	return ranks
end

-- CTeamControlPointMaster::GetBaseControlPoint over the points given
-- ({ index, defaultOwner }): the highest when the team owns it by default
-- (both ends included), else the lowest when it does, else NO_POINT.
function BaseControlPoint(team, points)
	local low, high
	for _, p in ipairs(points) do
		if not low or p.index < low.index then low = p end
		if not high or p.index > high.index then high = p end
	end
	if not low then return NO_POINT end
	if high.defaultOwner == team then return high.index end
	if low.defaultOwner == team then return low.index end
	return NO_POINT
end

-- CTFGameRules::GetFarthestOwnedControlPoint (without spawn points).
-- owners is indexed by rank 0..count-1.
function FarthestOwnedControlPoint(team, owners, count, base)
	if base == NO_POINT then return NO_POINT end
	local walk, enemyEnd = 1, count - 1
	if base ~= 0 then walk, enemyEnd = -1, 0 end
	local farthest = base
	local p = base
	while p ~= enemyEnd do
		if owners[p] ~= team then break end
		farthest = p
		p = p + walk
	end
	return farthest
end

-- q = { caplinear, index (rank), team, locked, previous = { three ranks,
-- NO_POINT unused }, playingMiniRounds, owners (by rank), count, base (the
-- team's base rank) }
function TeamMayCapturePoint(q)
	if not q.caplinear then return true end
	local needed = q.previous[1]
	if needed == q.index then return true end
	if q.locked then return false end
	if needed == NO_POINT then
		if q.playingMiniRounds then return true end
		local farthest = FarthestOwnedControlPoint(q.team, q.owners, q.count, q.base)
		return abs(farthest - q.index) <= 1
	end
	for _, prev in ipairs(q.previous) do
		if prev ~= NO_POINT and q.owners[prev] ~= q.team then return false end
	end
	return true
end

-- The HUD layout (CHudControlPointIcons::PerformLayout): caplayout lists
-- ranks, spaces between icons and commas between rows; unknown ranks are
-- skipped. Without one, a single row in rank order.
function Layout(caplayout, count)
	local rows, row = {}, {}
	for number, comma in gmatch(caplayout, "(%d+)%s*(,?)") do
		local rank = tonumber(number)
		if rank < count then
			row[#row + 1] = rank
			if comma ~= "" then
				rows[#rows + 1] = row
				row = {}
			end
		end
	end
	if #row > 0 then rows[#rows + 1] = row end
	if #rows > 0 then return rows end
	for rank = 0, count - 1 do row[#row + 1] = rank end
	return { row }
end

-- The PointSet -----------------------------------------------------------------------

local PointSet = {}
PointSet.__index = PointSet

local function Named(name, default)
	if name == nil or name == "" then return default end
	return name
end

-- team_control_point's team_icon_0/2/3 defaults (the FGD's): the HUD's icon
-- for each owner.
ICON_DEFAULT = {
	[NOBODY] = "sprites/obj_icons/icon_obj_neutral",
	[RED] = "sprites/obj_icons/icon_obj_red",
	[BLUE] = "sprites/obj_icons/icon_obj_blu",
}

-- spec.icons: owner -> the map's team_icon, nil or "" for the default.
local function Icons(icons)
	local list = {}
	for team, default in pairs(ICON_DEFAULT) do list[team] = Named(icons[team], default) end
	return list
end

local function NewPoint(spec, rank)
	local locked = spec.locked
	if locked == nil then locked = spec.startLocked end
	local sounds = spec.sounds
	return {
		sounds = {
			start = Named(sounds.start, SOUND_START),
			stop = Named(sounds.stop, SOUND_END),
			progress = Named(sounds.progress, SOUND_PROGRESS),
			interrupted = Named(sounds.interrupted, SOUND_INTERRUPTED),
		},
		capSounds = spec.capSounds,
		lastWarn = nil,
		id = spec.id,
		rank = rank,
		index = spec.index,
		defaultOwner = spec.defaultOwner,
		owner = spec.owner or spec.defaultOwner,
		locked = locked,
		-- m_flUnlockTime, and the objective resource's copy the HUD shows
		unlockAt = spec.unlockAt,
		shownUnlockAt = spec.unlockAt,
		group = spec.group,
		warnOnCap = spec.warnOnCap,
		warnSound = Named(spec.warnSound, WARN_SOUND_DEFAULT),
		printName = spec.printName,
		spawnflags = spec.spawnflags,
		previous = spec.previous,
		icons = Icons(spec.icons),
	}
end

function New(config)
	local indices = {}
	for i, spec in ipairs(config.points) do indices[i] = spec.index end
	local ranks = Ranks(indices)
	local byId, ids = {}, {}
	for i, spec in ipairs(config.points) do
		local point = NewPoint(spec, ranks[i])
		byId[spec.id] = point
		ids[ranks[i] + 1] = spec.id
	end
	return setmetatable({
		caplinear = config.caplinear,
		points = byId,
		ids = ids,
	}, PointSet)
end

-- The set's points as plain data (games.world.snapshot), keyed by
-- their ids through refs, unlock and warn times kept as seconds from now.
-- The point order and caplinear are the map's and the convar's.
local SNAPSHOT = Snapshot.Spec({
	name = "capture",
	skip = { "ids", "caplinear" },
	times = { "points.*.unlockAt", "points.*.shownUnlockAt", "points.*.lastWarn" },
})

function PointSet:Snapshot(now, refs) return Snapshot.Take(self, SNAPSHOT, now, refs) end
function PointSet:Restore(snapshot, now, refs) Snapshot.Apply(self, snapshot, SNAPSHOT, now, refs) end

-- The point an id names. An id the set does not hold is the caller's bug
-- (an entity the set was never rebuilt for): fail naming it, at the caller.
local function Point(self, id)
	local p = self.points[id]
	if p == nil then error("no control point " .. tostring(id) .. " in the set", 3) end
	return p
end

-- tf_caplinear, read by the controller each time it changes.
function PointSet:SetCaplinear(caplinear)
	self.caplinear = caplinear
end

-- Every point id in rank order.
function PointSet:Ids()
	local ids = {}
	for i, id in ipairs(self.ids) do ids[i] = id end
	return ids
end

function PointSet:Has(id)
	return self.points[id] ~= nil
end

function PointSet:Count()
	return #self.ids
end

function PointSet:Rank(id) return Point(self, id).rank end
function PointSet:Index(id) return Point(self, id).index end
function PointSet:Owner(id) return Point(self, id).owner end
function PointSet:DefaultOwner(id) return Point(self, id).defaultOwner end
function PointSet:Group(id) return Point(self, id).group end
function PointSet:Locked(id) return Point(self, id).locked end
function PointSet:PrintName(id) return Point(self, id).printName end
function PointSet:Spawnflags(id) return Point(self, id).spawnflags end

-- The unlock time the HUD counts down to, or nil.
function PointSet:UnlockAt(id)
	return Point(self, id).shownUnlockAt
end

-- point_warn_on_cap and point_warn_sound.
function PointSet:Warn(id)
	local p = Point(self, id)
	return p.warnOnCap, p.warnSound
end

-- The capture sounds games.gameplay.capture.area's PointSounds plays from the
-- point: { start, stop, progress, interrupted }.
function PointSet:Sounds(id)
	return Point(self, id).sounds
end

local function Line(hearer, team, sound)
	return {
		hearer = hearer,
		team = team,
		sound = sound,
	}
end

-- A capture starting (CTeamControlPoint::CaptureStart), as each client
-- hears it: with point_warn_on_cap 0 the players not capping hear the
-- point is contested (neutral or owned); with 1 they hear its warn sound,
-- at most every WARN_INTERVAL seconds.
function PointSet:CaptureStarted(id, team, now)
	local p = Point(self, id)
	if team == NOBODY then return {} end
	if p.warnOnCap == CP_WARN.NORMAL then
		return { Line(HEAR_OTHERS, team, p.owner ~= NOBODY and CONTESTED or CONTESTED_NEUTRAL) }
	end
	if p.warnOnCap == CP_WARN.FINALCAP and (p.lastWarn == nil or now > p.lastWarn + WARN_INTERVAL) then
		p.lastWarn = now
		return { Line(HEAR_OTHERS, team, p.warnSound) }
	end
	return {}
end

-- Owners -----------------------------------------------------------------------------

-- CTeamControlPoint::SetOwner (a capture), InputSetOwner (from a player or
-- not) and ForceOwner. Only a forced owner ignores whether points may be
-- captured now; an input naming the owner does nothing. cappers: a
-- capture's takers, by name (TF2's cappers), when they are known.
function PointSet:SetOwner(id, team, cause, pointsMayBeCaptured, cappers)
	local p = Point(self, id)
	local input = cause == CAUSE_INPUT or cause == CAUSE_PLAYER_INPUT
	if input and p.owner == team then return {} end
	if cause ~= CAUSE_FORCE and not pointsMayBeCaptured then return {} end
	local old = p.owner
	p.owner = team
	local sounding = cause == CAUSE_CAPTURE or cause == CAUSE_PLAYER_INPUT
	-- a team took it, by players or a relay (a payload cart): not forced
	local taken = cause ~= CAUSE_FORCE and team >= FIRST_GAME_TEAM
	-- InternalSetOwner: team_capsound_<team> to everyone, from the point
	local lines = {}
	local capSound = p.capSounds[team]
	if sounding and capSound and capSound ~= "" then lines[1] = Line(HEAR_EVERYONE, team, capSound) end
	return {
		{
			kind = "owner",
			id = id,
			old = old,
			team = team,
			sounding = sounding,
			scoring = taken,
			bell = taken and CAPTURE_BELL or nil,
			lines = lines,
			cappers = cause == CAUSE_CAPTURE and cappers or NO_CAPPERS,
		},
	}
end

-- CTeamControlPointMaster::TeamOwnsAllPoints over the given points, with
-- overrideId taken as owned by overrideTeam: each group is won by a team
-- owning every point in it; the lowest-numbered won group reports.
function PointSet:TeamOwnsAll(ids, overrideId, overrideTeam)
	local byGroup = {}
	for _, id in ipairs(ids) do
		local p = Point(self, id)
		local owner = p.owner
		if id == overrideId then owner = overrideTeam end
		local g = byGroup[p.group]
		if g == nil then
			byGroup[p.group] = owner
		elseif g ~= NOBODY and owner ~= g then
			byGroup[p.group] = NOBODY
		end
	end
	local groups = {}
	for group in pairs(byGroup) do groups[#groups + 1] = group end
	sort(groups)
	for _, group in ipairs(groups) do
		if byGroup[group] >= FIRST_GAME_TEAM then return byGroup[group] end
	end
	return NOBODY
end

-- Locks ------------------------------------------------------------------------------

-- CTeamControlPoint::InternalSetLocked: the HUD loses any unlock time;
-- unlocking (even an unlocked point) clears the timed unlock and fires
-- OnUnlocked. Locking keeps a pending timed unlock running, as the SDK does.
local function InternalSetLocked(p, locked, events)
	p.locked = locked
	p.shownUnlockAt = nil
	if locked then return end
	p.unlockAt = nil
	events[#events + 1] = {
		kind = "unlocked",
		id = p.id,
	}
end

function PointSet:SetLocked(id, locked)
	local events = {}
	InternalSetLocked(Point(self, id), locked, events)
	return events
end

-- InputSetUnlockTime: 0 or less unlocks now.
function PointSet:SetUnlockTime(id, seconds, now)
	local p = Point(self, id)
	local events = {}
	if seconds <= 0 then
		InternalSetLocked(p, false, events)
		return events
	end
	p.unlockAt = now + seconds
	p.shownUnlockAt = p.unlockAt
	events[1] = {
		kind = "unlock_time",
		id = id,
		at = p.unlockAt,
	}
	return events
end

-- CTeamControlPoint::UnlockThink: a timed unlock waits for the round to run.
function PointSet:Tick(now, roundRunning)
	local events = {}
	if not roundRunning then return events end
	for _, id in ipairs(self.ids) do
		local p = Point(self, id)
		if p.unlockAt and p.unlockAt < now then InternalSetLocked(p, false, events) end
	end
	return events
end

-- CTeamControlPoint::InputRoundActivate for the given points (default:
-- every point, in rank order, as the gamerules send it).
function PointSet:RoundActivate(ids)
	local events = {}
	for _, id in ipairs(ids or self.ids) do
		local p = Point(self, id)
		if p.owner >= FIRST_GAME_TEAM then
			events[#events + 1] = {
				kind = "round_start_owned",
				id = id,
				team = p.owner,
			}
		end
		InternalSetLocked(p, p.locked, events)
	end
	return events
end

-- Who may capture --------------------------------------------------------------------

local function PreviousRanks(self, p, team)
	local previous = {}
	local slots = p.previous[team] or {}
	for k = 1, MAX_PREVIOUS_POINTS do
		local prev = slots[k] and self.points[slots[k]]
		previous[k] = prev and prev.rank or NO_POINT
	end
	return previous
end

local function OwnersByRank(self)
	local owners = {}
	for rank, id in ipairs(self.ids) do owners[rank - 1] = Point(self, id).owner end
	return owners
end

-- TF2's rule alone. q = { playingMiniRounds, base = the team's base rank }.
local function MayCapturePoint(self, p, team, q)
	return TeamMayCapturePoint({
		caplinear = self.caplinear,
		index = p.rank,
		team = team,
		locked = p.locked,
		previous = PreviousRanks(self, p, team),
		playingMiniRounds = q.playingMiniRounds,
		owners = OwnersByRank(self),
		count = #self.ids,
		base = q.base,
	})
end

local function InRound(q, id)
	return not (q.playingMiniRounds and q.inRound and not q.inRound[id])
end

-- Whether a team may capture the point now: RED or BLU, not the owner, in
-- the mini-round being played, and TeamMayCapturePoint. q = {
-- playingMiniRounds, inRound = { [id] = true } or nil (every point), base =
-- the team's base rank (the master's BaseControlPoint) }.
function PointSet:TeamMayCapture(id, team, q)
	local p = Point(self, id)
	if not ENEMY[team] or p.owner == team or not InRound(q, id) then return false end
	return MayCapturePoint(self, p, team, q)
end

-- CControlPointProgressBar::SetupForPoint and UpdateBarText, in their order,
-- for a player of team standing on the point. q adds to TeamMayCapture's: {
-- pointsMayBeCaptured, blocked, capping (the capping team), cappers (the
-- player's team in the area), required (its team_numcap, 0 under
-- mp_capstyle 1), pauseOnBlock (mp_blockstyle 1), canCap = { [team] = the
-- area's team_cancap } }. The SDK's PlayerMayCapturePoint reasons (stealth,
-- invulnerability, disguise) have no Sandcastle counterpart.
function PointSet:CannotCapReason(id, team, q)
	local p = Point(self, id)
	if not q.blocked and q.capping ~= NOBODY and q.capping ~= p.owner and q.capping == team then
		return REASON_NONE
	end
	if not q.pointsMayBeCaptured or p.locked then return REASON_NOT_NOW end
	if q.pauseOnBlock and q.capping ~= NOBODY and q.capping ~= team then
		if q.blocked then return REASON_BLOCKING end
		if p.owner == NOBODY then return REASON_REVERTING end
	end
	if p.owner == team then
		if ENEMY[team] and not q.canCap[ENEMY[team]] then return REASON_OWNED end
		return REASON_OWN_POINT
	end
	if not MayCapturePoint(self, p, team, q) then return REASON_LINEAR end
	if q.capping == team and q.cappers >= q.required then return REASON_BLOCKED end
	if not q.canCap[team] then return REASON_CANNOT end
	return REASON_WAITING
end

-- The HUD --------------------------------------------------------------------------------

-- The area's count the HUD shows: the capping team's, else the one team
-- in the zone's.
local function ShownTeam(area)
	if area.capping ~= NOBODY then return area.capping end
	return area.teamInZone
end

-- What the objective resource tells clients about a point. q = { area = {
-- capping, teamInZone, touching, blocked, progress, numRequired, canCap,
-- scales } or nil, playingMiniRounds, inRound, bases = { [team] = rank },
-- hidden, timerEnd }. required is the shown team's team_numcap, 0 under
-- mp_capstyle 1 (no fixed count); a team may cap when its area lets it and
-- TeamMayCapture holds.
function PointSet:HudPoint(id, q)
	local p = Point(self, id)
	local area = q.area
	local hud = {
		owner = p.owner,
		locked = p.locked,
		unlockTime = p.shownUnlockAt or 0,
		capping = NOBODY,
		progress = 0,
		cappers = 0,
		required = 0,
		blocked = false,
		redCanCap = false,
		blueCanCap = false,
		inRound = InRound(q, id),
		hidden = q.hidden,
		name = p.printName,
		timerEnd = q.timerEnd,
		icon = p.icons[p.owner],
	}
	if not area then return hud end
	hud.capping = area.capping
	hud.progress = area.progress
	hud.blocked = area.blocked
	local shown = ShownTeam(area)
	if shown ~= NOBODY then
		hud.cappers = area.touching[shown]
		if not area.scales then hud.required = area.numRequired[shown] end
	end
	local function CanCap(team)
		return area.canCap[team] and self:TeamMayCapture(id, team, {
			playingMiniRounds = q.playingMiniRounds,
			inRound = q.inRound,
			base = q.bases[team],
		})
	end
	hud.redCanCap = CanCap(RED)
	hud.blueCanCap = CanCap(BLUE)
	return hud
end
