-- Server-side world helpers shared by the TF2 entities.

-- CTeamplayRoundBasedRules::BroadcastSound: a game sound every player of a
-- team hears as their own (announcer lines, win/lose music). Team 0 is
-- everyone. Each client decides whether it hears it (wetsand/sh_announcer.lua).
function WETSAND.BroadcastSound(team, name)
	WETSAND.Events.Fire("teamplay_broadcast_audio", {
		team = team,
		sound = name,
	})
end

-- A game sound every player not on the team hears as their own
-- (CLocalPlayerFilter lines: the capture's lines for the other team).
function WETSAND.BroadcastSoundToOthers(team, name)
	WETSAND.Events.Fire("teamplay_broadcast_audio", {
		team = team,
		sound = name,
		others = true,
	})
end

-- A game sound from an entity that only one player hears
-- (CSingleUserRecipientFilter): pickup and resupply sounds.
function WETSAND.PlaySoundTo(ply, ent, name)
	local filter = RecipientFilter()
	filter:AddPlayer(ply)
	ent:EmitSound(name, 75, 100, 1, CHAN_AUTO, 0, 0, filter)
end

-- Keyvalues of engine entities we read but do not implement. GMod exposes no
-- getter for a path_track's next node or a teamspawn's team, so they are
-- recorded as the map sets them.
WETSAND.KV = WETSAND.KV or setmetatable({}, { __mode = "k" })

local RECORDED = {
	path_track = true,
	info_player_teamspawn = true,
	team_control_point = true,
	-- the rounds feature fires its OnMultiNewRound, which GMod never does
	logic_auto = true,
}

-- logic_auto's "Remove on fire" (SF_AUTO_FIREONCE). Its outputs fire once
-- anyway (CLogicAuto::Think runs once), so the entity is kept for the rounds
-- feature to fire OnMultiNewRound at the first round, which in TF2 follows
-- the waiting-for-players restart that recreates it.
local LOGIC_AUTO_FIRE_ONCE = 1

-- Outputs are kept in map order in kv.outputs, since an output key may repeat.
hook.Add("EntityKeyValue", "wetsand_record_keyvalues", function(ent, key, value)
	if not RECORDED[ent:GetClass()] then return end
	if ent:GetClass() == "logic_auto" and string.lower(key) == "spawnflags" then
		return tostring(bit.band(tonumber(value) or 0, bit.bnot(LOGIC_AUTO_FIRE_ONCE)))
	end
	local kv = WETSAND.KV[ent]
	if not kv then
		kv = { outputs = {} }
		WETSAND.KV[ent] = kv
	end
	if string.sub(key, 1, 2) == "On" then
		kv.outputs[#kv.outputs + 1] = WETSAND.ParseOutput(key, value)
	else
		kv[string.lower(key)] = value
	end
end)

function WETSAND.KeyValues(ent)
	return WETSAND.KV[ent] or { outputs = {} }
end

function WETSAND.FindByName(name)
	if not name or name == "" then return NULL end
	return ents.FindByName(name)[1] or NULL
end

-- An output connection as Hammer writes it: target,input,param,delay,times
-- (newer compilers separate the fields with ESC instead of commas).
function WETSAND.ParseOutput(name, value)
	local sep = string.find(value, "\27", 1, true) and "\27" or ","
	local f = string.Explode(sep, value)
	return {
		name = name,
		target = f[1] or "",
		input = f[2] or "",
		param = f[3] or "",
		delay = tonumber(f[4]) or 0,
		times = tonumber(f[5]) or -1,
		fired = 0,
	}
end

local function OutputTargets(o, caller, activator)
	local t = string.lower(o.target)
	if t == "!self" or t == "!caller" then return { caller } end
	if t == "!activator" then return { activator } end
	if t == "!player" then return { player.GetAll()[1] } end
	return ents.FindByName(o.target)
end

-- Fire the named output of an engine entity whose outputs we recorded.
function WETSAND.FireOutput(caller, name, activator)
	for _, o in ipairs(WETSAND.KeyValues(caller).outputs) do
		if o.name == name and (o.times < 0 or o.fired < o.times) then
			o.fired = o.fired + 1
			for _, target in ipairs(OutputTargets(o, caller, activator)) do
				if IsValid(target) then
					target:Fire(o.input, o.param, o.delay, activator, caller)
				end
			end
		end
	end
end

-- The announcement line on every screen (the rounds view draws it), in the
-- team's colour; no team for the plain one.
function WETSAND.Announce(text, team)
	WETSAND.Events.Fire("announcement", {
		text = text,
		team = team,
	})
end

function WETSAND.IsAliveInGame(ply)
	return IsValid(ply) and ply:IsPlayer() and ply:Alive() and ply:GetObserverMode() == OBS_MODE_NONE
end

-- Players whose hull overlaps the entity's bounds, tested in the entity's own
-- space so a volume parented to the moving cart turns with it. Brush volumes
-- are treated as their bounding box.
local HULL = Vector(16, 16, 36)

local function Inside(volume, candidates, alive)
	local inside = {}
	if not IsValid(volume) then return inside end
	local mins, maxs = volume:OBBMins() - HULL, volume:OBBMaxs() + HULL
	for _, ent in ipairs(candidates) do
		if alive(ent) and volume:WorldToLocal(ent:WorldSpaceCenter()):WithinAABox(mins, maxs) then
			inside[#inside + 1] = ent
		end
	end
	return inside
end

function WETSAND.PlayersInside(ent)
	return Inside(ent, player.GetAll(), WETSAND.IsAliveInGame)
end

-- Entities other than players that fight for a team (the AI war's
-- soldiers): they stand on capture areas as its members and pass its team
-- filters. entity -> team; SetTeamMember(ent, nil) lets one go.
local teamMembers = setmetatable({}, { __mode = "k" })

function WETSAND.SetTeamMember(ent, team)
	teamMembers[ent] = team
end

-- A player's own team, else the team an entity fights for, else UNASSIGNED.
function WETSAND.TeamNumber(ent)
	if ent:IsPlayer() then return ent:Team() end
	return teamMembers[ent] or WETSAND.TEAM_UNASSIGNED
end

local function MemberAlive(ent)
	return IsValid(ent) and ent:Health() > 0
end

-- The living team members (not players) of a team.
function WETSAND.TeamMembers(team)
	local members = {}
	for member, memberTeam in pairs(teamMembers) do
		if memberTeam == team and MemberAlive(member) then members[#members + 1] = member end
	end
	return members
end

-- Living team members (not players) whose hull overlaps the entity's bounds.
function WETSAND.MembersInside(ent)
	local members = {}
	for member in pairs(teamMembers) do members[#members + 1] = member end
	return Inside(ent, members, MemberAlive)
end

-- A weapon's ammo ceiling: GMod's own per-type maximum when it sets one,
-- otherwise four clips (GMod reports 9999 for most types).
local function AmmoCeiling(wep, ammoType)
	local max = game.GetAmmoMax(ammoType)
	if max > 0 and max < 9999 then return max end
	return math.max(wep:GetMaxClip1(), 10) * 4
end

-- Refill every weapon's primary reserve by a fraction of its ceiling.
-- Returns whether anything was given.
function WETSAND.GiveAmmoFraction(ply, fraction)
	local gave = false
	for _, wep in ipairs(ply:GetWeapons()) do
		local ammoType = wep:GetPrimaryAmmoType()
		if ammoType >= 0 then
			local have = ply:GetAmmoCount(ammoType)
			local after = WETSAND.PlayerRules.AmmoAfterPack(have, AmmoCeiling(wep, ammoType), fraction)
			if after > have then
				ply:SetAmmo(after, ammoType)
				gave = true
			end
		end
	end
	return gave
end

function WETSAND.HealFraction(ply, fraction)
	local max = ply:GetMaxHealth()
	if ply:Health() >= max then return false end
	ply:SetHealth(math.min(max, ply:Health() + math.ceil(max * fraction)))
	ply:Extinguish()
	return true
end

-- path_track handles its own Enable/DisablePath; the train watcher only needs
-- to know which nodes are disabled, so note it and let the input through.
hook.Add("AcceptInput", "wetsand_path_track", function(ent, input)
	if ent:GetClass() ~= "path_track" then return end
	local kv = WETSAND.KV[ent]
	if not kv then return end
	input = string.lower(input)
	if input == "disablepath" then
		kv.wetsandDisabled = true
	elseif input == "enablepath" then
		kv.wetsandDisabled = nil
	elseif input == "togglepath" then
		kv.wetsandDisabled = not kv.wetsandDisabled or nil
	end
end)
