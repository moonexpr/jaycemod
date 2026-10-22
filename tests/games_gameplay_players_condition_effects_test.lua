local T = dofile("tests/harness.lua")
local P = T.require("games.gameplay.players")
local Teams = T.require("games.gameplay.teams")
local Effects = T.require("games.gameplay.players.condition_effects")

local C = P.COND

-- A holder's conditions as the client sees them: the time each ends.
local function Ends(map) return function(cond) return map[cond] or 0 end end

local function Names(shown)
	local names = {}
	for _, effect in ipairs(shown) do names[#names + 1] = effect.name end
	table.sort(names)
	return table.concat(names, ",")
end

T.test("nothing shows without a condition, nor once it ends", function()
	T.eq(Names(Effects.Shown(Ends({}), 5)), "", "none")
	T.eq(Names(Effects.Shown(Ends({ [C.URINE] = 5 }), 5)), "", "ended")
	T.eq(Names(Effects.Shown(Ends({ [C.URINE] = 6 }), 5)), "urine", "still wet")
end)

-- CTFPlayerShared::UpdateCritBoostEffect: every crit boost is one effect.
T.test("every crit boost shows the one crit effect", function()
	for _, cond in ipairs(P.CRIT_BOOSTS) do
		T.eq(Names(Effects.Shown(Ends({ [cond] = 10 }), 0)), "crit", "crit boost " .. cond)
	end
	T.eq(Names(Effects.Shown(Ends({ [C.CRITBOOSTED] = 10, [C.CRITBOOSTED_BONUS_TIME] = 10 }), 0)), "crit", "shown once")
end)

T.test("conditions held together each show", function()
	local shown = Effects.Shown(Ends({ [C.BURNING] = 10, [C.SPEED_BOOST] = 10, [C.INVULNERABLE] = 10 }), 0)
	T.eq(Names(shown), "burning,invulnerable,speed", "all three")
end)

-- TF2 picks a team's effect by GetTeamNumber: BLU's, else RED's.
T.test("a team effect is its team's colour, RED's for anyone else", function()
	local crit = Effects.Shown(Ends({ [C.CRITBOOSTED] = 10 }), 0)[1]
	T.eq(Effects.Particle(crit, Teams.RED), "critgun_weaponmodel_red", "RED")
	T.eq(Effects.Particle(crit, Teams.BLUE), "critgun_weaponmodel_blu", "BLU")
	T.eq(Effects.Particle(crit, Teams.UNASSIGNED), "critgun_weaponmodel_red", "no team")
	local wet = Effects.Shown(Ends({ [C.URINE] = 10 }), 0)[1]
	T.eq(Effects.Particle(wet, Teams.BLUE), "peejar_drips", "one for all")
	local uber = Effects.Shown(Ends({ [C.INVULNERABLE] = 10 }), 0)[1]
	T.eq(Effects.Particle(uber, Teams.RED), nil, "a material, no particle")
	T.eq(Effects.Material(uber, Teams.BLUE), "models/effects/invulnfx_blue", "BLU's uber")
end)

-- The server networks each shown condition's end; the client asks for no other.
T.test("every condition an effect shows is networked, each once", function()
	local seen = {}
	for _, cond in ipairs(Effects.NETWORKED) do
		T.eq(seen[cond], nil, "once: " .. cond)
		seen[cond] = true
	end
	for _, effect in ipairs(Effects.Shown(Ends({ [C.CRITBOOSTED_PUMPKIN] = 1, [C.MAD_MILK] = 1 }), 0)) do
		for _, cond in ipairs(effect.conds) do T.eq(seen[cond], true, effect.name .. " networks " .. cond) end
	end
end)

T.test("every particle an effect plays is in a particle file it loads", function()
	local files = {}
	for _, path in ipairs(Effects.FILES) do files[path] = true end
	for _, effect in ipairs(Effects.EFFECTS) do
		if effect.particle then T.eq(files[effect.file], true, effect.name .. "'s file " .. tostring(effect.file)) end
	end
end)

-- OnAddBurning: the burning player's own screen cooks (effects/imcookin),
-- their flames show to others only (not over their own first-person
-- view), and one who dies burning burns on as a corpse.
T.test("burning is TF2's: the holder's overlay, flames for others, a burning corpse", function()
	local burning = Effects.Shown(Ends({ [C.BURNING] = 10 }), 0)[1]
	T.eq(burning.overlay, "effects/imcookin", "the holder's screen")
	T.eq(burning.thirdPersonOnly, true, "not over their own view")
	T.eq(burning.corpse, "burningplayer_corpse", "the corpse burns")
	T.eq(burning.ignite, "Fire.Engulf", "the sound of catching fire")
	local crit = Effects.Shown(Ends({ [C.CRITBOOSTED] = 10 }), 0)[1]
	T.eq(crit.thirdPersonOnly, nil, "a crit glows in first person too (the view model)")
end)

T.test("catching a condition plays its effect's ignite sound, if it has one", function()
	T.eq(Effects.IgniteSound(C.BURNING), "Fire.Engulf", "catching fire")
	T.eq(Effects.IgniteSound(C.URINE), nil, "Jarate has none")
end)

-- The C menu's Conditions: each toggles one, and the client must see which
-- are held, so each is networked.
T.test("each condition the menu toggles is networked and found by its number", function()
	local networked = {}
	for _, cond in ipairs(Effects.NETWORKED) do networked[cond] = true end
	T.eq(#Effects.TOGGLES > 0, true, "some")
	for _, toggle in ipairs(Effects.TOGGLES) do
		T.eq(networked[toggle.cond], true, toggle.label .. " networked")
		T.eq(Effects.Toggle(toggle.cond), toggle, toggle.label .. " found")
	end
	T.eq(Effects.Toggle(C.HALLOWEEN_THRILLER), nil, "the dance is no toggle")
end)

T.finish()
