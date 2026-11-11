-- The Flag tool: a team's flag, and the zone where that team captures the enemy's.
-- Its helpers' other settings are their Edit Properties (features.builder).
AddCSLuaFile ()

local Builder = WS.require ("features.builder.model")

TOOL.Category = "Gameplay"
TOOL.Name = "#tool.build_flag.name"
TOOL.ClientConVar = { team = "2" }
TOOL.Information =
{
	{ name = "left" },
	{ name = "right" },
	{ name = "reload" }
}

if CLIENT then
	language.Add ("tool.build_flag.name", "Flag")
	language.Add ("tool.build_flag.desc", "Place capturable flags and their capture zones")
	language.Add ("tool.build_flag.left", "Place the team's flag (double-click one to give it this team)")
	language.Add ("tool.build_flag.right", "Place the team's capture zone, where it brings the enemy's flag")
	language.Add ("tool.build_flag.reload", "Remove the piece you are looking at")
end

local function Run (tool, method, ...)
	if CLIENT then return GetGlobal2Bool ("ws_builder_available", false) end
	return WS.Feature ("builder"):Do (method, tool:GetOwner (), ...)
end

local function Team (tool)
	return { TeamNum = Builder.PlayingTeam (tool:GetClientNumber ("team")) }
end

function TOOL:LeftClick (trace) return Run (self, "Place", trace, Builder.FLAG, Team (self)) end
function TOOL:RightClick (trace) return Run (self, "Place", trace, Builder.ZONE, Team (self)) end
function TOOL:Reload (trace) return Run (self, "RemoveAt", trace) end

function TOOL.BuildCPanel (panel)
	panel:Help ("For maps without objectives of their own. Hold C and right-click a helper for its properties.")
	local team = panel:ComboBox ("Team", "build_flag_team")
	team:AddChoice ("RED", 2)
	team:AddChoice ("BLU", 3)
end
