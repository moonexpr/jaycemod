-- player_expressive_base: the expressive player Sandcastle's classes stand on.
local T = dofile ("tests/harness.lua")

local FILE = "addons/sandcastle/gamemodes/sandcastle/gamemode/player_class/player_expressive_base.lua"

-- The globals the file's bytecode reads: a local used above its declaration reads a global.
local function GlobalsRead (path)
	local listing = assert (io.popen ("luajit -bl " .. path))
	local read    = {}
	for line in listing:lines () do
		local name = line:match ("GGET.-; \"([%w_]+)\"")
		if name then read [name] = true end
	end
	listing:close ()

	return read
end

T.test ("the gestures' classes are locals everywhere the class reads them", function ()
	local read = GlobalsRead (FILE)
	for _, name in ipairs ({ "Use", "Carry", "Pain", "Dying" }) do
		T.eq (read [name], nil, name .. " read as a global")
	end
end)

-- The class as the gamemode registers it, in neither realm: its rules.
local ACTIVITIES = { "ACT_MP_SWIM", "ACT_MP_SWIM_IDLE", "ACT_HL2MP_SWIM_IDLE" }
for index, name in ipairs (ACTIVITIES) do _G [name] = 9200 + index end
local registered
local chunk = assert (loadfile (FILE))
local env   =
{
	AddCSLuaFile     = function () end,
	DEFINE_BASECLASS = function () end,
	TauntCamera      = function () return {} end,
	baseclass        = { Get = function () return {} end },
	player_manager   = { RegisterClass = function (name, class) registered = class end }
}
setfenv (chunk, setmetatable (env, { __index = _G }))
chunk ()
local PLAYER = registered

T.test ("a flyer swims while it moves or its lean has not settled, and floats still once it has", function ()
	T.defined (PLAYER.NOCLIP_STILL,   "NOCLIP_STILL")
	T.defined (PLAYER.NOCLIP_LEANING, "NOCLIP_LEANING")
	local settled, leaning = { x = 0, y = 0 }, { x = 0.5, y = 0 }
	T.eq (PLAYER.NoclipActivity (PLAYER.NOCLIP_STILL * 4, settled), ACT_MP_SWIM,      "moving")
	T.eq (PLAYER.NoclipActivity (0, leaning),                       ACT_MP_SWIM,      "stopped, still leaning")
	T.eq (PLAYER.NoclipActivity (0, settled),                       ACT_MP_SWIM_IDLE, "settled")
	T.eq (PLAYER.NoclipActivity (0, nil),                           ACT_MP_SWIM_IDLE, "just started flying")
end)

T.test ("a flyer's lean eases toward its motion, never past it, and starts where the motion is", function ()
	T.defined (PLAYER.NOCLIP_GLIDE, "NOCLIP_GLIDE")
	local first = PLAYER.Glide (nil, 0.4, -0.2, 10)
	T.eq (first.x == 0.4 and first.y == -0.2 and first.at == 10, true, "starts at the motion")
	local eased = PLAYER.Glide ({ x = 0, y = 0, at = 10 }, 1, -1, 10.1)
	T.eq (eased.x > 0 and eased.x < 1,  true, "part of the way, forward")
	T.eq (eased.y < 0 and eased.y > -1, true, "part of the way, sideways")
	T.eq (eased.at,                     10.1, "stamped")
	local later = PLAYER.Glide ({ x = 0, y = 0, at = 10 }, 1, 0, 11)
	T.eq (later.x > eased.x and later.x < 1, true, "further with time, and never past")
end)

T.finish ()
