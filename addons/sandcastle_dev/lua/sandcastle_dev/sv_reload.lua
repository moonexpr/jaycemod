-- Hot reload that keeps the game where it is: dev.reload() captures the
-- state, loads the gamemode's changed Lua again, and restores the state.
-- Changed files are found by their times since the last reload (or since
-- the workbench loaded); opts.files names them instead, as repo paths
-- (addons/sandcastle/gamemodes/...) or LUA paths, which skips the scan.
--   foundation and games modules, and a feature's own modules
--   (features/<f>/model.lua):
--     run again in place; module(...) keeps the table, so every holder sees
--     the new functions, and each class the module keeps in an upvalue
--     (Round, Timer, PointSet...) gets the new methods copied onto the old
--     class table, so live instances run the new code too
--   a feature's server files (features/<f>/sv.lua, sv_*.lua): the root runs
--     again for real, adopting the live controller (its `local Controller =
--     {` is the live table, keeping its state): its parts redefine their
--     methods on it, and its hooks, timers, commands and listeners register
--     again under their ids, now closing over the live state
--   an entity file: registered again (scripted_ents.Register; live
--     entities get the new class, ENT:OnReloaded runs, Initialize does not)
-- Refused, with the reason: ws/ and the gamemode's root files (GMod's own
-- refresh runs the whole gamemode again), cl_ and sh_ files (clients keep
-- what they were sent: changelevel), files of features or modules this map
-- has not loaded (nothing to reload; they load fresh when needed).
-- opts.cleanup = true also cleans the map up (every map entity made again,
-- Initialize run) before the state is restored, a tick later; the result is
-- then dev.last_reload. Every step is timed.
dev.reload_live = dev.reload_live or { stamps = nil }
local live = dev.reload_live

local function Upvalue(fn, wanted)
	for i = 1, math.huge do
		local name, value = debug.getupvalue(fn, i)
		if name == nil then return nil end
		if name == wanted then return value end
	end
end

-- The gamemode's paths, from WS.require, once the gamemode is up (the
-- workbench loads before it).
local ROOT, CHUNK_ENV, ENTITIES

local function Paths()
	if ROOT then return end
	ROOT = Upvalue(WS.require, "GAMEMODE_ROOT") -- "sandcastle/gamemode/"
	CHUNK_ENV = Upvalue(WS.require, "CHUNK_ENV")
	ENTITIES = string.gsub(ROOT, "gamemode/$", "entities/entities/")
end

local SOURCE_PREFIX = "gamemodes/" -- how CompileFile names a gamemode file
local REPO_GAMEMODES = "addons/sandcastle/gamemodes/" -- a repo path's prefix before the LUA path
local ADOPT_FROM = "\nlocal Controller = {"
local ADOPT_TO = "\nlocal Controller = __dev_adopt {"
local CLEANUP_SETTLE = 0.1 -- s: the map's entities made again before the state goes back

-- Every Lua file under dir (a LUA path ending in /), recursively.
local function Files(dir, out)
	out = out or {}
	local files, dirs = file.Find(dir .. "*", "LUA")
	for _, name in ipairs(files) do
		if string.EndsWith(name, ".lua") then out[#out + 1] = dir .. name end
	end
	for _, sub in ipairs(dirs) do Files(dir .. sub .. "/", out) end
	return out
end

local function Stamps()
	Paths()
	local stamps = {}
	for _, path in ipairs(Files(ROOT)) do stamps[path] = file.Time(path, "LUA") end
	for _, path in ipairs(Files(ENTITIES)) do stamps[path] = file.Time(path, "LUA") end
	return stamps
end

local function Changed()
	local now, list = Stamps(), {}
	for path, time in pairs(now) do
		if live.stamps[path] == nil or live.stamps[path] < time then list[#list + 1] = path end
	end
	table.sort(list)
	return list, now
end

-- What a changed file is, and what reloading it means.
local function Classify(path)
	if string.StartWith(path, ENTITIES) then
		return { kind = "entity", class = string.match(path, "([^/]+)%.lua$") }
	end
	local rel = string.sub(path, #ROOT + 1)
	local feature, fileName = string.match(rel, "^features/([^/]+)/([^/]+)%.lua$")
	if feature then
		if string.match(fileName, "^sv_") or fileName == "sv" then return { kind = "feature", feature = feature } end
		if fileName == "sh" or fileName == "cl" or string.match(fileName, "^[sc][hl]_") then
			return { kind = "refused", why = "a client or shared file: clients keep what they were sent; changelevel" }
		end
		return { kind = "module", name = "features." .. feature .. "." .. fileName }
	end
	if string.match(rel, "_index%.lua$") or string.match(rel, "_init%.lua$") then
		return { kind = "refused", why = "a namespace's index runs with the loader; changelevel" }
	end
	if string.StartWith(rel, "foundation/") or string.StartWith(rel, "games/") then
		return { kind = "module", name = string.gsub(string.gsub(rel, "%.lua$", ""), "/", ".") }
	end
	return { kind = "refused", why = "the gamemode's own files (ws/, init.lua) run again only with the whole gamemode; changelevel" }
end

-- Class tables a module keeps in upvalues, by upvalue name: every table
-- whose __index is itself, reached from the module's functions and from
-- those classes' own methods.
local function Classes(functions)
	local classes, seen, queue = {}, {}, {}
	for _, fn in pairs(functions) do queue[#queue + 1] = fn end
	while #queue > 0 do
		local fn = table.remove(queue)
		if not seen[fn] and debug.getinfo(fn, "S").what ~= "C" then
			seen[fn] = true
			for i = 1, math.huge do
				local name, value = debug.getupvalue(fn, i)
				if name == nil then break end
				if type(value) == "table" and rawget(value, "__index") == value and not classes[name] then
					classes[name] = value
					for _, method in pairs(value) do
						if type(method) == "function" then queue[#queue + 1] = method end
					end
				elseif type(value) == "function" then
					queue[#queue + 1] = value
				end
			end
		end
	end
	return classes
end

local function FunctionsOf(module)
	local list = {}
	for key, value in pairs(module) do
		if type(value) == "function" then list[key] = value end
	end
	return list
end

local function ReloadModule(name)
	local module = package.loaded[name]
	if module == nil then return { skipped = name .. " is not loaded on this map" } end
	local old = Classes(FunctionsOf(module))
	local chunk = CompileFile(ROOT .. string.gsub(name, "%.", "/") .. ".lua")
	if not isfunction(chunk) then dev.Fail(name .. " did not compile; see the console") end
	setfenv(chunk, CHUNK_ENV)(name)
	local patched = {}
	for className, fresh in pairs(Classes(FunctionsOf(package.loaded[name]))) do
		local stale = old[className]
		if stale and stale ~= fresh then
			for key, value in pairs(fresh) do
				if type(value) == "function" then stale[key] = value end
			end
			patched[#patched + 1] = className
		end
	end
	table.sort(patched)
	return { module = name, classes = patched }
end

local function ReloadFeature(feature)
	if not WS.FeatureLoaded(feature) then return { skipped = "the " .. feature .. " feature is not loaded on this map" } end
	local controller = WS.Feature(feature)
	local path = ROOT .. "features/" .. feature .. "/sv.lua"
	local source, count = string.gsub(file.Read(path, "LUA"), ADOPT_FROM, ADOPT_TO, 1)
	if count ~= 1 then dev.Fail(path .. " has no `local Controller = {` for the reload to adopt") end
	local env = setmetatable({
		__dev_adopt = function(fresh)
			for key, value in pairs(fresh) do
				if controller[key] == nil then controller[key] = value end
			end
			return controller
		end,
	}, {
		__index = _G,
		__newindex = _G,
	})
	local chunk = CompileString(source, SOURCE_PREFIX .. path, false)
	if not isfunction(chunk) then dev.Fail(path .. " did not compile: " .. tostring(chunk)) end
	local returned = setfenv(chunk, env)()
	if returned ~= controller then dev.Fail(path .. " returned a controller other than the live one") end
	return { feature = feature }
end

local function ReloadEntity(class)
	local path = ENTITIES .. class .. ".lua"
	if not scripted_ents.GetStored(class) then return { skipped = class .. " is not registered" } end
	local previous = ENT
	ENT = { Folder = "entities/" .. class }
	local chunk = CompileFile(path)
	if not isfunction(chunk) then
		ENT = previous
		dev.Fail(path .. " did not compile; see the console")
	end
	chunk()
	scripted_ents.Register(ENT, class)
	ENT = previous
	return { entity = class }
end

local RELOAD = {
	module = function(c) return ReloadModule(c.name) end,
	feature = function(c) return ReloadFeature(c.feature) end,
	entity = function(c) return ReloadEntity(c.class) end,
}
-- modules first, so a feature run again builds on the new models
local ORDER = {
	module = 1,
	entity = 2,
	feature = 3,
}

local function Ms(since) return math.Round((SysTime() - since) * 1000, 1) end

function dev.reload(opts)
	Paths()
	opts = opts or {}
	local started = SysTime()
	local result = {
		reloaded = {},
		skipped = {},
		refused = {},
		timings = {},
	}
	local step = SysTime()
	local state = dev.capture()
	result.timings.capture_ms = Ms(step)

	step = SysTime()
	local changed, stamps
	if opts.files then
		-- named: no scan (reading every file's time costs ~0.5 ms a file under CrossOver)
		changed, stamps = {}, live.stamps
		for i, path in ipairs(opts.files) do
			changed[i] = string.gsub(path, "^" .. string.PatternSafe(REPO_GAMEMODES), "")
			stamps[changed[i]] = file.Time(changed[i], "LUA")
		end
	else
		changed, stamps = Changed()
	end
	result.timings.scan_ms = Ms(step)

	step = SysTime()
	local work, features = {}, {}
	for _, path in ipairs(changed) do
		local c = Classify(path)
		c.path = path
		if c.kind == "refused" then
			result.refused[#result.refused + 1] = path .. ": " .. c.why
		elseif c.kind == "feature" then
			if not features[c.feature] then
				features[c.feature] = true
				work[#work + 1] = c
			end
		else
			work[#work + 1] = c
		end
	end
	table.sort(work, function(a, b)
		if ORDER[a.kind] ~= ORDER[b.kind] then return ORDER[a.kind] < ORDER[b.kind] end
		return a.path < b.path
	end)
	for _, c in ipairs(work) do
		local done = RELOAD[c.kind](c)
		if done.skipped then result.skipped[#result.skipped + 1] = done.skipped else result.reloaded[#result.reloaded + 1] = done end
	end
	live.stamps = stamps
	result.timings.reload_ms = Ms(step)

	local function Restore()
		local applyStep = SysTime()
		result.apply = dev.apply(state)
		result.timings.apply_ms = Ms(applyStep)
		result.timings.total_ms = Ms(started)
		result.ok = #result.refused == 0 and result.apply.ok
		dev.last_reload = result
		print(string.format("dev_reload: %d reloaded, %d refused, restored in %s ms", #result.reloaded, #result.refused, result.timings.total_ms))
		return result
	end

	if opts.cleanup then
		step = SysTime()
		dev.Rounds():CleanUpMap()
		result.timings.cleanup_ms = Ms(step)
		result.pending = true
		dev.last_reload = result
		timer.Simple(CLEANUP_SETTLE, function()
			result.pending = nil
			Restore()
		end)
		return result
	end
	return Restore()
end

-- The files a reload would take now, and what it would do with each.
function dev.reload_plan()
	Paths()
	local changed = Changed()
	local plan = {}
	for _, path in ipairs(changed) do
		local c = Classify(path)
		plan[#plan + 1] = path .. ": " .. c.kind .. (c.why and (" (" .. c.why .. ")") or "")
	end
	return plan
end

-- Changes count from the map's load: the gamemode ran the files as they were then.
dev.WhenReady("reload", function()
	if not live.stamps then live.stamps = Stamps() end
end)

dev.Command("dev_reload", function(args)
	local opts = { cleanup = args[1] == "cleanup" }
	local first = opts.cleanup and 2 or 1
	if args[first] then opts.files = { unpack(args, first) } end
	return dev.reload(opts)
end, "dev_reload [cleanup] [files...]: capture, load the changed Lua again, restore")
dev.Command("dev_reload_plan", function() return dev.reload_plan() end, "the changed files a dev_reload would take")
