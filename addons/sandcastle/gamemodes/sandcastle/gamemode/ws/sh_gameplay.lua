-- The Gameplay Settings: the gamemode's Sandbox or Gameplay mode
-- (foundation.gamemode, run by features/gamemode). sv_gameplay_enabled
-- holds it, replicated for the menu and HUD; an admin setting it in the
-- server console, or pressing Begin Game or Stop Game (mp_gameplay_begin,
-- mp_gameplay_stop: clients cannot set a server setting), requests the
-- change. sv_gameplay_disable_sandbox keeps anything from entering Sandbox
-- mode. On a map with rounds the feature loads at map start and puts the map
-- in the mode the setting holds. The server keeps the map's Gameplay
-- Settings entity (ws_gameplay_settings: the round timer, respawn
-- times, win conditions and team scores). On clients: the Utilities menu's
-- Admin > Gameplay Settings, the modes and those settings, and a note on the
-- HUD in Sandbox mode.
local Gamemode = WS.require("foundation.gamemode")
local Permissions = WS.require("foundation.permissions")

local SETTINGS = "ws_gameplay_settings"

local ENABLED = CreateConVar("sv_gameplay_enabled", "0", { FCVAR_REPLICATED, FCVAR_NOTIFY },
	"1: Gameplay mode, the rounds run; 0: Sandbox mode, no rounds and spawn doors open. "
		.. "Setting it requests the change: 1 counts down to Gameplay mode.", 0, 1)

-- The gamemode feature's game events (features/gamemode/sv.lua fires
-- them): a title and lines for every player's chat (a new game's
-- description, a request's story), and the transition to Gameplay mode
-- called off, with the sounds it had played for the clients to silence.
local E = WS.Events
local COUNT_BITS = 8

E.Define("game_gameplay_chat", {
	title = E.String(),
	lines = E.List(E.String(), COUNT_BITS),
})
E.Define("game_gameplay_transition_cancelled", {
	sounds = E.List(E.String(), COUNT_BITS),
})

if SERVER then
	CreateConVar("sv_gameplay_disable_sandbox", "0", FCVAR_NOTIFY,
		"1: nothing enters Sandbox mode (Stop Game, sv_gameplay_enabled 0)", 0, 1)

	local function Command(name, want, help)
		concommand.Add(name, function(ply)
			if not WS.Can(ply, Permissions.MATCH) then
				ply:ChatPrint("Gameplay: you may not do that")
				return
			end
			WS.Feature("gamemode"):Request(want, Gamemode.SOURCE_BUTTON, ply)
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

	-- Kept in WS across a Lua refresh: whether the map has loaded. The
	-- rounds controller applies the mode (StartAtLoad) once its rules exist.
	hook.Add("InitPostEntity", "ws_gamemode", function()
		WS.gamemodeLoaded = true
	end)

	-- One settings entity a map, made again when a cleanup removes it.
	local function KeepSettings()
		if IsValid(ents.FindByClass(SETTINGS)[1]) then return end
		ents.Create(SETTINGS):Spawn()
	end
	hook.Add("InitPostEntity", "ws_gameplay_settings", KeepSettings)
	hook.Add("PostCleanupMap", "ws_gameplay_settings", KeepSettings)

	-- Before the map has loaded (server.cfg) a change only sets the mode the map starts in.
	cvars.AddChangeCallback(ENABLED:GetName(), function(_, _, value)
		if not WS.gamemodeLoaded then return end
		WS.Feature("gamemode"):SettingChanged(tobool(value), ConsoleRequester())
	end, "ws_gamemode")
	return
end

local HELP = "Sandcastle plays in Sandbox mode or Gameplay mode (sv_gameplay_enabled). "
	.. "Sandbox mode has no rounds and pauses the timer: the map plays like Sandbox, "
	.. "with spawn doors and forcefields open to everyone. Begin Game announces a new game, "
	.. "counts down from " .. Gamemode.COUNTDOWN .. ", clears the scores, restarts the rounds and sends everyone "
	.. "back to the team menu, without a team, until they choose one. Stop Game returns to Sandbox mode, "
	.. "unless sv_gameplay_disable_sandbox is 1."

local PROPERTIES_TALL = 420

local function BuildPanel(panel)
	panel:ClearControls()
	panel:Help(HELP)
	local status = panel:Help("")
	function status:Think()
		local text
		if not WS.Active() then
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
	-- the settings entity's fields, admins' to edit; it arrives with the map,
	-- and again after a cleanup
	local settings = vgui.Create("DEntityProperties", panel)
	settings:SetTall(PROPERTIES_TALL)
	panel:AddItem(settings)
	function settings:Think()
		local ent = ents.FindByClass(SETTINGS)[1]
		if IsValid(ent) then self:SetEntity(ent) end
	end
end

-- A new game's description in chat: the title in gold, the objectives in white.
local TITLE_COLOR, LINE_COLOR = Color(255, 205, 80), Color(235, 235, 235)

E.Listen("game_gameplay_chat", "ws_gameplay", function(fields)
	chat.AddText(TITLE_COLOR, fields.title)
	for _, line in ipairs(fields.lines) do chat.AddText(LINE_COLOR, line) end
end)

-- A countdown called off: silence what it played.
E.Listen("game_gameplay_transition_cancelled", "ws_gameplay", function(fields)
	local ply = LocalPlayer()
	if not IsValid(ply) then return end
	for _, path in ipairs(fields.sounds) do ply:StopSound(path) end
end)

hook.Add("PopulateToolMenu", "ws_gameplay", function()
	spawnmenu.AddToolMenuOption("Utilities", "Admin", "ws_gameplay", "Gameplay Settings", "", "", BuildPanel)
end)

hook.Add("HUDPaint", "ws_gameplay", function()
	if not WS.Active() or ENABLED:GetBool() then return end
	draw.SimpleTextOutlined("Sandbox mode", "DermaLarge", ScrW() / 2, 24, color_white,
		TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 1, color_black)
end)
