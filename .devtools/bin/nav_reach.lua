-- What WS.NavLinkCrossable refuses on the running map, and what that cuts
-- off (dt lua -f .devtools/bin/nav_reach.lua): the links refused, level
-- ones and drops; and from each team's spawn areas, the areas reached over
-- every link against those reached over crossable links alone, with a few
-- of the areas lost.
local SAMPLE = 8
local STEP = 18

local level, levelRefused, drops, dropsRefused = 0, 0, 0, 0
for _, a in ipairs(navmesh.GetAllNavAreas()) do
	for _, b in ipairs(a:GetAdjacentAreas()) do
		local drop = a:GetCenter().z - b:GetCenter().z > STEP
		local ok = WS.NavLinkCrossable(a, b)
		if drop then
			drops = drops + 1
			if not ok then dropsRefused = dropsRefused + 1 end
		elseif b:GetCenter().z - a:GetCenter().z <= STEP then
			level = level + 1
			if not ok then levelRefused = levelRefused + 1 end
		end
	end
end

local Graph = WS.require("foundation.core.graph")
local AREAS = #navmesh.GetAllNavAreas()

-- The areas reached from starts (area -> true), over every link or over
-- crossable links alone.
local function Reach(starts, crossableOnly)
	local function Neighbors(a)
		if not crossableOnly then return a:GetAdjacentAreas() end
		local list = {}
		for _, b in ipairs(a:GetAdjacentAreas()) do
			if WS.NavLinkCrossable(a, b) then list[#list + 1] = b end
		end
		return list
	end
	local reached = Graph.Flood(starts, Neighbors, function() return true end, AREAS)
	local set = {}
	for _, area in ipairs(reached) do set[area] = true end
	return set
end

local out = { string.format("level links %d, refused %d; drops %d, refused %d", level, levelRefused, drops, dropsRefused) }
for _, team in ipairs({ 2, 3 }) do
	local starts = {}
	for _, spawn in ipairs(ents.FindByClass("info_player_teamspawn")) do
		if tonumber(spawn:GetKeyValues().TeamNum) == team then
			local area = navmesh.GetNearestNavArea(spawn:GetPos(), false, 128, false, true)
			if IsValid(area) then starts[#starts + 1] = area end
		end
	end
	local all, crossable = Reach(starts, false), Reach(starts, true)
	local nAll, nCross, lost = 0, 0, {}
	for a in pairs(all) do
		nAll = nAll + 1
		if crossable[a] then nCross = nCross + 1 elseif #lost < SAMPLE then lost[#lost + 1] = a:GetID() .. " " .. tostring(a:GetCenter()) end
	end
	out[#out + 1] = string.format("team %d from %d spawn areas: %d reached, %d over crossable links; lost e.g. %s",
		team, #starts, nAll, nCross, table.concat(lost, "; "))
end
return table.concat(out, "\n")
