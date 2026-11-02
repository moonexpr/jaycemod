-- Which team stands nearer to completing its objective, for a match the
-- gamerules close before it is won (a forced closure the AI war requests
-- when its soldiers are cut off from the objective): the team ahead on the
-- match score (rounds won), else the one nearer to winning the round by the
-- map's objective: its cart farther along its track (payload), more of the
-- flags it needs (CTF), less left on its clock (KOTH), more of the round's
-- points owned (control points). nil when it is genuinely a tie: a deciding
-- round decides it.
--
-- objective = { carts (team -> progress along its track, 0 to 1), captures
-- (team -> flags captured) and caplimit, clocks (team -> seconds left on
-- its clock), points ({ owner, inRound, hidden } each) }, each part only
-- on a map with it; the first the map has is judged.
local Teams = gameplay.teams
local ipairs, next = ipairs, next
module(...)

local RED, BLUE = Teams.RED, Teams.BLUE
-- Completions closer than this are even.
local EVEN = 1e-6

-- Each team's completion of the round's objective (higher is nearer); nil
-- for a map with none.
local function Completions(objective)
	if objective.carts and next(objective.carts) then
		return { [RED] = objective.carts[RED] or 0, [BLUE] = objective.carts[BLUE] or 0 }
	end
	if objective.captures and objective.caplimit and objective.caplimit > 0 then
		return { [RED] = objective.captures[RED] / objective.caplimit, [BLUE] = objective.captures[BLUE] / objective.caplimit }
	end
	if objective.clocks then
		return { [RED] = -objective.clocks[RED], [BLUE] = -objective.clocks[BLUE] }
	end
	if objective.points then
		local owned, total = { [RED] = 0, [BLUE] = 0 }, 0
		for _, point in ipairs(objective.points) do
			if point.inRound and not point.hidden then
				total = total + 1
				if owned[point.owner] then owned[point.owner] = owned[point.owner] + 1 end
			end
		end
		if total > 0 then return owned end
	end
	return nil
end

-- The leading team, or nil on a tie. scores: team -> rounds won.
function Leader(objective, scores)
	if scores[RED] ~= scores[BLUE] then return scores[RED] > scores[BLUE] and RED or BLUE end
	local c = Completions(objective)
	if not c then return nil end
	if c[RED] - c[BLUE] > EVEN then return RED end
	if c[BLUE] - c[RED] > EVEN then return BLUE end
	return nil
end
