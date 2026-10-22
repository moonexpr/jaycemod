-- The zapper (halloween_zapper, CTFHellZap in tf_weapon_spellbook.cpp): a
-- beam from the zapper to everyone inside its touch_trigger. The beam is
-- only a particle; it deals no damage. An ON_TOUCH zapper zaps whoever is
-- inside every 0.25 s from the moment someone walks in; an ON_TEST zapper
-- zaps only on ZapTouching, which works in either mode.
--
-- Config, from its keyvalues: { type (ZapperType), particle
-- (ParticleEffect) }. Touches come from its dispenser_touch_trigger.
local require = require
local Hazards = require("foundation.hazards")
local Teams = require("games.gameplay.teams")
local ipairs, huge, remove = ipairs, math.huge, table.remove
module(...)

-- EZapperType
ZAP_ON_TOUCH, ZAP_ON_TEST = 0, 1

ZAP_INTERVAL = 0.25 -- ZapThink

INPUT_ENABLE, INPUT_DISABLE, INPUT_ZAP_TOUCHING = "enable", "disable", "zaptouching"

-- SetContextThink(ZapThink, gpGlobals->curtime): due at the next tick.
local ZAP_NOW = -huge

function NewState(config, now)
	return {
		type = config.type,
		particle = config.particle,
		targets = {},
		zapAt = nil,
	}
end

function Team(state) return Teams.UNASSIGNED end

local function Remove(list, value)
	for i, v in ipairs(list) do
		if v == value then
			remove(list, i)
			return
		end
	end
end

-- ZapAllTouching
local function ZapAll(state)
	if #state.targets == 0 then return Hazards.Nothing end
	local targets = {}
	for i, t in ipairs(state.targets) do targets[i] = t end
	return Hazards.Zap(targets, state.particle)
end

-- StartTouch and EndTouch. StartTouch starts an ON_TOUCH zapper even while
-- it is disabled, as CTFHellZap does.
function OnTouch(state, toucher)
	if toucher.leaving then
		Remove(state.targets, toucher.target)
		if #state.targets == 0 and state.type == ZAP_ON_TOUCH then state.zapAt = nil end
	else
		state.targets[#state.targets + 1] = toucher.target
		if state.type == ZAP_ON_TOUCH then state.zapAt = ZAP_NOW end
	end
	return Hazards.Nothing
end

-- The inputs, by name. Enable and Disable only start and stop the
-- ZapThink; CTFHellZap's m_bEnabled is never read.
INPUTS = {
	[INPUT_ENABLE] = function(state)
		if #state.targets > 0 and state.type == ZAP_ON_TOUCH then state.zapAt = ZAP_NOW end
		return Hazards.Nothing
	end,
	[INPUT_DISABLE] = function(state)
		state.zapAt = nil
		return Hazards.Nothing
	end,
	[INPUT_ZAP_TOUCHING] = ZapAll,
}

function OnInput(state, name, value)
	return INPUTS[name](state)
end

-- ZapThink: zap, then again in 0.25 s while anyone is inside.
function Tick(state, now)
	if state.zapAt == nil or now < state.zapAt then return Hazards.Nothing end
	local outcome = ZapAll(state)
	if #state.targets > 0 then
		state.zapAt = now + ZAP_INTERVAL
	else
		state.zapAt = nil
	end
	return outcome
end
