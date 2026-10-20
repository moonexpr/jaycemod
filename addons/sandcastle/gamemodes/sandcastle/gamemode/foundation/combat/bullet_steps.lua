-- The steps every bullet fired passes through, in a fixed order. GMod's
-- EntityFireBullets stops at the first hook that answers, so systems that
-- each change a shot (the weapon balance, the soldiers' marksmanship, the
-- fixed pellet spread) cannot be hooks side by side: they are steps of the
-- one hook (ws/sh_bullets.lua). A step takes (shooter, data) and answers
-- CHANGED (fire data as it now is), SUPPRESSED (fire nothing; no later step
-- runs) or nil (leave it).
local ipairs, setmetatable, sort = ipairs, setmetatable, table.sort
module(...)

CHANGED, SUPPRESSED = true, false

-- Each step's place: the weapon's own spread first, then how well its
-- shooter aims it, then the pellets it splits into.
BALANCE, AIM, PELLETS = 10, 20, 30

local Steps = {}
Steps.__index = Steps

function New()
	return setmetatable({ list = {} }, Steps)
end

-- Adds step under name at order (lower runs first), replacing any of that
-- name, so a reloaded file adds its step again.
function Steps:Add(name, order, step)
	local kept = {}
	for _, entry in ipairs(self.list) do
		if entry.name ~= name then kept[#kept + 1] = entry end
	end
	kept[#kept + 1] = { name = name, order = order, step = step }
	sort(kept, function(a, b) return a.order < b.order end)
	self.list = kept
end

-- What the hook answers for the shot: CHANGED, SUPPRESSED or nil.
function Steps:Run(shooter, data)
	local changed = nil
	for _, entry in ipairs(self.list) do
		local answer = entry.step(shooter, data)
		if answer == SUPPRESSED then return SUPPRESSED end
		if answer == CHANGED then changed = CHANGED end
	end
	return changed
end
