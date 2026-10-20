-- Team Tint's client convars and the tuning they edit. Each knob of
-- teamtint_tuning's SCHEMA is a convar, teamtint_<name>, holding its value
-- for the scope being edited (teamtint_scope: all classes, or one class of
-- teamtint_catalog's); changing scope loads that scope's values into the
-- convars. The tuning is this player's, saved to data/teamtint/tuning.json;
-- the addon's shipped one (data_static/teamtint/tuning.json) is the start.
local Tuning = TeamTint.Tuning

local SAVED = "teamtint/tuning.json"
local SHIPPED = "data_static/teamtint/tuning.json"

TeamTint.CONVAR_PREFIX = "teamtint_"

TeamTint.ENABLED = CreateClientConVar("teamtint_enable", "1", true, false,
	"Team Tint: theme bodies by their team (0 shows every body as made)", 0, 1)
TeamTint.VIEW = CreateClientConVar("teamtint_view", "0", false, false,
	"Team Tint's debug view: 0 normal, 1 albedo, 2 tint off, 3 lighting, 4 spec + rim, 5 value, 6 silhouette",
	0, #Tuning.VIEWS - 1)
TeamTint.OVERLAY = CreateClientConVar("teamtint_overlay", "0", false, false,
	"Team Tint: label each body with its team, where it came from, and how each material is themed", 0, 1)
TeamTint.SCOPE = CreateClientConVar("teamtint_scope", Tuning.ALL, false, false,
	"Team Tint: the class of material the teamtint_* knobs edit (all, or a class: armor, cloth, hide, skin...)")
TeamTint.BENCH = CreateClientConVar("teamtint_bench_softwareskin", "0", false, false,
	"Team Tint: draw themed bodies with $softwareskin 1 (CPU skinning), to measure its cost against GPU skinning", 0, 1)

local function Scope()
	local scope = TeamTint.SCOPE:GetString()
	if scope == Tuning.ALL or TeamTint.Catalog.CLASSES[scope] then return scope end
	return Tuning.ALL
end
TeamTint.Scope = Scope

-- A scope's value of a knob: all's, or the class's own over all's.
local function ScopeValue(scope, name)
	if scope == Tuning.ALL then return TeamTint.tuning.base[name] end
	return Tuning.Get(TeamTint.tuning, scope, name)
end

local function Load()
	local text = file.Read(SAVED, "DATA") or file.Read(SHIPPED, "GAME")
	return Tuning.Decode(text and util.JSONToTable(text) or nil)
end

function TeamTint.Save()
	file.CreateDir("teamtint")
	file.Write(SAVED, util.TableToJSON(Tuning.Encode(TeamTint.tuning), true))
end

TeamTint.tuning = TeamTint.tuning or Load()

local function Same(a, b, name)
	return Tuning.Format(name, a) == Tuning.Format(name, b)
end

TeamTint.knobs = {}
for _, p in ipairs(Tuning.SCHEMA) do
	local name = p.name
	local cvar = CreateClientConVar(TeamTint.CONVAR_PREFIX .. name, Tuning.Format(name, ScopeValue(Scope(), name)), false, false,
		"Team Tint: " .. p.label .. " (for teamtint_scope)")
	TeamTint.knobs[name] = cvar
	cvars.AddChangeCallback(cvar:GetName(), function(_, _, text)
		local value = Tuning.Parse(name, text)
		-- loading a scope writes the values it already holds: nothing to set
		if value == nil or Same(value, ScopeValue(Scope(), name), name) then return end
		Tuning.Set(TeamTint.tuning, Scope(), name, value)
		TeamTint.Changed()
	end, "teamtint")
end

-- The convars show scope's values.
function TeamTint.LoadScope()
	local scope = Scope()
	for name, cvar in pairs(TeamTint.knobs) do cvar:SetString(Tuning.Format(name, ScopeValue(scope, name))) end
end

cvars.AddChangeCallback("teamtint_scope", function() TeamTint.LoadScope() end, "teamtint")

-- The tuning changed: the materials follow at once, the file a moment later.
function TeamTint.Changed()
	if TeamTint.RebuildMaterials then TeamTint.RebuildMaterials() end
	timer.Create("teamtint_save", 1, 1, TeamTint.Save)
end

concommand.Add("teamtint_reset_scope", function()
	Tuning.Clear(TeamTint.tuning, Scope())
	TeamTint.LoadScope()
	TeamTint.Changed()
end, nil, "Team Tint: the scope being edited (teamtint_scope) goes back to all's values, or all to the defaults")

-- Every knob of the scope as console lines, for a cfg or a note.
function TeamTint.ConvarText()
	local lines = { "teamtint_scope " .. Scope() }
	for _, p in ipairs(Tuning.SCHEMA) do
		lines[#lines + 1] = string.format('%s%s "%s"', TeamTint.CONVAR_PREFIX, p.name, TeamTint.knobs[p.name]:GetString())
	end
	return table.concat(lines, "\n")
end
