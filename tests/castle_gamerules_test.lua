-- castle_gamerules: the entity that represents the mode and the round to
-- the world, and the gamemode's side of it (gamemode/castle_gamerules.lua):
-- one a map, made when asked for, restated whenever it had to be made again.
local T = dofile ("tests/harness.lua")

NULL = NULL or {}

local ENTITY = "addons/sandcastle/gamemodes/sandcastle/entities/entities/castle_gamerules.lua"
local GAMEMODE_FILE = "addons/sandcastle/gamemodes/sandcastle/gamemode/castle_gamerules.lua"
local WAITING, PREPARE, ACTIVE, OVER = 0, 1, 2, 3
local TRANSMIT = "always"

-- A realm: its entities of the class, the gamemode's two truths on the
-- server (the operator's switch and round_manager's round), and the hooks.
local function Realm (server)
	local realm = { gameplay = false, round = WAITING, made = 0, entities = {}, hooks = {}, callbacks = {} }
	realm.companions, realm.commands, realm.outcomes = {}, {}, {}
	local class = {}
	local env
	local function Spawned ()
		local ent = setmetatable ({ valid = true }, { __index = class })
		function ent:NetworkVar (_, _, name)
			self ["Get" .. name] = function (e) return e ["nw" .. name] end
			self ["Set" .. name] = function (e, value) e ["nw" .. name] = value end
		end
		function ent:Spawn () self:SetupDataTables () if server then self:Initialize () end end
		function ent:SetNoDraw () end
		function ent:DrawShadow () end
		function ent:SetSolid () end
		function ent:SetMoveType () end
		function ent:StoreOutput (name) self.stored [#self.stored + 1] = name end
		function ent:TriggerOutput (name) realm.outputs [#realm.outputs + 1] = name end
		ent.stored = {}
		realm.entities [#realm.entities + 1] = ent
		return ent
	end
	env = setmetatable (
		{
			SERVER = server,
			CLIENT = not server,
			NULL = NULL,
			ROUND_WAITING = WAITING,
			TRANSMIT_ALWAYS = TRANSMIT,
			AddCSLuaFile = function () end,
			IsValid = function (ent) return ent ~= nil and ent.valid == true end,
			GetConVar = function () return { GetBool = function () return realm.gameplay end } end,
			round_manager =
			{
				State = function () return realm.round end,
				RoundOutcome = function (outcome) realm.outcomes [#realm.outcomes + 1] = outcome end
			},
			RunConsoleCommand = function (...) realm.commands [#realm.commands + 1] = table.concat ({ ... }, " ") end,
			cvars = { AddChangeCallback = function (name, fn) realm.callbacks [name] = fn end },
			hook = { Add = function (event, _, fn) realm.hooks [event] = fn end },
			ents =
			{
				Create = function ()
					realm.made = realm.made + 1
					return Spawned ()
				end,
				FindByClass = function (class)
					realm.finds = (realm.finds or 0) + 1
					local found = {}
					for _, ent in ipairs (realm.entities) do
						if ent.valid then found [#found + 1] = ent end
					end
					if class == "*_gamerules" then
						for _, ent in ipairs (realm.companions) do found [#found + 1] = ent end
					end
					return found
				end
			}
		}, { __index = _G })
	env.ENT, env.GM = class, { IsGameplay = function () return realm.gameplay end }
	realm.outputs = {}
	setfenv (assert (loadfile (ENTITY)), env) ()
	setfenv (assert (loadfile (GAMEMODE_FILE)), env) ()
	realm.gm, realm.class, realm.Spawned = env.GM, class, Spawned
	-- One the map has, with these keyvalues.
	function realm.Placed (kv)
		local ent = Spawned ()
		for key, value in pairs (kv) do ent:KeyValue (key, value) end
		ent:Spawn ()
		return ent
	end
	function realm:Outputs ()
		local fired = table.concat (self.outputs, ",")
		self.outputs = {}
		return fired
	end
	return realm
end

T.test ("on the server there is none until the map's entities are up, then one, made when asked for", function ()
	local server = Realm (true)
	T.eq (server.gm:GameRules (),     NULL,    "none while the map loads")
	T.eq (server.gm:GetRoundState (), WAITING, "no round then")
	T.eq (server.made,                0,       "nothing made")
	server.hooks.InitPostEntity ()
	local rules = server.gm:GameRules ()
	T.eq (rules.valid,                  true,     "made")
	T.eq (server.gm:GameRules (),       rules,    "the same one each time")
	T.eq (server.made,                  1,        "once")
	T.eq (rules:UpdateTransmitState (), TRANSMIT, "every client has it")
end)

T.test ("it starts as the mode and the round are, and follows them", function ()
	local server = Realm (true)
	server.gameplay, server.round = true, ACTIVE
	server.hooks.InitPostEntity ()
	local rules = server.gm:GameRules ()
	T.eq (rules:GetGameplay (),       true,   "gameplay mode")
	T.eq (rules:GetRoundState (),     ACTIVE, "the round on")
	T.eq (server.gm:GetRoundState (), ACTIVE, "the gamemode's answer is its")
	server.round = OVER
	server.gm:OnRoundStateChanged (OVER)
	T.eq (rules:GetRoundState (), OVER, "the round's change")
	server.gameplay = false
	server.callbacks.sandcastle_gameplay ()
	T.eq (rules:GetGameplay (), false, "the operator's switch")
end)

T.test ("a map cleaned up under it: the next one asked for is as the mode and the round are now", function ()
	local server = Realm (true)
	server.gameplay, server.round = true, PREPARE
	server.hooks.InitPostEntity ()
	local old = server.gm:GameRules ()
	old.valid = false
	server.round = ACTIVE
	local new = server.gm:GameRules ()
	T.eq (new ~= old,           true,   "another")
	T.eq (new:GetGameplay (),   true,   "the mode")
	T.eq (new:GetRoundState (), ACTIVE, "the round as it is now")
	T.eq (server.made,          2,      "made again once")
end)

T.test ("a round changing with none there makes one", function ()
	local server = Realm (true)
	server.hooks.InitPostEntity ()
	server.round = PREPARE
	server.gm:OnRoundStateChanged (PREPARE)
	T.eq (server.made,                1,       "made")
	T.eq (server.gm:GetRoundState (), PREPARE, "with the round")
end)

T.test ("a client reads the one the server sent, found once, and sandbox with no round until it comes", function ()
	local client = Realm (false)
	T.eq (client.gm:GameRules (),     NULL,    "not here yet")
	T.eq (client.gm:GetRoundState (), WAITING, "no round")
	T.eq (client.made,                0,       "a client makes none")
	local sent = client.Spawned ()
	sent:SetupDataTables ()
	sent:SetGameplay (true)
	sent:SetRoundState (ACTIVE)
	T.eq (client.gm:GameRules (),     sent,   "the server's")
	T.eq (client.gm:GetRoundState (), ACTIVE, "its round")
	local finds = client.finds
	client.gm:GameRules ()
	client.gm:GetRoundState ()
	T.eq (client.finds, finds, "not searched for again while it is there")
	sent.valid = false
	T.eq (client.gm:GetRoundState (), WAITING, "gone with a cleanup: no round until the next comes")
end)

-- A companion to a map's other gamerules ------------------------------------------------

local RED, BLUE = TEAM_RED, TEAM_BLUE

T.test ("a map's own is the one used, with what the map set on it", function ()
	local server = Realm (true)
	local placed = server.Placed (
		{
			spawnmenu = "1",
			spawnflags = "6",
			team_scramble = "1",
			team_balance = "0",
			max_wins = "2",
			max_rounds = "5",
			max_win_difference = "0",
			observer_point = "overview",
			spectator_free_roam = "1",
			OnGameStart = "relay,Trigger,,0,-1"
		}
	)
	server.hooks.InitPostEntity ()
	local rules = server.gm:GameRules ()
	T.eq (rules,                         placed,        "the map's")
	T.eq (server.made,                   0,             "none made beside it")
	T.eq (rules.stored [1],              "OnGameStart", "its outputs kept")
	T.eq (rules:GetSpawnMenu (),         1,             "the spawn menu allowed")
	T.eq (rules:GetSpawnDisabled (),     6,             "but for weapons and NPCs")
	T.eq (rules:GetTeamScramble (),      true,          "teams scrambled")
	T.eq (rules:GetTeamBalance (),       false,         "not balanced")
	T.eq (rules:GetMaxWins (),           2,             "wins a team needs")
	T.eq (rules:GetMaxRounds (),         5,             "rounds in all")
	T.eq (rules:GetMaxWinDifference (),  0,             "no lead that ends it")
	T.eq (rules:GetObserverPoint (),     "overview",    "where a player first looks from")
	T.eq (rules:GetSpectatorFreeRoam (), true,          "spectators roam")
end)

T.test ("one the map set nothing on leaves every choice to the gamemode", function ()
	local server = Realm (true)
	server.hooks.InitPostEntity ()
	local rules = server.gm:GameRules ()
	T.eq (rules:GetSpawnMenu (),         -1,    "the spawn menu by the mode")
	T.eq (rules:GetSpawnDisabled (),     0,     "nothing disabled")
	T.eq (rules:GetTeamScramble (),      false, "no scramble")
	T.eq (rules:GetTeamBalance (),       false, "no balance")
	T.eq (rules:GetMaxWins (),           0,     "no wins suggested")
	T.eq (rules:GetObserverPoint (),     "",    "no observation point")
	T.eq (rules:GetSpectatorFreeRoam (), false, "no free roam")
	T.eq (server.gm:MatchLimits ().wins, nil,   "so the match's wins are mp_winlimit's")
end)

T.test ("the match's limits are what the map suggests", function ()
	local server = Realm (true)
	server.Placed ({ max_wins = "2", max_rounds = "5", max_win_difference = "0" })
	server.hooks.InitPostEntity ()
	local limits = server.gm:MatchLimits ()
	T.eq (limits.wins,       2,   "wins")
	T.eq (limits.rounds,     5,   "rounds")
	T.eq (limits.difference, nil, "0 suggests nothing")
end)

T.test ("each of the match's events fires its output", function ()
	local server = Realm (true)
	server.hooks.InitPostEntity ()
	local rules = server.gm:GameRules ()
	for _, event in ipairs (
		{
			"PreStart", "PreEnd", "SetupStart", "SetupEnd", "GameStart", "RoundStart", "RoundEnd",
			"TieBreakStart", "TieBreakEnd", "GameDone"
		}
	) do
		rules:MatchEvent (event)
		T.eq (server:Outputs (), "On" .. event, event)
	end
	rules:MatchEvent ("WinTeam", RED)
	T.eq (server:Outputs (), "OnWinTeam1", "RED's match")
	rules:MatchEvent ("WinTeam", BLUE)
	T.eq (server:Outputs (), "OnWinTeam2", "BLU's match")
end)

T.test ("it hears of the match first, then a map's other gamerules do", function ()
	local server = Realm (true)
	server.hooks.InitPostEntity ()
	local heard = {}
	server.companions [1] =
	{
		valid = true,
		MatchEvent = function (_, event, team)
			heard [#heard + 1] = { event = event, team = team, after = #server.outputs }
		end
	}
	server.companions [2] = { valid = true } -- gamerules that take no match events
	server.gm:MatchEvent ("WinTeam", BLUE)
	T.eq (server:Outputs (), "OnWinTeam2", "castle_gamerules' output")
	T.eq (#heard,            1,            "the companion told once")
	T.eq (heard [1].event,   "WinTeam",    "the event")
	T.eq (heard [1].team,    BLUE,         "and its team")
	T.eq (heard [1].after,   1,            "after castle_gamerules fired its own")
end)

T.test ("the spawn menu goes by the mode unless the map says, and a map may disable kinds", function ()
	local sandbox = Realm (true)
	sandbox.hooks.InitPostEntity ()
	T.eq (sandbox.gm:SpawnAllowed ("props"), true, "sandbox: allowed")
	sandbox.gameplay = true
	T.eq (sandbox.gm:SpawnAllowed ("props"), false, "gameplay: not")
	local allowed = Realm (true)
	allowed.gameplay = true
	allowed.Placed ({ spawnmenu = "1", spawnflags = "6" })
	allowed.hooks.InitPostEntity ()
	T.eq (allowed.gm:SpawnAllowed (),          true,  "the map allows it in gameplay")
	T.eq (allowed.gm:SpawnAllowed ("props"),   true,  "props")
	T.eq (allowed.gm:SpawnAllowed ("weapons"), false, "weapons disabled")
	T.eq (allowed.gm:SpawnAllowed ("npcs"),    false, "NPCs disabled")
	local refused = Realm (true)
	refused.Placed ({ spawnmenu = "0" })
	refused.hooks.InitPostEntity ()
	T.eq (refused.gm:SpawnAllowed ("props"),                        false, "the map refuses it in sandbox")
	T.eq (pcall (refused.gm.SpawnAllowed, refused.gm, "furniture"), false, "an unknown kind is our mistake")
end)

T.test ("a kind is disabled only by the map's word: its flag, or the spawn menu refused", function ()
	local plain = Realm (true)
	plain.gameplay = true
	plain.hooks.InitPostEntity ()
	T.eq (plain.gm:SpawnDisabled ("npcs"), false, "gameplay alone disables no kind: a mode makes its own NPCs")
	local flagged = Realm (true)
	flagged.Placed ({ spawnflags = "4" })
	flagged.hooks.InitPostEntity ()
	T.eq (flagged.gm:SpawnDisabled ("npcs"),     true,  "NPCs flagged")
	T.eq (flagged.gm:SpawnDisabled ("vehicles"), false, "vehicles not")
	local refused = Realm (true)
	refused.Placed ({ spawnmenu = "0" })
	refused.hooks.InitPostEntity ()
	T.eq (refused.gm:SpawnDisabled ("vehicles"),                     true,  "the menu refused: every kind")
	T.eq (pcall (refused.gm.SpawnDisabled, refused.gm, "furniture"), false, "an unknown kind is our mistake")
end)

T.test ("its inputs change the mode and close the round", function ()
	local server = Realm (true)
	server.hooks.InitPostEntity ()
	local rules = server.gm:GameRules ()
	T.eq (rules:AcceptInput ("SetGameplay", nil, nil, "1"), true,                    "SetGameplay taken")
	T.eq (server.commands [1],                              "sandcastle_gameplay 1", "the operator's switch")
	rules:AcceptInput ("RoundWin", nil, nil, tostring (BLUE))
	T.eq (server.outcomes [1].team, BLUE, "the round to BLU")
	rules:AcceptInput ("RoundStalemate")
	T.eq (server.outcomes [2].team,   nil,   "a stalemate")
	T.eq (rules:AcceptInput ("Kill"), false, "any other is the engine's")
end)

T.finish ()
