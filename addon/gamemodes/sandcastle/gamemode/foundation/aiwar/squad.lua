-- Squads (docs/aiwar-command.md §3): a fire team of foundation.aiwar with a
-- leader, and the claims soldiers put on spots so no two take the same.
--
-- A fire team is { team, role, index, members = place -> member, leader };
-- a member is foundation.aiwar's roster entry, which a soldier's orders keep
-- current with what its squad needs to know of it: pos (where it is), enemy
-- (the enemy it fights, an opaque handle) and hero (its kit is a hero's);
-- and the controller with its slot's pin (foundation.aiwar.slots).
local ipairs, pairs, setmetatable = ipairs, pairs, setmetatable
local floor, HUGE = math.floor, math.huge
local Slots = require("foundation.aiwar.slots")
module(...)

-- Leaders -------------------------------------------------------------------------

-- Whether the member still belongs to the fire team.
local function Within(fireTeam, member)
	return member ~= nil and member.fireTeam == fireTeam and fireTeam.members[member.place] == member
end

-- Who may lead, best first: a member whose slot is pinned to lead, a hero
-- (the settled question: heroes lead), any other member, and last a member
-- whose slot is pinned to follow, who leads only a fire team of its own.
local PINNED_LEADER_TIER, HERO_TIER, MEMBER_TIER, PINNED_MEMBER_TIER = 3, 2, 1, 0

local function Tier(member)
	if member.pin == Slots.LEADER then return PINNED_LEADER_TIER end
	if member.pin == Slots.MEMBER then return PINNED_MEMBER_TIER end
	if member.hero then return HERO_TIER end
	return MEMBER_TIER
end

local function Better(a, b)
	if b == nil then return true end
	if Tier(a) ~= Tier(b) then return Tier(a) > Tier(b) end
	return (a.seq or HUGE) < (b.seq or HUGE)
end

-- The fire team's leader, elected when it has none or lost it: the best by
-- tier, then the member longest in the war (the lowest seq). A leader stays
-- until it leaves or one of a better tier is in the fire team.
function Leader(fireTeam)
	local best
	for _, member in pairs(fireTeam.members) do
		if Better(member, best) then best = member end
	end
	local current = fireTeam.leader
	if Within(fireTeam, current) and Tier(current) >= Tier(best) then return current end
	fireTeam.leader = best
	return best
end

-- "leader", "member" (of a squad with a leader other than it) or "solo"
-- (in no fire team).
function Kind(member)
	local fireTeam = member.fireTeam
	if not fireTeam then return "solo" end
	return Leader(fireTeam) == member and "leader" or "member"
end

-- Claims ---------------------------------------------------------------------------

-- Spots are claimed by the CLAIM_GRID cell they fall in, so two spots a
-- few units apart are one.
CLAIM_GRID = 48

function Key(kind, p)
	return kind .. ":" .. floor(p.x / CLAIM_GRID) .. ":" .. floor(p.y / CLAIM_GRID) .. ":" .. floor((p.z or 0) / CLAIM_GRID)
end

Claims = {}
Claims.__index = Claims

function Claims.New()
	return setmetatable({ held = {} }, Claims) -- key -> { holder, expires }
end

-- Who holds the claim at now, or nil.
function Claims:Holder(key, now)
	local claim = self.held[key]
	if claim and now < claim.expires then return claim.holder end
	return nil
end

-- Whether the key is free for the holder (unclaimed, expired, or its own).
function Claims:FreeFor(key, holder, now)
	local other = self:Holder(key, now)
	return other == nil or other == holder
end

-- Takes (or renews) the claim for ttl seconds; false when another holds it.
function Claims:Take(key, holder, now, ttl)
	if not self:FreeFor(key, holder, now) then return false end
	self.held[key] = { holder = holder, expires = now + ttl }
	return true
end

function Claims:Release(key, holder)
	local claim = self.held[key]
	if claim and claim.holder == holder then self.held[key] = nil end
end

-- Everything the holder held (it died, or left the war).
function Claims:ReleaseAll(holder)
	for key, claim in pairs(self.held) do
		if claim.holder == holder then self.held[key] = nil end
	end
end
