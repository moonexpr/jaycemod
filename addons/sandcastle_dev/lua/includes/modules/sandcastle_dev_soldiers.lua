-- The dev workbench's pairing of the bot soldiers a scenario saved with the bot players live now;
-- each is a { name, team } table:
--   Pair(saved, bots) -> chosen, chosen[i] the live bot standing in for saved[i], or nil: the bot of
--     its name on its team, else the first bot of its team no other saved bot took. Bots are named
--     afresh each session, so a saved name rarely survives one; a team is what makes a soldier
local ipairs = ipairs
module (...)

function Pair (saved, bots)
	local chosen, taken = {}, {}
	for i, soldier in ipairs (saved) do
		for _, bot in ipairs (bots) do
			if not taken [bot] and bot.team == soldier.team and bot.name == soldier.name then
				chosen [i], taken [bot] = bot, true
				break
			end
		end
	end
	for i, soldier in ipairs (saved) do
		if not chosen [i] then
			for _, bot in ipairs (bots) do
				if not taken [bot] and bot.team == soldier.team then
					chosen [i], taken [bot] = bot, true
					break
				end
			end
		end
	end
	return chosen
end
