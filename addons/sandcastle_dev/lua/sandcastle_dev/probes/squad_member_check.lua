-- npc_pathfollower driven by its legs on a live server, as the Path Follower stool's Local mode
-- drives it, its feet held: three members crowded
-- together and one apart, told to muster (stationary, alert, cautious, close), to fall back
-- (stationary, panicked), to muster again and lose half of them, the first leading (its leader
-- calls the fall back: "Fall back!" in the chat and console), and dissolved, each read back as data.
-- Leaves nothing behind. Run it, wait for its steps, then read the result:
--   dt gmod/instances MAP - < sandcastle_dev/probes/squad_member_check.lua
--   dt gmod/instances MAP 'return NSSquadCheck'
local Legs = nextsoldier.behavior.group_identity
local STEP = 1.5
local CROWD = 30

local function Point (v) return { x = v.x, y = v.y, z = v.z } end

local function Largest ()
	local best
	for _, area in ipairs (navmesh.GetAllNavAreas ()) do
		if not best or area:GetSizeX () * area:GetSizeY () > best:GetSizeX () * best:GetSizeY () then best = area end
	end
	return best
end

-- a round won would change the map under it
RunConsoleCommand ("mp_winlimit",  "0")
RunConsoleCommand ("mp_timelimit", "0")
RunConsoleCommand ("mp_maxrounds", "0")

local center = Largest ():GetCenter ()
local straggler = navmesh.GetNearestNavArea (center + Vector (400, 400, 0)):GetClosestPointOnArea (center + Vector (400, 400, 0))
local spots = { center, center + Vector (CROWD, 0, 0), center + Vector (0, CROWD, 0), straggler }
local members = {}
for i, spot in ipairs (spots) do
	local member = ents.Create ("npc_pathfollower")
	member.ToolManaged = true
	member:SetPos (spot + Vector (0, 0, 1))
	member:Spawn ()
	member:Activate ()
	member:SetWarTeam (WS.TEAM_BLUE)
	member:SetDriver ("legs")
	member:HoldFeet (true)
	members [i] = member
end

-- One member as its legs stand: its trees, its order, its place and spot, how far it moved.
local function Line (member, i)
	local names = {}
	for j, frame in ipairs (nextsoldier.engine.Stack (member)) do names [j] = frame.name end
	local push = member:GetNW2Vector ("LegsPush", vector_origin)
	local place = member:GetNW2Vector ("LegsPlace", vector_origin)
	local spot = member:GetNW2Vector ("LegsSpot", vector_origin)
	local path = member:GetPath ()
	return string.format ("%s | order %q mode %d place %.0f,%.0f,%.0f spot %.0f from it, path %s, stands %s | moved %.0f | push %.2f,%.2f spacing %.0f",
		table.concat (names, " > "), member:GetNW2String ("LegsOrder", ""), member:GetNW2Int ("LegsMode", -1),
		place.x, place.y, place.z, spot:Distance (place), tostring (path and path:IsValid ()),
		tostring (member:GetNW2Bool ("LegsStands", false)), member:GetPos ():Distance2D (spots [i]),
		push.x, push.y, member:GetNW2Float ("LegsSpacing", 0))
end

local function Read ()
	local out = {}
	for i, member in ipairs (members) do
		out [i] = (IsValid (member) and member:Health () > 0) and Line (member, i) or "dead"
	end
	return table.concat (out, "\n")
end

local current

local function Tell (order)
	current = order
	local positions = {}
	for i, member in ipairs (members) do positions [i] = Point (member:GetPos ()) end
	local places = order:Places (positions, nextsoldier.engine.GroupSpacing (), members [1]:LegsAdmit (Vector (order.point.x, order.point.y, order.point.z)))
	for i, member in ipairs (members) do member:LegsGive (order, places [i]) end
	order:Lead (members [1])
end

NSSquadCheck = "running"
local result = {}
local steps =
{
	function () result [#result + 1] = "AT EASE\n" .. Read () Tell (Legs.Muster (Point (center))) end,
	function () result [#result + 1] = "MUSTER\n" .. Read () current:SetMode (Legs.MODE.ALERT) end,
	function () result [#result + 1] = "ALERT\n" .. Read () current:SetMode (Legs.MODE.CAUTIOUS) end,
	function () result [#result + 1] = "CAUTIOUS\n" .. Read () current:SetMode (Legs.MODE.CLOSE) end,
	function () result [#result + 1] = "CLOSE\n" .. Read () Tell (Legs.FallBack (Point (center), Point (center + Vector (600, 0, 0)))) end,
	function () result [#result + 1] = "FALL BACK\n" .. Read () current:SetMode (Legs.MODE.PANIC) end,
	function ()
		result [#result + 1] = "PANIC\n" .. Read ()
		Tell (Legs.Muster (Point (center)))
		for i = 2, 3 do members [i]:TakeDamage (10000) end
	end,
	function ()
		result [#result + 1] = string.format ("CASUALTIES lost %d of %d, mode %d, routed %s\n", current.lost, current.size,
			current.mode, tostring (current.routed)) .. Read ()
		for _, member in ipairs (members) do if IsValid (member) then member:LegsGive (nil) end end
	end,
	function ()
		result [#result + 1] = "DISSOLVED\n" .. Read ()
		for _, member in ipairs (members) do if IsValid (member) then member:Remove () end end
		local tool = weapons.GetStored ("gmod_tool")
		result [#result + 1] = "stool registered: " .. tostring (tool and tool.Tool and tool.Tool.ns_pathfollower ~= nil)
		NSSquadCheck = table.concat (result, "\n\n")
	end
}
for i, step in ipairs (steps) do timer.Simple (i * STEP, step) end
return "started at " .. tostring (center) .. " on " .. game.GetMap ()
