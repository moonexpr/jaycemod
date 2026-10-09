-- The AI war's switch: the team-size convar, the commands that start and
-- end it, mp_aiwar_autostart, which starts it as each map loads, the slot
-- list's commands and events (foundation.aiwar.slots), and on clients the
-- Utilities menu entry: a button that reads "Start AI War" or "End AI
-- War", and the slot list (wetsand/cl_aiwar_slots.lua). The war itself is
-- the aiwar feature (features/aiwar), loaded the first time it starts or
-- its slots are asked for.
local AiWar = WETSAND.require("foundation.aiwar")
local Slots = WETSAND.require("foundation.aiwar.slots")
local E = WETSAND.Events

local ACTIVE_KEY = "wetsand.aiwar"

CreateConVar("mp_aiwar_team_size", tostring(AiWar.TEAM_SIZE_DEFAULT), { FCVAR_ARCHIVE, FCVAR_REPLICATED },
	"Soldiers each side of the AI war keeps in the field; -1: each side's own slots, as the AI War panel's slot list "
		.. "(mp_aiwar_slots_*) edits them", Slots.CUSTOM_SIZE, AiWar.TEAM_SIZE_MAX)
-- Replicated, so the Debug NextSoldier panel (wetsand/cl_ns_debug.lua)
-- shows whether it is on.
CreateConVar("wetsand_aiwar_debug_full", "0", { FCVAR_ARCHIVE, FCVAR_REPLICATED },
	"Show each soldier's whole action stack (the monitors too) in the AI war overlay and report")

function WETSAND.AiWarActive()
	return GetGlobal2Bool(ACTIVE_KEY, false)
end

local SLOT_TEAM_COUNT_BITS = 2
local SLOT_INDEX_BITS = 16 -- entity indexes

-- The slot list, to the admins whose AI War panel asked for it (and again
-- whenever it changes): whether it sets the sides' sizes (the team size is
-- Slots.CUSTOM_SIZE), and each team's faction and slots in order. A slot's
-- pin is leader, member or none; an empty slot's index is 0 and its texts
-- empty; squad names its soldier's fire team ("" for none), and leads says
-- whether it leads it.
E.Define("aiwar_slots", {
	custom = E.Bool(),
	teams = E.List(E.Record({
		team = E.Team(),
		faction = E.String(),
		slots = E.List(E.Record({
			id = E.UInt(Slots.ID_BITS),
			pin = E.String(),
			index = E.UInt(SLOT_INDEX_BITS),
			class = E.String(),
			role = E.String(),
			squad = E.String(),
			leads = E.Bool(),
		}), Slots.COUNT_BITS),
	}), SLOT_TEAM_COUNT_BITS),
})

-- An admin's AI War panel asks for the slot list.
E.Define("aiwar_slots_request", {}, {
	clientSendable = true,
	rate = {
		count = 4,
		seconds = 10,
	},
})

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

	-- The slot list's edits, for admins: each runs the aiwar controller's,
	-- which says how it went, in the caller's console.
	local function SlotCommand(name, run, help)
		concommand.Add(name, function(ply, _, args)
			if IsValid(ply) and not ply:IsAdmin() then
				Tell(ply, "AI war: only admins can change the slots")
				return
			end
			for _, line in ipairs(run(WETSAND.Feature("aiwar"), args)) do
				if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, line) else print(line) end
			end
		end, nil, help)
	end

	-- The ids a command names, or nil after saying it named none.
	local function Ids(command, args)
		local ids, bad = Slots.ParseIds(args)
		if ids == nil then return nil, { string.format("%s: '%s' is no slot id; give the slots' ids (mp_aiwar_slots_print)", command, bad) } end
		return ids
	end

	SlotCommand("mp_aiwar_slots_add", function(war, args)
		local team = args[1] and Slots.ParseTeam(args[1])
		if team == nil then return { "mp_aiwar_slots_add: RED or BLU" } end
		return war:AddSlot(team)
	end, "Add a slot for RED's or BLU's faction (RED or BLU); the team size becomes -1, each side's own slots")

	SlotCommand("mp_aiwar_slots_remove", function(war, args)
		local ids, told = Ids("mp_aiwar_slots_remove", args)
		if ids == nil then return told end
		return war:RemoveSlots(ids)
	end, "Remove slots by id, and their soldiers; the team size becomes -1, each side's own slots")

	local PINS = {
		mp_aiwar_slots_leader = {
			pin = Slots.LEADER,
			help = "Pin slots by id to lead: their soldiers lead their squads",
		},
		mp_aiwar_slots_member = {
			pin = Slots.MEMBER,
			help = "Pin slots by id to follow: their soldiers never lead while another is in their squad",
		},
		mp_aiwar_slots_unpin = {
			pin = nil,
			help = "Unpin slots by id: their soldiers lead as heroes and the longest serving do",
		},
	}
	for name, pinning in pairs(PINS) do
		SlotCommand(name, function(war, args)
			local ids, told = Ids(name, args)
			if ids == nil then return told end
			return war:PinSlots(name, ids, pinning.pin)
		end, pinning.help)
	end

	SlotCommand("mp_aiwar_slots_print", function(war)
		return war:SlotReport()
	end, "Print each side's slots: their ids, pins and soldiers")

	E.Listen("aiwar_slots_request", "wetsand_aiwar", function(_, ply)
		if ply:IsAdmin() then WETSAND.Feature("aiwar"):WatchSlots(ply) end
	end)

	-- A tick after the map loads, once the gamemode has put it in its mode
	-- (its own InitPostEntity); a map the war cannot be fought on says why
	-- in the server console.
	local AUTOSTART = CreateConVar("mp_aiwar_autostart", "0", FCVAR_ARCHIVE,
		"1: start the AI war on every map as it loads, as mp_aiwar_start does", 0, 1)
	hook.Add("InitPostEntity", "wetsand_aiwar_autostart", function()
		timer.Simple(0, function()
			if not AUTOSTART:GetBool() or WETSAND.AiWarActive() then return end
			local war = WETSAND.Feature("aiwar")
			local ok, why = war:Start()
			if not ok then print("AI war: not started on its own: " .. why) end
		end)
	end)
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
	WETSAND.ServerSlider(panel, "Soldiers per side (-1: the slot list's)", "mp_aiwar_team_size")
	WETSAND.AiWarSlotList(panel)
	panel:NumSlider("Ragdolls fade after (s, 0: never)", "cl_npc_ragdoll_lifetime", 0, 120, 0)
	panel:NumSlider("Most ragdolls kept", "g_ragdoll_maxcount", 0, 64, 0)
	panel:Help("Debugging the soldiers (overlays, reports, tuning): Utilities > Sandcastle > Debug NextSoldier.")
end

hook.Add("PopulateToolMenu", "wetsand_aiwar", function()
	spawnmenu.AddToolMenuOption("Utilities", "Sandcastle", "wetsand_aiwar", "AI War", "", "", BuildPanel)
end)
