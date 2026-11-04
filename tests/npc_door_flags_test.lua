local T = dofile("tests/harness.lua")

-- The npc controller's blockers over a fake of the nav mesh: the engine's blocked flag
-- under a door, which its path search refuses before asking any price.
local Vec
local Meta = { __sub = function(a, b) return Vec(a.x - b.x, a.y - b.y, a.z - b.z) end }
Vec = function(x, y, z) return setmetatable({ x = x, y = y, z = z }, Meta) end

local function Area(id)
	local area = { id = id, flagged = true }
	function area:GetID() return self.id end
	function area:MarkAsUnblocked() self.flagged = false end
	return area
end

local door = {}
function door:WorldSpaceAABB() return Vec(0, 0, 0), Vec(100, 16, 100) end
function door:GetInternalVariable() return nil end
function door:GetSpawnFlags() return 0 end
function door:GetName() return "door" end

local under, beside = Area(1), Area(2)
local environment = setmetatable({
	Vector = Vec,
	SortedPairs = pairs,
	hook = { Add = function() end },
	navmesh = { FindInBox = function() return { under } end },
	ents = { FindByClass = function(class) return class == "func_door*" and { door } or {} end },
	WS = { TEAM_UNASSIGNED = 0 },
}, { __index = _G })

local controller = { nextBlockerRefresh = 0, navDisabled = {}, navBlocked = {}, blockerGeneration = 0, blockerLog = {} }
setfenv(assert(loadfile(T.ROOT .. "features/npc/sv_blockers.lua")), environment)(controller)

T.test("the engine's flag lets go of an area under a door, and of no other", function()
	controller:RefreshBlockers(1)
	T.eq(under.flagged, false, "under the door: the search may price it")
	T.eq(beside.flagged, true, "the map's own blockers still count")
end)

T.finish()
