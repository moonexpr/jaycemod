-- The Gameplay Settings: the admin commands that stop the game (non-gameplay
-- mode, played like Sandbox) and start a new one (features/gameplay), and
-- on clients the Utilities menu entry and a note on the HUD while stopped.
if SERVER then
	local function Command(name, method, help)
		concommand.Add(name, function(ply)
			if IsValid(ply) and not ply:IsAdmin() then
				ply:ChatPrint("Gameplay: only admins may do that")
				return
			end
			local gameplay = WETSAND.Feature("gameplay")
			local ok, why = gameplay[method](gameplay)
			if not ok then
				local text = "Gameplay: " .. why
				if IsValid(ply) then ply:ChatPrint(text) else print(text) end
			end
		end, nil, help)
	end

	Command("wetsand_game_stop", "Stop", "Stop the game: no rounds or timer, spawn doors open, free play like Sandbox")
	Command("wetsand_game_new", "StartNewGame",
		"Start a new game: a 12 second countdown, then everyone spectates and chooses a team")
	return
end

local HELP = "Stop Game ends the round system and pauses the timer: the map plays like Sandbox, "
	.. "with spawn doors and forcefields open to everyone. Start New Game announces a new game, "
	.. "counts down from 12, clears the scores, restarts the rounds and sends everyone to the team menu "
	.. "as spectators until they choose a team."

local function BuildPanel(panel)
	panel:ClearControls()
	panel:Help(HELP)
	local status = panel:Help("")
	function status:Think()
		local text
		if not WETSAND.Active() then
			text = "This map has no TF2 rounds."
		elseif WETSAND.GameplayStopped() then
			text = "Status: stopped (free play)"
		else
			text = "Status: running"
		end
		if self:GetText() ~= text then self:SetText(text) end
	end
	panel:Button("Stop Game", "wetsand_game_stop")
	panel:Button("Start New Game", "wetsand_game_new")
end

hook.Add("PopulateToolMenu", "wetsand_gameplay", function()
	spawnmenu.AddToolMenuOption("Utilities", "Sandcastle", "wetsand_gameplay", "Gameplay Settings", "", "", BuildPanel)
end)

hook.Add("HUDPaint", "wetsand_gameplay", function()
	if not WETSAND.GameplayStopped() then return end
	draw.SimpleTextOutlined("Free play: the game is stopped", "DermaLarge", ScrW() / 2, 24, color_white,
		TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 1, color_black)
end)
