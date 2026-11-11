local T = dofile ("tests/harness.lua")

-- The npc controller's blockers over a fake of the nav mesh: the engine's blocked flag
-- under a door, which its path search refuses before asking any price.
local Vec
local Meta = { __sub = function (a, b) return Vec (a.x - b.x, a.y - b.y, a.z - b.z) end }
Vec = function (x, y, z) return setmetatable ({ x = x, y = y, z = z }, Meta) end

local function Area (id)
	local area = { id = id, flagged = true }
	function area:GetID () return self.id end
	function area:MarkAsUnblocked () self.flagged = false end
	return area
end

local door = {}
function door:WorldSpaceAABB () return Vec (0, 0, 0), Vec (100, 16, 100) end
function door:GetInternalVariable () return nil end
function door:GetSpawnFlags () return 0 end
function door:GetName () return "door" end

local brush = { solid = true }
function brush:IsSolid () return self.solid end
function brush:EntIndex () return 7 end
local rebuilds = 0

local under, beside = Area (1), Area (2)
local environment = setmetatable (
	{
		Vector = Vec,
		SortedPairs = pairs,
		hook = { Add = function () end },
		navmesh = { FindInBox = function () return { under } end },
		ents =
		{
			FindByClass = function (class)
				if class == "func_door*" then return { door } end
				if class == "func_brush" then return { brush } end
				return {}
			end
		},
		WS =
		{
			TEAM_UNASSIGNED = 0,
			BridgeNavGaps = function () rebuilds = rebuilds + 1 end
		}
	}, { __index = _G })

local controller = { nextBlockerRefresh = 0, navDisabled = {}, navBlocked = {}, blockerGeneration = 0, blockerLog = {} }
setfenv (assert (loadfile (T.ROOT .. "features/npc/sv_blockers.lua")), environment) (controller)
controller.BrushAreas = function () return {} end

T.test ("the engine's flag lets go of an area under a door, and of no other", function ()
	controller:RefreshBlockers (1)
	T.eq (under.flagged,  false, "under the door: the search may price it")
	T.eq (beside.flagged, true,  "the map's own blockers still count")
end)

-- cp_dustbowl's stages: a capture's outputs switch gate_2nd_spawn off and cap1_fence_brush on,
-- and what was measured against them is wrong from then on.
T.test ("a brush switched on or off has what was measured against it measured again", function ()
	local at = 100
	local function Refresh ()
		at = at + 10
		controller:RefreshBlockers (at)
	end
	Refresh ()
	local settled = rebuilds
	Refresh ()
	T.eq (rebuilds, settled, "nothing changed: nothing measured again")
	brush.solid = false
	Refresh ()
	T.eq (rebuilds, settled + 1, "switched off")
	Refresh ()
	T.eq (rebuilds, settled + 1, "once, not every look")
	brush.solid = true
	Refresh ()
	T.eq (rebuilds, settled + 2, "and on again")
end)

T.test ("a map's first look at its brushes changes nothing", function ()
	local fresh = { nextBlockerRefresh = 0, navDisabled = {}, navBlocked = {}, blockerGeneration = 0, blockerLog = {} }
	setfenv (assert (loadfile (T.ROOT .. "features/npc/sv_blockers.lua")), environment) (fresh)
	fresh.BrushAreas = function () return {} end
	local before = rebuilds
	fresh:RefreshBlockers (1)
	T.eq (rebuilds, before, "the mesh was measured as the map loaded")
end)

T.finish ()
