-- hit_audit: how often a client's bullets hit what the server's did
-- (docs/net2.md). With the server's hit_audit 1, each client claims over net2
-- what its predicted shots hit; the server compares that with its own
-- trace of the same command, pellet by pellet, and counts the outcomes by
-- weapon. It changes no shot: the server's trace still decides.
--
--   hit_audit 0|1          server: audit players' bullets
--   hit_audit_print        server console: the counts by weapon
--   hit_audit_reset        server console: start the counts over
--   hit_audit_show 0|1     client: draw each disagreement of your own shots,
--                          yours in yellow and the server's in red (needs
--                          developer 1, as debugoverlay does)
--
-- A shot is the bullets of one player command, known on both realms by the
-- command's number. hit_audit.New(port) is the server's model over a port
-- (Now, Distance, Result), hit_audit.Shots(send) the client's.
local ipairs, pairs, setmetatable, type = ipairs, pairs, setmetatable, type
local max = math.max
module("hit_audit", package.seeall)

CLAIM = "hit_audit_claim" -- client to server: what a command's bullets hit
RESULT = "hit_audit_result" -- server to the shooter: a shot they disagreed on
CLAIM_RATE = {
	count = 66,
	seconds = 1,
}
HOLD_SECONDS = 2 -- how long one realm's shot waits for the other's
HELD = 64 -- shots held for one player, either realm's
PELLETS = 32 -- bullets of one command
WEAPON_BYTES = 64

AGREE, CLIENT_ONLY, SERVER_ONLY, DIFFERENT = "agree", "clientOnly", "serverOnly", "different"

local Audit = {}
Audit.__index = Audit

function New(port)
	return setmetatable({
		port = port,
		players = {},
		stats = {},
		unmatched = { server = 0, client = 0 },
	}, Audit)
end

function Audit:Stats()
	return self.stats
end

function Audit:Unmatched()
	return self.unmatched
end

function Audit:Reset()
	self.stats = {}
	self.unmatched = { server = 0, client = 0 }
end

function Audit:Forget(ply)
	self.players[ply] = nil
end

function Audit:Held(ply)
	local player = self.players[ply]

	return player and player.count or 0
end

-- A player's shots by command: { at, weapon, server = hits, client = hits }.
-- Past HELD the oldest goes, unmatched.
function Audit:Shot(ply, cmd)
	local player = self.players[ply]
	if not player then
		player = { shots = {}, order = {}, count = 0 }
		self.players[ply] = player
	end

	local shot = player.shots[cmd]
	if shot then return shot, player end

	if player.count >= HELD then self:Drop(player, player.order[1]) end
	shot = { at = self.port.Now() }
	player.shots[cmd] = shot
	player.order[#player.order + 1] = cmd
	player.count = player.count + 1

	return shot, player
end

function Audit:Drop(player, cmd, matched)
	local shot = player.shots[cmd]
	if not shot then return end

	if not matched then
		local side = shot.server and "server" or "client"
		self.unmatched[side] = self.unmatched[side] + 1
	end
	player.shots[cmd] = nil
	player.count = player.count - 1
	for i, other in ipairs(player.order) do
		if other == cmd then
			table.remove(player.order, i)

			break
		end
	end
end

local function outcomeOf(client, server)
	if client.ent == server.ent then return AGREE end
	if server.ent == nil then return CLIENT_ONLY end
	if client.ent == nil then return SERVER_ONLY end

	return DIFFERENT
end

function Audit:Compare(ply, player, cmd, shot)
	local stats = self.stats[shot.weapon]
	if not stats then
		stats = {
			shots = 0,
			pellets = 0,
			agree = 0,
			clientOnly = 0,
			serverOnly = 0,
			different = 0,
			count = 0, -- shots whose pellet counts differed
			worstError = 0, -- units between the two realms' hit positions, where they agreed
		}
		self.stats[shot.weapon] = stats
	end

	stats.shots = stats.shots + 1
	local client, server = shot.client, shot.server
	self:Drop(player, cmd, true)
	if #client ~= #server then
		stats.count = stats.count + 1

		return
	end

	local pellets, disagreed = {}, false
	for i, mine in ipairs(server) do
		local theirs = client[i]
		local outcome = outcomeOf(theirs, mine)
		stats.pellets = stats.pellets + 1
		stats[outcome] = stats[outcome] + 1
		if outcome == AGREE then
			stats.worstError = max(stats.worstError, self.port.Distance(theirs.pos, mine.pos))
		else
			disagreed = true
		end
		pellets[i] = { outcome = outcome, client = theirs.pos, server = mine.pos }
	end
	if disagreed then self.port.Result(ply, { cmd = cmd, weapon = shot.weapon, pellets = pellets }) end
end

-- One bullet of the server's, as it lands. ent: nil for the world or a miss.
function Audit:ServerHit(ply, cmd, weapon, ent, pos)
	local shot = self:Shot(ply, cmd)
	shot.weapon = weapon
	shot.server = shot.server or {}
	if #shot.server < PELLETS then shot.server[#shot.server + 1] = { ent = ent, pos = pos } end
end

local function validClaim(claim, isPosition)
	if type(claim) ~= "table" or type(claim.cmd) ~= "number" or type(claim.hits) ~= "table" then return false end
	if type(claim.weapon) ~= "string" or #claim.weapon > WEAPON_BYTES or #claim.hits > PELLETS then return false end

	for _, hit in ipairs(claim.hits) do
		if type(hit) ~= "table" or not isPosition(hit.pos) then return false end
	end

	return true
end

-- A client's word on one command's bullets: false when it is no claim. It is
-- compared at once when the server has fired that command, else at Think.
function Audit:Claim(ply, claim)
	local isPosition = self.port.IsPosition or function(pos) return type(pos) == "table" end
	if not validClaim(claim, isPosition) then return false end

	local player = self.players[ply]
	local known = player and player.shots[claim.cmd]
	if known and known.client then return false end

	local shot
	shot, player = self:Shot(ply, claim.cmd)
	shot.client = claim.hits
	if shot.server then self:Compare(ply, player, claim.cmd, shot) end

	return true
end

-- Each tick: shots both realms have told of are compared (the server's
-- bullets of a command are all in by then), and old ones let go.
function Audit:Think()
	local now = self.port.Now()
	for ply, player in pairs(self.players) do
		for _, cmd in ipairs({ unpack(player.order) }) do
			local shot = player.shots[cmd]
			if shot.client and shot.server then
				self:Compare(ply, player, cmd, shot)
			elseif now - shot.at > HOLD_SECONDS then
				self:Drop(player, cmd)
			end
		end
	end
end

-- The client's side: a command's bullets gathered as they land, claimed
-- together at Flush (send(claim)).
local Gathered = {}
Gathered.__index = Gathered

function Shots(send)
	return setmetatable({ send = send, shots = {}, order = {} }, Gathered)
end

function Gathered:Hit(cmd, weapon, ent, pos)
	local shot = self.shots[cmd]
	if not shot then
		shot = { cmd = cmd, weapon = weapon, hits = {} }
		self.shots[cmd] = shot
		self.order[#self.order + 1] = cmd
	end
	if #shot.hits < PELLETS then shot.hits[#shot.hits + 1] = { ent = ent, pos = pos } end
end

function Gathered:Flush()
	local order, shots = self.order, self.shots
	if #order == 0 then return end

	self.order, self.shots = {}, {}
	for _, cmd in ipairs(order) do self.send(shots[cmd]) end
end

-- GMod

-- What a bullet hit, for the audit: an entity, or nil for the world or a miss.
local function hitEntity(trace)
	local ent = trace.Entity
	if not IsValid(ent) or ent:IsWorld() then return nil end

	return ent
end

local function weaponClass(ply)
	local weapon = ply:GetActiveWeapon()

	return IsValid(weapon) and weapon:GetClass() or "none"
end

-- The number of the command being run, the same on both realms: nil outside one.
local function commandNumber(ply)
	local command = ply:GetCurrentCommand()

	return command and command:CommandNumber() or nil
end

local function installServer(enabled)
	local audit = New({
		Now = CurTime,
		Distance = function(a, b) return a:Distance(b) end,
		IsPosition = isvector,
		Result = function(ply, result)
			if ply:GetInfoNum("hit_audit_show", 0) ~= 0 then net2.Send(RESULT, result, { to = ply }) end
		end,
	})
	current = audit
	net2.Accept(CLAIM, CLAIM_RATE)
	net2.Receive(CLAIM, function(claim, ply)
		if enabled:GetBool() then audit:Claim(ply, claim) end
	end)

	hook.Add("PostEntityFireBullets", "sandcastle/hit-audit/record-shot", function(ent, data)
		if not enabled:GetBool() or not ent:IsPlayer() or ent:IsBot() then return end

		local cmd = commandNumber(ent)
		if cmd then audit:ServerHit(ent, cmd, weaponClass(ent), hitEntity(data.Trace), data.Trace.HitPos) end
	end)
	hook.Add("Tick", "sandcastle/hit-audit/compare", function()
		if enabled:GetBool() then audit:Think() end
	end)
	hook.Add("PlayerDisconnected", "sandcastle/hit-audit/forget-player", function(ply) audit:Forget(ply) end)

	local line = "%-28s shots %6d  pellets %6d  agree %6d  client only %5d  server only %5d  different %5d"
		.. "  count %4d  worst error %6.1f"
	concommand.Add("hit_audit_print", function(ply)
		if IsValid(ply) and not ply:IsSuperAdmin() then return end

		for weapon, s in SortedPairs(audit:Stats()) do
			MsgN(string.format(line, weapon, s.shots, s.pellets, s.agree, s.clientOnly, s.serverOnly, s.different,
				s.count, s.worstError))
		end
		MsgN("unmatched: server ", audit:Unmatched().server, ", client ", audit:Unmatched().client)
	end, nil, "hit_audit: how the clients' shots compared with the server's, by weapon")
	concommand.Add("hit_audit_reset", function(ply)
		if IsValid(ply) and not ply:IsSuperAdmin() then return end

		audit:Reset()
	end, nil, "hit_audit: start the counts over")
end

local SHOW_SECONDS = 4
local CROSS_SIZE = 4

local function installClient(enabled)
	local CLIENT_COLOR = Color(255, 220, 0)
	local SERVER_COLOR = Color(255, 40, 40)
	CreateClientConVar("hit_audit_show", "0", true, true, "hit_audit: draw each disagreement of your own shots")
	local shots = Shots(function(claim) net2.Send(CLAIM, claim) end)

	hook.Add("PostEntityFireBullets", "sandcastle/hit-audit/record-shot", function(ent, data)
		if not enabled:GetBool() or ent ~= LocalPlayer() or not IsFirstTimePredicted() then return end

		local cmd = commandNumber(ent)
		if cmd then shots:Hit(cmd, weaponClass(ent), hitEntity(data.Trace), data.Trace.HitPos) end
	end)
	hook.Add("Tick", "sandcastle/hit-audit/claim-shots", function() shots:Flush() end)

	net2.Receive(RESULT, function(result)
		for _, pellet in ipairs(result.pellets or {}) do
			local disagreed = pellet.outcome ~= AGREE and isvector(pellet.client) and isvector(pellet.server)
			if disagreed then
				debugoverlay.Cross(pellet.client, CROSS_SIZE, SHOW_SECONDS, CLIENT_COLOR, true)
				debugoverlay.Cross(pellet.server, CROSS_SIZE, SHOW_SECONDS, SERVER_COLOR, true)
				debugoverlay.Line(pellet.client, pellet.server, SHOW_SECONDS, SERVER_COLOR, true)
				debugoverlay.Text(pellet.server, tostring(pellet.outcome), SHOW_SECONDS)
			end
		end
	end)
end

if SERVER or CLIENT then
	local help = "1: compare each client's bullets with the server's"
	local enabled = CreateConVar("hit_audit", "0", FCVAR_REPLICATED, help)
	if SERVER then installServer(enabled) else installClient(enabled) end
end
