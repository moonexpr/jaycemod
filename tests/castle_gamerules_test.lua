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
			round_manager = { State = function () return realm.round end },
			cvars = { AddChangeCallback = function (name, fn) realm.callbacks [name] = fn end },
			hook = { Add = function (event, _, fn) realm.hooks [event] = fn end },
			ents =
			{
				Create = function ()
					realm.made = realm.made + 1
					return Spawned ()
				end,
				FindByClass = function ()
					realm.finds = (realm.finds or 0) + 1
					local found = {}
					for _, ent in ipairs (realm.entities) do
						if ent.valid then found [#found + 1] = ent end
					end
					return found
				end
			}
		}, { __index = _G })
	env.ENT, env.GM = class, {}
	setfenv (assert (loadfile (ENTITY)), env) ()
	setfenv (assert (loadfile (GAMEMODE_FILE)), env) ()
	realm.gm, realm.class, realm.Spawned = env.GM, class, Spawned
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

T.finish ()
