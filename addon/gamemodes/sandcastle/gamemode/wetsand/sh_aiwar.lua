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
	.. "the Combine spawn at RED's and defend it. Sandcastle's Combine and Resistance soldiers you spawn join their side. "
	.. "Payload maps only. Needs DrGBase (Steam Workshop) for its soldiers."

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

-- Brighter than the teams' HUD colours, to read over any map.
local DEBUG_COLOR = { [WETSAND.TEAM_RED] = Color(255, 90, 90), [WETSAND.TEAM_BLUE] = Color(110, 175, 255) }
local DEBUG_BACKGROUND = Color(24, 24, 28)
local DEBUG_PADDING, DEBUG_LINE_GAP = 6, 1

surface.CreateFont("WetsandAiwarHeading", { font = "Tahoma", size = 15, weight = 800 })
surface.CreateFont("WetsandAiwarDetail", { font = "Tahoma", size = 13, weight = 500 })

net.Receive(DEBUG_NET, function()
	local soldiers = {}
	for i = 1, net.ReadUInt(8) do
		local soldier = { ent = net.ReadEntity(), team = net.ReadUInt(3), heading = net.ReadString(), details = {}, route = {} }
		for j = 1, net.ReadUInt(4) do soldier.details[j] = net.ReadString() end
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
			local color = DEBUG_COLOR[soldier.team] or color_white
			local from = soldier.ent:GetPos() + Vector(0, 0, 8)
			for _, point in ipairs(soldier.route) do
				render.DrawLine(from, point + Vector(0, 0, 8), color, false)
				from = point + Vector(0, 0, 8)
			end
			if soldier.goal then render.DrawWireframeSphere(soldier.goal, 16, 8, 8, color, false) end
		end
	end
end)

-- A box above each soldier's head: the heading in bold and its team's
-- colour, then the labelled details in white, on an opaque background.
-- Boxes are laid out nearest soldier first so none covers another
-- (foundation.aiwar.overlay); a box moved off its soldier keeps a line to
-- its head.
local Overlay = WETSAND.require("foundation.aiwar.overlay")

local function Measure(soldier)
	surface.SetFont("WetsandAiwarHeading")
	local width, headingHeight = surface.GetTextSize(soldier.heading)
	surface.SetFont("WetsandAiwarDetail")
	local _, lineHeight = surface.GetTextSize("Ag")
	for _, detail in ipairs(soldier.details) do width = math.max(width, (surface.GetTextSize(detail))) end
	local height = headingHeight + #soldier.details * (lineHeight + DEBUG_LINE_GAP)
	return width + DEBUG_PADDING * 2, height + DEBUG_PADDING * 2, headingHeight, lineHeight
end

local function DrawSoldierBox(soldier, rect, anchor)
	local color = DEBUG_COLOR[soldier.team] or color_white
	if rect.moved then
		surface.SetDrawColor(color)
		surface.DrawLine(rect.left + rect.w / 2, rect.top + rect.h, anchor.x, anchor.y)
	end
	draw.RoundedBox(4, rect.left - 1, rect.top - 1, rect.w + 2, rect.h + 2, color)
	draw.RoundedBox(4, rect.left, rect.top, rect.w, rect.h, DEBUG_BACKGROUND)
	local x, y = rect.left + DEBUG_PADDING, rect.top + DEBUG_PADDING
	draw.SimpleText(soldier.heading, "WetsandAiwarHeading", x, y, color)
	y = y + soldier.headingHeight
	for _, detail in ipairs(soldier.details) do
		draw.SimpleText(detail, "WetsandAiwarDetail", x, y, color_white)
		y = y + soldier.lineHeight + DEBUG_LINE_GAP
	end
end

hook.Add("HUDPaint", "wetsand_aiwar_debug", function()
	if not DebugLive() then return end
	local eye = EyePos()
	local shown = {}
	for _, soldier in ipairs(debug.soldiers) do
		if IsValid(soldier.ent) then
			local head = soldier.ent:GetPos() + Vector(0, 0, DEBUG_TEXT_HEIGHT)
			local screen = head:ToScreen()
			if screen.visible then
				soldier.anchor, soldier.distance = screen, eye:DistToSqr(head)
				shown[#shown + 1] = soldier
			end
		end
	end
	table.sort(shown, function(a, b) return a.distance < b.distance end)
	local boxes = {}
	for i, soldier in ipairs(shown) do
		local w, h, headingHeight, lineHeight = Measure(soldier)
		soldier.headingHeight, soldier.lineHeight = headingHeight, lineHeight
		boxes[i] = { x = soldier.anchor.x, bottom = soldier.anchor.y, w = w, h = h }
	end
	local rects = Overlay.Layout(boxes)
	-- farthest first, so a leader line never crosses a nearer box
	for i = #shown, 1, -1 do DrawSoldierBox(shown[i], rects[i], shown[i].anchor) end
end)

hook.Add("PopulateToolMenu", "wetsand_aiwar", function()
	spawnmenu.AddToolMenuOption("Utilities", "Sandcastle", "wetsand_aiwar", "AI War", "", "", BuildPanel)
end)
