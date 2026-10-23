-- What players see of a player's or soldier's conditions (games.gameplay.players'
-- COND), as TF2's client shows them (CTFPlayerShared::OnConditionAdded and
-- its OnAdd* effects): a particle on the body or the weapon, a looping
-- sound, a screen overlay for the holder, a material over the model. The
-- server networks the end of each condition in NETWORKED (ws/sv_teams_conditions.lua);
-- ws/cl_conditions.lua shows what Shown answers.
--
-- An effect: name; conds, any of which shows it; file, the particle file of
-- its particle; particle, by team (red, blue) or for all (any); on, BODY or
-- WEAPON (the active weapon: the view model for its holder in first person);
-- loop, a game sound played while it shows; overlay, the holder's screen
-- material; material, by team, over the model and its weapon;
-- thirdPersonOnly: its particle not shown to its holder in first person;
-- corpse, the particle one who dies holding it burns on with; ignite, the
-- game sound of catching it (ws/sv_teams_conditions.lua).
local P = gameplay.players
local Teams = gameplay.teams
local ipairs = ipairs
module(...)

local C = P.COND

BODY, WEAPON = "body", "weapon"

EFFECTS = {
	-- UpdateCritBoostEffect
	{
		name = "crit",
		conds = P.CRIT_BOOSTS,
		file = "particles/firstperson_weapon_fx.pcf",
		particle = { red = "critgun_weaponmodel_red", blue = "critgun_weaponmodel_blu" },
		on = WEAPON,
		loop = "Weapon_General.CritPower",
	},
	-- OnAddBurning, and C_TFRagdoll's burning corpse
	{
		name = "burning",
		conds = { C.BURNING },
		file = "particles/burningplayer.pcf",
		particle = { red = "burningplayer_red", blue = "burningplayer_blue" },
		on = BODY,
		thirdPersonOnly = true,
		overlay = "effects/imcookin", -- TF_SCREEN_OVERLAY_MATERIAL_BURNING
		corpse = "burningplayer_corpse",
		ignite = "Fire.Engulf",
	},
	-- OnAddUrine, OnAddMadMilk
	{
		name = "urine",
		conds = { C.URINE },
		file = "particles/item_fx.pcf",
		particle = { any = "peejar_drips" },
		on = BODY,
		overlay = "effects/jarate_overlay", -- TF_SCREEN_OVERLAY_MATERIAL_URINE
	},
	{
		name = "milk",
		conds = { C.MAD_MILK },
		file = "particles/item_fx.pcf",
		particle = { any = "peejar_drips_milk" },
		on = BODY,
		overlay = "effects/milk_screen", -- TF_SCREEN_OVERLAY_MATERIAL_MILK
	},
	-- OnAddSpeedBoost
	{
		name = "speed",
		conds = { C.SPEED_BOOST, C.HALLOWEEN_SPEED_BOOST },
		file = "particles/soldierbuff.pcf",
		particle = { any = "speed_boost_trail" },
		on = BODY,
	},
	-- OnAddInvulnerable: the uber's material (TF_INVULN_MATERIAL_*)
	{
		name = "invulnerable",
		conds = { C.INVULNERABLE, C.INVULNERABLE_USER_BUFF, C.INVULNERABLE_CARD_EFFECT },
		material = { red = "models/effects/invulnfx_red", blue = "models/effects/invulnfx_blue" },
	},
}

-- The conditions the C menu's Conditions toggles on a player or soldier
-- (ws/sh_condition_menu.lua), in its order.
TOGGLES = {
	{ cond = C.CRITBOOSTED, label = "Crit boosted" },
	{ cond = C.INVULNERABLE, label = "Ubercharged" },
	{ cond = C.SPEED_BOOST, label = "Speed boost" },
	{ cond = C.BLAST_IMMUNE, label = "Blast immune" },
	{ cond = C.HALLOWEEN_QUICK_HEAL, label = "Quick heal" },
	{ cond = C.BURNING, label = "Burning" },
	{ cond = C.URINE, label = "Jarate" },
	{ cond = C.MAD_MILK, label = "Mad Milk" },
}

function Toggle(cond)
	for _, toggle in ipairs(TOGGLES) do
		if toggle.cond == cond then return toggle end
	end
	return nil
end

-- The particle files the effects play from, each once.
FILES = {}
-- The conditions whose end the server networks, each once: the effects'
-- and the toggles'.
NETWORKED = {}
do
	local files, conds = {}, {}
	for _, toggle in ipairs(TOGGLES) do
		conds[toggle.cond] = true
		NETWORKED[#NETWORKED + 1] = toggle.cond
	end
	for _, effect in ipairs(EFFECTS) do
		if effect.file and not files[effect.file] then
			files[effect.file] = true
			FILES[#FILES + 1] = effect.file
		end
		for _, cond in ipairs(effect.conds) do
			if not conds[cond] then
				conds[cond] = true
				NETWORKED[#NETWORKED + 1] = cond
			end
		end
	end
end

-- The effects showing now; endsOf(cond) is the time cond ends, 0 for one
-- not held.
function Shown(endsOf, now)
	local shown = {}
	for _, effect in ipairs(EFFECTS) do
		for _, cond in ipairs(effect.conds) do
			if now < endsOf(cond) then
				shown[#shown + 1] = effect
				break
			end
		end
	end
	return shown
end

-- The sound of catching cond, or nil.
function IgniteSound(cond)
	for _, effect in ipairs(EFFECTS) do
		for _, held in ipairs(effect.conds) do
			if held == cond and effect.ignite then return effect.ignite end
		end
	end
	return nil
end

local function ByTeam(choices, team)
	if not choices then return nil end
	if choices.any then return choices.any end
	return team == Teams.BLUE and choices.blue or choices.red
end

-- An effect's particle and material for team: BLU's, else RED's.
function Particle(effect, team) return ByTeam(effect.particle, team) end
function Material(effect, team) return ByTeam(effect.material, team) end
