-- The map loaded in Sandcastle, with the features its entities pull in
-- (docs/pass4-koth-cp.md §7.3, docs/pass3-halloween.md "Loading"), its Lua
-- memory, and, on a map with rounds, in Sandbox mode: sv_gameplay_enabled 0,
-- the rounds halted in BETWEEN_RNDS.
-- args: { rounds = bool, has = { feature... }, lacks = { feature... },
--         lacks_modules = { module... } }
local SETTLE_TIMEOUT = 5 -- seconds for the rounds controller's SetUpMap (timer.Simple(0))

return function(t)
	local args = t.args
	t:Check("gamemode is sandcastle", engine.ActiveGamemode() == "sandcastle", engine.ActiveGamemode())

	if args.rounds then
		local halted = t:WaitFor(SETTLE_TIMEOUT, function()
			return WS.Active() and WS.State() == WS.STATE.BETWEEN_RNDS
		end)
		t:Check("rounds active (a tf_gamerules bound)", WS.Active(), tostring(WS.Active()))
		t:Check("starts in Sandbox mode: sv_gameplay_enabled 0", GetConVar("sv_gameplay_enabled"):GetInt() == 0,
			GetConVar("sv_gameplay_enabled"):GetString())
		t:Check("Sandbox mode halts the rounds", WS.GameplayStopped(), tostring(WS.GameplayStopped()))
		t:Check("rounds wait in BETWEEN_RNDS", halted ~= nil, WS_TESTS.StateName(WS.State()))
	else
		t:Check("no rounds on this map", not WS.Active(), tostring(WS.Active()))
	end

	local loaded = WS.FeatureLoader:Loaded()
	t:Info("features", loaded)
	for _, name in ipairs(args.has or {}) do
		t:Check("feature " .. name .. " loaded", t:Loaded(name), table.concat(loaded, ", "))
	end
	for _, name in ipairs(args.lacks or {}) do
		t:Check("feature " .. name .. " not loaded", not t:Loaded(name), table.concat(loaded, ", "))
	end
	for _, name in ipairs(args.lacks_modules or {}) do
		t:Check("module " .. name .. " not in package.loaded", package.loaded[name] == nil, "")
	end

	local modules = {}
	for name in pairs(package.loaded) do
		if string.StartWith(name, "foundation") then modules[#modules + 1] = name end
	end
	table.sort(modules)
	t:Info("foundation_modules", modules)

	local count = collectgarbage("count")
	collectgarbage("collect")
	t:Info("lua_memory_kb", math.floor(count))
	t:Info("lua_memory_kb_after_collect", math.floor(collectgarbage("count")))
	t:Info("ws_memory", WS.FeatureLoader:MemoryReport(count, collectgarbage("count")))
	t:Info("navmesh", navmesh.IsLoaded() and navmesh.GetNavAreaCount() or 0)
	t:Info("drgbase", DrGBase ~= nil)
end
