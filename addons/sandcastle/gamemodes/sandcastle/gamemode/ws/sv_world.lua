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

-- The map's entity I/O (foundation.core.map_io): cached lookups by name and
-- class, recorded output connections, and observers of outputs and inputs.
-- Its maps are rebuilt when the map's entities are all spawned or cleaned
-- up; entities created after join them as they are created.
local MapIO = WS.require("foundation.core.map_io")

-- The port outlives a reload with WS.MapIO, so a reload redefines its
-- methods in place.
WS.MapIOWorld = WS.MapIOWorld or {}
local World = WS.MapIOWorld
function World:Entities() return ents.GetAll() end
function World:NameOf(ent) return ent:GetName() end
function World:ClassOf(ent) return ent:GetClass() end
-- GMod's IsValid is false for the world entity, which still exists.
function World:IsValid(ent) return IsValid(ent) or (ent ~= nil and ent == game.GetWorld()) end
function World:FirstPlayer() return player.GetAll()[1] end
function World:Fire(target, input, param, delay, activator, caller)
	target:Fire(input, param, delay, activator, caller)
end

WS.MapIO = WS.MapIO or MapIO.New(World)

local function Recache() WS.MapIO:Recache() end
hook.Add("InitPostEntity", "ws_map_io_recache", Recache)
hook.Add("PostCleanupMap", "ws_map_io_recache", Recache)
hook.Add("OnEntityCreated", "ws_map_io_track", function(ent) WS.MapIO:Track(ent) end)
hook.Add("EntityRemoved", "ws_map_io_forget", function(ent) WS.MapIO:Forget(ent) end)

-- Keyvalues of engine entities we read but do not implement. GMod exposes no
-- getter for a path_track's next node or a teamspawn's team, so they are
-- recorded as the map sets them.
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
	WS.MapIO:RecordKeyValue(ent, key, value)
end)

-- An ambient_generic naming a voice line TF2 has since made an .mp3
-- (ws.sound_paths) plays the .mp3.
local SoundPaths = WS.require("ws.sound_paths")
local function GameFileExists(path) return file.Exists(path, "GAME") end

hook.Add("EntityKeyValue", "ws_sound_paths", function(ent, key, value)
	if ent:GetClass() ~= "ambient_generic" or string.lower(key) ~= "message" then return end
	return SoundPaths.Replacement(value, GameFileExists)
end)

function WS.KeyValues(ent)
	return WS.MapIO:KeyValues(ent)
end

function WS.FindByName(name)
	if not name then return NULL end
	return WS.MapIO:FirstByName(name) or NULL
end

function WS.FindAllByName(name) return WS.MapIO:FindByName(name) end
function WS.FindByClass(class) return WS.MapIO:FindByClass(class) end

-- An output connection as Hammer writes it (foundation.core.map_io).
WS.ParseOutput = MapIO.ParseOutput

-- Fire the named output of an engine entity whose outputs we recorded.
function WS.FireOutput(caller, name, activator)
	WS.MapIO:FireOutput(caller, name, activator)
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
local lastTeams = setmetatable({}, { __mode = "k" }) -- entity -> the team it last fought for

function WS.SetTeamMember(ent, team)
	teamMembers[ent] = team
	if team then
		lastTeams[ent] = team
		WS.OpenAccount(ent) -- ws/sv_economy.lua
	end
	-- for the scoreboard's columns (ws/cl_scoreboard.lua)
	ent:SetNW2Int("ws_team", team or WS.TEAM_UNASSIGNED)
	if team then WS.JoinTeamFaction(ent, team) end
end

-- A player's own team, else the team an entity fights for, else UNASSIGNED.
function WS.TeamNumber(ent)
	if ent:IsPlayer() then return ent:Team() end
	return teamMembers[ent] or WS.TEAM_UNASSIGNED
end

-- The team an entity fights for, or last fought for: a soldier's war lets it
-- go as it dies (OnNPCKilled), maybe before its killer is credited.
function WS.LastTeamNumber(ent)
	if ent:IsPlayer() then return ent:Team() end
	return lastTeams[ent] or WS.TEAM_UNASSIGNED
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

-- Every input the engine delivers reaches its map I/O observers; returning
-- nothing lets it through. An AddOutput setting a targetname renames the
-- entity, so it is filed again.
hook.Add("AcceptInput", "ws_map_io_input", function(ent, input, activator, caller, value)
	WS.MapIO:AcceptInput(ent, input, value, activator, caller)
end)

-- This file's observers, dropped and added again when it reloads, since
-- WS.MapIO (and the keyvalues it recorded at map load) outlives a reload.
for _, id in ipairs(WS.MapIOObservers or {}) do WS.MapIO:Unobserve(id) end
WS.MapIOObservers = {}

local function Observe(kind, name, fn)
	WS.MapIOObservers[#WS.MapIOObservers + 1] = WS.MapIO:Observe(kind, name, fn)
end

Observe(MapIO.INPUT, "AddOutput", function(ent, _, value)
	if string.lower(string.match(value or "", "^%s*(%S+)") or "") == "targetname" then
		WS.MapIO:Reindex(ent)
	end
end)

-- path_track handles its own Enable/DisablePath; the train watcher only needs
-- to know which nodes are disabled, so note it and let the input through.
local function PathTrackObserver(disabled)
	return function(ent)
		if ent:GetClass() ~= "path_track" then return end
		local kv = WS.KeyValues(ent)
		kv.wsDisabled = disabled(kv.wsDisabled)
	end
end

Observe(MapIO.INPUT, "DisablePath", PathTrackObserver(function() return true end))
Observe(MapIO.INPUT, "EnablePath", PathTrackObserver(function() return nil end))
Observe(MapIO.INPUT, "TogglePath", PathTrackObserver(function(was) return not was or nil end))
