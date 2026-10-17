-- What the AI war's soldiers say about the cart, as response rules
-- (foundation.core.response) in the shape of TF2's (scripts/talker/*.txt:
-- each class's CartMoving{Forward,Backwards}{Offense,Defense} and
-- CartMovingStopped rules): a concept the cart's watcher has them speak
-- (team_train_watcher: TLK_CART_MOVING_FORWARD to its pushers,
-- TLK_CART_STOP and TLK_CART_MOVING_BACKWARD to everyone), on offense or
-- defense, by CHANCE, and not again in that role for SAID_SECONDS. TF2 says
-- only "stop" when the enemy cuts the cart off; here a stop with the cart
-- blocked (cartblocked) has lines of its own.
--
-- A skeleton: each voice (foundation.npc.voices' names) has a few of
-- HL2's own lines where one fits and a print placeholder where none does.
local format, ipairs = string.format, ipairs
local Response = require("foundation.core.response")
module(...)

CONCEPT_CART_MOVING_FORWARD = "TLK_CART_MOVING_FORWARD"
CONCEPT_CART_MOVING_BACKWARD = "TLK_CART_MOVING_BACKWARD"
CONCEPT_CART_STOP = "TLK_CART_STOP"
-- TF2's teamrole criterion
OFFENSE, DEFENSE = "offense", "defense"
-- response_rules.txt's 75PercentChance, and TF2's "Said...:1:20" contexts
CHANCE = 75
SAID_SECONDS = 20

VOICES = { "male", "female", "alyx", "combine", "metrocop", "vortigaunt" }

-- A soldier's criteria set: its team's role, its voice, a random draw
-- 0..100 (TF2's randomnum), and whether the enemy holds the cart.
function Criteria(role, voice, randomnum, blocked)
	return { teamrole = role, voice = voice, randomnum = randomnum, cartblocked = blocked and 1 or 0 }
end

-- The situations each voice speaks to: a concept in a role, and the stop
-- with the cart cut off (its rule outscores the plain stop's by its
-- required cartblocked).
local SITUATIONS = {
	{ name = "CartMovingForwardOffense", concept = CONCEPT_CART_MOVING_FORWARD, role = OFFENSE, said = "SaidCartMovingForwardO" },
	{ name = "CartMovingForwardDefense", concept = CONCEPT_CART_MOVING_FORWARD, role = DEFENSE, said = "SaidCartMovingForwardD" },
	{ name = "CartMovingBackwardsOffense", concept = CONCEPT_CART_MOVING_BACKWARD, role = OFFENSE, said = "SaidCartMovingBackwardO" },
	{ name = "CartMovingBackwardsDefense", concept = CONCEPT_CART_MOVING_BACKWARD, role = DEFENSE, said = "SaidCartMovingBackwardD" },
	{ name = "CartMovingStoppedOffense", concept = CONCEPT_CART_STOP, role = OFFENSE, said = "SaidCartMovingStoppedO" },
	{ name = "CartMovingStoppedDefense", concept = CONCEPT_CART_STOP, role = DEFENSE, said = "SaidCartMovingStoppedD" },
	{ name = "CartBlockedOffense", concept = CONCEPT_CART_STOP, role = OFFENSE, said = "SaidCartMovingStoppedO", blocked = true },
	{ name = "CartBlockedDefense", concept = CONCEPT_CART_STOP, role = DEFENSE, said = "SaidCartMovingStoppedD", blocked = true },
}

local function Print(text) return { "print", text } end
local function Speak(path) return { "speak", path } end

-- voice -> situation -> lines
local LINES = {
	male = {
		CartMovingForwardOffense = { Speak("vo/npc/male01/letsgo01.wav"), Speak("vo/npc/male01/letsgo02.wav"), Speak("vo/npc/male01/okimready01.wav") },
		CartMovingForwardDefense = { Speak("vo/npc/male01/uhoh.wav"), Speak("vo/npc/male01/ohno.wav") },
		CartMovingBackwardsOffense = { Speak("vo/npc/male01/ohno.wav"), Speak("vo/npc/male01/goodgod.wav") },
		CartMovingBackwardsDefense = { Speak("vo/npc/male01/nice.wav"), Speak("vo/npc/male01/yeah02.wav"), Speak("vo/npc/male01/finally.wav") },
		CartMovingStoppedOffense = { Print("the cart's stopped: back on it") },
		CartMovingStoppedDefense = { Speak("vo/npc/male01/nice.wav") },
		CartBlockedOffense = { Speak("vo/npc/male01/combine01.wav"), Speak("vo/npc/male01/headsup01.wav"), Speak("vo/npc/male01/watchout.wav") },
		CartBlockedDefense = { Speak("vo/npc/male01/yeah02.wav"), Speak("vo/npc/male01/gethellout.wav") },
	},
	female = {
		CartMovingForwardOffense = { Speak("vo/npc/female01/letsgo01.wav"), Speak("vo/npc/female01/letsgo02.wav") },
		CartMovingForwardDefense = { Speak("vo/npc/female01/uhoh.wav"), Speak("vo/npc/female01/ohno.wav") },
		CartMovingBackwardsOffense = { Speak("vo/npc/female01/ohno.wav") },
		CartMovingBackwardsDefense = { Speak("vo/npc/female01/nice01.wav"), Speak("vo/npc/female01/yeah02.wav"), Speak("vo/npc/female01/finally.wav") },
		CartMovingStoppedOffense = { Print("the cart's stopped: back on it") },
		CartMovingStoppedDefense = { Speak("vo/npc/female01/nice01.wav") },
		CartBlockedOffense = { Speak("vo/npc/female01/combine01.wav"), Speak("vo/npc/female01/headsup01.wav"), Speak("vo/npc/female01/watchout.wav") },
		CartBlockedDefense = { Speak("vo/npc/female01/yeah02.wav") },
	},
	alyx = {
		CartMovingForwardOffense = { Print("Alyx: keep it moving") },
		CartMovingForwardDefense = { Speak("vo/npc/alyx/ohno_startle01.wav") },
		CartMovingBackwardsOffense = { Speak("vo/npc/alyx/ohno_startle01.wav") },
		CartMovingBackwardsDefense = { Print("Alyx: it's rolling back") },
		CartMovingStoppedOffense = { Print("Alyx: the cart's stopped") },
		CartMovingStoppedDefense = { Print("Alyx: we've stopped it") },
		CartBlockedOffense = { Speak("vo/npc/alyx/watchout01.wav") },
		CartBlockedDefense = { Print("Alyx: we're holding the cart") },
	},
	combine = {
		CartMovingForwardOffense = { Speak("npc/combine_soldier/vo/movein.wav"), Speak("npc/combine_soldier/vo/sweepingin.wav"), Speak("npc/combine_soldier/vo/closing.wav") },
		CartMovingForwardDefense = { Speak("npc/combine_soldier/vo/contact.wav"), Speak("npc/combine_soldier/vo/engaging.wav") },
		CartMovingBackwardsOffense = { Speak("npc/combine_soldier/vo/heavyresistance.wav"), Speak("npc/combine_soldier/vo/coverhurt.wav") },
		CartMovingBackwardsDefense = { Speak("npc/combine_soldier/vo/affirmative.wav"), Speak("npc/combine_soldier/vo/containmentproceeding.wav") },
		CartMovingStoppedOffense = { Speak("npc/combine_soldier/vo/stayalert.wav"), Speak("npc/combine_soldier/vo/gosharp.wav") },
		CartMovingStoppedDefense = { Speak("npc/combine_soldier/vo/copy.wav") },
		CartBlockedOffense = { Speak("npc/combine_soldier/vo/contact.wav"), Speak("npc/combine_soldier/vo/suppressing.wav"), Speak("npc/combine_soldier/vo/flush.wav") },
		CartBlockedDefense = { Speak("npc/combine_soldier/vo/containmentproceeding.wav") },
	},
	metrocop = {
		CartMovingForwardOffense = { Speak("npc/metropolice/vo/moveit.wav"), Speak("npc/metropolice/vo/allunitsmovein.wav") },
		CartMovingForwardDefense = { Speak("npc/metropolice/vo/lookout.wav"), Speak("npc/metropolice/vo/backup.wav") },
		CartMovingBackwardsOffense = { Speak("npc/metropolice/vo/officerneedsassistance.wav"), Speak("npc/metropolice/vo/takecover.wav") },
		CartMovingBackwardsDefense = { Speak("npc/metropolice/vo/affirmative.wav"), Speak("npc/metropolice/vo/movealong.wav") },
		CartMovingStoppedOffense = { Print("metrocop: the cart's stopped") },
		CartMovingStoppedDefense = { Speak("npc/metropolice/vo/holdit.wav") },
		CartBlockedOffense = { Speak("npc/metropolice/vo/getdown.wav"), Speak("npc/metropolice/vo/backup.wav") },
		CartBlockedDefense = { Speak("npc/metropolice/vo/holdit.wav") },
	},
	vortigaunt = {
		CartMovingForwardOffense = { Speak("vo/npc/vortigaunt/onward.wav"), Speak("vo/npc/vortigaunt/forfreedom.wav") },
		CartMovingForwardDefense = { Print("vortigaunt: the cart advances") },
		CartMovingBackwardsOffense = { Print("vortigaunt: the cart retreats") },
		CartMovingBackwardsDefense = { Speak("vo/npc/vortigaunt/vortigese02.wav") },
		CartMovingStoppedOffense = { Print("vortigaunt: the cart is still") },
		CartMovingStoppedDefense = { Print("vortigaunt: we hold it") },
		CartBlockedOffense = { Print("vortigaunt: they bar the way") },
		CartBlockedDefense = { Print("vortigaunt: we bar their way") },
	},
}

-- The rules, built once (Response.System refuses any that names what it
-- lacks).
function System()
	local criteria = {
		ConceptCartMovingForward = { "concept", CONCEPT_CART_MOVING_FORWARD, required = true },
		ConceptCartMovingBackward = { "concept", CONCEPT_CART_MOVING_BACKWARD, required = true },
		ConceptCartMovingStopped = { "concept", CONCEPT_CART_STOP, required = true },
		IsOnOffense = { "teamrole", OFFENSE, required = true },
		IsOnDefense = { "teamrole", DEFENSE, required = true },
		CartBlocked = { "cartblocked", "1", required = true },
		Chance = { "randomnum", format(">%d", 100 - CHANCE), required = true },
	}
	local CONCEPT = {
		[CONCEPT_CART_MOVING_FORWARD] = "ConceptCartMovingForward",
		[CONCEPT_CART_MOVING_BACKWARD] = "ConceptCartMovingBackward",
		[CONCEPT_CART_STOP] = "ConceptCartMovingStopped",
	}
	local responses, rules = {}, {}
	for _, voice in ipairs(VOICES) do
		local isVoice = "Is_" .. voice
		criteria[isVoice] = { "voice", voice, required = true }
		for _, s in ipairs(SITUATIONS) do
			local notSaid = "NotSaid" .. s.said
			criteria[notSaid] = { s.said, "!=1", required = true, weight = 0 }
			local name = s.name .. "_" .. voice
			responses[name] = LINES[voice][s.name]
			local list = { CONCEPT[s.concept], s.role == OFFENSE and "IsOnOffense" or "IsOnDefense", isVoice, notSaid, "Chance" }
			if s.blocked then list[#list + 1] = "CartBlocked" end
			rules[name] = { criteria = list, response = name, applyContext = { format("%s:1:%d", s.said, SAID_SECONDS) } }
		end
	end
	return Response.System({ criteria = criteria, responses = responses, rules = rules })
end
