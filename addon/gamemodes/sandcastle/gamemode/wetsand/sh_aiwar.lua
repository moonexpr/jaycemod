-- The AI war's switch: the team-size convar, the commands that start and
-- end it, and on clients the Utilities menu entry, a button that reads
-- "Start AI War" or "End AI War". The war itself is the aiwar feature
-- (features/aiwar), loaded the first time it starts.
local AiWar = WETSAND.require("foundation.aiwar")

local ACTIVE_KEY = "wetsand.aiwar"

CreateConVar("mp_aiwar_team_size", tostring(AiWar.TEAM_SIZE_DEFAULT), { FCVAR_ARCHIVE, FCVAR_REPLICATED },
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

	Command("mp_aiwar_start", "Start",
		"Start the war, the Combine (RED) against the Resistance (BLU) on payload, control point and "
			.. "King of the Hill maps; in Sandbox mode, Gameplay mode counts down and begins")
	Command("mp_aiwar_end", "End", "End the AI war; its soldiers leave, NPCs players spawned stay")
	return
end

-- Dead soldiers' ragdolls are made on clients, as every NPC's is
-- (wetsand/cl_npc_ragdolls.lua); engine NPCs fighting in the war die into
-- the engine's own clientside ragdolls, which fade the same way.
hook.Add("CreateClientsideRagdoll", "wetsand_aiwar_ragdoll_fade", function(owner, ragdoll)
	if IsValid(owner) and AiWar.FactionTeam(owner:GetClass()) then WETSAND.FadeRagdollLater(ragdoll) end
end)

local HELP = "In Sandbox mode, counts down to Gameplay mode and a new round. "
	.. "The Resistance spawn at BLU's spawn and the Combine at RED's, and fight the map's round: "
	.. "they push or stop the cart, take and hold the points, or fight for the hill. "
	.. "Sandcastle's Combine and Resistance soldiers you spawn join their side. "
	.. "Payload, control point and King of the Hill maps. Needs DrGBase (Steam Workshop) for its soldiers."

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
		RunConsoleCommand(WETSAND.AiWarActive() and "mp_aiwar_end" or "mp_aiwar_start")
	end
	panel:NumSlider("Soldiers per side", "mp_aiwar_team_size", 1, AiWar.TEAM_SIZE_MAX, 0)
	panel:NumSlider("Ragdolls fade after (s, 0: never)", "cl_npc_ragdoll_lifetime", 0, 120, 0)
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
