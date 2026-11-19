local T = dofile ("tests/harness.lua")

local GAMEMODE = T.ROOT
local ENTITIES = "addons/sandcastle/gamemodes/sandcastle/entities/entities/"
local NEXTSOLDIER_ENTITIES = T.ADDON_TREES.nextsoldier .. "entities/"

local function Read (path)
	local file = assert (io.open (path))
	local text = file:read ("*a")
	file:close ()
	return (text:gsub ("%-%-%[%[.-%]%]", ""):gsub ("%-%-[^\n]*", ""))
end

T.test ("war soldiers hate the opposing HL2 faction and default to hostility", function ()
	local base = Read (NEXTSOLDIER_ENTITIES .. "base_nextsoldier.lua")
	local soldier = Read (ENTITIES .. "npc_nextsoldier.lua")
	T.eq (soldier:find ("ENT.DefaultRelationship = D_HT", 1, true) ~= nil,                true)
	T.eq (base:find ("local enemy = Host.current:FactionEnemy(faction)", 1, true) ~= nil, true)
	T.eq (base:find ("SetFaction(enemy, D_HT)", 1, true) ~= nil,                          true)
	local host = Read (T.ROOT .. "sh_nextsoldier_host.lua")
	T.eq (host:find ("[Factions.HL2_COMBINE] = Factions.HL2_REBELS", 1, true) ~= nil, true)
	T.eq (host:find ("[Factions.HL2_REBELS] = Factions.HL2_COMBINE", 1, true) ~= nil, true)
end)

-- Its locomotion moves under its solid mask, the engine's NPC mask until told: on
-- a map built for players a body under that walks a stair's bare treads, not the
-- clip laid over them, and one wider than it is deep stops at a riser. So it is
-- the base's, not only for those the war enlists.
T.test ("a body moves under the mask its host names, whoever spawned it", function ()
	local base = Read (NEXTSOLDIER_ENTITIES .. "base_nextsoldier.lua")
	local initialize = base:match ("function ENT:Initialize%s*%(%)(.-)\nend")
	T.eq (initialize:find ("self:SetSolidMask(Host.current:SolidMask())", 1, true) ~= nil, true, "set as it is made")
end)

-- GMod's CLuaBehaviour sets its child from InitialContainedAction just before it
-- calls BehaveStart, so that is the first moment a link under it holds.
T.test ("a class's first engine action goes in as the bot starts, after it resets", function ()
	local base = Read (NEXTSOLDIER_ENTITIES .. "base_nextsoldier.lua")
	local start = base:match ("function ENT:BehaveStart%s*%(%)(.-)\nend")
	local reset = start:find ("self:Reset()", 1, true)
	local asked = start:find ("self:InitialAction()", 1, true)
	local inserted = start:find ("nextsoldier.engine.Insert(self, action)", 1, true)
	T.eq (reset ~= nil and asked ~= nil and inserted ~= nil and reset < asked and asked < inserted, true, start)
	T.eq (base:find ("function ENT:InitialAction()", 1, true) ~= nil, true, "none by default")
end)

T.test ("a class the engine runs shows the debug layer the engine's stack", function ()
	local base = Read (NEXTSOLDIER_ENTITIES .. "base_nextsoldier.lua")
	local stack = base:match ("function ENT:DebugStack%s*%(%)(.-)\nend")
	T.eq (stack:find ("self.nsEngineDebug:Stack()", 1, true) ~= nil, true, "its actions, not its class's name")
	local start = base:match ("function ENT:BehaveStart%s*%(%)(.-)\nend")
	T.eq (start:find ("Action.DebugNpc(self, nextsoldier.engine.Stack, nextsoldier.engine.GroupStack)", 1, true) ~= nil, true,
		"made as they go in, its leggings after them")
end)

-- BehaveUpdate waits while a body scrambles, but an engine action is updated by the
-- engine whatever it is doing, and each new leap starts over: one asking every update
-- never lands.
T.test ("following a path leaves a leap under way alone", function ()
	local base = Read (NEXTSOLDIER_ENTITIES .. "base_nextsoldier.lua")
	local follow = base:match ("function ENT:FollowPath%s*%(goal, tolerance%)(.-)\nend")
	local waits = follow:find ("if self:IsScrambling() then return \"moving\" end", 1, true)
	T.eq (waits ~= nil and waits < follow:find ("local path", 1, true), true, "before anything else")
end)

T.finish ()
