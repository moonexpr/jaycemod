-- Part of the capture controller (sv.lua): what the point HUD (ws_point_*)
-- and each player's capture panel show, and publishing them.
local Controller, capstyle, blockstyle, Points, AreaPoint = ...
local Capture = WS.require("foundation.capture")
local Area = WS.require("foundation.capture.area")
local PointByName, AreasOf, OrderQuery = Points.PointByName, Points.AreasOf, Points.OrderQuery

local NOBODY, RED, BLUE = WS.TEAM_UNASSIGNED, WS.TEAM_RED, WS.TEAM_BLUE

local NO_POINT_STOOD_ON = 0 -- ws_capture_point: ranks are published 1-based

-- The HUD --------------------------------------------------------------------------------

-- The first enabled area on the point, with the state the HUD shows.
local function HudArea(self, point)
	for _, a in ipairs(AreasOf(self, point)) do
		if a.enabled then
			return {
				capping = a.state.cappingTeam,
				teamInZone = a.state.teamInZone,
				touching = a.state.touching,
				blocked = a.state.blocked,
				progress = a.lastInput and Area.Progress(a.state, a.lastInput) or 0,
				numRequired = a.numRequired,
				canCap = a.canCap,
				scales = capstyle:GetBool(),
			}
		end
	end
	return nil
end

local function Key(rank, field)
	return "ws_point_" .. rank .. "_" .. field
end

local function PublishPoint(rank, hud)
	SetGlobal2Int(Key(rank, "owner"), hud.owner)
	SetGlobal2Bool(Key(rank, "locked"), hud.locked)
	SetGlobal2Float(Key(rank, "unlock_time"), hud.unlockTime)
	SetGlobal2Int(Key(rank, "capping"), hud.capping)
	SetGlobal2Float(Key(rank, "progress"), hud.progress)
	SetGlobal2Int(Key(rank, "cappers"), hud.cappers)
	SetGlobal2Int(Key(rank, "required"), hud.required)
	SetGlobal2Bool(Key(rank, "blocked"), hud.blocked)
	SetGlobal2Bool(Key(rank, "red_can_cap"), hud.redCanCap)
	SetGlobal2Bool(Key(rank, "blue_can_cap"), hud.blueCanCap)
	SetGlobal2Bool(Key(rank, "in_round"), hud.inRound)
	SetGlobal2Bool(Key(rank, "hidden"), hud.hidden)
	SetGlobal2String(Key(rank, "name"), hud.name)
	SetGlobal2Float(Key(rank, "timer_end"), hud.timerEnd)
	SetGlobal2String(Key(rank, "icon"), hud.icon)
end

-- Every point with what the HUD shows of it, in rank order: { point, rank
-- (0-based), hud (PointSet:HudPoint) }. What a player may know of the
-- points, so the AI war reads its capture state here.
function Controller:HudPoints()
	local set = self:Set()
	local q = OrderQuery(self, RED)
	local bases = {
		[RED] = q.base,
		[BLUE] = OrderQuery(self, BLUE).base,
	}
	local list = {}
	for _, point in ipairs(set:Ids()) do
		list[#list + 1] = {
			point = point,
			rank = set:Rank(point),
			hud = set:HudPoint(point, {
				area = HudArea(self, point),
				playingMiniRounds = q.playingMiniRounds,
				inRound = q.inRound,
				bases = bases,
				hidden = self.hudHidden[point] == true,
				timerEnd = self.pointTimers[point] or 0,
			}),
		}
	end
	return list
end

-- The point's enabled trigger_capture_area entities.
function Controller:AreaEntities(point)
	local list = {}
	for ent, a in pairs(self.areas) do
		if IsValid(ent) and a.enabled and PointByName(a.pointName) == point then list[#list + 1] = ent end
	end
	return list
end

local function PublishPoints(self)
	local set = self:Set()
	for _, entry in ipairs(self:HudPoints()) do PublishPoint(entry.rank + 1, entry.hud) end
	SetGlobal2Int("ws_point_count", set:Count())
	SetGlobal2String("ws_point_layout", self.master and self.master:CapLayout() or "")
end

-- The capture panel of each player standing in an area (C_TFPlayer's
-- control point, CControlPointProgressBar::UpdateBarText).
local function PublishPanels(self)
	local standing = {}
	for ent, a in pairs(self.areas) do
		local point = IsValid(ent) and a.enabled and AreaPoint(self, a) or NULL
		if IsValid(point) then
			for _, ply in ipairs(WS.PlayersInside(ent)) do
				local team = WS.TeamOf(ply)
				if team ~= NOBODY then
					local q = OrderQuery(self, team)
					q.pointsMayBeCaptured = self.rounds:PointsMayBeCaptured()
					q.blocked = a.state.blocked
					q.capping = a.state.cappingTeam
					q.cappers = a.state.touching[team]
					q.required = capstyle:GetBool() and 0 or a.numRequired[team]
					q.pauseOnBlock = blockstyle:GetInt() == Area.BLOCKSTYLE_PAUSE
					q.canCap = a.canCap
					standing[ply] = {
						rank = self.set:Rank(point) + 1,
						reason = self.set:CannotCapReason(point, team, q),
						-- what the panel pins to: the cart an area rides, else the point
						anchor = IsValid(ent:GetParent()) and ent:GetParent() or point,
					}
				end
			end
		end
	end
	for _, ply in ipairs(player.GetAll()) do
		local s = standing[ply]
		ply:SetNW2Int("ws_capture_point", s and s.rank or NO_POINT_STOOD_ON)
		ply:SetNW2Int("ws_capture_reason", s and s.reason or Capture.REASON_NONE)
		ply:SetNW2Entity("ws_capture_anchor", s and s.anchor or NULL)
	end
end

return PublishPoints, PublishPanels
