-- npc_squadmember on a live server, as the Local Behavior Tool drives it: three members crowded
-- together and one apart, told to muster, to fall back, and dissolved, each read back as data.
-- Leaves nothing behind. Run it, wait for its steps, then read the result:
--   python3 .devtools/bin/instances.py MAP - < .devtools/bin/squad_member_check.lua
--   python3 .devtools/bin/instances.py MAP 'return NSSquadCheck'
local Legs = nextsoldier.behavior.group_identity
local STEP = 1.5
local CROWD = 30

local function Point(v) return { x = v.x, y = v.y, z = v.z } end

local function Largest()
	local best
	for _, area in ipairs(navmesh.GetAllNavAreas()) do
		if not best or area:GetSizeX() * area:GetSizeY() > best:GetSizeX() * best:GetSizeY() then best = area end
	end
	return best
end

-- a round won would change the map under it
RunConsoleCommand("mp_winlimit", "0")
RunConsoleCommand("mp_timelimit", "0")
RunConsoleCommand("mp_maxrounds", "0")

local center = Largest():GetCenter()
local straggler = navmesh.GetNearestNavArea(center + Vector(400, 400, 0)):GetClosestPointOnArea(center + Vector(400, 400, 0))
local spots = { center, center + Vector(CROWD, 0, 0), center + Vector(0, CROWD, 0), straggler }
local members = {}
for i, spot in ipairs(spots) do
	local member = ents.Create("npc_squadmember")
	member:SetPos(spot + Vector(0, 0, 1))
	member:Spawn()
	member:Activate()
	members[i] = member
end

local function Read()
	local out = {}
	for i, member in ipairs(members) do
		local names = {}
		for j, frame in ipairs(nextsoldier.engine.Stack(member)) do names[j] = frame.name end
		local push = member:GetNW2Vector("NSLegsPush", vector_origin)
		local place = member:GetNW2Vector("NSLegsPlace", vector_origin)
		out[i] = string.format("%s | order %q place %.0f,%.0f,%.0f stands %s | moved %.0f | push %.2f,%.2f spacing %.0f",
			table.concat(names, " > "), member:GetNW2String("NSLegsOrder", ""), place.x, place.y, place.z,
			tostring(member:GetNW2Bool("NSLegsStands", false)), member:GetPos():Distance2D(spots[i]),
			push.x, push.y, member:GetNW2Float("NSLegsSpacing", 0))
	end
	return table.concat(out, "\n")
end

local function Tell(order)
	local positions = {}
	for i, member in ipairs(members) do positions[i] = Point(member:GetPos()) end
	local places = order:Places(positions, nextsoldier.engine.GroupSpacing(), members[1]:NSLegsAdmit(Vector(order.point.x, order.point.y, order.point.z)))
	for i, member in ipairs(members) do member:NSLegsGive(order, places[i]) end
end

NSSquadCheck = "running"
local result = {}
local steps = {
	function() result[#result + 1] = "AT EASE\n" .. Read() Tell(Legs.Muster(Point(center))) end,
	function() result[#result + 1] = "MUSTER\n" .. Read() Tell(Legs.FallBack(Point(center), Point(center + Vector(600, 0, 0)))) end,
	function() result[#result + 1] = "FALL BACK\n" .. Read() for _, member in ipairs(members) do member:NSLegsGive(nil) end end,
	function()
		result[#result + 1] = "DISSOLVED\n" .. Read()
		for _, member in ipairs(members) do member:Remove() end
		local tool = weapons.GetStored("gmod_tool")
		result[#result + 1] = "stool registered: " .. tostring(tool and tool.Tool and tool.Tool.ns_localbehavior ~= nil)
		NSSquadCheck = table.concat(result, "\n\n")
	end,
}
for i, step in ipairs(steps) do timer.Simple(i * STEP, step) end
return "started at " .. tostring(center) .. " on " .. game.GetMap()
