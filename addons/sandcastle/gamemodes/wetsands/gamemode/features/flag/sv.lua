-- Wetsands' answers to the flags (Sandcastle's game_ctf): its team members
-- (the AI war's soldiers) carry flags too, the round's mode decides who carries
-- and whether captures score (MvM's bomb is BLU's own), and CTF's announcer
-- and crits are this game's. What the other features ask of the flags
-- goes through this controller.
--
-- Loaded when a map adds a flag (init.lua). It loads rounds.
local Flag = WS.require("features.flag.model")
local Game = game_manager.GetClass("game_ctf")

local NOBODY, RED, BLUE = WS.TEAM_UNASSIGNED, WS.TEAM_RED, WS.TEAM_BLUE
local HOOK = "ws_flag"
local Log = WS.Logger("flag")

local function TeamName(team)
	if team == RED then return "RED" end
	if team == BLUE then return "BLU" end
	if team == NOBODY then return "unassigned" end
	return "team " .. tostring(team)
end

local captureBonusTime = CreateConVar("tf_ctf_bonus_time", "10", FCVAR_NOTIFY, "Length of team crit time for CTF capture.")

local Controller = {
	rounds = WS.Feature("rounds"),
	tally = Game.tally,
}

-- CTFGameRules::Activate: an item_teamflag makes the game CTF.
Controller.rounds:SetMode(Flag.Mode)

local function Mode()
	return Controller.rounds:Mode()
end

function Controller:Flags() return Game.Flags() end
function Controller:Zones() return Game.Zones() end
function Controller:CapLimit() return Game.CapLimit() end
function Controller:FlagAt(ent) return Game.Model(ent) end
function Controller:ZoneTeam(ent) return Game.ZoneTeam(ent) end
function Controller:Give(ent, carrier) return ent:Give(carrier) end

-- What the mode lets a carrier do now (Flag:PickUp's q), and whose spawn
-- rooms keep the flag (MvM's invaders).
function Controller:Rules()
	local mode = Mode()
	return {
		ownersCarry = mode.FLAG_OWNERS_CARRY,
		mayBeCapped = Flag.MayBeCapped(self.rounds:State(), self.rounds:InSetup(), mode.FLAG_WAITS_FOR_WAVE),
		invaders = mode.FLAG_INVADERS,
		scores = mode.FLAG_CAPS_SCORE,
	}
end

hook.Add("FlagRules", HOOK, function() return Controller:Rules() end)
hook.Add("FlagTeam", HOOK, function(ent) return WS.TeamNumber(ent) end)

hook.Add("FlagCarrierAlive", HOOK, function(ent)
	if ent:IsPlayer() then return WS.IsAliveInGame(ent) end
	return ent:Health() > 0
end)

-- The players and team members standing on the flag or in the zone.
hook.Add("FlagMembersInside", HOOK, function(ent)
	local inside = WS.PlayersInside(ent)
	for _, member in ipairs(WS.MembersInside(ent)) do inside[#inside + 1] = member end
	return inside
end)

-- CTFGameRules::HandleCTFCaptureBonus: the capturing team's living players,
-- and here its soldiers too (as the winners' bonus crits are theirs), are
-- crit-boosted for tf_ctf_bonus_time seconds.
local function CaptureBonus(team)
	local seconds = captureBonusTime:GetFloat()
	if seconds <= 0 then return end
	local members = WS.TeamMembers(team)
	for _, ply in ipairs(player.GetAll()) do
		if WS.TeamOf(ply) == team then members[#members + 1] = ply end
	end
	for _, ent in ipairs(members) do
		local alive = ent:IsPlayer() and ent:Alive() or not ent:IsPlayer() and ent:Health() > 0
		if alive then WS.AddCondition(ent, WS.PlayerRules.COND.CRITBOOSTED_CTF_CAPTURE, seconds) end
	end
end

local ACTIONS = {
	[Flag.PICKUP] = "picked up",
	[Flag.DROP] = "dropped",
	[Flag.CAPTURE] = "captured",
	[Flag.RETURN] = "returned",
}

hook.Add("FlagEvent", HOOK, function(ent, e, activator)
	local mode = Mode()
	Log("flag #%d for %s %s by %s", ent:EntIndex(), TeamName(Game.Model(ent):Team()), ACTIONS[e.kind], TeamName(e.team))
	-- the carrier, as the capture is made (player analytics, ws/sv_player_analytics.lua)
	if e.kind == Flag.CAPTURE then hook.Run("WSFlagCaptured", ent, e.team, activator) end
	if mode.FLAG_CAPS_SCORE then
		for _, line in ipairs(Flag.Lines(e)) do WS.BroadcastSoundscape(line.team, line.sound) end
		if e.kind == Flag.CAPTURE then CaptureBonus(e.team) end
	elseif mode.FLAG_INVADERS then
		for _, line in ipairs(Flag.InvadeLines(e)) do WS.BroadcastSoundscape(line.team, line.sound) end
	end
	return true
end)

-- This game's lines are FlagEvent's, above.
function Game.AnnounceCapture() end

-- Snapshots ---------------------------------------------------------------------------

-- The flags' state as plain data, for the dev workbench's capture and
-- restore: each flag (its model, and where it lies when not carried), the
-- capture and reset zones and the tally. Entities go through refs
-- (Encode(ent) -> key, Decode(key) -> the entity or nil).
function Controller:Snapshot(now, refs)
	local snapshot = {
		flags = {},
		zones = {},
		resetZones = {},
		tally = self.tally:Snapshot(),
	}
	for ent, flag in pairs(Game.Flags()) do
		snapshot.flags[refs:Encode(ent)] = {
			model = Flag.SnapshotFlag(flag, now, refs),
			pos = ent:GetPos(),
			angles = ent:GetAngles(),
		}
	end
	for ent, zone in pairs(Game.Zones()) do snapshot.zones[refs:Encode(ent)] = zone.enabled end
	for ent, zone in pairs(Game.ResetZones()) do snapshot.resetZones[refs:Encode(ent)] = zone.enabled end
	return snapshot
end

-- Each flag where its state says: home, carried by its carrier, or lying
-- where it was. A carried flag whose carrier is gone is dropped where it
-- was, and named in notes. Returns { missing = { keys }, notes = { text } }.
function Controller:Restore(snapshot, now, refs)
	local missing, notes = {}, {}
	local flags, zones, resetZones = Game.Flags(), Game.Zones(), Game.ResetZones()
	for key, data in pairs(snapshot.flags) do
		local ent = refs:Decode(key)
		local flag = IsValid(ent) and flags[ent]
		if not flag then
			missing[#missing + 1] = key
		else
			local ok, err = pcall(Flag.RestoreFlag, flag, data.model, now, refs)
			if not ok then
				-- the carrier is gone: a fresh drop where the flag was
				notes[#notes + 1] = key .. ": " .. tostring(err) .. "; dropped where it was"
				local dropped = table.Copy(data.model)
				dropped.carrier, dropped.carrierTeam, dropped.state = nil, NOBODY, Flag.DROPPED
				dropped.returnAt = flag:ReturnTime()
				Flag.RestoreFlag(flag, dropped, now, refs)
			end
			ent:ForgetCarry()
			if flag:State() == Flag.CARRIED then
				ent:Carry(flag:Carrier())
			elseif flag:State() == Flag.HOME then
				ent:GoHome()
			else
				ent:SetParent(NULL)
				ent:SetPos(data.pos)
				ent:SetAngles(data.angles)
			end
			ent:SetSkin(ent:WsSkin(flag:Team()))
			ent:Publish()
		end
	end
	for key, enabled in pairs(snapshot.zones) do
		local zone = zones[refs:Decode(key) or NULL]
		if zone then zone:SetEnabled(enabled) else missing[#missing + 1] = key end
	end
	for key, enabled in pairs(snapshot.resetZones) do
		local zone = resetZones[refs:Decode(key) or NULL]
		if zone then zone.enabled = enabled else missing[#missing + 1] = key end
	end
	self.tally:Restore(snapshot.tally)
	for ent in pairs(flags) do ent:PublishTally() end
	return {
		missing = missing,
		notes = notes,
	}
end

return Controller
