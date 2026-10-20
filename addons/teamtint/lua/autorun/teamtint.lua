-- Team Tint: RED and BLU NPCs in TF2's illustrative style. A body's
-- materials are swapped, on each client, for VertexLitGeneric copies that
-- carry TF2's shading terms and its team's colour (teamtint_catalog says
-- which materials and how, teamtint_tuning what the knobs become); which
-- team a body shows is teamtint_resolve's. Any gamemode: a gamemode with
-- teams answers the TeamTintTeamOf hook, and without one a body shows a
-- team only when the teamtint tool (or teamtint_paint) sets it.
--
-- Hooks a gamemode may answer:
--   TeamTintTeamOf(ent) -> "red", "blu" or nil (client): the team ent fights for
--   TeamTintCanOverride(ply, ent) -> false to refuse (server): the tool's and
--     teamtint_paint's override, a debug tool that shows a false team
--
-- Design and tuning workflow: docs/team-theming-plan.md.
AddCSLuaFile()

local MODULES = { "teamtint_catalog", "teamtint_resolve", "teamtint_tuning" }
local SHARED = { "teamtint/sh.lua" }
local CLIENT_FILES = {
	"teamtint/cl_convars.lua", "teamtint/cl_materials.lua", "teamtint/cl_apply.lua",
	"teamtint/cl_debug.lua", "teamtint/cl_panel.lua",
}

if SERVER then
	for _, name in ipairs(MODULES) do AddCSLuaFile("includes/modules/" .. name .. ".lua") end
	for _, path in ipairs(SHARED) do AddCSLuaFile(path) end
	for _, path in ipairs(CLIENT_FILES) do AddCSLuaFile(path) end
end

for _, path in ipairs(SHARED) do include(path) end
if SERVER then
	include("teamtint/sv.lua")
else
	for _, path in ipairs(CLIENT_FILES) do include(path) end
end
