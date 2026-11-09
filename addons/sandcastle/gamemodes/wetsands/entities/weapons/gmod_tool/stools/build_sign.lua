-- The Signage tool: TF2's gameplay signs, pointing the way to the objective.
-- Its helpers' other settings are their Edit Properties (features.builder).
AddCSLuaFile()

local Builder = WS.require("features.builder.model")

TOOL.Category = "Gameplay"
TOOL.Name = "#tool.build_sign.name"
TOOL.Information = {
	{ name = "left" },
	{ name = "right" },
	{ name = "reload" },
}

if CLIENT then
	language.Add("tool.build_sign.name", "Signage")
	language.Add("tool.build_sign.desc", "Place signs pointing toward the objective")
	language.Add("tool.build_sign.left", "Place a sign on a wall or the ground")
	language.Add("tool.build_sign.right", "Flip the arrow of the sign you are looking at")
	language.Add("tool.build_sign.reload", "Remove the piece you are looking at")
end

local function Run(tool, method, ...)
	if CLIENT then return GetGlobal2Bool("ws_builder_available", false) end
	return WS.Feature("builder"):Do(method, tool:GetOwner(), ...)
end

function TOOL:LeftClick(trace) return Run(self, "Place", trace, Builder.SIGN) end
function TOOL:RightClick(trace) return Run(self, "Act", Builder.SIGN, "FlipAt", trace) end
function TOOL:Reload(trace) return Run(self, "RemoveAt", trace) end

function TOOL.BuildCPanel(panel)
	panel:Help("For maps without objectives of their own. Hold C and right-click a helper for its properties.")
end
