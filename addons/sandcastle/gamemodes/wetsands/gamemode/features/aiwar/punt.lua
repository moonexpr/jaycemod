-- A soldier's gravity gun gadget (ws/sv_soldier.lua's GADGETS.punt): it
-- punts the nearest enemy within the gravity gun's reach with nothing solid
-- between them, as a player's punt does (weapon_balance's
-- weapon_physcannon: its damage, and a throw that can slam into a wall).
local ipairs = ipairs
module(...)

REACH = 250 -- HL2's physcannon_tracelength

-- candidates: each { distance, enemy, clear (nothing solid between) } and
-- whatever else the caller keeps. The one to punt, or nil.
function Pick(candidates)
	local best
	for _, c in ipairs(candidates) do
		if c.enemy and c.clear and c.distance <= REACH and (best == nil or c.distance < best.distance) then best = c end
	end
	return best
end
