-- What the AI war's soldiers bring to the response rules (the
-- responserules addon, addons/responserules): their criteria set. The rules
-- and lines are data in that addon (scripts/responserules/), by the speaker
-- model's affiliation, not its team, as a team may wear either side's models.
module(...)

-- TF2's teamrole criterion: the cart's own team is on offense.
OFFENSE, DEFENSE = "offense", "defense"

-- A soldier settling into its battle stance where it rests in setup says it
-- is ready (NextSoldier's own concept; TF2 has none for it).
CONCEPT_BATTLE_STANCE = "TLK_NS_BATTLE_STANCE"

-- A soldier greets a teammate player passing it (heard by that player
-- alone), and calls out an enemy it has just spotted (heard by all near).
CONCEPT_PLAYER_PASSING = "TLK_NS_PLAYER_PASSING"
CONCEPT_ENEMY_SPOTTED = "TLK_NS_ENEMY_SPOTTED"

-- A hurt soldier calls for a medic (features.aiwar.orders' CallMedic),
-- heard by all near.
CONCEPT_CALL_MEDIC = "TLK_NS_CALL_MEDIC"

-- A hurt soldier calls out as it falls back to cover, and as it leaves
-- cover (or its post) for a health kit (features.aiwar.orders'
-- RetreatToCover and FindHealth), heard by all near.
CONCEPT_RETREAT_TO_COVER = "TLK_NS_RETREAT_TO_COVER"
CONCEPT_GET_HEALTH = "TLK_NS_GET_HEALTH"

-- Squad chatter, heard by all near: a soldier that killed an enemy says so;
-- the nearest soldier to a teammate falling within ALLY_DOWN_RANGE of it
-- calls the loss; a soldier whose last enemy slipped out of sight (still
-- alive) says it lost contact; and between fights, every IDLE_INTERVAL,
-- one soldier of each team not fighting talks on the radio.
-- A squad leader calls its squad out on its mission, its wait over
-- (features.aiwar.orders' Muster), heard by all near.
CONCEPT_MOVE_OUT = "TLK_NS_MOVE_OUT"
-- A squad leader calls its squad together to a hiding spot, its mission
-- gone wrong (heavy casualties, no progress), heard by all near.
CONCEPT_REGROUP = "TLK_NS_REGROUP"
-- A soldier taunting (a celebration or greeting played whole, standing:
-- features/aiwar/sv_gestures.lua) says a long line to go with it, heard by
-- all near.
CONCEPT_TAUNT = "TLK_NS_TAUNT"

CONCEPT_ENEMY_KILLED = "TLK_NS_ENEMY_KILLED"
CONCEPT_ALLY_DOWN = "TLK_NS_ALLY_DOWN"
CONCEPT_CONTACT_LOST = "TLK_NS_CONTACT_LOST"
CONCEPT_IDLE = "TLK_NS_IDLE"
ALLY_DOWN_RANGE = 1500
IDLE_INTERVAL = 5

function WitnessesFall(distance)
	return distance <= ALLY_DOWN_RANGE
end

-- A player passes a soldier within GREET_RANGE, moving at PASS_SPEED or
-- faster (a walk; standing about beside it is not passing).
GREET_RANGE, PASS_SPEED = 128, 90

function Passes(distance, speed)
	return distance <= GREET_RANGE and speed >= PASS_SPEED
end

-- A soldier's criteria set: its voice's affiliation and name
-- (ws.voices), its team's role, a random draw 0..100 (TF2's
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
