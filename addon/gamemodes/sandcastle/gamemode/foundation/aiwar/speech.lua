-- What the AI war's soldiers bring to the response rules (the
-- responserules addon, addons/responserules): their criteria set. The rules
-- and lines are data in that addon (scripts/responserules/), by the speaker
-- model's affiliation, not its team, as a team may wear either side's models.
module(...)

-- TF2's teamrole criterion: the cart's own team is on offense.
OFFENSE, DEFENSE = "offense", "defense"

-- A soldier's criteria set: its voice's affiliation and name
-- (foundation.npc.voices), its team's role, a random draw 0..100 (TF2's
-- randomnum), and whether the enemy holds the cart.
function Criteria(voice, role, randomnum, blocked)
	return {
		affiliation = voice.affiliation,
		voice = voice.name,
		teamrole = role,
		randomnum = randomnum,
		cartblocked = blocked and 1 or 0,
	}
end
