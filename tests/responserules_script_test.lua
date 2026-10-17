-- responserules_script (addons/responserules): TF2's talker script files
-- (scripts/talker/*.txt, the grammar AI_ResponseSystem.cpp parses) into the
-- definitions foundation.responserules builds a system from.
local T = dofile("tests/harness.lua")
local Script = T.require("responserules_script")
local Response = T.require("responserules")

local function First(n) if n then return 1 end return 0 end
local function Speaker() return { memory = Response.Memory(), contexts = Response.Contexts() } end

-- Parses text as one file, with no includes.
local function Parse(text) return Script.Load("test.txt", function(path) if path == "test.txt" then return text end end) end

local function Refused(text)
	local ok, err = pcall(Parse, text)
	return not ok and tostring(err) or nil
end

T.test("a criterion line: its key, value, weight and required, keywords in any case", function()
	local defs = Parse([[
Criterion "ConceptCartStop" "Concept" "TLK_CART_STOP" required
criteria "Half" "randomnum" ">50" weight 2
criterion Bare health ">10,<=50"
]])
	local stop = defs.criteria.ConceptCartStop
	T.eq(stop[1], "Concept", "its key")
	T.eq(stop[2], "TLK_CART_STOP", "its value")
	T.eq(stop.required, true, "required")
	T.eq(defs.criteria.Half.weight, 2, "a weight")
	T.eq(defs.criteria.Half.required, nil, "not required")
	T.eq(defs.criteria.Bare[2], ">10,<=50", "unquoted")
end)

-- TokenWaiting: a criterion reads its options from its own line only.
T.test("a criterion's options are on its own line", function()
	T.eq(Refused("criterion A x 1\nrequired\n"):find("test.txt:2", 1, true) ~= nil, true, "a lone option is no command")
end)

T.test("comments run to the end of the line; quoted words keep their spaces", function()
	local defs = Parse([[
// the cart
criterion "Said" "SaidIt" "!=1" required // not yet
response "Lines" { print "the cart's stopped: back on it" }
]])
	T.eq(defs.criteria.Said[2], "!=1", "past the comment")
	T.eq(defs.responses.Lines[1][2], "the cart's stopped: back on it", "the whole line")
end)

T.test("a response group: its flags, lines, weights and parameters", function()
	local defs = Parse([[
response "Cart"
{
	permitrepeats
	sequential
	norepeat
	speak "vo/a.wav" weight 3 odds 50 delay 1,2 soundlevel "SNDLVL_90dB"
	speak "vo/b.wav" respeakdelay 10 speakonce
	print "c" defaultdelay
}
]])
	local g = defs.responses.Cart
	T.eq(g.permitrepeats and g.sequential and g.norepeat, true, "the flags")
	T.eq(#g, 3, "three lines")
	T.eq(g[1][1], "speak", "a sound")
	T.eq(g[1].weight, 3, "weighted")
	T.eq(g[3][1], "print", "a print")
	-- AI_ResponseParams are the group's, whichever line sets them
	T.eq(g.params.odds, 50, "odds")
	T.eq(g.params.soundlevel, "SNDLVL_90dB", "a sound level")
	T.eq(g.params.respeakdelay[1], 10, "a respeak delay")
	T.eq(g.params.speakonce, true, "speakonce")
	T.eq(g.params.delay[1], Script.DEFAULT_DELAY[1], "the last delay set: defaultdelay")
	T.eq(g.params.delay[2], Script.DEFAULT_DELAY[2], "to its end")
end)

T.test("nodelay takes no argument, and leaves no delay", function()
	local defs = Parse([[
response "Quick" { speak "vo/a.wav" nodelay weight 2 }
]])
	T.eq(defs.responses.Quick.params.delay[2], 0, "none")
	T.eq(defs.responses.Quick[1].weight, 2, "the option after it still read")
end)

T.test("a response group on one line", function()
	local defs = Parse([[
response "One" odds 25 speak "vo/a.wav"
criterion "C" "concept" "TLK_A"
]])
	T.eq(defs.responses.One[1][2], "vo/a.wav", "its line")
	T.eq(defs.responses.One.params.odds, 25, "its odds")
	T.eq(defs.criteria.C ~= nil, true, "the next definition")
end)

T.test("a rule: its criteria and groups by line, contexts, matchonce, and inline criteria", function()
	local defs = Parse([[
criterion "A" "concept" "TLK_A" required
criterion "B" "x" "1"
response "G" { print "g" }
response "H" { print "h" }
rule "R"
{
	criteria A B
	"teamrole" "offense" required
	ApplyContext "SaidA:1:20"
	applycontext "SaidB:1"
	matchonce
	Response G H
}
]])
	local r = defs.rules.R
	T.eq(table.concat(r.criteria, " "), "A B [R001]", "named, then inline")
	T.eq(defs.criteria["[R001]"][1], "teamrole", "the inline criterion's key")
	T.eq(defs.criteria["[R001]"].required, true, "and its option")
	T.eq(table.concat(r.responses, " "), "G H", "both groups")
	T.eq(table.concat(r.applyContext, " "), "SaidA:1:20 SaidB:1", "both contexts")
	T.eq(r.matchonce, true, "matchonce")
end)

T.test("an enumeration and a criterion of criteria", function()
	local defs = Parse([[
enumeration "NPCState"
{
	"Idle" "1"
	"Combat" "3"
}
criterion "X" "x" "1"
criterion "Y" "y" "1"
criterion "Either" { X Y } required weight 2
]])
	T.eq(defs.enumerations["[npcstate::combat]"], 3, "the member, lower case")
	T.eq(table.concat(defs.criteria.Either.subcriteria, " "), "X Y", "the criteria it holds")
	T.eq(defs.criteria.Either.required, true, "required")
	T.eq(defs.criteria.Either.weight, 2, "weighted")
end)

T.test("an include is read relative to the scripts folder, once", function()
	local files = {
		["responserules/root.txt"] = '#include "responserules/a.txt"\n#include "responserules/b.txt"\n',
		["responserules/a.txt"] = 'criterion "A" "concept" "TLK_A" required\n',
		["responserules/b.txt"] = 'response "G" { print "g" }\nrule "R" { criteria A\n response G }\n',
	}
	local read = {}
	local defs = Script.Load("responserules/root.txt", function(path) read[#read + 1] = path return files[path] end)
	T.eq(#read, 3, "every file")
	local said = Response.System(defs):Speak(Speaker(), "TLK_A", {}, First, 0)
	T.eq(said.response.value, "g", "the rules across them work")
end)

T.test("an include that comes back round to a file being read is refused", function()
	local files = { ["a.txt"] = '#include "b.txt"\n', ["b.txt"] = '#include "a.txt"\n' }
	T.eq((pcall(Script.Load, "a.txt", function(path) return files[path] end)), false, "refused")
end)

T.test("what cannot be read or parsed is refused, saying where", function()
	T.eq((pcall(Script.Load, "missing.txt", function() return nil end)), false, "a missing file")
	T.eq(Refused('speech "x"\n'):find("test.txt:1", 1, true) ~= nil, true, "an unknown command, with its line")
	T.eq(Refused('response "G" { scene "x.vcd" }\n') ~= nil, true, "a kind this engine does not play")
	T.eq(Refused('response "G" { speak "x.wav" loudly }\n') ~= nil, true, "an unknown option")
	T.eq(Refused('response "G" { speak "x.wav" predelay 1 }\n') ~= nil, true, "an option this engine does not play")
	T.eq(Refused('response "G" { speak "x.wav"\n') ~= nil, true, "an unclosed group")
	T.eq(Refused('rule "R" { applyContextToWorld\n }\n') ~= nil, true, "world contexts")
	T.eq(Refused('criterion "A" x 1\ncriterion "A" y 1\n'):find("test.txt:2", 1, true) ~= nil, true, "a second definition")
	T.eq(Refused('response "G" { speak "x.wav" delay soon }\n') ~= nil, true, "an interval that is no number")
end)

-- TF2's own text, as soldier.txt and response_rules.txt have it.
T.test("TF2's own rules parse and answer", function()
	local text = [[
criterion "ConceptCartMovingBackward" "Concept" "TLK_CART_MOVING_BACKWARD" required
criterion "IsOnDefense" "teamrole" "defense" required
criterion "IsSoldier" "playerclass" "Soldier" "required"
criterion "75PercentChance"  "randomnum"               ">25"   required
Criterion "SoldierNotSaidCartMovingBackwardD" "SaidCartMovingBackwardD" "!=1" "required" weight 0
Response CartMovingBackwardsDefenseSoldier
{
	scene "scenes/Player/Soldier/low/7371.vcd"
}
Rule CartMovingBackwardsDefenseSoldier
{
	criteria ConceptCartMovingBackward IsOnDefense IsSoldier SoldierNotSaidCartMovingBackwardD 75PercentChance
	ApplyContext "SaidCartMovingBackwardD:1:20"
	Response CartMovingBackwardsDefenseSoldier
}
]]
	-- a scene is not played here: the line is a sound instead
	local defs = Parse((text:gsub('scene "scenes/Player/Soldier/low/7371.vcd"', 'speak "vo/soldier.wav"')))
	local said = Response.System(defs):Speak(Speaker(), "TLK_CART_MOVING_BACKWARD",
		{ teamrole = "defense", playerclass = "Soldier", randomnum = 90 }, First, 0)
	T.eq(said.rule, "CartMovingBackwardsDefenseSoldier", "TF2's rule")
	T.eq(defs.criteria.IsSoldier.required, true, "a quoted \"required\"")
end)

T.finish()
