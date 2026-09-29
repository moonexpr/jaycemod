-- What a new game is, told to the players as it starts: the game mode the
-- map plays and its objectives, from what the map holds (payload trains, a
-- race, control points and their rounds) and its name's prefix (pl_, plr_,
-- koth_, ctf_, cp_, arena_...).
local format, lower, match = string.format, string.lower, string.match
module(...)

-- info = { map, trains (team_train_watchers), race (tf_logic_multiple_escort
-- or plr_), points (team_control_points), rounds (team_control_point_rounds),
-- flags (item_teamflags) }. Returns the title and the objective lines.
function Describe(info)
	local prefix = lower(match(info.map or "", "^(%a+)_") or "")
	local lines = {}
	local function Stages()
		if (info.rounds or 0) > 1 then lines[#lines + 1] = format("%d stages; each won stage moves the fight on to the next.", info.rounds) end
	end
	if info.race or prefix == "plr" then
		lines[#lines + 1] = "Each team pushes its own cart along its own track."
		lines[#lines + 1] = "The first cart to reach the end of its track wins; stand by your cart to push it and near theirs to stop it."
		Stages()
		return "Payload Race gameplay activated!", lines
	end
	if (info.trains or 0) > 0 or prefix == "pl" then
		lines[#lines + 1] = "BLU: push the cart past every checkpoint to the end of the track before the time runs out."
		lines[#lines + 1] = "RED: stop the cart; each checkpoint BLU reaches adds time to the clock."
		if (info.points or 0) > 0 then lines[#lines + 1] = format("%d checkpoints on the track.", info.points) end
		Stages()
		return "Payload gameplay activated!", lines
	end
	if prefix == "koth" then
		lines[#lines + 1] = "Capture the point in the middle and hold it."
		lines[#lines + 1] = "Your team's clock runs while you own the point; the first team whose clock runs out wins."
		return "King of the Hill gameplay activated!", lines
	end
	if (info.flags or 0) > 0 or prefix == "ctf" then
		lines[#lines + 1] = "Steal the enemy's intelligence and carry it back to your base to score."
		lines[#lines + 1] = "Guard your own intelligence; a dropped briefcase returns home after a while."
		return "Capture the Flag gameplay activated!", lines
	end
	if prefix == "arena" then
		lines[#lines + 1] = "One life each: eliminate the other team, or capture the point once it unlocks."
		return "Arena gameplay activated!", lines
	end
	if (info.points or 0) > 0 or prefix == "cp" then
		lines[#lines + 1] = format("Capture the control points (%d on this map); own them all to win.", info.points or 0)
		lines[#lines + 1] = "Stand on a point to capture it; more teammates capture faster, an enemy on it blocks you."
		Stages()
		return "Control Points gameplay activated!", lines
	end
	lines[#lines + 1] = "Play the map's objectives; the round system is running."
	return "Sandcastle gameplay activated!", lines
end
