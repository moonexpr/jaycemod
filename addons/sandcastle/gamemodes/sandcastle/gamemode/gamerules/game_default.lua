-- The base of the games: played nowhere, deciding nothing.
local GAME = {}

-- true: can settle a tie, and is only ever played as that bonus round.
GAME.bonus_suddendeath = false

-- The controller types a map must have for this game to be played
-- (GM:AddController); a game requiring none is played nowhere.
GAME.Requires = {}

function GAME:Applies ()
	if #self.Requires == 0 then return false end
	for _, kind in ipairs (self.Requires) do
		if not GAMEMODE:HasController (kind) then return false end
	end
	return true
end

-- On the server, each Think while the game is played.
function GAME:Think ()
end

-- On the server: an entity of the map added its controller.
function GAME:ControllerAdded (controller)
end

-- On the server: an entity of the map took an input. Whether the game used it.
function GAME:ControllerInput (ent, name, value, activator)
	return false
end

-- On the server, what happens in the round while the game is played.
function GAME:RoundPrepare ()
end

function GAME:RoundStart ()
end

-- winner: the team that won, or nil for a stalemate.
function GAME:RoundEnd (winner)
end

function GAME:PlayerDeath (victim, inflictor, attacker)
end

-- The team that has won the round, or nil while it goes on.
function GAME:RoundWinner ()
end

-- Adds this game's part of how near each team is to completing the objective.
function GAME:Standing (objective)
end

-- What this game asks of a map's entities (game_manager.GetCurrentScenario).
-- Every key is optional: an entity left unasked behaves as it would anywhere.
function GAME:GetRules ()
	return {}
end

-- On the server: round_manager's AddTeamScore. A game may end the round for
-- it, with round_manager.RoundOutcome. info: team, score, activator, event (what
-- for: "flag_capture", "round_win").
function GAME:TeamScored (info)
end

-- The vgui rendering this game's objectives, or nil for none. On the client.
function GAME:CreatePanel ()
end

-- A panel over the whole HUD, painted by draw( w, h ).
function GAME:ObjectivePanel (draw)

	local panel = vgui.Create ("Panel")
	panel:ParentToHUD ()
	panel:SetSize (ScrW (), ScrH ())
	panel:SetMouseInputEnabled (false)
	panel:SetKeyboardInputEnabled (false)
	function panel:OnScreenSizeChanged () self:SetSize (ScrW (), ScrH ()) end
	function panel:Paint (w, h) draw (w, h) end
	return panel

end

game_manager.RegisterClass ("game_default", GAME)
