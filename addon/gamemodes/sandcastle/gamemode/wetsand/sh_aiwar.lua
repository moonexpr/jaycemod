-- The AI war's switch: the team-size convar, the commands that start and
-- end it, and on clients the Utilities menu entry, a button that reads
-- "Start AI War" or "End AI War". The war itself is the aiwar feature
-- (features/aiwar), loaded the first time it starts.
local AiWar = WETSAND.require("foundation.aiwar")

local ACTIVE_KEY = "wetsand.aiwar"

CreateConVar("wetsand_aiwar_team_size", tostring(AiWar.TEAM_SIZE_DEFAULT), { FCVAR_ARCHIVE, FCVAR_REPLICATED },
	"Soldiers each side of the AI war keeps in the field", 1, AiWar.TEAM_SIZE_MAX)

function WETSAND.AiWarActive()
	return GetGlobal2Bool(ACTIVE_KEY, false)
end

if SERVER then
	local function Tell(ply, text)
		if IsValid(ply) then ply:ChatPrint(text) else print(text) end
	end

	local function Command(name, method, help)
		concommand.Add(name, function(ply)
			if IsValid(ply) and not ply:IsAdmin() then
				Tell(ply, "AI war: only admins can start or end it")
				return
			end
			local war = WETSAND.Feature("aiwar")
			local ok, why = war[method](war)
			if not ok then Tell(ply, "AI war: " .. why) end
		end, nil, help)
	end

	Command("wetsand_aiwar_start", "Start",
		"Restart the round with the Combine (RED) defending the cart against the Resistance (BLU)")
	Command("wetsand_aiwar_end", "End", "End the AI war; its soldiers leave, NPCs players spawned stay")
	return
end

local HELP = "Restarts the round: the Resistance spawn at BLU's spawn and push the cart, "
	.. "the Combine spawn at RED's and defend it. Combine and Resistance NPCs you spawn join their side. "
	.. "Payload maps only."

local function BuildPanel(panel)
	panel:ClearControls()
	panel:Help(HELP)
	local button = panel:Button("Start AI War")
	function button:Think()
		local on = WETSAND.AiWarActive()
		if self.warOn == on then return end
		self.warOn = on
		self:SetText(on and "End AI War" or "Start AI War")
	end
	function button:DoClick()
		RunConsoleCommand(WETSAND.AiWarActive() and "wetsand_aiwar_end" or "wetsand_aiwar_start")
	end
	panel:NumSlider("Soldiers per side", "wetsand_aiwar_team_size", 1, AiWar.TEAM_SIZE_MAX, 0)
	panel:Help("Debugging (admins): draw each soldier's route and state, or print them all to the console.")
	panel:Button("Toggle Soldier Overlay", "wetsand_aiwar_debug")
	panel:Button("Print Soldier Report", "wetsand_aiwar_report")
end

-- The soldier overlay (wetsand_aiwar_debug): what the server last sent,
-- drawn until it goes stale.
local DEBUG_NET = "wetsand_aiwar_debug"
local DEBUG_STALE = 2
local DEBUG_TEXT_HEIGHT = 80
local debug = { soldiers = {}, received = 0 }

net.Receive(DEBUG_NET, function()
	local soldiers = {}
	for i = 1, net.ReadUInt(8) do
		local soldier = { ent = net.ReadEntity(), team = net.ReadUInt(3), text = net.ReadString(), route = {} }
		if net.ReadBool() then soldier.goal = net.ReadVector() end
		for j = 1, net.ReadUInt(8) do soldier.route[j] = net.ReadVector() end
		soldiers[i] = soldier
	end
	debug.soldiers, debug.received = soldiers, CurTime()
end)

local function DebugLive()
	return CurTime() - debug.received < DEBUG_STALE
end

hook.Add("PostDrawTranslucentRenderables", "wetsand_aiwar_debug", function(depth, skybox)
	if skybox or not DebugLive() then return end
	for _, soldier in ipairs(debug.soldiers) do
		if IsValid(soldier.ent) then
			local color = WETSAND.TeamColor[soldier.team] or color_white
			local from = soldier.ent:GetPos() + Vector(0, 0, 8)
			for _, point in ipairs(soldier.route) do
				render.DrawLine(from, point + Vector(0, 0, 8), color, false)
				from = point + Vector(0, 0, 8)
			end
			if soldier.goal then render.DrawWireframeSphere(soldier.goal, 16, 8, 8, color, false) end
		end
	end
end)

hook.Add("HUDPaint", "wetsand_aiwar_debug", function()
	if not DebugLive() then return end
	for _, soldier in ipairs(debug.soldiers) do
		if IsValid(soldier.ent) then
			local screen = (soldier.ent:GetPos() + Vector(0, 0, DEBUG_TEXT_HEIGHT)):ToScreen()
			if screen.visible then
				draw.SimpleTextOutlined(soldier.text, "DefaultSmall", screen.x, screen.y, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM, 1, color_black)
			end
		end
	end
end)

hook.Add("PopulateToolMenu", "wetsand_aiwar", function()
	spawnmenu.AddToolMenuOption("Utilities", "Sandcastle", "wetsand_aiwar", "AI War", "", "", BuildPanel)
end)
