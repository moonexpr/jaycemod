-- Where the AI war's soldiers join the fight on a map without TF2's team
-- spawns (info_player_teamspawn): each team at its faction's HL2
-- deathmatch spawns (FACTION_CLASSES: the Combine's, the rebels'), whichever
-- team the faction fights for;
-- a team without them at the nav mesh's hiding spots, split between the
-- teams (Split) so each has its own side of the map; and on a map without
-- hiding spots, at its shared player starts (SHARED_CLASSES).
--
-- The hiding spots spawned at are the spawn bases: only those in the largest
-- group of nav areas each of which reaches every other one and back
-- (Connected), so no team starts on a roof it can only drop from, or in a pit
-- it can never leave, cut off from the fight.
--
-- Positions are { x, y, z } tables.
local ipairs, sort = ipairs, table.sort
local ceil, huge = math.ceil, math.huge
local Teams = gameplay.teams
local Spawn = gameplay.spawn
local Search = graph.search
local Box = math.box
local AiWar = require("features.aiwar.model")
module(...)

FACTION_CLASSES = {
	[AiWar.COMBINE] = { "info_player_combine" },
	[AiWar.RESISTANCE] = { "info_player_rebel" },
}
SHARED_CLASSES = { "info_player_deathmatch", "info_player_start" }

local function Present(classes, present)
	local list = {}
	for _, class in ipairs(classes) do
		if present(class) then list[#list + 1] = class end
	end
	return list
end

-- The spawn classes of faction (an id: features.aiwar.model's COMBINE,
-- RESISTANCE) the map has (present(class) -> bool); none sends its team to
-- the hiding spots.
function Classes(faction, present)
	return Present(FACTION_CLASSES[faction] or {}, present)
end

-- The spawn classes of a team's CS:S side the map has (gameplay.spawn's
-- SIDE_CLASSES: the terrorists are RED and the counter-terrorists BLU,
-- whichever faction fights for either).
function TeamClasses(team, present)
	local class = Spawn.SideClass(team)
	return Present(class and { class } or {}, present)
end

-- The shared player start classes the map has.
function Shared(present)
	return Present(SHARED_CLASSES, present)
end

local function Admit() return true end

-- The areas start reaches and that reach start back: those the flood from
-- it reaches, flooded back from start over the links among them reversed.
local function GroupOf(start, neighbors)
	local forward = Search.Flood({ start }, neighbors, Admit, huge)
	local inForward, back = {}, {}
	for _, area in ipairs(forward) do inForward[area] = true end
	for _, area in ipairs(forward) do
		for _, to in ipairs(neighbors(area)) do
			if inForward[to] then
				local list = back[to]
				if not list then
					list = {}
					back[to] = list
				end
				list[#list + 1] = area
			end
		end
	end
	return Search.Flood({ start }, function(area) return back[area] or {} end, Admit, huge)
end

-- The spawn bases among spots ({ x, y, z, area }): those whose areas lie in
-- one group where every area reaches every other and back, through
-- neighbors(area) -> the areas a soldier crosses to from it (a drop it may
-- rappel down is a link down only). The group holding the most spots wins,
-- on a tie the first spot's; spots keep their order.
function Connected(spots, neighbors)
	local groupOf, counts, best = {}, {}, nil
	for _, spot in ipairs(spots) do
		local group = groupOf[spot.area]
		if group == nil then
			group = #counts + 1
			counts[group] = 0
			for _, area in ipairs(GroupOf(spot.area, neighbors)) do groupOf[area] = group end
		end
		counts[group] = counts[group] + 1
	end
	for group, count in ipairs(counts) do
		if best == nil or count > counts[best] then best = group end
	end
	local kept = {}
	for _, spot in ipairs(spots) do
		if groupOf[spot.area] == best then kept[#kept + 1] = spot end
	end
	return kept
end

-- The team's share of the hiding spots: sorted along the longer side of
-- their extent, RED the low half and BLU the high, the middle one of an odd
-- count both teams'.
function Split(spots, team)
	if #spots == 0 then return {} end
	local axis = Box.LongestAxis2D(Box.Extent(spots))
	local sorted = {}
	for i, p in ipairs(spots) do sorted[i] = p end
	sort(sorted, function(a, b) return a[axis] < b[axis] end)
	local half = ceil(#sorted / 2)
	local from, to = 1, half
	if team == Teams.BLUE then from, to = #sorted - half + 1, #sorted end
	local share = {}
	for i = from, to do share[#share + 1] = sorted[i] end
	return share
end
