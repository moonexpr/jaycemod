-- The teamtint tool: paint a body RED or BLU (an override of the team it
-- shows), clear it, or spawn a RED and a BLU copy beside it to compare.
-- Its menu is Team Tint's panel (teamtint/cl_panel.lua).
TOOL.Category = "Render"
TOOL.Name = "#tool.teamtint.name"
TOOL.Information = {
	{ name = "left" },
	{ name = "right" },
	{ name = "reload" },
}

if CLIENT then
	language.Add("tool.teamtint.name", "Team Tint")
	language.Add("tool.teamtint.desc", "Show a body as RED or BLU, and tune the team look")
	language.Add("tool.teamtint.left", "Paint RED (hold sprint: spawn a RED and a BLU copy beside it)")
	language.Add("tool.teamtint.right", "Paint BLU")
	language.Add("tool.teamtint.reload", "Clear: the body shows its own team again")
end

local function Target(trace)
	local ent = trace.Entity
	if not IsValid(ent) or ent:IsPlayer() or ent:IsWorld() then return nil end
	return ent
end

local function Paint(tool, trace, rep)
	local ent = Target(trace)
	if not ent or not TeamTint then return false end
	if CLIENT then return true end
	local ply = tool:GetOwner()
	if not TeamTint.CanOverride(ply, ent) then return false end
	if rep == TeamTint.Resolve.RED and ply:KeyDown(IN_SPEED) then
		TeamTint.SpawnPair(ply, ent)
	else
		TeamTint.SetOverride(ent, rep)
	end
	return true
end

function TOOL:LeftClick(trace) return Paint(self, trace, TeamTint and TeamTint.Resolve.RED) end
function TOOL:RightClick(trace) return Paint(self, trace, TeamTint and TeamTint.Resolve.BLU) end
function TOOL:Reload(trace) return Paint(self, trace, nil) end

function TOOL.BuildCPanel(panel)
	if TeamTint and TeamTint.BuildPanel then TeamTint.BuildPanel(panel) end
end
