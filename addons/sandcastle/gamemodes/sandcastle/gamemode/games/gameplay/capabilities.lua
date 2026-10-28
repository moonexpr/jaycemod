-- The AI capabilities a team's soldiers may use beyond their opponents'
-- (decision Q6 b, docs/spawn-menu-design.md §4.4.1): a set, an immutable
-- value. AMBUSH is the first; later ones join KNOWN. A team holds one
-- through the war (War:SetCapabilities); the AI Commander, once built,
-- offers the jobs a capability opens. Until then a set is held and
-- published and changes no behaviour.
--   None() -> the empty set; set:With(capability) -> a new set with it
--   (an unknown capability is our bug: an error, never a player's
--   refusal); set:Has(capability)
local error, pairs, setmetatable, tostring = error, pairs, setmetatable, tostring
module(...)

AMBUSH = "ambush"
KNOWN = { [AMBUSH] = true }

local Set = {}
Set.__index = Set

local function Of(members)
	return setmetatable({ members = members }, Set)
end

function None()
	return Of({})
end

function Set:With(capability)
	if not KNOWN[capability] then error("unknown AI capability " .. tostring(capability), 2) end
	local members = {}
	for member in pairs(self.members) do members[member] = true end
	members[capability] = true
	return Of(members)
end

function Set:Has(capability)
	return self.members[capability] == true
end
