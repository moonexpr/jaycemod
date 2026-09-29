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

-- The soldier overlay (wetsand_aiwar_debug) is drawn by the nbdebug
-- feature's view (features/nbdebug/cl.lua), as its AIWAR layer, with the
-- other NPC debug layers.

hook.Add("PopulateToolMenu", "wetsand_aiwar", function()
	spawnmenu.AddToolMenuOption("Utilities", "Sandcastle", "wetsand_aiwar", "AI War", "", "", BuildPanel)
end)
