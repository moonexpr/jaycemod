-- The Control Point tool: points to capture along the map.
-- Its helpers' other settings are their Edit Properties (features.builder).
AddCSLuaFile ()

local Builder = WS.require ("features.builder.model")

TOOL.Category = "Gameplay"
TOOL.Name = "#tool.build_point.name"
TOOL.Information =
{
	{ name = "left" },
	{ name = "right" },
	{ name = "reload" }
}

if CLIENT then
	language.Add ("tool.build_point.name",   "Control Point")
	language.Add ("tool.build_point.desc",   "Place control points along the map")
	language.Add ("tool.build_point.left",   "Place a control point")
	language.Add ("tool.build_point.right",  "Change who owns the point you are looking at at the start")
	language.Add ("tool.build_point.reload", "Remove the piece you are looking at")
end

local function Run (tool, method, ...)
	if CLIENT then return GetGlobal2Bool ("ws_builder_available", false) end
	return WS.Feature ("builder"):Do (method, tool:GetOwner (), ...)
end

function TOOL:LeftClick (trace) return Run (self, "Place", trace, Builder.POINT) end
function TOOL:RightClick (trace) return Run (self, "Act", Builder.POINT, "CycleOwner", trace) end
function TOOL:Reload (trace) return Run (self, "RemoveAt", trace) end

function TOOL.BuildCPanel (panel)
	panel:Help ("For maps without objectives of their own. Hold C and right-click a helper for its properties.")
end
