-- Server-side world helpers shared by the TF2 entities.

-- CTeamplayRoundBasedRules::BroadcastSound: a game sound every player of a
-- team hears as their own (announcer lines, win/lose music). Team 0 is
-- everyone. Each client decides whether it hears it (ws/sh_announcer.lua).
function WS.BroadcastSound(team, name)
	WS.Events.Fire("teamplay_broadcast_audio", {
		team = team,
		sound = name,
	})
end

function WS.BroadcastPA(team, name)
	WS.Events.Fire("teamplay_broadcast_audio", {
		team = team,
		sound = name,
		channel = CHAN_VOICE2
	})
end

-- A game sound every player not on the team hears as their own
-- (CLocalPlayerFilter lines: the capture's lines for the other team).
function WS.BroadcastSoundToOthers(team, name)
	WS.Events.Fire("teamplay_broadcast_audio", {
		team = team,
		sound = name,
		others = true,
	})
end

-- A game sound from an entity that only one player hears
-- (CSingleUserRecipientFilter): pickup and resupply sounds.
function WS.PlaySoundTo(ply, ent, name)
	local filter = RecipientFilter()
	filter:AddPlayer(ply)
	ent:EmitSound(name, 75, 100, 1, CHAN_AUTO, 0, 0, filter)
end

-- Keyvalues of engine entities we read but do not implement. GMod exposes no
-- getter for a path_track's next node or a teamspawn's team, so they are
-- recorded as the map sets them.
WS.KV = WS.KV or setmetatable({}, { __mode = "k" })

local RECORDED = {
	path_track = true,
	info_player_teamspawn = true,
	team_control_point = true,
	-- which doors a trigger opens (foundation.npc.doors Opens)
	trigger_multiple = true,
	-- the rounds feature fires its OnMultiNewRound, which GMod never does
	logic_auto = true,
	-- the arena feature fires its OnArenaRoundStart and OnCapEnabled
	tf_logic_arena = true,
}

-- logic_auto's "Remove on fire" (SF_AUTO_FIREONCE). Its outputs fire once
-- anyway (CLogicAuto::Think runs once), so the entity is kept for the rounds
-- feature to fire OnMultiNewRound at the first round, which in TF2 follows
-- the waiting-for-players restart that recreates it.
local LOGIC_AUTO_FIRE_ONCE = 1

-- Outputs are kept in map order in kv.outputs, since an output key may repeat.
hook.Add("EntityKeyValue", "ws_record_keyvalues", function(ent, key, value)
	if not RECORDED[ent:GetClass()] then return end
	if ent:GetClass() == "logic_auto" and string.lower(key) == "spawnflags" then
		return tostring(bit.band(tonumber(value) or 0, bit.bnot(LOGIC_AUTO_FIRE_ONCE)))
	end
	local kv = WS.KV[ent]
	if not kv then
		kv = { outputs = {} }
		WS.KV[ent] = kv
	end
	if string.sub(key, 1, 2) == "On" then
		kv.outputs[#kv.outputs + 1] = WS.ParseOutput(key, value)
	else
		kv[string.lower(key)] = value
	end
end)

-- An ambient_generic naming a voice line TF2 has since made an .mp3
-- (foundation.sound_paths) plays the .mp3.
local SoundPaths = WS.require("foundation.sound_paths")
local function GameFileExists(path) return file.Exists(path, "GAME") end

hook.Add("EntityKeyValue", "ws_sound_paths", function(ent, key, value)
	if ent:GetClass() ~= "ambient_generic" or string.lower(key) ~= "message" then return end
	return SoundPaths.Replacement(value, GameFileExists)
end)

function WS.KeyValues(ent)
	return WS.KV[ent] or { outputs = {} }
end

function WS.FindByName(name)
	if not name or name == "" then return NULL end
	return ents.FindByName(name)[1] or NULL
end

-- An output connection as Hammer writes it: target,input,param,delay,times
-- (newer compilers separate the fields with ESC instead of commas).
function WS.ParseOutput(name, value)
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
function WS.FireOutput(caller, name, activator)
	for _, o in ipairs(WS.KeyValues(caller).outputs) do
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
-- audience (who sees it, everyone when nil) and icon (TF2's card when
-- given) are optional (ws/sh_announcer.lua).
function WS.Announce(text, team, audience, icon)
	WS.Events.Fire("announcement", {
		text = text,
		team = team,
		audience = audience,
		icon = icon,
	})
end

-- foundation.admin_notices' notices: each one's chime on CHAN_AUTO and
-- announcer line on CHAN_VOICE2 (the neutral alert once in a while:
-- Spoken), then its card, to its audience. The alert's time is kept for
-- the map: the first neutral notice on a new map speaks it.
local AdminNotices = WS.require("foundation.admin_notices")
local neutralLineAt

function WS.Notify(notices)
	notices, neutralLineAt = AdminNotices.Spoken(notices, neutralLineAt, SysTime())
	for _, n in ipairs(notices) do
		if n.chime then WS.BroadcastSound(n.audience, n.chime) end
		if n.sound then WS.BroadcastPA(n.audience, n.sound) end
		WS.Announce(n.text, n.team, n.audience, n.icon)
	end
end

function WS.IsAliveInGame(ply)
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

function WS.PlayersInside(ent)
	return Inside(ent, player.GetAll(), WS.IsAliveInGame)
end

-- Entities other than players that fight for a team (the AI war's
-- soldiers): they stand on capture areas as its members and pass its team
-- filters, and join its DrGBase faction (WS.JoinTeamFaction).
-- entity -> team; SetTeamMember(ent, nil) lets one go, in the faction it
-- had.
local teamMembers = setmetatable({}, { __mode = "k" })

function WS.SetTeamMember(ent, team)
	teamMembers[ent] = team
	if team then WS.JoinTeamFaction(ent, team) end
end

-- A player's own team, else the team an entity fights for, else UNASSIGNED.
function WS.TeamNumber(ent)
	if ent:IsPlayer() then return ent:Team() end
	return teamMembers[ent] or WS.TEAM_UNASSIGNED
end

local function MemberAlive(ent)
	return IsValid(ent) and ent:Health() > 0
end

-- The living team members (not players) of a team.
function WS.TeamMembers(team)
	local members = {}
	for member, memberTeam in pairs(teamMembers) do
		if memberTeam == team and MemberAlive(member) then members[#members + 1] = member end
	end
	return members
end

-- Living team members (not players) whose hull overlaps the entity's bounds.
function WS.MembersInside(ent)
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
function WS.GiveAmmoFraction(ply, fraction)
	local gave = false
	for _, wep in ipairs(ply:GetWeapons()) do
		local ammoType = wep:GetPrimaryAmmoType()
		if ammoType >= 0 then
			local have = ply:GetAmmoCount(ammoType)
			local after = WS.PlayerRules.AmmoAfterPack(have, AmmoCeiling(wep, ammoType), fraction)
			if after > have then
				ply:SetAmmo(after, ammoType)
				gave = true
			end
		end
	end
	return gave
end

function WS.HealFraction(ply, fraction)
	local max = ply:GetMaxHealth()
	if ply:Health() >= max then return false end
	ply:SetHealth(math.min(max, ply:Health() + math.ceil(max * fraction)))
	ply:Extinguish()
	return true
end

-- path_track handles its own Enable/DisablePath; the train watcher only needs
-- to know which nodes are disabled, so note it and let the input through.
hook.Add("AcceptInput", "ws_path_track", function(ent, input)
	if ent:GetClass() ~= "path_track" then return end
	local kv = WS.KV[ent]
	if not kv then return end
	input = string.lower(input)
	if input == "disablepath" then
		kv.wsDisabled = true
	elseif input == "enablepath" then
		kv.wsDisabled = nil
	elseif input == "togglepath" then
		kv.wsDisabled = not kv.wsDisabled or nil
	end
end)
