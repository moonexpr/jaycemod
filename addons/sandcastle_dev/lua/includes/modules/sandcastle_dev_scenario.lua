-- The dev workbench's scenario: a captured state (dev.capture) with a name
-- and a description, saved as JSON under its map. Loading one checks it
-- against the map the server is on and the workbench's schema: another
-- map's is refused, an older schema's migrates step by step (and says so),
-- a newer one's is refused. Never applied silently.
--   New(name, description, state, savedAt) -> a scenario
--   Path(base, map, name) -> where its file goes
--   Parse(decoded, file) -> a scenario, or an error naming the file
--   Load(scenario, map, schema, migrations) -> the state to apply, notes;
--     migrations[n](state) -> the state at schema n + 1
local error, pairs, tostring, type = error, pairs, tostring, type
local format = string.format
module(...)

FORMAT = 1 -- the file's own layout, apart from the state's schema
MAX_NAME = 64

local NAME_PATTERN = "^[a-z0-9_%-]+$"

local function Copy(value)
	if type(value) ~= "table" then return value end
	local copy = {}
	for k, v in pairs(value) do copy[k] = Copy(v) end
	return copy
end

function CheckName(name)
	if type(name) ~= "string" or #name == 0 or #name > MAX_NAME or not name:find(NAME_PATTERN) then
		error(format("a scenario's name is 1 to %d of a-z, 0-9, _ and -, not %q", MAX_NAME, tostring(name)), 3)
	end
	return name
end

function New(name, description, state, savedAt)
	return {
		format = FORMAT,
		name = CheckName(name),
		description = description or "",
		map = state.map,
		schema = state.schema,
		saved_at = savedAt,
		state = state,
	}
end

function Path(base, map, name)
	return base .. map .. "/" .. name .. ".json"
end

function Parse(decoded, file)
	if type(decoded) ~= "table" then error(file .. ": not a scenario (unreadable JSON)", 2) end
	for _, field in pairs({ "name", "map", "schema", "state" }) do
		if decoded[field] == nil then error(file .. ": not a scenario (no " .. field .. ")", 2) end
	end
	if type(decoded.state) ~= "table" or type(decoded.state.sections) ~= "table" then error(file .. ": its state has no sections", 2) end
	return decoded
end

function Load(scenario, map, schema, migrations)
	if scenario.map ~= map then
		error(format("scenario %s was saved on %s, the server is on %s: changelevel %s first", scenario.name, scenario.map, map, scenario.map), 2)
	end
	if scenario.schema > schema then
		error(format("scenario %s is schema %d, newer than this workbench's %d: update the workbench", scenario.name, scenario.schema, schema), 2)
	end
	local state, notes = Copy(scenario.state), {}
	local from = scenario.schema
	while state.schema < schema do
		local step = migrations[state.schema]
		if not step then
			error(format("scenario %s: no migration from schema %d to %d", scenario.name, state.schema, state.schema + 1), 2)
		end
		state = step(state)
		state.schema = state.schema + 1
	end
	if from < schema then notes[#notes + 1] = format("migrated scenario %s from schema %d to %d", scenario.name, from, schema) end
	return state, notes
end
