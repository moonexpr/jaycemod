-- A fire team's tactics in a fight (foundation.aiwar.orders reads them).
--
-- Contact: what one member sees, its whole team knows: the last place an
-- enemy was seen, for CONTACT_MEMORY seconds; and where a member fell, for
-- INVESTIGATE_MEMORY, so the team goes to fight there.
--
-- Offensive, bounding overwatch: the team splits in two elements by place
-- (even, odd). One moves BOUND_DISTANCE toward the objective, from cover to
-- cover, while the other holds where it is and fires; when every moving
-- member has arrived, or BOUND_TIME has passed, they swap. A flanking team
-- first swings out to FLANK_OFFSET beside the enemy, on its side of the
-- line from team to enemy, before it bounds.
--
-- Defensive: members hold the line from cover near their post, out of the
-- threat's sight; one that is hurt moves to other cover. A team falls back
-- a step (FALLBACK_STEP further from the threat, up to FALLBACK_STEPS) when
-- it is down to FALLBACK_MEMBERS or fewer, or the enemy is within
-- FALLBACK_RANGE of its post, at most every FALLBACK_INTERVAL; it goes back
-- to its post once contact has been lost for CONTACT_MEMORY.
--
-- Positions are plain { x, y, z } tables.
local ipairs, math, sqrt = ipairs, math, math.sqrt
module(...)

CONTACT_MEMORY = 8
-- A squadmate's death is investigated this long (ReportDeath).
INVESTIGATE_MEMORY = 25
BOUND_DISTANCE, BOUND_TIME = 320, 6
FLANK_OFFSET = 480
FALLBACK_STEP, FALLBACK_STEPS = 384, 3
FALLBACK_MEMBERS, FALLBACK_RANGE, FALLBACK_INTERVAL = 1, 300, 10

local function Distance(a, b)
	local dx, dy, dz = a.x - b.x, a.y - b.y, (a.z or 0) - (b.z or 0)
	return sqrt(dx * dx + dy * dy + dz * dz)
end

-- The point `distance` from `from` toward `to`, on the ground plane (z
-- from `from`); `to` itself when nearer.
function Toward(from, to, distance)
	local dx, dy = to.x - from.x, to.y - from.y
	local length = sqrt(dx * dx + dy * dy)
	if length <= distance or length == 0 then return { x = to.x, y = to.y, z = to.z } end
	local t = distance / length
	return { x = from.x + dx * t, y = from.y + dy * t, z = from.z }
end

-- Contact --------------------------------------------------------------------

local function Remember(fireTeam, pos, now, memory)
	fireTeam.contact = { pos = { x = pos.x, y = pos.y, z = pos.z }, time = now, memory = memory }
end

function Report(fireTeam, pos, now)
	Remember(fireTeam, pos, now, CONTACT_MEMORY)
end

-- A member fell at pos (its killer's place, when known): its squadmates go
-- and investigate, so they engage the enemy rather than walk on. The
-- contact lasts INVESTIGATE_MEMORY, long enough to get there; an enemy seen
-- meanwhile takes its place.
function ReportDeath(fireTeam, pos, now)
	Remember(fireTeam, pos, now, INVESTIGATE_MEMORY)
end

-- The team's contact, or nil once it is older than its memory.
function Contact(fireTeam, now)
	local contact = fireTeam.contact
	if contact and now - contact.time <= contact.memory then return contact end
	return nil
end

-- Bounding overwatch ---------------------------------------------------------------

function Element(member)
	return member.place % 2
end

-- The team's bound, begun on first call: { moving (the element moving),
-- since, arrived = place -> true }.
function Bound(fireTeam, now)
	fireTeam.bound = fireTeam.bound or { moving = 0, since = now, arrived = {} }
	return fireTeam.bound
end

-- A member of the moving element has reached its spot.
function Arrived(fireTeam, member)
	if fireTeam.bound then fireTeam.bound.arrived[member.place] = true end
end

-- Swaps the elements once every moving member (members: the team's, in
-- place order) has arrived, or BOUND_TIME has passed. Returns whether it
-- swapped.
function UpdateBound(fireTeam, members, now)
	local bound = fireTeam.bound
	if not bound then return false end
	local done = now - bound.since >= BOUND_TIME
	if not done then
		done = true
		for _, member in ipairs(members) do
			if Element(member) == bound.moving and not bound.arrived[member.place] then
				done = false
				break
			end
		end
	end
	if not done then return false end
	fireTeam.bound = { moving = 1 - bound.moving, since = now, arrived = {} }
	return true
end

-- Ends the team's fight state: no bound, no flank, no fall back.
function Stand(fireTeam)
	fireTeam.bound, fireTeam.flank = nil, nil
end

-- Flanking ---------------------------------------------------------------------

-- Every other team of a role flanks: the odd indexed, to its own side.
function Flanks(fireTeam)
	return fireTeam.index % 2 == 1
end

-- The point FLANK_OFFSET beside the enemy, to the left (side 1) or right
-- (side -1) of the line from `from` to it.
function FlankPoint(from, enemy, side)
	local dx, dy = enemy.x - from.x, enemy.y - from.y
	local length = sqrt(dx * dx + dy * dy)
	if length == 0 then return { x = enemy.x, y = enemy.y, z = enemy.z } end
	local px, py = -dy / length, dx / length
	return { x = enemy.x + px * FLANK_OFFSET * side, y = enemy.y + py * FLANK_OFFSET * side, z = enemy.z }
end

function FlankSide(fireTeam)
	return (fireTeam.index % 4 == 1) and 1 or -1
end

-- Falling back -------------------------------------------------------------------

-- Whether the team should fall back a step now: members alive, the enemy's
-- distance to the post. Losses count only against the most the team has
-- had in this fight: a team of one is not down to its last.
function ShouldFallBack(fireTeam, alive, enemyToPost, now)
	fireTeam.peak = math.max(fireTeam.peak or 0, alive)
	if (fireTeam.fallback or 0) >= FALLBACK_STEPS then return false end
	if now - (fireTeam.fallbackAt or -FALLBACK_INTERVAL) < FALLBACK_INTERVAL then return false end
	local depleted = fireTeam.peak > FALLBACK_MEMBERS and alive <= FALLBACK_MEMBERS
	return depleted or enemyToPost <= FALLBACK_RANGE
end

function FallBack(fireTeam, now)
	fireTeam.fallback = (fireTeam.fallback or 0) + 1
	fireTeam.fallbackAt = now
end

-- Back to the post: contact lost.
function Regroup(fireTeam)
	fireTeam.fallback, fireTeam.fallbackAt, fireTeam.peak = nil, nil, nil
end

-- The post, FALLBACK_STEP per step further from the threat.
function FallbackPoint(post, threat, steps)
	if not steps or steps <= 0 then return post end
	local dx, dy = post.x - threat.x, post.y - threat.y
	local length = sqrt(dx * dx + dy * dy)
	if length == 0 then return post end
	local d = FALLBACK_STEP * steps / length
	return { x = post.x + dx * d, y = post.y + dy * d, z = post.z }
end
