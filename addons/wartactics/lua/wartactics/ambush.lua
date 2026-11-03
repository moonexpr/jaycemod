-- Ambush hints (docs/incursion-native-plan.md): hiding spots beside the
-- entrances an enemy squad comes through. .devtools/bin/ambush.py is the
-- reference.
--
-- An entrance is where an enemy's path (an incursion route or breach) steps
-- into a room, from the area outside through a doorway or a window (its
-- aperture, as wide as the crossing) into the area inside. Its approach is
-- the walk up to it, the last stretch of each path through it; a room
-- stepped into straight from the spawn has none, and is no entrance. Walking
-- up, the squad sees into the room only through the aperture: from each
-- point of the approach, a wedge (the frustum through the doorway). A hiding
-- spot is an ambush for the defenders at an entrance when it is in the room
-- the entrance opens into, between near and far of it; outside the frustum
-- from every point of the approach (behind the wall the doorway is cut in);
-- standing up from it, a player sees just inside the entrance; and the
-- defenders' walk reaches it before the enemy's reaches the entrance.
--
-- Entrances(paths, crossings, region, approach) -> { { team, outside,
--   inside, room, via, width, heading, approach (points, the farthest
--   first), paths } }; paths: { { team, areas } }; crossings: area -> area ->
--   { cost, via, width } (wartactics.incursion's); region(area) -> its space.
-- Hidden(pos, entrance) -> whether out of the frustum from every point.
-- Ambushes(entrances, spots, fields, g, region, near, far) -> { { team, spot,
--   entrance, distance } }, nearest the entrance first for each; spots:
--   { pos, area, sees (area -> true) }; fields: team -> its walk; g: the
--   incursion's graph.
-- Positions are { x, y, z }, judged across the ground.
local ipairs, pairs, sort, huge, sqrt, abs = ipairs, pairs, table.sort, math.huge, math.sqrt, math.abs
module(...)

local function Ground(a, b)
	local dx, dy = a.x - b.x, a.y - b.y
	return sqrt(dx * dx + dy * dy)
end

local function Heading(a, b)
	local dx, dy = b.x - a.x, b.y - a.y
	local length = sqrt(dx * dx + dy * dy)
	return { x = dx / length, y = dy / length }
end

function Entrances(paths, crossings, region, approach)
	local found, order = {}, {}
	for _, path in ipairs(paths) do
		local areas = path.areas
		for i = 2, #areas do
			local outside, inside = areas[i - 1], areas[i]
			local room = region(inside)
			if room and room.kind ~= "corridor" and region(outside) ~= room then
				local door = crossings[outside][inside]
				local points, walked, j = {}, 0, i - 1
				while j > 1 do
					local step = crossings[areas[j - 1]][areas[j]]
					walked = walked + step.cost
					if walked > approach then break end
					points[#points + 1] = step.via
					j = j - 1
				end
				if #points > 0 then
					local key = path.team .. ":" .. outside .. ":" .. inside
					local e = found[key]
					if not e then
						local ahead = {}
						for k = #points, 1, -1 do ahead[#ahead + 1] = points[k] end
						e = { team = path.team, outside = outside, inside = inside, room = room, via = door.via,
							width = door.width, heading = Heading(points[1], door.via), approach = ahead, paths = 0 }
						found[key], order[#order + 1] = e, key
					end
					e.paths = e.paths + 1
				end
			end
		end
	end
	local list = {}
	for i, key in ipairs(order) do list[i] = found[key] end
	return list
end

function Hidden(pos, door)
	local hx, hy = door.heading.x, door.heading.y
	local nx, ny = -hy, hx
	local vx, vy = door.via.x, door.via.y
	local ahead = (pos.x - vx) * hx + (pos.y - vy) * hy
	if ahead <= 0 then return false end
	for _, point in ipairs(door.approach) do
		local behind = (point.x - vx) * hx + (point.y - vy) * hy
		if behind < 0 then
			local t = -behind / (ahead - behind)
			local x, y = point.x + t * (pos.x - point.x), point.y + t * (pos.y - point.y)
			if abs((x - vx) * nx + (y - vy) * ny) <= door.width / 2 then return false end
		end
	end
	return true
end

function Ambushes(entrances, spots, fields, g, region, near, far)
	local teams = {}
	for team in pairs(fields) do teams[#teams + 1] = team end
	sort(teams)
	local function At(field, area)
		local n = g.node[area]
		return n and field:Distance(n) or huge
	end
	local found = {}
	for _, door in ipairs(entrances) do
		local enemyAt = At(fields[door.team], door.outside)
		for _, team in ipairs(teams) do
			if team ~= door.team then
				local here = {}
				for _, spot in ipairs(spots) do
					local distance = Ground(spot.pos, door.via)
					if region(spot.area) == door.room and distance >= near and distance <= far and spot.sees[door.inside]
						and Hidden(spot.pos, door) and At(fields[team], spot.area) < enemyAt then
						here[#here + 1] = { team = team, spot = spot, entrance = door, distance = distance }
					end
				end
				sort(here, function(a, b)
					if a.distance ~= b.distance then return a.distance < b.distance end
					if a.spot.pos.x ~= b.spot.pos.x then return a.spot.pos.x < b.spot.pos.x end
					return a.spot.pos.y < b.spot.pos.y
				end)
				for _, mark in ipairs(here) do found[#found + 1] = mark end
			end
		end
	end
	return found
end
