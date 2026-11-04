AddCSLuaFile()

TOOL.Category = "NextSoldier"
TOOL.Name = "#tool.ns_pathfollower.name"
TOOL.Command = nil
TOOL.ConfigName = ""
TOOL.ClientConVar = {
	model = "models/player/p2_chell.mdl",
}

-- The yes-or-no queries a follower answers, a checkbox each, unchecked by default.
local QUERIES = nextsoldier.behavior.YES_NO_QUERIES
local QUERY_LABELS = {
	ShouldAttack = "Should attack?",
	ShouldHurry = "Should hurry?",
	ShouldRetreat = "Should retreat?",
	ShouldPickUp = "Should pick up?",
}
local QUERY_HELP = {
	ShouldHurry = "Should hurry? (runs when checked, walks when not)",
}

local function QueryConVar(name) return "query_" .. name:lower() end

for _, name in ipairs(QUERIES) do
	TOOL.ClientConVar[QueryConVar(name)] = "0"
end

TOOL.Information = {
	{ name = "left" },
	{ name = "right" },
	{ name = "reload" },
}

local MODELS = {
	"models/player/p2_chell.mdl",
	"models/player/scout.mdl",
	"models/bots/headless_hatman.mdl",
	"models/bots/boss_bot/static_boss_tank.mdl",
	"models/bots/bot_worker/bot_worker.mdl",
	"models/bots/merasmus/merasmus.mdl",
}

local MODEL_NAMES = {
	["models/player/p2_chell.mdl"] = "Chell",
	["models/player/scout.mdl"] = "Scout",
	["models/bots/headless_hatman.mdl"] = "Headless Hatman",
	["models/bots/boss_bot/static_boss_tank.mdl"] = "Tank",
	["models/bots/bot_worker/bot_worker.mdl"] = "Bot Worker",
	["models/bots/merasmus/merasmus.mdl"] = "Merasmus",
}

local MODEL_COLLISION_BOUNDS = {
	["models/player/p2_chell.mdl"] = { x = 13, y = 13, z = 72 },
	["models/player/scout.mdl"] = { x = 19.3, y = 16.6, z = 83.1 },
	["models/bots/headless_hatman.mdl"] = { x = 25.6, y = 38.2, z = 138.5 },
	["models/bots/boss_bot/static_boss_tank.mdl"] = { x = 117.4, y = 79.2, z = 176.2 },
	["models/bots/bot_worker/bot_worker.mdl"] = { x = 34.5, y = 16, z = 54.4 },
	["models/bots/merasmus/merasmus.mdl"] = { x = 92.8, y = 49.7, z = 190.4 },
}

local selections = setmetatable({}, { __mode = "k" })


if CLIENT then
	language.Add("tool.ns_pathfollower.name", "Path Follower")
	language.Add("tool.ns_pathfollower.desc", "Spawn pathfollowers and send them along navigation routes")
	language.Add("tool.ns_pathfollower.left", "Spawn a pathfollower, or add/remove one from your selection")
	language.Add("tool.ns_pathfollower.right", "Send selected pathfollowers to this position")
	language.Add("tool.ns_pathfollower.reload", "Clear your selection")
end

local function Selection(ply)
	local selected = selections[ply]
	if not selected then
		selected = {}
		selections[ply] = selected
	end
	return selected
end

function TOOL:LeftClick(trace)
	if CLIENT then return true end
	local ply = self:GetOwner()
	if not IsValid(ply) then return false end

	local hit = trace.Entity
	if IsValid(hit) and hit:GetClass() == "npc_pathfollower" and hit:GetNW2Bool("NSPathFollowerDebug", false) then
		local selected = Selection(ply)
		if selected[hit] then
			selected[hit] = nil
		else
			selected[hit] = true
		end
		return true
	end
	if not trace.Hit or trace.HitSky then return false end

	local model = self:GetClientInfo("model")
	if not MODEL_NAMES[model] then return false end
	if not util.IsValidModel(model) then
		ply:ChatPrint("[Path Follower] Model is not mounted: " .. model)
		return false
	end

	local follower = ents.Create("npc_pathfollower")
	if not IsValid(follower) then
		ply:ChatPrint("[Path Follower] Could not create npc_pathfollower.")
		return false
	end
	follower.NSToolManaged = true
	follower.NSLaneTeam = WS.TeamOf(ply) or WS.TEAM_UNASSIGNED
	follower:SetNW2Int("ws_team", follower.NSLaneTeam)
	follower.Models = { model }
	follower.CollisionBounds = MODEL_COLLISION_BOUNDS[model]
	follower:SetPos(trace.HitPos + Vector(0, 0, 1))
	follower:Spawn()
	follower:Activate()
	if not IsValid(follower) then
		ply:ChatPrint("[Path Follower] The pathfollower failed to spawn.")
		return false
	end
	ply:AddCleanup("ns_pathfollower", follower)
	undo.Create("Path Follower")
	undo.AddEntity(follower)
	undo.SetPlayer(ply)
	undo.Finish()
	Selection(ply)[follower] = true
	return true
end

function TOOL:RightClick(trace)
	if CLIENT then return true end
	local ply = self:GetOwner()
	if not IsValid(ply) or not trace.Hit or trace.HitSky then return false end

	local selected, count = Selection(ply), 0
	for follower in pairs(selected) do
		if IsValid(follower) then
			follower:NSSetGoal(trace.HitPos)
			count = count + 1
		else
			selected[follower] = nil
		end
	end
	if count == 0 then
		ply:ChatPrint("[Path Follower] Spawn or select a pathfollower with left-click first.")
		return false
	end
	return true
end

function TOOL:Reload()
	if CLIENT then return true end
	local ply = self:GetOwner()
	if not IsValid(ply) then return false end
	selections[ply] = nil
	return true
end

-- Its selected followers answer as the boxes say, a change at once.
function TOOL:Think()
	if CLIENT then return end
	local selected = selections[self:GetOwner()]
	if not selected then return end
	for follower in pairs(selected) do
		if IsValid(follower) then
			for _, name in ipairs(QUERIES) do
				follower:NSRespond(name, self:GetClientNumber(QueryConVar(name)) ~= 0)
			end
		else
			selected[follower] = nil
		end
	end
end

if CLIENT then
	local YES_COLOR, NO_COLOR = Color(120, 255, 120), Color(255, 140, 140)
	local QUERY_LINE_HEIGHT, QUERY_OFFSET = 16, 24

	-- What the follower under the crosshair answers.
	function TOOL:DrawHUD()
		local follower = self:GetOwner():GetEyeTrace().Entity
		if not IsValid(follower) or follower:GetClass() ~= "npc_pathfollower" then return end
		local x, y = ScrW() / 2 + QUERY_OFFSET, ScrH() / 2 + QUERY_OFFSET
		for i, name in ipairs(QUERIES) do
			local yes = follower:GetNW2Bool("NSQuery" .. name, false)
			draw.SimpleTextOutlined(QUERY_LABELS[name] .. " " .. (yes and "yes" or "no"), "DermaDefaultBold",
				x, y + (i - 1) * QUERY_LINE_HEIGHT, yes and YES_COLOR or NO_COLOR,
				TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 1, color_black)
		end
	end
end

function TOOL.BuildCPanel(panel)
	panel:Help("Left-click to spawn a follower or add/remove one from your selection. Right-click sends all selected followers; right-click again changes their target. Reload clears the selection.")
	panel:Help("The overlay shows the generated path in cyan, an active AI-war lane in amber, and the local movement command at the follower's feet in magenta.")
	local combo = panel:ComboBox("Model", "ns_pathfollower_model")
	for _, model in ipairs(MODELS) do
		combo:AddChoice(MODEL_NAMES[model], model)
	end
	panel:Help("What the selected followers answer when asked. Aim at a follower to see its answers.")
	for _, name in ipairs(QUERIES) do
		panel:CheckBox(QUERY_HELP[name] or QUERY_LABELS[name], "ns_pathfollower_" .. QueryConVar(name))
	end
end
