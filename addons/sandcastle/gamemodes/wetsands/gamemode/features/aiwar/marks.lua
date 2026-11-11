-- What the Path Follower stool tells the war by hand, each mark of a team at a point: a POST
-- its defenders hold (the field's posts), a RALLY a recalled squad regroups at, an ENEMY its
-- squads have seen there (a contact), an area to AVOID (closed to every team, as a hazard), a
-- DANGER its squads retreat from (an object, or a place in a room), a CAMP an enemy has killed its
-- members from again and again (features.aiwar.camps finds them as the war goes): the spots its
-- squads' grenades and rockets are for.
-- Positions are plain { x, y, z } tables.
--   New() -> marks: Add(kind, team, pos), RemoveNear(pos, reach) -> how many, All(), Of(team,
--   kind), Posts(team), Rallies(team), Camps(team) (nil for none), DangerNear(team, pos, reach) (the nearest
--   of the team's dangers within reach of pos, across the ground; nil for none), Version() (each
--   change counts), Encode()
--   -> text; Decode(text) -> marks as { kind, team, pos }.
local ipairs, setmetatable, error, tostring, tonumber = ipairs, setmetatable, error, tostring, tonumber
local concat, format = table.concat, string.format
module (...)

POST, RALLY, ENEMY, AVOID, DANGER, CAMP = "post", "rally", "enemy", "avoid", "danger", "camp"
KINDS = { POST, RALLY, ENEMY, AVOID, DANGER, CAMP }
local KNOWN = { [POST] = true, [RALLY] = true, [ENEMY] = true, [AVOID] = true, [DANGER] = true, [CAMP] = true }

local Marks = {}
Marks.__index = Marks

function New ()
	return setmetatable ({ list = {}, version = 0 }, Marks)
end

function Marks:Add (kind, team, pos)
	if not KNOWN [kind] then error ("no mark of kind " .. tostring (kind), 2) end
	self.list [#self.list + 1] = { kind = kind, team = team, pos = { x = pos.x, y = pos.y, z = pos.z or 0 } }
	self.version = self.version + 1
end

function Marks:RemoveNear (pos, reach)
	local kept, removed = {}, 0
	for _, mark in ipairs (self.list) do
		local dx, dy, dz = mark.pos.x - pos.x, mark.pos.y - pos.y, mark.pos.z - (pos.z or 0)
		if dx * dx + dy * dy + dz * dz <= reach * reach then removed = removed + 1 else kept [#kept + 1] = mark end
	end
	if removed > 0 then self.list, self.version = kept, self.version + 1 end
	return removed
end

function Marks:All () return self.list end
function Marks:Version () return self.version end

function Marks:Of (team, kind)
	local found = {}
	for _, mark in ipairs (self.list) do
		if mark.team == team and mark.kind == kind then found [#found + 1] = mark end
	end
	return found
end

local function Points (marks, team, kind)
	local points = {}
	for i, mark in ipairs (marks:Of (team, kind)) do points [i] = mark.pos end
	return points [1] and points or nil
end

function Marks:Posts (team) return Points (self, team, POST) end
function Marks:Rallies (team) return Points (self, team, RALLY) end
function Marks:Camps (team) return Points (self, team, CAMP) end

function Marks:DangerNear (team, pos, reach)
	local nearest, best = nil, reach * reach
	for _, mark in ipairs (self:Of (team, DANGER)) do
		local dx, dy = mark.pos.x - pos.x, mark.pos.y - pos.y
		local d = dx * dx + dy * dy
		if d <= best then nearest, best = mark.pos, d end
	end
	return nearest
end

function Marks:Encode ()
	local parts = {}
	for i, mark in ipairs (self.list) do
		parts [i] = format ("%s %d %.0f %.0f %.0f", mark.kind, mark.team, mark.pos.x, mark.pos.y, mark.pos.z)
	end
	return concat (parts, ";")
end

function Decode (text)
	local marks = {}
	for kind, team, x, y, z in text:gmatch ("(%a+) (%-?%d+) (%-?%d+) (%-?%d+) (%-?%d+)") do
		marks [#marks + 1] = { kind = kind, team = tonumber (team), pos = { x = tonumber (x), y = tonumber (y), z = tonumber (z) } }
	end
	return marks
end
