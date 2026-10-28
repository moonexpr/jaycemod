-- Part of the AI war controller (sv.lua): bot players as soldiers. While
-- the war runs, tf_bot_quota keeps bots on the server as TF2 keeps its own
-- (wartactics.bot_quota): each joins a team as a player is
-- auto-assigned, spawns in its team's respawn waves as every player does,
-- and is enlisted as it spawns, under the same orders as the war's NPC
-- soldiers. ns_soldiers_actor picks one or the other: bots kept by the
-- quota, or NPCs drafted in the waves (Reinforce), never both. Being
-- players, bots pass the map's triggers and filters for players, and the
-- rounds' rules (freezes, stuns, humiliation) reach their keys as anyone's.
--
-- A bot soldier (sv_bot_soldier.lua) looks around every LOOK_INTERVAL (its
-- nextsoldier.vision), and every tick its body
-- (nextsoldier.player_body) presses its keys (StartCommand).
local Controller, Map = ...
local Quota = wartactics.bot_quota
local Vision = nextsoldier.vision
local Teams = gameplay.teams
local HL2Path = WS.require("foundation.wetsands.path.hl2")
local Arms = WS.require("features.aiwar.arms")
local Marksmanship = WS.require("features.aiwar.marksmanship")
local Orders = WS.require("features.aiwar.orders")
local NpcSystem = npc.nextbot
local Point = Map.Point
local RED, BLUE = Map.RED, Map.BLUE

local FLAGS = { FCVAR_ARCHIVE, FCVAR_NOTIFY }
local QUOTA = CreateConVar("tf_bot_quota", "0", FLAGS,
	"How many bot soldiers the AI war keeps as players (counted as tf_bot_quota_mode says); 0: none")
local QUOTA_MODE = CreateConVar("tf_bot_quota_mode", "normal", FLAGS,
	"What tf_bot_quota counts: normal (bots), fill (players on the teams), match (bots for each human)")
local JOIN_AFTER_PLAYER = CreateConVar("tf_bot_join_after_player", "1", FLAGS,
	"Whether the AI war's bots wait for a human to join a team")
local ACTOR = CreateConVar("ns_soldiers_actor", "npc", FLAGS,
	"Who the AI war's soldiers are, never both: npc (its NextBots; tf_bot_quota is ignored) "
	.. "or bot (bot players; no NPCs are drafted, and a tf_bot_quota of 0 fills the teams' sizes)")
local DIFFICULTY = GetConVar("tf_bot_difficulty") -- ws/sh_votes.lua's
local MIMIC = GetConVar("bot_mimic")

cvars.AddChangeCallback("tf_bot_quota_mode", function(_, old, new)
	if Quota.Mode(new) then return end
	print(string.format("tf_bot_quota_mode: %q is none of normal, fill, match; kept %s", new, old))
	QUOTA_MODE:SetString(old)
end, "ws_aiwar_bots")

cvars.AddChangeCallback("ns_soldiers_actor", function(_, old, new)
	if not Quota.Actors(new) then
		print(string.format("ns_soldiers_actor: %q is neither npc nor bot; kept %s", new, old))
		ACTOR:SetString(old)
		return
	end
	-- bots take over: the drafted NPCs go now; NPCs take over: the bots are
	-- kicked a second at a time by the quota, and the waves draft in their place
	if Quota.Actors(new) == Quota.BOT and Controller.war then Controller:DismissDrafted() end
end, "ws_aiwar_bots")

-- Who the war's soldiers are (ns_soldiers_actor): Quota.NPC or Quota.BOT.
function Controller:Actors()
	return Quota.Actors(ACTOR:GetString())
end

-- How often the quota is kept (MaintainBotQuota's think) and a bot looks.
local QUOTA_INTERVAL, LOOK_INTERVAL = 1, 0.2
-- How far a bot sees, and its field of view: TF2's bots see 90 degrees.
local SIGHT_RANGE = 4000
local FOV_COS = math.cos(math.rad(45))
-- An enemy that hurt it is noticed whichever way it faces, this long after;
-- one within NOTICE_NEAR, at any time (it hears its steps).
local NOTICE_ATTACKER, NOTICE_NEAR = 2, 256
-- What it feels for ahead the way it moves (GLambda's players' obstacle
-- check): a hull PROBE_REACH long at its knees, above a step, and one at its
-- head, above a crouch.
local PROBE_REACH = 32
local KNEE_LIFT, KNEE_MINS, KNEE_MAXS = Vector(0, 0, 20), Vector(-12, -12, 0), Vector(12, 12, 16)
local HEAD_LIFT, HEAD_MINS, HEAD_MAXS = Vector(0, 0, 40), Vector(-12, -12, 0), Vector(12, 12, 30)
-- Its enemy's width at its distance, for when a shot is on (a player's
-- hull, half across).
local AIM_RADIUS = 16
-- Ammunition: topped back up to AMMO_RESERVE when below AMMO_FLOOR, as the
-- war's NPC soldiers never run dry.
local AMMO_RESERVE, AMMO_FLOOR = 300, 100
-- The command's forward move: past any speed, so the engine's top speed
-- for its gait is the one it moves at.
local FORWARD = 10000

local function Reaction() return Marksmanship.For(DIFFICULTY:GetInt()).reaction end

-- The quota --------------------------------------------------------------------

-- Players on each game team, and how many of them are the quota's bots.
function Controller:TeamCounts()
	local counts = {
		[RED] = { players = 0, bots = 0 },
		[BLUE] = { players = 0, bots = 0 },
	}
	for _, ply in ipairs(player.GetAll()) do
		local side = counts[WS.TeamOf(ply)]
		if side then
			side.players = side.players + 1
			if self.bots[ply] then side.bots = side.bots + 1 end
		end
	end
	return counts
end

function Controller:BotsOn(team)
	local n = 0
	for bot in pairs(self.bots) do
		if IsValid(bot) and WS.TeamOf(bot) == team then n = n + 1 end
	end
	return n
end

-- Everyone but the quota's bots counts as a human, a bot of the harness's
-- included, as TF2 counts its non-TFBot players.
function Controller:Population()
	local humans, spectators, bots = 0, 0, 0
	for _, ply in ipairs(player.GetAll()) do
		if self.bots[ply] then
			bots = bots + 1
		elseif WS.TeamOf(ply) == WS.TEAM_UNASSIGNED then
			spectators = spectators + 1
		else
			humans = humans + 1
		end
	end
	return {
		humans = humans,
		spectators = spectators,
		bots = bots,
		slots = game.MaxPlayers(),
	}
end

function Controller:AddBot()
	local counts = self:TeamCounts()
	local team = Teams.AutoTeam(counts[RED].players, counts[BLUE].players)
	self.botSerial = (self.botSerial or 0) + 1
	local bot = player.CreateNextBot(string.format("%s %d", self:FactionName(team), self.botSerial))
	if not IsValid(bot) then return end
	self.bots[bot] = true
	-- the body it was made with goes quietly: joining a team alive would
	-- kill it, a suicide on the scoreboard
	bot:KillSilent()
	WS.SetPlayerTeam(bot, team)
end

-- A bot of the team TeamToKick names, a dead one first; any of the
-- quota's when none is on a team.
function Controller:KickBot()
	local team = Quota.TeamToKick(self:TeamCounts())
	local pick
	for bot in pairs(self.bots) do
		if IsValid(bot) and (team == nil or WS.TeamOf(bot) == team) and (pick == nil or not bot:Alive()) then pick = bot end
	end
	if pick then pick:Kick("tf_bot_quota") end
end

function Controller:MaintainBotQuota()
	local sizes = self:Sizes()
	local step = Quota.Step({
		mode = Quota.Mode(QUOTA_MODE:GetString()),
		quota = QUOTA:GetInt(),
		joinAfterPlayer = JOIN_AFTER_PLAYER:GetBool(),
		actors = self:Actors(),
		soldiers = sizes[RED] + sizes[BLUE],
	}, self:Population())
	if step == Quota.ADD then
		self:AddBot()
	elseif step == Quota.KICK then
		self:KickBot()
	end
end

-- A bot alive on a game team but not a soldier (it spawned before it had a
-- team, and joining one did not spawn it again) is enlisted.
function Controller:EnlistStrays()
	for bot in pairs(self.bots) do
		local team = IsValid(bot) and WS.TeamOf(bot)
		if team and (team == RED or team == BLUE) and bot:Alive() and not self.soldiers[bot] then self:EnlistBot(bot) end
	end
end

-- The war over, its bots leave with it.
function Controller:DismissBots()
	for bot in pairs(self.bots) do
		if IsValid(bot) then bot:Kick("the AI war ended") end
	end
	self.bots = {}
end

-- Enlisting ---------------------------------------------------------------------

function Controller:NewBotSoldier(ply, team)
	return self.BotSoldier.New(ply, self, team, Reaction())
end

-- The new entry's soldier: which of two enemies is the more dangerous is
-- its orders' (SelectMoreDangerousThreat), else the nearer; it looks at once.
function Controller:ReadyBot(ply, entry)
	local soldier = entry.soldier
	soldier.better = function(a, b)
		local pick = entry.npc:Query("SelectMoreDangerousThreat", a, b)
		if pick == a then return true end
		if pick == b then return false end
		local pos = ply:GetPos()
		return pos:DistToSqr(a:GetPos()) < pos:DistToSqr(b:GetPos())
	end
	soldier.nextLook = 0
	soldier.attackedAt = -math.huge
	soldier.sense = { eye = {} }
	-- its navigator learns where it stands before its first route
	soldier:Navigator()
end

-- A bot spawned (a wave, the round's start): enlisted afresh, its orders
-- starting over from where it stands.
function Controller:EnlistBot(ply)
	if not ply:Alive() then return end
	local team = WS.TeamOf(ply)
	if team ~= RED and team ~= BLUE then return end
	if self.soldiers[ply] then self:Discharge(ply) end
	-- TF2's teammates pass through each other: a bot held up behind another
	-- in a doorway climbed onto its head and stayed there
	ply:SetNoCollideWithTeammates(true)
	self:Enlist(ply, team, false)
end

-- The model a recruit of the faction wears (its NextBot's ENT.Models).
local function FactionModel(faction)
	local stored = scripted_ents.GetStored(faction.recruits[1].class)
	local models = stored.t.Models
	return models[math.random(#models)]
end

-- A role's kit on a bot (Equip; a DrGBase soldier's is its NSKit): its
-- model, its loadout's weapons with ammunition, its health. A kit with no
-- arms (the vortigaunt medic's) leaves what it carries.
function Controller:KitBot(ply, soldier, kit)
	ply:SetModel(kit.model or FactionModel(self:Faction(soldier.team)))
	if kit.primary then
		local loadout = Arms.Loadout(kit, math.random)
		ply:StripWeapons()
		for _, class in ipairs(Arms.Classes(loadout)) do
			local weapon = ply:Give(class)
			if IsValid(weapon) and weapon:GetPrimaryAmmoType() >= 0 then ply:GiveAmmo(AMMO_RESERVE, weapon:GetPrimaryAmmoType(), true) end
		end
		ply:SelectWeapon(loadout.primary)
		soldier.loadout = loadout
	end
	if kit.health and ply:GetMaxHealth() ~= kit.health then
		ply:SetMaxHealth(kit.health)
		ply:SetHealth(kit.health)
	end
end

-- Looking ------------------------------------------------------------------------

-- The live fighters of each game team, players (bots included) and the
-- war's NPC soldiers.
function Controller:Fighters()
	local fighters = { [RED] = {}, [BLUE] = {} }
	for _, ply in ipairs(player.GetAll()) do
		local list = fighters[WS.TeamOf(ply)]
		if list and ply:Alive() then list[#list + 1] = ply end
	end
	for ent, entry in pairs(self.soldiers) do
		local list = fighters[entry.soldier.team]
		if list and IsValid(ent) and not ent:IsPlayer() and ent:Health() > 0 then list[#list + 1] = ent end
	end
	return fighters
end

-- Tells a bot's orders what its vision saw, and the war its contacts (its
-- call-outs: sv_speech.lua).
function Controller:TellSight(ply, entry, events)
	for _, e in ipairs(events) do
		entry.npc:Event(e.kind, e.handle)
		if e.kind == Vision.CONTACT then
			hook.Run("WSSoldierContact", ply, e.handle)
		elseif e.kind == Vision.CONTACT_LOST then
			hook.Run("WSSoldierContactLost", ply, e.handle)
		end
	end
end

-- A look around: the point it steers for on its way (BotSoldier:Steer);
-- the enemies in its field of view (or that just hurt it, or are near),
-- within SIGHT_RANGE and in a clear line, to its vision; then whether its
-- orders let it fire, the weapon for its contact's distance, the nav area
-- it stands in, and its ammunition.
function Controller:Look(ply, entry, enemies, now)
	local soldier = entry.soldier
	soldier:Steer(now)
	local eye, facing = ply:EyePos(), ply:GetAimVector()
	local seen = {}
	for _, enemy in ipairs(enemies) do
		local center = enemy:WorldSpaceCenter()
		local to = center - eye
		local distance = to:Length()
		if distance <= SIGHT_RANGE then
			local noticed = distance <= NOTICE_NEAR or (soldier.attacker == enemy and now - soldier.attackedAt <= NOTICE_ATTACKER)
			if noticed or to:Dot(facing) >= FOV_COS * distance then
				local tr = util.TraceLine({ start = eye, endpos = center, mask = MASK_SHOT, filter = ply })
				if not tr.Hit or tr.Entity == enemy then seen[enemy] = Point(enemy:GetPos()) end
			end
		end
	end
	self:TellSight(ply, entry, soldier.vision:Update(now, seen, soldier.better))

	local contact = soldier:Enemy()
	soldier.mayFire = contact ~= nil and not soldier.disarmed and entry.npc:Query("ShouldAttack", contact) ~= NpcSystem.ANSWER_NO
	if soldier.loadout then
		local class = contact and Arms.Choose(soldier.loadout, ply:GetPos():Distance(contact:GetPos())) or soldier.loadout.primary
		soldier.wantWeapon = ply:GetWeapon(class)
	end

	local area = navmesh.GetNavArea(ply:GetPos(), HL2Path.LIMITS.stepHeight * 2)
	if area ~= soldier.navArea then
		entry.npc:Event("OnNavAreaChanged", soldier.navArea, area)
		soldier.navArea = area
		local attributes = IsValid(area) and area:GetAttributes() or 0
		soldier.crouchArea = HL2Path.MustCrouch(attributes)
		soldier.jumpArea = bit.band(attributes, HL2Path.NAV_MESH_JUMP) ~= 0
	end

	for _, weapon in ipairs(ply:GetWeapons()) do
		local ammo = weapon:GetPrimaryAmmoType()
		if ammo >= 0 and ply:GetAmmoCount(ammo) < AMMO_FLOOR then ply:GiveAmmo(AMMO_RESERVE, ammo, true) end
	end

	self:FeelAhead(ply, soldier)
end

-- Fighters (players, NPCs, NextBots) are not obstacles: they move.
local function Obstacle(ent) return not (ent:IsPlayer() or ent:IsNPC() or ent:IsNextBot()) end

-- What stands ahead of it the way it last moved: lowBlocked, headBlocked
-- and doorAhead for its body.
function Controller:FeelAhead(ply, soldier)
	local yaw = soldier.heading
	if not yaw then
		soldier.lowBlocked, soldier.headBlocked, soldier.doorAhead = false, false, false
		return
	end
	local pos = ply:GetPos()
	local ahead = Angle(0, yaw, 0):Forward() * PROBE_REACH
	local low = util.TraceHull({ start = pos + KNEE_LIFT, endpos = pos + KNEE_LIFT + ahead, mins = KNEE_MINS, maxs = KNEE_MAXS, mask = MASK_PLAYERSOLID, filter = Obstacle })
	local head = util.TraceHull({ start = pos + HEAD_LIFT, endpos = pos + HEAD_LIFT + ahead, mins = HEAD_MINS, maxs = HEAD_MAXS, mask = MASK_PLAYERSOLID, filter = Obstacle })
	soldier.lowBlocked, soldier.headBlocked = low.Hit, head.Hit
	soldier.doorAhead = (IsValid(low.Entity) and Map.IsDoor(low.Entity)) or (IsValid(head.Entity) and Map.IsDoor(head.Entity)) or false
end

-- Every look due, the fighters gathered once for all of them.
function Controller:LookAround(now)
	local fighters
	for ply, entry in pairs(self.soldiers) do
		local soldier = entry.soldier
		if IsValid(ply) and ply:IsPlayer() and ply:Alive() and now >= soldier.nextLook then
			soldier.nextLook = now + LOOK_INTERVAL
			fighters = fighters or self:Fighters()
			self:Look(ply, entry, fighters[Teams.EnemyOf(soldier.team)] or {}, now)
		end
	end
end

-- An enemy dead or gone: every bot forgets it.
function Controller:ForgetFighter(ent)
	for ply, entry in pairs(self.soldiers) do
		if IsValid(ply) and ply:IsPlayer() then self:TellSight(ply, entry, entry.soldier.vision:Forget(ent)) end
	end
end

-- Driving --------------------------------------------------------------------------

-- The keys for this tick, from its body's command.
function Controller:Drive(ply, entry, cmd)
	local soldier, now = entry.soldier, CurTime()
	local enemy = soldier:Enemy()
	local vision = soldier.vision
	local aim = enemy and vision:Visible(enemy) and vision:Recognized(enemy, now) and enemy:WorldSpaceCenter() or nil
	local weapon = ply:GetActiveWeapon()
	local arm = IsValid(weapon) and Arms.WEAPONS[weapon:GetClass()]
	local sense, eye = soldier.sense, ply:EyeAngles()
	sense.pos, sense.eyePos = ply:GetPos(), ply:EyePos()
	sense.eye.pitch, sense.eye.yaw = eye.p, eye.y
	sense.speed = ply:GetVelocity():Length2D()
	sense.onGround = ply:OnGround()
	sense.target = soldier.steer
	sense.walk = soldier.gait == Orders.WALK
	sense.crouchArea, sense.jumpArea = soldier.crouchArea, soldier.jumpArea
	sense.hop = soldier:Hopping(now)
	sense.lowBlocked, sense.headBlocked, sense.doorAhead = soldier.lowBlocked, soldier.headBlocked, soldier.doorAhead
	sense.look = soldier.look
	sense.aim, sense.aimRadius = aim, AIM_RADIUS
	local ranges = arm and Arms.Ranges(weapon:GetClass())
	sense.chase, sense.avoid = ranges and ranges.chase, ranges and ranges.avoid
	sense.fire = soldier.mayFire
	sense.weapon = arm and {
		automatic = arm.automatic == true,
		melee = arm.melee == true,
		reach = arm.melee and Arms.MELEE_REACH or arm.reach,
		clip = weapon:Clip1(),
		reserve = ply:GetAmmoCount(weapon:GetPrimaryAmmoType()),
	} or nil
	local out = soldier.body:Command(now, engine.TickInterval(), sense)
	soldier.heading = out.moveYaw

	-- a bot's command angles are where it moves; its eyes are set apart
	if out.moveYaw then
		cmd:SetViewAngles(Angle(0, out.moveYaw, 0))
		cmd:SetForwardMove(FORWARD)
	else
		cmd:SetViewAngles(Angle(out.pitch, out.yaw, 0))
	end
	local buttons = 0
	if out.walk then buttons = bit.bor(buttons, IN_WALK) end
	if out.duck then buttons = bit.bor(buttons, IN_DUCK) end
	if out.jump then buttons = bit.bor(buttons, IN_JUMP) end
	if out.use then buttons = bit.bor(buttons, IN_USE) end
	if out.attack then buttons = bit.bor(buttons, IN_ATTACK) end
	if out.reload then buttons = bit.bor(buttons, IN_RELOAD) end
	cmd:SetButtons(buttons)
	ply:SetEyeAngles(Angle(out.pitch, out.yaw, 0))
	if IsValid(soldier.wantWeapon) and soldier.wantWeapon ~= weapon then cmd:SelectWeapon(soldier.wantWeapon) end
end

-- Hooks ------------------------------------------------------------------------------

-- Every tick, a bot's keys are its body's: the engine's own command for a
-- bot holds IN_DUCK, so a bot with no orders (not yet enlisted, paused,
-- dead) presses nothing. bot_mimic leaves them to copy the host's.
hook.Add("StartCommand", "ws_aiwar_bots", function(ply, cmd)
	if not Controller.bots[ply] or MIMIC:GetBool() then return end
	cmd:ClearButtons()
	cmd:ClearMovement()
	local entry = Controller.war and Controller.soldiers[ply]
	if entry and not Controller.paused and ply:Alive() then Controller:Drive(ply, entry, cmd) end
end)

hook.Add("Think", "ws_aiwar_bots", function()
	local war = Controller.war
	if not war then return end
	local now = CurTime()
	if now >= (Controller.nextQuota or 0) then
		Controller.nextQuota = now + QUOTA_INTERVAL
		Controller:MaintainBotQuota()
		Controller:EnlistStrays()
	end
	if not Controller.paused then Controller:LookAround(now) end
end)

-- After the spawn's own setup (the gamemode's loadout and model), so the
-- kit Equip gives it replaces them.
hook.Add("PlayerSpawn", "ws_aiwar_bots", function(ply)
	if not (Controller.war and Controller.bots[ply]) then return end
	timer.Simple(0, function()
		if IsValid(ply) and Controller.war then Controller:EnlistBot(ply) end
	end)
end)

hook.Add("PlayerHurt", "ws_aiwar_bots", function(ply, attacker, _, damage)
	local entry = Controller.war and Controller.soldiers[ply]
	if not entry or not ply:IsPlayer() then return end
	entry.soldier.attacker, entry.soldier.attackedAt = attacker, CurTime()
	entry.npc:Event("OnInjured", attacker, damage)
end)

hook.Add("PlayerDeath", "ws_aiwar_bots", function(victim, _, attacker)
	if not Controller.war then return end
	Controller:ForgetFighter(victim)
	if Controller.soldiers[victim] then
		Controller:Fallen(victim, attacker)
		Controller:Discharge(victim)
	end
end)

hook.Add("OnNPCKilled", "ws_aiwar_bots", function(ent)
	if Controller.war then Controller:ForgetFighter(ent) end
end)

hook.Add("EntityRemoved", "ws_aiwar_bots", function(ent)
	if Controller.war and (ent:IsPlayer() or ent:IsNPC() or ent:IsNextBot()) then Controller:ForgetFighter(ent) end
end)

hook.Add("PlayerDisconnected", "ws_aiwar_bots", function(ply)
	Controller.bots[ply] = nil
end)
