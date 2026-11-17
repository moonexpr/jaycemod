-- The workbench's dev.WhenReady (addons/sandcastle_dev's sv_util.lua): fn once
-- Sandcastle's gamemode and the map's entities are up. The workbench is mounted
-- on servers running other gamemodes too (Club Random, on the same dev server),
-- where Sandcastle's WS never exists: there fn never runs, so it cannot fail
-- inside InitPostEntity and stop the hooks after it (the other gamemode's).
local T = dofile ("tests/harness.lua")

local SV_UTIL = "addons/sandcastle_dev/lua/sandcastle_dev/sv_util.lua"

-- sv_util.lua loaded against stub hook and ents; the InitPostEntity hooks it adds.
local function Load (entityCount)
	local hooks = {}
	local saved = { dev = dev, hook = hook, ents = ents, WS = WS }
	dev = {}
	hook = { Add = function (event, id, fn) hooks [event .. "/" .. id] = fn end }
	ents = { GetAll = function () local all = {} for i = 1, entityCount do all [i] = i end return all end }
	dofile (SV_UTIL)
	local loaded = dev
	return loaded, hooks, function () dev, hook, ents, WS = saved.dev, saved.hook, saved.ents, saved.WS end
end

T.test ("at map start without Sandcastle's gamemode, a ready callback never runs", function ()
	local d, hooks, restore = Load (1)
	WS = nil
	local ran = false
	d.WhenReady ("probe", function () ran = true end)
	hooks ["InitPostEntity/sandcastle_dev_probe"] ()
	restore ()
	T.eq (ran, false, "not run under another gamemode")
end)

T.test ("at map start under Sandcastle's gamemode, a ready callback runs", function ()
	local d, hooks, restore = Load (1)
	WS = { gamemodeLoaded = true }
	local ran = false
	d.WhenReady ("probe", function () ran = true end)
	hooks ["InitPostEntity/sandcastle_dev_probe"] ()
	restore ()
	T.eq (ran, true, "run at InitPostEntity")
end)

T.test ("with the gamemode and the map's entities already up, it runs at once", function ()
	local d, _, restore = Load (5)
	WS = { gamemodeLoaded = true }
	local ran = false
	d.WhenReady ("probe", function () ran = true end)
	restore ()
	T.eq (ran, true, "run now")
end)

T.finish ()
