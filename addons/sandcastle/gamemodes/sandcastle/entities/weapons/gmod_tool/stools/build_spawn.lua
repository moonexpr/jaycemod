-- The Spawn tool: where a team spawns, the room around it, and its resupply.
-- Its helpers' other settings are their Edit Properties (features.builder).
AddCSLuaFile()

local Builder = WS.require("features.builder.model")

TOOL.Category = "Gameplay"
TOOL.Name = "#tool.build_spawn.name"
TOOL.ClientConVar = { team = "2", model = Builder.SPAWN_MODELS[1] }
TOOL.Information = {
	{ name = "left" },
	{ name = "right" },
	{ name = "reload" },
}

if CLIENT then
	language.Add("tool.build_spawn.name", "Spawn")
	language.Add("tool.build_spawn.desc", "Place a team's spawners, spawn room and resupply closets")
	language.Add("tool.build_spawn.left", "Place a spawner (double-click one to give it these settings)")
	language.Add("tool.build_spawn.right", "Spawn room: click one corner, then the opposite corner")
	language.Add("tool.build_spawn.reload", "Make a resupply closet on the nearest wall, or remove the piece you are looking at")
end

local function Run(tool, method, ...)
	if CLIENT then return GetGlobal2Bool("ws_builder_available", false) end
	return WS.Feature("builder"):Do(method, tool:GetOwner(), ...)
end

local function Team(tool)
	return { TeamNum = Builder.PlayingTeam(tool:GetClientNumber("team")) }
end

function TOOL:LeftClick(trace)
	local values = Team(self)
	values.BodyModel = Builder.SpawnModel(self:GetClientInfo("model"))
	return Run(self, "Place", trace, Builder.SPAWN, values)
end

function TOOL:RightClick(trace) return Run(self, "Place", trace, Builder.ROOM, Team(self)) end
function TOOL:Reload(trace) return Run(self, "Act", Builder.LOCKER, "Reload", trace, self:GetClientNumber("team")) end

function TOOL.BuildCPanel(panel)
	panel:Help("For maps without objectives of their own. Hold C and right-click a helper for its properties.")
	local team = panel:ComboBox("Team", "build_spawn_team")
	team:AddChoice("RED", 2)
	team:AddChoice("BLU", 3)
	local models = {}
	for _, model in ipairs(Builder.SPAWN_MODELS) do models[model] = {} end
	panel:PropSelect("Spawner", "build_spawn_model", models, 2)
end
