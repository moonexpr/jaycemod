-- A map's hostage settings, from its cs_logic_hostage's keyvalues (lower
-- case keys): bodyclass, the class of entity each hostage_entity spawns as
-- the hostage it observes (BODY_CLASS when left out or empty: any class
-- will do, a prop_physics as well); bodymodel, the model it is given before
-- it spawns (a prop needs one; left out, the body keeps its own); pistol, 1
-- for one hostage a round armed (features.hostage.pistol), 0 for none. A map
-- without cs_logic_hostage takes the defaults. A value that is not one is
-- refused, naming its key.
local error, tostring = error, tostring
module(...)

BODY_CLASS = "npc_civilian"

local function Refuse(key, value, wanted)
	error("cs_logic_hostage: " .. key .. " " .. tostring(value) .. " is not " .. wanted, 3)
end

-- keyvalues: key -> text. Returns { bodyClass, bodyModel (or nil), pistol }.
function Parse(keyvalues)
	local bodyClass = keyvalues.bodyclass
	if bodyClass == nil or bodyClass == "" then
		bodyClass = BODY_CLASS
	elseif not bodyClass:match("^[%w_]+$") then
		Refuse("bodyclass", bodyClass, "an entity class")
	end
	local bodyModel = keyvalues.bodymodel
	if bodyModel == "" then
		bodyModel = nil
	elseif bodyModel ~= nil and not bodyModel:match("^[%w_/%.%-]+%.mdl$") then
		Refuse("bodymodel", bodyModel, "a model (.mdl)")
	end
	local pistol = keyvalues.pistol
	if pistol == nil or pistol == "" then
		pistol = true
	elseif pistol == "0" or pistol == "1" then
		pistol = pistol == "1"
	else
		Refuse("pistol", pistol, "0 or 1")
	end
	return { bodyClass = bodyClass, bodyModel = bodyModel, pistol = pistol }
end
