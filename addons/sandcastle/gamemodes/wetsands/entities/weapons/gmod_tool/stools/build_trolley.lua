-- The Trolley tool: the path a cart is pushed along, its track, and its checkpoints.
-- Its helpers' other settings are their Edit Properties (features.builder).
AddCSLuaFile ()

local Builder = WS.require ("features.builder.model")

TOOL.Category = "Gameplay"
TOOL.Name = "#tool.build_trolley.name"
TOOL.Information =
{
	{ name = "left" },
	{ name = "right" },
	{ name = "reload" }
}

if CLIENT then
	language.Add ("tool.build_trolley.name", "Trolley")
	language.Add ("tool.build_trolley.desc", "Lay the track of a pushable cart")
	language.Add ("tool.build_trolley.left", "Add a node to the end of the track (the first brings the cart)")
	language.Add ("tool.build_trolley.right", "Put a control point on the node, making it a checkpoint, or take it off")
	language.Add ("tool.build_trolley.reload", "Remove the last node")
end

local function Run (tool, method, ...)
	if CLIENT then return GetGlobal2Bool ("ws_builder_available", false) end
	return WS.Feature ("builder"):Do (method, tool:GetOwner (), ...)
end

function TOOL:LeftClick (trace) return Run (self, "Place", trace, Builder.NODE) end
function TOOL:RightClick (trace) return Run (self, "Act", Builder.NODE, "ToggleHelper", trace) end
function TOOL:Reload () return Run (self, "Act", Builder.NODE, "RemoveTail") end

function TOOL.BuildCPanel (panel)
	panel:Help ("For maps without objectives of their own. Hold C and right-click a helper for its properties.")
end
