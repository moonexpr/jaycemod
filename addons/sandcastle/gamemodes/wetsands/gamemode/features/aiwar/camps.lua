-- Camps: a spot an enemy kills from again and again. A killer's CAMP_KILLS kills within CAMP_WINDOW
-- seconds of each other, each from within CAMP_REACH of the newest, make a camp at their middle,
-- its victims' team's to know (features.aiwar.marks' CAMP), named once a spot.
-- Positions are plain { x, y, z } tables; a killer is anything that names it.
--   New() -> camps: Kill(killer, killerTeam, victimTeam, at, now) -> { team, pos } for a camp just
--   found, else nil
local ipairs, setmetatable = ipairs, setmetatable
module (...)

CAMP_KILLS, CAMP_WINDOW, CAMP_REACH = 3, 60, 256

local Camps = {}
Camps.__index = Camps

function New ()
	return setmetatable ({ kills = {}, named = {} }, Camps)
end

local function Within (a, b, reach)
	local dx, dy, dz = a.x - b.x, a.y - b.y, (a.z or 0) - (b.z or 0)
	return dx * dx + dy * dy + dz * dz <= reach * reach
end

function Camps:Kill (killer, killerTeam, victimTeam, at, now)
	if killerTeam == victimTeam then return nil end
	local recent = {}
	for _, kill in ipairs (self.kills [killer] or {}) do
		if now - kill.at <= CAMP_WINDOW then recent [#recent + 1] = kill end
	end
	recent [#recent + 1] = { at = now, pos = { x = at.x, y = at.y, z = at.z or 0 } }
	self.kills [killer] = recent
	local near, middle = 0, { x = 0, y = 0, z = 0 }
	for _, kill in ipairs (recent) do
		if Within (kill.pos, at, CAMP_REACH) then
			near = near + 1
			middle.x, middle.y, middle.z = middle.x + kill.pos.x, middle.y + kill.pos.y, middle.z + kill.pos.z
		end
	end
	if near < CAMP_KILLS then return nil end
	middle.x, middle.y, middle.z = middle.x / near, middle.y / near, middle.z / near
	for _, named in ipairs (self.named) do
		if named.team == victimTeam and Within (named.pos, middle, CAMP_REACH) then return nil end
	end
	local camp = { team = victimTeam, pos = middle }
	self.named [#self.named + 1] = camp
	return camp
end
