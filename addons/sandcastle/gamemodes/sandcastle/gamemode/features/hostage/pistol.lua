-- The round's one pistol among the hostages, as a value apart from any
-- entity. One hostage, drawn at random, is armed as the round begins (Arm),
-- to defend itself; when it dies the pistol lies where it fell (Drop), every
-- hostage still held or following rushes for it (Rushers), and the nearest
-- within PICKUP_RANGE takes it up (Claimant, PickUp).
--
-- It is HL2's pistol as the soldiers fire it (nextsoldier.weapons), but for
-- its reload: RELOAD seconds, a civilian's fumbling, not a soldier's drill.
--
-- A pistol is immutable: each move returns a new one, and refuses what does
-- not follow (dropping one lying, taking up one held) as an error at the
-- caller's line.
local error, ipairs, pairs, require, setmetatable = error, ipairs, pairs, require, setmetatable
local Weapons = nextsoldier.weapons
local Geometry = math.geometry
local Rescue = require("features.hostage.model")
module(...)

CLASS = "weapon_pistol"
RELOAD = 4
-- A hostage this near a pistol lying takes it up.
PICKUP_RANGE = 40

STATS = (function()
	local spec = {}
	for key, value in pairs(Weapons.STATS[CLASS]) do spec[key] = value end
	spec.reload = RELOAD
	return Weapons.Stats(spec)
end)()

local Pistol = {}
Pistol.__index = Pistol

local function Made(holder, lying) return setmetatable({ holder = holder, lying = lying }, Pistol) end

-- The pistol in the hand of one of ids (a list of hostage ids), drawn by
-- randomInt(low, high); nil when there are no hostages.
function Arm(ids, randomInt)
	if #ids == 0 then return nil end
	return Made(ids[randomInt(1, #ids)], nil)
end

-- Who holds it, or nil while it lies.
function Pistol:Holder() return self.holder end

-- Where it lies ({ x, y, z }), or nil while held.
function Pistol:Lying() return self.lying end

-- Its holder died at pos.
function Pistol:Drop(pos)
	if not self.holder then error("a pistol lying is not dropped", 2) end
	return Made(nil, pos)
end

-- A hostage takes it up.
function Pistol:PickUp(id)
	if not self.lying then error("a pistol held is not taken up", 2) end
	return Made(id, nil)
end

-- The hostages of round (features.hostage.model's) who rush for it: while it
-- lies, each still held or following.
function Pistol:Rushers(round)
	local ids = {}
	if not self.lying then return ids end
	for _, id in ipairs(round.ids) do
		local state = round:StateOf(id)
		if state == Rescue.HELD or state == Rescue.FOLLOWING then ids[#ids + 1] = id end
	end
	return ids
end

-- Of positions (id -> { x, y, z }), the nearest within PICKUP_RANGE of the
-- pistol lying, or nil.
function Pistol:Claimant(positions)
	if not self.lying then return nil end
	local best, bestDistance = nil, PICKUP_RANGE
	for id, pos in pairs(positions) do
		local distance = Geometry.Distance(pos, self.lying)
		if distance <= bestDistance then best, bestDistance = id, distance end
	end
	return best
end
