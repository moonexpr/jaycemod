-- The game event library's realm adapter (docs/game-events.md): the
-- foundation.events registry carried on GMod's net library, as
-- WETSAND.Events. Every message between server and clients is an event, on
-- one of this file's two net messages; nothing else registers one.
--
--   Define(name, fields, options)   both realms, where the feature loads
--   Listen(name, id, fn), Ignore(name, id)   both realms; fn(fields[, ply])
--   Fire(name, fields, recipients)  server: its listeners, then the clients
--   Request(name, fields)           client: a client-sendable event to the server
--
-- and the field types (String, Bool, UInt(bits), Int(bits), Float, Entity,
-- Vector, Angle, Team, List(type, countBits), Record(fields), Optional(type),
-- Default(type, value)). Included by sh_core.lua, before anything that
-- defines an event.
local Events = WETSAND.require("foundation.events")

local FIRE_NET = "wetsand_game_event_fire" -- server to clients
local REQUEST_NET = "wetsand_game_event_request" -- client to server

-- A client says it is ready once, and may repeat it after a Lua refresh.
local CLIENT_READY_RATE = {
	count = 2,
	seconds = 10,
}

-- Kept across a Lua refresh: features define their events once, as they load.
WETSAND.EventRegistry = WETSAND.EventRegistry or Events.NewRegistry({
	entity = IsEntity,
	vector = isvector,
	angle = isangle,
})
local registry = WETSAND.EventRegistry

local API = {}
WETSAND.Events = API

for _, name in ipairs({ "String", "Bool", "UInt", "Int", "Float", "Entity", "Vector", "Angle", "Team", "List", "Record", "Optional", "Default" }) do
	API[name] = Events[name]
end

-- The core raises named errors (tables); GMod reports a string best, at
-- the line that called the API.
local function Checked(fn, ...)
	local ok, result = pcall(fn, ...)
	if not ok then error(tostring(result), 3) end
	return result
end

function API.Define(name, fields, options)
	Checked(registry.Define, registry, name, fields, options)
end

function API.Listen(name, id, fn)
	Checked(registry.Listen, registry, name, id, fn)
end

function API.Ignore(name, id)
	registry:Ignore(name, id)
end

-- Whether a player's client has loaded (its client_ready request): events
-- go only to ready clients, since net messages sent earlier are lost.
function WETSAND.IsReady(ply)
	return ply.wetsandReady == true
end

-- Sent by a client as it finishes loading (InitPostEntity); a fresh join and
-- a returning player alike.
API.Define("client_ready", {}, {
	clientSendable = true,
	rate = CLIENT_READY_RATE,
})

if SERVER then
	util.AddNetworkString(FIRE_NET)
	util.AddNetworkString(REQUEST_NET)

	local DEVELOPER = GetConVar("developer")

	local function Listed(list)
		local players = {}
		for _, ply in ipairs(list) do
			if IsValid(ply) and not ply:IsBot() and WETSAND.IsReady(ply) then players[#players + 1] = ply end
		end
		return players
	end

	-- recipients: nil for every player, a team number, a player, a list of
	-- players, or a Vector for the players whose PVS holds it.
	local function Recipients(recipients)
		if recipients == nil then return Listed(player.GetAll()) end
		if isnumber(recipients) then return Listed(team.GetPlayers(recipients)) end
		if isvector(recipients) then
			local filter = RecipientFilter()
			filter:AddPVS(recipients)
			return Listed(filter:GetPlayers())
		end
		if IsEntity(recipients) then return Listed({ recipients }) end
		return Listed(recipients)
	end

	-- The server's own listeners hear it first, then the ready clients among
	-- the recipients.
	function API.Fire(name, fields, recipients)
		local event = Checked(registry.Build, registry, name, fields or {})
		registry:Dispatch(event)
		local players = Recipients(recipients)
		if #players == 0 then return end
		net.Start(FIRE_NET, event.definition.unreliable)
		registry:Write(event, net)
		net.Send(players)
	end

	-- A request the model refuses is the client's mistake: dropped, and
	-- shown only with developer on.
	net.Receive(REQUEST_NET, function(_, ply)
		local event, refusal = registry:ReadRequest(ply, net, CurTime())
		if not event then
			if DEVELOPER:GetInt() > 0 then print(string.format("game event request from %s refused: %s", tostring(ply), tostring(refusal))) end
			return
		end
		registry:Dispatch(event, ply)
	end)

	API.Listen("client_ready", "wetsand_events", function(_, ply)
		ply.wetsandReady = true
	end)
else
	function API.Request(name, fields)
		local event = Checked(registry.BuildRequest, registry, name, fields or {})
		net.Start(REQUEST_NET, event.definition.unreliable)
		registry:Write(event, net)
		net.SendToServer()
	end

	-- An event this client has no definition of means the realms disagree:
	-- the error names its id.
	net.Receive(FIRE_NET, function()
		registry:Dispatch(Checked(registry.Read, registry, net))
	end)

	-- Whether this client has loaded: net messages reach it from
	-- InitPostEntity on.
	function WETSAND.LocalReady()
		return WETSAND.localReady == true
	end

	hook.Add("InitPostEntity", "wetsand_events", function()
		WETSAND.localReady = true
		API.Request("client_ready")
	end)
end
