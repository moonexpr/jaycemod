-- Scenarios: captured states saved as JSON under data/sandcastle_dev/
-- scenarios/<map>/<name>.json (linked to the repo's .devtools/scenarios by
-- server_root.py), loaded back in place. A scenario of another map, or of a
-- schema this workbench cannot migrate, is refused with what to do
-- (sandcastle_dev_scenario).
--   dev.scenario.save(name[, description]), load(name), list([{ all = true }]),
--   diff(a, b) (a name, or "current" for the live state),
--   quicksave([slot]), quickload([slot])
local Scenario = dev.require("sandcastle_dev_scenario")
local Diff = dev.require("sandcastle_dev_diff")

local BASE = "sandcastle_dev/scenarios/"
local CURRENT = "current"
local QUICK_PREFIX = "quick_"
local DEFAULT_SLOT = 1
-- schema n -> its state migrated to n + 1 (none yet: schema 1 is the first)
local MIGRATIONS = {}

dev.scenario = dev.scenario or {}
local S = dev.scenario

local function ReadAt(path)
	return Scenario.Parse(util.JSONToTable(file.Read(path, "DATA") or ""), path)
end

-- The scenario of that name for the map; one of that name saved on another
-- map is read too, so loading it refuses with where it belongs.
local function Read(map, name)
	local path = Scenario.Path(BASE, map, Scenario.CheckName(name))
	if file.Exists(path, "DATA") then return ReadAt(path) end
	local _, maps = file.Find(BASE .. "*", "DATA")
	for _, other in ipairs(maps) do
		local elsewhere = Scenario.Path(BASE, other, name)
		if file.Exists(elsewhere, "DATA") then return ReadAt(elsewhere) end
	end
	dev.Fail("no scenario " .. name .. " (data/" .. path .. "); scenario_list all shows the saved ones")
end

function S.save(name, description)
	local state = dev.capture()
	local scenario = Scenario.New(name, description, state, os.date("%Y-%m-%d %H:%M:%S"))
	local path = Scenario.Path(BASE, state.map, scenario.name)
	file.CreateDir(BASE .. state.map)
	file.Write(path, util.TableToJSON(scenario, true))
	if not file.Exists(path, "DATA") then dev.Fail("could not write data/" .. path) end
	return {
		saved = scenario.name,
		path = "data/" .. path,
		map = scenario.map,
		schema = scenario.schema,
		summary = dev.state(),
	}
end

function S.load(name)
	local scenario = Read(game.GetMap(), name)
	local state, notes = Scenario.Load(scenario, game.GetMap(), dev.SCHEMA, MIGRATIONS)
	local report = dev.apply(state)
	for _, note in ipairs(notes) do table.insert(report.notes, 1, note) end
	report.loaded = scenario.name
	report.description = scenario.description
	report.summary = dev.state()
	return report
end

-- The scenarios of this map (all = true: of every map), newest first.
function S.list(opts)
	local maps = { game.GetMap() }
	if opts and opts.all then
		local _, dirs = file.Find(BASE .. "*", "DATA")
		maps = dirs
	end
	local list = {}
	for _, map in ipairs(maps) do
		for _, fileName in ipairs((file.Find(BASE .. map .. "/*.json", "DATA"))) do
			local path = BASE .. map .. "/" .. fileName
			local ok, scenario = pcall(Scenario.Parse, util.JSONToTable(file.Read(path, "DATA") or ""), path)
			list[#list + 1] = ok and {
				name = scenario.name,
				map = scenario.map,
				description = scenario.description,
				saved_at = scenario.saved_at,
				schema = scenario.schema,
			} or {
				name = fileName,
				map = map,
				error = tostring(scenario),
			}
		end
	end
	table.sort(list, function(a, b) return (a.saved_at or "") > (b.saved_at or "") end)
	return list
end

local function StateOf(name)
	if name == CURRENT then return dev.capture() end
	local scenario = Read(game.GetMap(), name)
	return (Scenario.Load(scenario, game.GetMap(), dev.SCHEMA, MIGRATIONS))
end

-- The differences from a to b; either may be "current".
function S.diff(a, b)
	local differences = dev.diff(StateOf(a), StateOf(b))
	return {
		a = a,
		b = b,
		count = #differences,
		differences = Diff.Text(differences),
	}
end

local function Slot(slot)
	slot = tonumber(slot) or DEFAULT_SLOT
	if slot < 1 or slot ~= math.floor(slot) then dev.Fail("a quick slot is a whole number from 1") end
	return QUICK_PREFIX .. slot
end

function S.quicksave(slot) return S.save(Slot(slot), "quicksave") end
function S.quickload(slot) return S.load(Slot(slot)) end

dev.Command("scenario_save", function(args) return S.save(args[1], table.concat(args, " ", 2)) end,
	"scenario_save <name> [description]: the gameplay state, saved under this map")
dev.Command("scenario_load", function(args) return S.load(args[1]) end, "scenario_load <name>: restore a saved state in place")
dev.Command("scenario_list", function(args) return S.list({ all = args[1] == "all" }) end, "scenario_list [all]")
dev.Command("scenario_diff", function(args) return S.diff(args[1], args[2]) end, "scenario_diff <a> <b>: names, or current")
dev.Command("dev_quicksave", function(args) return S.quicksave(args[1]) end, "dev_quicksave [slot]")
dev.Command("dev_quickload", function(args) return S.quickload(args[1]) end, "dev_quickload [slot]")
