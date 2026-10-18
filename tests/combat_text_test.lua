local T = dofile("tests/harness.lua")
local P = T.require("foundation.players")
local Text = T.require("foundation.combat.combat_text")

local VICTIM, OTHER = "victim", "other"
local POS = { x = 0, y = 0, z = 64 }
local WINDOW = 0.2 -- hud_combattext_batching_window

T.test("a hit shows its damage, rising and fading out over its life", function()
	local texts = Text.New(WINDOW)
	texts:Add(VICTIM, 15, P.HIT_NORMAL, POS, 0)
	local shown = texts:Live(0)
	T.eq(#shown, 1, "one number")
	T.eq(shown[1].amount, 15, "its damage")
	T.eq(shown[1].alpha, 1, "opaque at first")
	T.eq(shown[1].rise, 0, "where it was hit")
	local later = texts:Live(Text.LIFETIME / 2)[1]
	T.eq(later.rise > 0, true, "risen")
	T.eq(later.alpha < 1 and later.alpha > 0, true, "fading")
	T.eq(#texts:Live(Text.LIFETIME), 0, "gone at the end of its life")
end)

-- hud_combattext_batching: a shotgun's pellets are one number.
T.test("hits on one victim within the batching window add into one number", function()
	local texts = Text.New(WINDOW)
	texts:Add(VICTIM, 9, P.HIT_NORMAL, POS, 0)
	texts:Add(VICTIM, 9, P.HIT_NORMAL, POS, WINDOW / 2)
	texts:Add(OTHER, 4, P.HIT_NORMAL, POS, WINDOW / 2)
	local shown = texts:Live(WINDOW / 2)
	T.eq(#shown, 2, "one per victim")
	T.eq(shown[1].amount, 18, "added")
	T.eq(shown[2].amount, 4, "the other's own")
	texts:Add(VICTIM, 9, P.HIT_NORMAL, POS, WINDOW * 2)
	T.eq(#texts:Live(WINDOW * 2), 3, "a later hit is a new number")
end)

-- hud_combattext_batching 0: every hit its own number.
T.test("without a batching window every hit is its own number", function()
	local texts = Text.New(0)
	texts:Add(VICTIM, 9, P.HIT_NORMAL, POS, 0)
	texts:Add(VICTIM, 9, P.HIT_NORMAL, POS, 0)
	T.eq(#texts:Live(0), 2, "two numbers")
end)

T.test("a batch is the strongest hit in it", function()
	local texts = Text.New(WINDOW)
	texts:Add(VICTIM, 9, P.HIT_NORMAL, POS, 0)
	texts:Add(VICTIM, 27, P.HIT_CRIT, POS, 0)
	texts:Add(VICTIM, 9, P.HIT_MINICRIT, POS, 0)
	T.eq(texts:Live(0)[1].kind, P.HIT_CRIT, "a crit")
end)

T.test("damage shows whole", function()
	local texts = Text.New(WINDOW)
	texts:Add(VICTIM, 12.6, P.HIT_NORMAL, POS, 0)
	T.eq(texts:Live(0)[1].text, "-13", "rounded, TF2's minus")
end)

T.finish()
