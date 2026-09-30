-- The Gameplay Settings: the gamemode's Sandbox or Gameplay mode
-- (foundation.gamemode, run by features/gamemode). sv_gameplay_enabled
-- holds it, replicated for the menu and HUD; an admin setting it in the
-- server console, or pressing Begin Game or Stop Game (mp_gameplay_begin,
-- mp_gameplay_stop: clients cannot set a server setting), requests the
-- change. sv_gameplay_disable_sandbox keeps anything from entering Sandbox
-- mode. On a map with rounds the feature loads at map start and puts the map
-- in the mode the setting holds. On clients: the Utilities menu entry and a
-- note on the HUD in Sandbox mode.
local Gamemode = WETSAND.require("foundation.gamemode")

local ENABLED = CreateConVar("sv_gameplay_enabled", "0", { FCVAR_REPLICATED, FCVAR_NOTIFY },
	"1: Gameplay mode, the rounds run; 0: Sandbox mode, no rounds and spawn doors open. "
		.. "Setting it requests the change: 1 counts down to Gameplay mode.", 0, 1)

if SERVER then
	CreateConVar("sv_gameplay_disable_sandbox", "0", FCVAR_NOTIFY,
		"1: nothing enters Sandbox mode (Stop Game, sv_gameplay_enabled 0)", 0, 1)

	local function Command(name, want, help)
		concommand.Add(name, function(ply)
			if IsValid(ply) and not ply:IsAdmin() then
				ply:ChatPrint("Gameplay: only admins may do that")
				return
			end
			WETSAND.Feature("gamemode"):Request(want, Gamemode.SOURCE_BUTTON, ply)
		end, nil, help)
	end

	Command("mp_gameplay_begin", Gamemode.GAMEPLAY,
		"Begin Gameplay mode: a countdown, then the rounds restart and everyone chooses a team")
	Command("mp_gameplay_stop", Gamemode.SANDBOX, "Enter Sandbox mode: no rounds or timer, spawn doors open")

	-- Who changed a server setting from a console: the listen server's host,
	-- or nil for the server console (rcon, a dedicated server).
	local function ConsoleRequester()
		for _, ply in ipairs(player.GetHumans()) do
			if ply:IsListenServerHost() then return ply end
		end
	end

	-- Kept in WETSAND across a Lua refresh: whether the map has loaded.
	-- The mode is applied a tick after InitPostEntity: on koth_viaduct the
	-- rules were not yet valid at InitPostEntity itself, and the map ran its
	-- rounds in Sandbox mode. rulesAtLoad records what each moment saw.
	hook.Add("InitPostEntity", "wetsand_gamemode", function()
		WETSAND.gamemodeLoaded = true
		WETSAND.rulesAtLoad = { initPostEntity = IsValid(WETSAND.Rules) }
		timer.Simple(0, function()
			WETSAND.rulesAtLoad.nextTick = IsValid(WETSAND.Rules)
			if IsValid(WETSAND.Rules) then WETSAND.Feature("gamemode"):StartAtLoad() end
		end)
	end)

	-- Before the map has loaded (server.cfg) a change only sets the mode the map starts in.
	cvars.AddChangeCallback(ENABLED:GetName(), function(_, _, value)
		if not WETSAND.gamemodeLoaded then return end
		WETSAND.Feature("gamemode"):SettingChanged(tobool(value), ConsoleRequester())
	end, "wetsand_gamemode")
	return
end

local HELP = "Sandcastle plays in Sandbox mode or Gameplay mode (sv_gameplay_enabled). "
	.. "Sandbox mode has no rounds and pauses the timer: the map plays like Sandbox, "
	.. "with spawn doors and forcefields open to everyone. Begin Game announces a new game, "
	.. "counts down from " .. Gamemode.COUNTDOWN .. ", clears the scores, restarts the rounds and sends everyone "
	.. "to the team menu as spectators until they choose a team. Stop Game returns to Sandbox mode, "
	.. "unless sv_gameplay_disable_sandbox is 1."

local function BuildPanel(panel)
	panel:ClearControls()
	panel:Help(HELP)
	local status = panel:Help("")
	function status:Think()
		local text
		if not WETSAND.Active() then
			text = "This map has no rounds (no tf_gamerules): Sandbox mode."
		elseif ENABLED:GetBool() then
			text = "Status: Gameplay mode"
		else
			text = "Status: Sandbox mode"
		end
		if self:GetText() ~= text then self:SetText(text) end
	end
	panel:Button("Begin Game", "mp_gameplay_begin")
	panel:Button("Stop Game", "mp_gameplay_stop")
end

-- A new game's description in chat: the title in gold, the objectives in white.
local TITLE_COLOR, LINE_COLOR = Color(255, 205, 80), Color(235, 235, 235)

net.Receive("wetsand_gameplay_chat", function()
	chat.AddText(TITLE_COLOR, net.ReadString())
	for _ = 1, net.ReadUInt(8) do chat.AddText(LINE_COLOR, net.ReadString()) end
end)

-- A countdown called off: silence what it played.
net.Receive("wetsand_gameplay_stop_sounds", function()
	local ply = LocalPlayer()
	for _ = 1, net.ReadUInt(8) do
		local path = net.ReadString()
		if IsValid(ply) then ply:StopSound(path) end
	end
end)

hook.Add("PopulateToolMenu", "wetsand_gameplay", function()
	spawnmenu.AddToolMenuOption("Utilities", "Sandcastle", "wetsand_gameplay", "Gameplay Settings", "", "", BuildPanel)
end)

hook.Add("HUDPaint", "wetsand_gameplay", function()
	if not WETSAND.Active() or ENABLED:GetBool() then return end
	draw.SimpleTextOutlined("Sandbox mode", "DermaLarge", ScrW() / 2, 24, color_white,
		TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 1, color_black)
end)
