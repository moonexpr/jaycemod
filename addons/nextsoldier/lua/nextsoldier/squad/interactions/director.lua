-- A squad's director: who its leader answers to (Overwatch, for the Combine), given by the mode
-- hosting the squad. Before the squad leaves a place it holds, its leader asks the director for
-- clearance (REQUEST_VACATE) and waits; the director answers over the radio with one of ANSWERS:
--   VACATE    clear to go: the squad leaves on its leader's word
--   DEFEND    hold the location: a plan comes with it (decision.plan: PATROL or AMBUSH)
--   ATTACK    assault the next room: its target comes with it (decision.target)
--   STANDBY   stand by: the squad stands down where it is, its leader appointing a new patrol
-- DEFEND and ATTACK are new orders the mode hosting the squad gives it (Directive), the leader only
-- acknowledging them (COPY).
--
-- PORT: what a director answers, Request(order, request). Set(order, director) (checked); Request(
-- order, request) -> true the once: the director asked, or with none, the leader's own word stands
-- (cleared); Answer(order, kind, decision) -> the radio's entry, the director to the leader, kept as
-- the order's directive (an unknown kind refused); Directive(order) -> the answer, or nil while none
-- is given; Requested(order) whether it has been asked; Forget(order) the request and its answer, to
-- ask again.
local Port = core.port
local Radio = nextsoldier.squad.comms.radio
local error, tostring, pairs = error, tostring, pairs
module("nextsoldier.squad.interactions.director")

PORT = Port.New("SquadDirector", { "Request" })

ANSWERS = { VACATE = true, DEFEND = true, ATTACK = true, STANDBY = true }

function Set(order, director)
	PORT:Check(director)
	order.director = director
end

function Request(order, request)
	if order.requested then return false end
	order.requested = true
	if order.director then
		order.director:Request(order, request)
	else
		order.directive = { kind = "VACATE" }
	end
	return true
end

function Answer(order, kind, decision)
	if not ANSWERS[kind] then error("no director's answer " .. tostring(kind), 2) end
	local directive = { kind = kind }
	for key, value in pairs(decision or {}) do directive[key] = value end
	directive.kind = kind
	order.directive = directive
	return Radio.Say(order, Radio.DIRECTOR, order.leader, kind)
end

function Directive(order) return order.directive end

function Requested(order) return order.requested == true end

function Forget(order) order.requested, order.directive = nil, nil end
