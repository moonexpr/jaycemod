-- Team Tint's client runtime (addons/teamtint/lua/teamtint/cl_*.lua)
-- under stubbed GMod globals: the stubs stand in for convars, hooks,
-- materials and entities only as far as the runtime touches them, so this
-- checks its wiring (which copy a body wears, knobs and scopes written
-- live, views, overrides, ragdolls, the bench, export), not how anything
-- draws. Each test goes on from the state the last left.
local T = dofile("tests/harness.lua")
local ROOT = "addons/teamtint/lua/"
package.path = ROOT .. "includes/modules/?.lua;" .. package.path
CLIENT, SERVER = true, false
local log = {}
local function Log(...) log[#log + 1] = table.concat({ ... }, " ") end

-- convars
local convars, callbacks = {}, {}
local ConVar = {}
ConVar.__index = ConVar
function ConVar:GetString() return self.value end
function ConVar:GetInt() return math.floor(tonumber(self.value) or 0) end
function ConVar:GetFloat() return tonumber(self.value) or 0 end
function ConVar:GetBool() return self:GetInt() ~= 0 end
function ConVar:GetName() return self.name end
function ConVar:SetString(v)
	local old = self.value
	self.value = tostring(v)
	for _, fn in pairs(callbacks[self.name] or {}) do fn(self.name, old, self.value) end
end
function CreateClientConVar(name, default)
	convars[name] = convars[name] or setmetatable({ name = name, value = tostring(default) }, ConVar)
	return convars[name]
end
cvars = { AddChangeCallback = function(name, fn, id) callbacks[name] = callbacks[name] or {}; callbacks[name][id or fn] = fn end }
function RunConsoleCommand(name, value) convars[name]:SetString(value) end

local hooks = {}
hook = {
	Add = function(event, id, fn) hooks[event] = hooks[event] or {}; hooks[event][id] = fn end,
	Run = function(event, ...)
		for _, fn in pairs(hooks[event] or {}) do
			local a = fn(...)
			if a ~= nil then return a end
		end
	end,
}
local timers = {}
timer = { Create = function(id, _, _, fn) timers[id] = fn end, Simple = function(_, fn) fn() end }
local commands = {}
concommand = { Add = function(name, fn) commands[name] = fn end }
local files = {}
file = {
	Read = function(path) return files[path] end,
	Write = function(path, text) files[path] = text end,
	CreateDir = function() end,
	Exists = function(path)
		return path:find("^materials/models/") ~= nil or path == "materials/teamtint/lightwarp.vtf"
			or path == "materials/teamtint/white.vtf" or path == "materials/teamtint/black.vtf"
			or path == "materials/teamtint/flat_normal.vtf"
			or path == "materials/teamtint/red/models/combine_soldier/combinesoldiersheet.vtf"
	end,
}
util = { TableToJSON = function() return "{}" end, JSONToTable = function() return nil end, IsValidModel = function() return true end }
function istable(v) return type(v) == "table" end
function IsValid(v) return v ~= nil and (type(v) ~= "table" or not v.removed) end
function Vector(x, y, z) return { x = x, y = y, z = z } end
function Color(r, g, b) return { r = r, g = g, b = b } end
function SortedPairs(t)
	local keys = {}
	for k in pairs(t) do keys[#keys + 1] = k end
	table.sort(keys)
	local i = 0
	return function() i = i + 1; if keys[i] then return keys[i], t[keys[i]] end end
end
render = { SetLightingMode = function(m) Log("lighting", m) end }
function DrawColorModify() Log("greyscale") end
spawnmenu = { AddToolMenuOption = function() end }
draw = { SimpleTextOutlined = function() end }
color_black = {}
TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP = 1, 3

-- materials
local SOURCES = {
	["models/combine_soldier/combinesoldiersheet"] = { shader = "VertexLitGeneric", base = "models/combine_soldier/combinesoldiersheet", tint = 0 },
	["models/humans/male/group03/citizen_sheet"] = { shader = "VertexLitGeneric", base = "models/humans/male/group03/citizen_sheet", tint = 1 },
	["models/combine_soldier/eyeball_l"] = { shader = "EyeRefract", base = "models/combine_soldier/eye" },
	["models/humans/male/group01/joe_facemap"] = { shader = "VertexLitGeneric", base = "models/humans/male/group01/joe_facemap", tint = 0 },
}
local IMaterial = {}
IMaterial.__index = IMaterial
function IMaterial:IsError() return self.err end
function IMaterial:GetShader() return self.shader end
function IMaterial:GetString(k)
	if k == "$basetexture" then return self.params[k] end
	return self.params[k]
end
function IMaterial:GetInt(k) return self.params[k] or 0 end
function IMaterial:GetKeyValues()
	local tex = setmetatable({}, { __index = { IsError = function() return false end, GetName = function() return self.params["$basetexture"] end } })
	return { ["$basetexture"] = tex, ["$flags"] = 2048, ["$color"] = Vector(1, 1, 1) }
end
function IMaterial:SetTexture(k, v) self.params[k] = v end
function IMaterial:SetUndefined(k) self.params[k] = nil end
function IMaterial:SetVector(k, v) self.params[k] = { v.x, v.y, v.z } end
function IMaterial:SetInt(k, v) self.params[k] = v end
function IMaterial:SetFloat(k, v) self.params[k] = v end
function IMaterial:Recompute() self.recomputed = (self.recomputed or 0) + 1 end
function Material(path)
	local s = SOURCES[path]
	if not s then return setmetatable({ err = true, params = {} }, IMaterial) end
	return setmetatable({ shader = s.shader, params = { ["$basetexture"] = s.base, ["$blendtintbybasealpha"] = s.tint } }, IMaterial)
end
local created = {}
function CreateMaterial(name, shader, kv)
	local m = setmetatable({ shader = shader, params = {}, kv = kv }, IMaterial)
	created[name] = m
	return m
end
local _type = type
function type(v)
	if _type(v) == "table" and getmetatable(v) and getmetatable(v).__index and getmetatable(v).__index.GetName then return "ITexture" end
	if _type(v) == "table" and v.x and v.y and v.z and not v.GetMaterials then return "Vector" end
	return _type(v)
end

-- entities
local Ent = {}
Ent.__index = Ent
function Ent:IsPlayer() return false end
function Ent:IsWeapon() return false end
function Ent:IsNPC() return false end
function Ent:IsNextBot() return self.nextbot end
function Ent:IsRagdoll() return self.ragdoll end
function Ent:IsDormant() return false end
function Ent:GetNW2Int(_, d) return self.nw or d end
function Ent:GetModel() return self.model end
function Ent:GetMaterials() return self.materials end
function Ent:SetSubMaterial(i, name)
	if i == nil then self.sub = {} return end
	self.sub[i] = name
end
function Ent:GetSubMaterial(i) return self.sub[i] or "" end
local all = {}
local function NewEnt(fields)
	local e = setmetatable(fields, Ent)
	e.sub = {}
	all[#all + 1] = e
	return e
end
ents = { GetAll = function() return all end }

-- load as the autorun does on a client
require = function(name) dofile(ROOT .. "includes/modules/" .. name .. ".lua") end
function include(path) dofile(ROOT .. path) end
function AddCSLuaFile() end
dofile(ROOT .. "autorun/teamtint.lua")

local function Check(cond, what) T.eq(not not cond, true, what) end
local soldier, rebel, entry, cloth, ragdoll, before, exported

T.test("a Combine NextBot on RED (the gamemode's answer) wears RED's copies", function()
	soldier = NewEnt({ nextbot = true, model = "models/player/combine_soldier.mdl",
		materials = { "models/combine_soldier/combinesoldiersheet", "models/combine_soldier/eyeball_l" } })
	hook.Add("TeamTintTeamOf", "test", function(ent) return ent.team end)
	soldier.team = "red"
	timers.teamtint_sweep()
	Check(soldier.sub[0] == "!teamtint_red_models_combine_soldier_combinesoldiersheet", "the sheet wears RED's copy: " .. tostring(soldier.sub[0]))
	Check(soldier.sub[1] == nil, "the eye is left alone")
	entry = TeamTint.materials["red|models/combine_soldier/combinesoldiersheet"]
	Check(entry and entry.strategy == "baked", "the sheet is baked (its RED texture exists)")
	Check(entry.material.params["$basetexture"] == "teamtint/red/models/combine_soldier/combinesoldiersheet", "it wears the baked base")
	Check(entry.material.params["$lightwarptexture"] == "teamtint/lightwarp", "it has the warp")
	Check(entry.material.kv["$model"] == "1", "it is a model material")
	Check(entry.material.kv["$bumpmap"] == "teamtint/flat_normal", "a sheet without a normal map gets a flat one (the phong path needs one)")
end)

T.test("a rebel on BLU through the tint mask", function()
	rebel = NewEnt({ nextbot = true, model = "models/player/group03/male_01.mdl", team = "blu",
		materials = { "models/humans/male/group03/citizen_sheet", "models/humans/male/group01/joe_facemap" } })
	timers.teamtint_sweep()
	cloth = TeamTint.materials["blu|models/humans/male/group03/citizen_sheet"]
	Check(cloth.strategy == "proxy", "the clothes take the colour through the mask")
	Check(math.abs(cloth.material.params["$color2"][1] - 88 / 255) < 1e-6, "BLU's colour")
	local face = TeamTint.materials["blu|models/humans/male/group01/joe_facemap"]
	Check(face.strategy == "shade" and face.material.params["$color2"][1] == 1, "the face takes the shading, not the colour")
end)

T.test("a knob turned rewrites the copies", function()
	before = cloth.material.recomputed
	convars.teamtint_rim_boost:SetString("5")
	Check(cloth.material.params["$rimlightboost"] == 5, "rim boost written live")
	Check(cloth.material.recomputed > before, "recomputed")
	Check(TeamTint.tuning.base.rim_boost == 5, "kept in the tuning for all")
end)

T.test("a scope: armour's own value, cloth keeps all's", function()
	convars.teamtint_scope:SetString("armor")
	Check(convars.teamtint_rim_boost:GetString() == "5", "armour shows all's value")
	convars.teamtint_rim_boost:SetString("7")
	Check(entry.material.params["$rimlightboost"] == 7 and cloth.material.params["$rimlightboost"] == 5, "armour 7, cloth still 5")
	convars.teamtint_scope:SetString("all")
	Check(convars.teamtint_rim_boost:GetString() == "5", "back on all: 5")
	Check(TeamTint.tuning.classes.armor.rim_boost == 7, "loading a scope wrote nothing")
end)

T.test("the views swap the copies' parameters and the lighting", function()
	convars.teamtint_view:SetString("3")
	Check(cloth.material.params["$basetexture"] == "teamtint/white", "lighting view: white")
	convars.teamtint_view:SetString("0")
	Check(cloth.material.params["$basetexture"] == "models/humans/male/group03/citizen_sheet", "back to its own base")
	convars.teamtint_view:SetString("1")
	hooks.PreRender.teamtint_view()
	Check(log[#log] == "lighting 1", "albedo view draws unlit")
	hooks.PreDrawHUD.teamtint_view()
	Check(log[#log] == "lighting 0", "and relights before the HUD")
	convars.teamtint_view:SetString("0")
end)

T.test("an override beats the team; clearing returns to it", function()
	soldier.nw = TeamTint.Resolve.ToNetwork("blu")
	hooks.EntityNetworkedVarChanged.teamtint(soldier, "teamtint")
	Check(soldier.sub[0] == "!teamtint_blu_models_combine_soldier_combinesoldiersheet", "overridden to BLU")
	Check(soldier.TeamTintReport.source == "override", "the overlay says it is an override")
	soldier.nw = TeamTint.Resolve.ToNetwork("original")
	hooks.EntityNetworkedVarChanged.teamtint(soldier, "teamtint")
	Check(soldier.sub[0] == nil, "ORIGINAL: as made")
	soldier.nw = nil
	hooks.EntityNetworkedVarChanged.teamtint(soldier, "teamtint")
	Check(soldier.sub[0] == "!teamtint_red_models_combine_soldier_combinesoldiersheet", "cleared: RED again")
end)

T.test("a full update clears the sub-materials: the sweep puts them back", function()
	soldier.sub = {}
	timers.teamtint_sweep()
	Check(soldier.sub[0] == "!teamtint_red_models_combine_soldier_combinesoldiersheet", "reapplied after a reset")
end)

T.test("a ragdoll shows its body's team", function()
	ragdoll = NewEnt({ ragdoll = true, model = soldier.model, materials = soldier.materials })
	hooks.CreateClientsideRagdoll.teamtint(soldier, ragdoll)
	Check(ragdoll.sub[0] == "!teamtint_red_models_combine_soldier_combinesoldiersheet", "the ragdoll is RED")
end)

T.test("the bench swaps in $softwareskin copies", function()
	convars.teamtint_bench_softwareskin:SetString("1")
	Check(soldier.sub[0] == "!teamtint_red_ss_models_combine_soldier_combinesoldiersheet", "bench copy")
	Check(created.teamtint_red_ss_models_combine_soldier_combinesoldiersheet.kv["$softwareskin"] == "1", "with $softwareskin")
	convars.teamtint_bench_softwareskin:SetString("0")
	Check(soldier.sub[0] == "!teamtint_red_models_combine_soldier_combinesoldiersheet", "bench off")
end)

T.test("off: every body as made", function()
	convars.teamtint_enable:SetString("0")
	Check(soldier.sub[0] == nil and rebel.sub[0] == nil, "disabled")
	convars.teamtint_enable:SetString("1")
end)

T.test("the export writes each copy as a VMT", function()
	commands.teamtint_export()
	for path, text in pairs(files) do
		if path:find("^teamtint/export/red/") then exported = text end
	end
	Check(exported and exported:find('"$lightwarptexture" "teamtint/lightwarp"', 1, true), "an exported VMT")
	Check(TeamTint.ConvarText():find("teamtint_rim_boost", 1, true), "the knobs as text")
end)

T.finish()
