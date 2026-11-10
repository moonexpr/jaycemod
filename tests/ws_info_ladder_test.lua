local T = dofile("tests/harness.lua")


local function Load(path, entity, globals)
	local env = { ENT = entity }
	for key, value in pairs(globals or {}) do env[key] = value end
	setmetatable(env, { __index = _G })
	setfenv(assert(loadfile(path)), env)()
	return env.ENT
end

local base = Load(T.Entity("ws_inert_point.lua"), {}, { TRANSMIT_NEVER = 7 })
local ladder = setmetatable({}, { __index = base })
Load(T.Entity("info_ladder.lua"), ladder)

T.test("info_ladder inherits the inert point behavior and keeps BSP bounds", function()
	T.eq(ladder.Type, "point", "entity type")
	T.eq(ladder.Base, "ws_inert_point", "entity base")

	local outputs = {}
	local entity = setmetatable({
		StoreOutput = function(_, key, value) outputs[key] = value end,
	}, { __index = ladder })
	for key, value in pairs({
		["mins.x"] = "-16",
		["mins.y"] = "-8",
		["mins.z"] = "0",
		["maxs.x"] = "16",
		["maxs.y"] = "8",
		["maxs.z"] = "128",
		OnUser1 = "target,Open,,0,-1",
	}) do
		entity:KeyValue(key, value)
	end

	T.eq(entity.wsKv["mins.x"], "-16", "lower bound")
	T.eq(entity.wsKv["maxs.z"], "128", "upper bound")
	T.eq(outputs.OnUser1, "target,Open,,0,-1", "map output")
	T.eq(entity:UpdateTransmitState(), 7, "point entity is not transmitted")
end)

T.finish()
