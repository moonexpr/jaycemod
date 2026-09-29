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
	-- Dead soldiers' ragdolls are made by each client (WETSAND.DrgSoldier's
	-- BecomeRagdoll sends RAGDOLL_NET), never by the server, unless this is
	-- turned off (then DrGBase's serverside ones, which the war still caps).
	CreateConVar("wetsand_aiwar_client_ragdolls", "1", FCVAR_ARCHIVE,
		"Dead soldiers leave clientside ragdolls (no server physics, no shared memory) rather than DrGBase's serverside ones")
	util.AddNetworkString("wetsand_soldier_ragdoll")

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

-- Dead soldiers' clientside ragdolls (wetsand_aiwar_client_ragdolls) fade
-- by each player's own settings: after wetsand_ragdoll_lifetime seconds (0
-- keeps them), the engine's own fade (at g_ragdoll_fadespeed) removes them;
-- g_ragdoll_maxcount caps how many stay, as for any clientside ragdoll.
local RAGDOLL_LIFETIME = CreateClientConVar("wetsand_ragdoll_lifetime", "20", true, false,
	"Seconds a dead soldier's ragdoll stays before fading away (0: until g_ragdoll_maxcount pushes it out)", 0, 600)

local function FadeLater(ragdoll)
	if ragdoll.wetsandFading then return end
	ragdoll.wetsandFading = true
	local lifetime = RAGDOLL_LIFETIME:GetFloat()
	if lifetime <= 0 then return end
	timer.Simple(lifetime, function()
		if IsValid(ragdoll) then ragdoll:SetSaveValue("m_bFadingOut", true) end
	end)
end

hook.Add("CreateClientsideRagdoll", "wetsand_aiwar_ragdoll_fade", function(owner, ragdoll)
	if IsValid(owner) and AiWar.FactionTeam(owner:GetClass()) then FadeLater(ragdoll) end
end)

-- A soldier died: its ragdoll, made here from its last pose (the engine's
-- clientside ragdoll; else a ClientsideRagdoll posed bone by bone), pushed
-- by the killing blow. The server removes the soldier a moment later.
net.Receive("wetsand_soldier_ragdoll", function()
	local ent, force = net.ReadEntity(), net.ReadVector()
	if not IsValid(ent) then return end
	local ragdoll = ent.BecomeRagdollOnClient and ent:BecomeRagdollOnClient()
	if not IsValid(ragdoll) then
		ragdoll = ClientsideRagdoll(ent:GetModel())
		if not IsValid(ragdoll) then return end
		ragdoll:SetSkin(ent:GetSkin())
		for _, group in ipairs(ent:GetBodyGroups() or {}) do ragdoll:SetBodygroup(group.id, ent:GetBodygroup(group.id)) end
		ent:SetupBones()
		for i = 0, ragdoll:GetPhysicsObjectCount() - 1 do
			local phys = ragdoll:GetPhysicsObjectNum(i)
			local matrix = IsValid(phys) and ent:GetBoneMatrix(ragdoll:TranslatePhysBoneToBone(i))
			if matrix then
				phys:SetPos(matrix:GetTranslation())
				phys:SetAngles(matrix:GetAngles())
				phys:Wake()
			end
		end
	end
	local count = ragdoll:GetPhysicsObjectCount()
	for i = 0, count - 1 do
		local phys = ragdoll:GetPhysicsObjectNum(i)
		if IsValid(phys) then phys:ApplyForceCenter(force / math.max(count, 1)) end
	end
	ent:SetNoDraw(true)
	FadeLater(ragdoll)
end)

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
	panel:NumSlider("Ragdolls fade after (s, 0: never)", "wetsand_ragdoll_lifetime", 0, 120, 0)
	panel:NumSlider("Most ragdolls kept", "g_ragdoll_maxcount", 0, 64, 0)
	panel:Help("Debugging (admins): draw each soldier's route and state, or print them all to the console.")
	panel:Button("Toggle Soldier Overlay", "wetsand_aiwar_debug")
	panel:Button("Print Soldier Report", "wetsand_aiwar_report")
	panel:Help("Trace the soldier you aim at: every question DrGBase asks its orders and every event it tells them, in the server console. Aim at nothing to stop.")
	panel:Button("Trace Soldier Aimed At", "wetsand_aiwar_trace")
	panel:CheckBox("Overlay shows the whole action stack", "wetsand_aiwar_debug_full")
end

-- The soldier overlay (wetsand_aiwar_debug): what the server last sent,
-- drawn until it goes stale.
local DEBUG_NET = "wetsand_aiwar_debug"
local DEBUG_STALE = 2
local DEBUG_TEXT_HEIGHT = 80
local debug = { soldiers = {}, teams = {}, spheres = {}, received = 0 }

-- Brighter than the teams' HUD colours, to read over any map.
local DEBUG_COLOR = { [WETSAND.TEAM_RED] = Color(255, 90, 90), [WETSAND.TEAM_BLUE] = Color(110, 175, 255) }
local DEBUG_BACKGROUND = Color(24, 24, 28)
local DEBUG_PADDING, DEBUG_LINE_GAP = 6, 1

surface.CreateFont("WetsandAiwarHeading", { font = "Tahoma", size = 15, weight = 800 })
surface.CreateFont("WetsandAiwarDetail", { font = "Tahoma", size = 13, weight = 500 })

net.Receive(DEBUG_NET, function()
	local teams, soldiers = {}, {}
	for i = 1, net.ReadUInt(8) do
		local fireTeam = { team = net.ReadUInt(3), name = net.ReadString(), contact = net.ReadVector() }
		if net.ReadBool() then fireTeam.flank = net.ReadVector() end
		teams[i] = fireTeam
	end
	local spheres = {}
	for i = 1, net.ReadUInt(4) do
		spheres[i] = { team = net.ReadUInt(3), center = net.ReadVector(), radius = net.ReadFloat(), push = net.ReadBool() }
	end
	debug.spheres = spheres
	local lanes = {}
	for i = 1, net.ReadUInt(4) do
		local lane = { team = net.ReadUInt(3), index = net.ReadUInt(3), points = {} }
		for j = 1, net.ReadUInt(6) do lane.points[j] = net.ReadVector() end
		lanes[i] = lane
	end
	debug.lanes = lanes
	for i = 1, net.ReadUInt(8) do
		local soldier = { ent = net.ReadEntity(), team = net.ReadUInt(3), heading = net.ReadString(), details = {}, route = {} }
		for j = 1, net.ReadUInt(4) do soldier.details[j] = net.ReadString() end
		if net.ReadBool() then soldier.goal = net.ReadVector() end
		for j = 1, net.ReadUInt(8) do soldier.route[j] = net.ReadVector() end
		soldier.fireTeam = teams[net.ReadUInt(8)]
		soldier.moving = net.ReadBool()
		if net.ReadBool() then soldier.cover = net.ReadVector() end
		soldiers[i] = soldier
	end
	debug.teams, debug.soldiers, debug.received = teams, soldiers, CurTime()
end)

-- The tactics markers: contacts in amber, cover spots in green, flank
-- points as diamonds in the team's colour.
local CONTACT_COLOR, COVER_COLOR = Color(255, 190, 40), Color(90, 230, 120)
local COVER_BOX, FLANK_BOX, FLANK_ANGLE = Vector(8, 8, 8), Vector(14, 14, 14), Angle(45, 45, 0)
local LANE_MARK = Vector(4, 4, 4)

local function Dim(color)
	return Color(color.r * 0.45, color.g * 0.45, color.b * 0.45)
end

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
			if soldier.cover then render.DrawWireframeBox(soldier.cover, angle_zero, -COVER_BOX, COVER_BOX, COVER_COLOR, false) end
			-- in a fight: a line to its team's contact, bright moving, dim holding
			if soldier.fireTeam then
				local body = soldier.ent:GetPos() + Vector(0, 0, 40)
				render.DrawLine(body, soldier.fireTeam.contact, soldier.moving and color or Dim(color), false)
			end
		end
	end
	-- the cart spheres: rings on the ground, the push sphere bright, the
	-- support sphere dim
	for _, sphere in ipairs(debug.spheres) do
		local color = DEBUG_COLOR[sphere.team] or color_white
		if not sphere.push then color = Dim(color) end
		local segments, lift = sphere.push and 24 or 48, Vector(0, 0, 6)
		local last
		for i = 0, segments do
			local angle = i / segments * math.pi * 2
			local point = sphere.center + Vector(math.cos(angle) * sphere.radius, math.sin(angle) * sphere.radius, 0) + lift
			if last then render.DrawLine(last, point, color, false) end
			last = point
		end
	end
	-- each team's lanes: a dim line along its waypoints, a mark at each
	for _, lane in ipairs(debug.lanes or {}) do
		local color = Dim(DEBUG_COLOR[lane.team] or color_white)
		local lift = Vector(0, 0, 12 + lane.index * 4)
		for j = 2, #lane.points do render.DrawLine(lane.points[j - 1] + lift, lane.points[j] + lift, color, false) end
		for _, point in ipairs(lane.points) do render.DrawWireframeBox(point + lift, angle_zero, -LANE_MARK, LANE_MARK, color, false) end
	end
	-- each fire team in contact: the enemy's last seen place, its flank point
	for _, fireTeam in ipairs(debug.teams) do
		local color = DEBUG_COLOR[fireTeam.team] or color_white
		render.DrawWireframeSphere(fireTeam.contact, 24, 6, 6, CONTACT_COLOR, false)
		render.DrawLine(fireTeam.contact, fireTeam.contact + Vector(0, 0, 96), CONTACT_COLOR, false)
		if fireTeam.flank then
			render.DrawWireframeBox(fireTeam.flank, FLANK_ANGLE, -FLANK_BOX, FLANK_BOX, color, false)
			render.DrawLine(fireTeam.contact, fireTeam.flank, Dim(color), false)
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
	for _, fireTeam in ipairs(debug.teams) do
		local screen = (fireTeam.contact + Vector(0, 0, 104)):ToScreen()
		if screen.visible then
			draw.SimpleTextOutlined("contact: " .. fireTeam.name, "WetsandAiwarDetail", screen.x, screen.y,
				DEBUG_COLOR[fireTeam.team] or color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM, 1, color_black)
		end
		if fireTeam.flank then
			screen = (fireTeam.flank + Vector(0, 0, 24)):ToScreen()
			if screen.visible then
				draw.SimpleTextOutlined("flank: " .. fireTeam.name, "WetsandAiwarDetail", screen.x, screen.y,
					DEBUG_COLOR[fireTeam.team] or color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM, 1, color_black)
			end
		end
	end
end)

hook.Add("PopulateToolMenu", "wetsand_aiwar", function()
	spawnmenu.AddToolMenuOption("Utilities", "Sandcastle", "wetsand_aiwar", "AI War", "", "", BuildPanel)
end)
