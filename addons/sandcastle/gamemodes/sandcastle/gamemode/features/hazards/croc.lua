-- The croc (func_croc, CFuncCroc and CEntityCroc in func_croc.cpp): a
-- trigger where a crocodile surfaces under each player who walks in and
-- plays its attack. 0.1 s later (CrocAttack) whoever it came for, if still
-- touching the trigger, takes 1000 crushing damage from the croc, which
-- fires OnEat, then OnEatRed or OnEatBlue by the victim's team. The croc is
-- never spent.
--
-- Config, from its keyvalues: { team (TeamNum), model (croc_model when the
-- file exists) }. The binding forwards only touches that pass the trigger's
-- filters (living players, filtername) while it is enabled; Enable, Disable
-- and Toggle are the trigger's.
local require = require
local Hazards = require("features.hazards.model")
local Teams = gameplay.teams
local Actor = npc.actor
local ipairs = ipairs
module(...)

MODEL = "models/props_island/crocodile/crocodile.mdl" -- CROC_MODEL
ATTACK_SEQUENCE = "attack"
ATTACK_DELAY = 0.1
DAMAGE = 1000
DAMAGE_TYPE = Actor.DMG_CRUSH

OUTPUT_EAT = "OnEat"
local TEAM_OUTPUTS = {
	[Teams.RED] = "OnEatRed",
	[Teams.BLUE] = "OnEatBlue",
}

function NewState(config, now)
	return {
		team = config.team,
		model = config.model or MODEL,
		touching = {},
		attacks = {},
	}
end

function Team(state) return state.team end

-- StartTouch raises a croc aimed at the toucher; EndTouch only ends the
-- touch, so a croc already up may still find them back inside.
function OnTouch(state, toucher)
	if toucher.leaving then
		state.touching[toucher.target] = nil
		return Hazards.Nothing
	end
	state.touching[toucher.target] = true
	state.attacks[#state.attacks + 1] = {
		target = toucher.target,
		team = toucher.team,
		at = toucher.now + ATTACK_DELAY,
	}
	return Hazards.Animate(state.model, ATTACK_SEQUENCE, toucher.target)
end

-- CFuncCroc::FireOutputs
local function Outputs(team)
	local outputs = { OUTPUT_EAT }
	if TEAM_OUTPUTS[team] then outputs[#outputs + 1] = TEAM_OUTPUTS[team] end
	return outputs
end

-- CrocAttack, for every croc whose bite is due.
function Tick(state, now)
	local hits, waiting = {}, {}
	for _, attack in ipairs(state.attacks) do
		if now < attack.at then
			waiting[#waiting + 1] = attack
		elseif state.touching[attack.target] then
			hits[#hits + 1] = {
				target = attack.target,
				outputs = Outputs(attack.team),
			}
		end
	end
	state.attacks = waiting
	if #hits == 0 then return Hazards.Nothing end
	return Hazards.Hurt(hits, DAMAGE, DAMAGE_TYPE)
end
