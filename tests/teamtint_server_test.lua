-- Team Tint's server half (addons/teamtint/lua/teamtint/sv.lua) and its
-- tool, under stubbed GMod globals: the override set and cleared, kept
-- through the duplicator, refused by a gamemode's TeamTintCanOverride,
-- and set without a toolgun by teamtint_paint (admins only).
local T = dofile("tests/harness.lua")
local ROOT = "addons/teamtint/lua/"
CLIENT, SERVER = false, true

local hooks, commands, modifiers = {}, {}, {}
hook = {
	Add = function(event, id, fn) hooks[event] = hooks[event] or {}; hooks[event][id] = fn end,
	Run = function(event, ...)
		for _, fn in pairs(hooks[event] or {}) do
			local a = fn(...)
			if a ~= nil then return a end
		end
	end,
}
concommand = { Add = function(name, fn) commands[name] = fn end }
duplicator = {
	RegisterEntityModifier = function(name, fn) modifiers[name] = fn end,
	StoreEntityModifier = function(ent, name, data) ent.mods[name] = data end,
	ClearEntityModifier = function(ent, name) ent.mods[name] = nil end,
}
function istable(v) return type(v) == "table" end
function IsValid(v) return v ~= nil end
IN_SPEED = 131072

local Ent = {}
Ent.__index = Ent
function Ent:IsPlayer() return self.player end
function Ent:IsWorld() return false end
function Ent:SetNW2Int(_, v) self.nw = v end
function Ent:GetNW2Int(_, d) return self.nw or d end
local function NewEnt(fields)
	fields.mods = {}
	return setmetatable(fields, Ent)
end

require = function(name) dofile(ROOT .. "includes/modules/" .. name .. ".lua") end
function include(path) dofile(ROOT .. path) end
function AddCSLuaFile() end
dofile(ROOT .. "autorun/teamtint.lua")
local Resolve = TeamTint.Resolve

local body = NewEnt({})
local function Player(admin, target)
	local ply = NewEnt({ player = true })
	function ply:IsAdmin() return admin end
	function ply:GetEyeTrace() return { Entity = target } end
	function ply:KeyDown() return false end
	function ply:ChatPrint(text) self.said = text end
	return ply
end

T.test("an override is stored on the body and kept for the duplicator", function()
	TeamTint.SetOverride(body, Resolve.BLU)
	T.eq(TeamTint.Override(body), Resolve.BLU, "BLU")
	T.eq(body.mods.teamtint.rep, Resolve.BLU, "kept for a dupe")
	TeamTint.SetOverride(body, nil)
	T.eq(TeamTint.Override(body), nil, "cleared")
	T.eq(body.mods.teamtint, nil, "and its dupe data")
end)

T.test("a pasted dupe takes its override back, and ignores one it cannot read", function()
	local copy = NewEnt({})
	modifiers.teamtint(nil, copy, { rep = Resolve.RED })
	T.eq(TeamTint.Override(copy), Resolve.RED, "RED")
	modifiers.teamtint(nil, copy, { rep = "green" })
	T.eq(TeamTint.Override(copy), nil, "no team")
end)

T.test("teamtint_paint paints what an admin looks at; others it ignores", function()
	commands.teamtint_paint(Player(true, body), nil, { "RED" })
	T.eq(TeamTint.Override(body), Resolve.RED, "an admin")
	commands.teamtint_paint(Player(false, body), nil, { "blu" })
	T.eq(TeamTint.Override(body), Resolve.RED, "a player: unchanged")
	commands.teamtint_paint(Player(true, body), nil, { "clear" })
	T.eq(TeamTint.Override(body), nil, "clear")
	local ply = Player(true, body)
	commands.teamtint_paint(ply, nil, { "green" })
	T.eq(ply.said ~= nil, true, "a word it does not know: the usage")
end)

T.test("a gamemode's TeamTintCanOverride refuses the override", function()
	hook.Add("TeamTintCanOverride", "test", function() return false end)
	commands.teamtint_paint(Player(true, body), nil, { "red" })
	T.eq(TeamTint.Override(body), nil, "refused")
	hooks.TeamTintCanOverride.test = nil
end)

T.test("the tool paints RED, BLU, and clears; it never paints a player", function()
	TOOL = {}
	dofile(ROOT .. "weapons/gmod_tool/stools/teamtint.lua")
	local tool = setmetatable({}, { __index = TOOL })
	local ply = Player(true, body)
	function tool:GetOwner() return ply end
	T.eq(tool:LeftClick({ Entity = body }), true, "left")
	T.eq(TeamTint.Override(body), Resolve.RED, "RED")
	tool:RightClick({ Entity = body })
	T.eq(TeamTint.Override(body), Resolve.BLU, "BLU")
	tool:Reload({ Entity = body })
	T.eq(TeamTint.Override(body), nil, "cleared")
	T.eq(tool:LeftClick({ Entity = ply }), false, "a player")
	T.eq(tool:LeftClick({ Entity = nil }), false, "nothing")
end)

T.finish()
