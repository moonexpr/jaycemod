-- Part of the AI war controller (sv.lua): relationships, humiliation,
-- teammates passing through each other, and how well soldiers shoot
-- (tf_bot_difficulty).
local Controller, Map = ...
local AiWar = WS.require("features.aiwar.model")
local Rounds = gameplay.rounds
local Hearing = nextsoldier.hearing
local Factions = WS.require("ws.factions")
local Marksmanship = WS.require("features.aiwar.marksmanship")
local BulletSteps = WS.require("games.gameplay.combat.bullet_steps")
local RED, BLUE = Map.RED, Map.BLUE
local Point, PassThrough = Map.Point, Map.PassThrough

local RELATIONSHIP_PRIORITY = 99

-- Relationships ---------------------------------------------------------------

local DISPOSITION = { [AiWar.ALLY] = D_LI, [AiWar.ENEMY_OF] = D_HT, [AiWar.FEAR] = D_FR, [AiWar.NEUTRAL] = D_NU }

function Controller:Disposition(team, otherTeam)
	return DISPOSITION[AiWar.Relation(team, otherTeam, self.losers)]
end

-- A soldier toward each team's DrGBase faction (ws.factions; it is
-- in its own team's, WS.SetTeamMember): its team's its allies, the
-- other its enemies, or feared once its side lost. DrGBase relates it so to
-- every soldier and player in each, as they come and go.
--
-- Each SetFactionRelationship has DrGBase update the soldier's relationship
-- with every entity on the map (about 34 ms for all factions), so the
-- dispositions it was last given are kept on it (NSRelations) and set again
-- only when they differ: a new soldier, another team, or the losers changed.
-- A body the reserve revives for its own team keeps its relationships.
function Controller:RelateToFactions(ent, team)
	local dispositions = {}
	for i, entry in ipairs(Factions.ALL) do dispositions[i] = self:Disposition(team, entry.team) end
	local signature = table.concat(dispositions, ",")
	if ent.NSRelations == signature then return end
	for i, entry in ipairs(Factions.ALL) do
		ent:SetFactionRelationship(entry.faction, dispositions[i], RELATIONSHIP_PRIORITY)
	end
	ent.NSRelations = signature
end

-- Gadgets: the grenades, turrets and manhacks soldiers put in the field,
-- each { owner (the soldier's entity), team, kind, expires (or nil) }. They
-- fight for their owner's side, their damage is their owner's, and they do
-- none to its side.
function Controller:AddGadget(gadget, soldier, kind, expires)
	self.gadgets = self.gadgets or {}
	self.gadgets[gadget] = { owner = soldier.ent, team = soldier.team, kind = kind, expires = expires }
	if gadget:IsNPC() then self:RelateGadget(gadget) end
end

function Controller:GadgetsOf(soldier, kind)
	local n = 0
	for gadget, info in pairs(self.gadgets or {}) do
		if info.owner == soldier.ent and info.kind == kind and IsValid(gadget) and gadget:Health() > 0 then n = n + 1 end
	end
	return n
end

-- Bot players are related as players are (DrGBase and the engine relate to
-- a player by its team): the soldier passes below are the NPCs'.
function Controller:RelateGadget(gadget)
	local info = self.gadgets[gadget]
	for ent, entry in pairs(self.soldiers) do
		if IsValid(ent) and not ent:IsPlayer() then
			gadget:AddEntityRelationship(ent, self:Disposition(info.team, entry.soldier.team), RELATIONSHIP_PRIORITY)
			ent:AddEntityRelationship(gadget, self:Disposition(entry.soldier.team, info.team), RELATIONSHIP_PRIORITY)
		end
	end
	for _, ply in ipairs(player.GetAll()) do
		gadget:AddEntityRelationship(ply, self:Disposition(info.team, WS.TeamOf(ply)), RELATIONSHIP_PRIORITY)
	end
	for other, otherInfo in pairs(self.gadgets) do
		if other ~= gadget and IsValid(other) and other:IsNPC() then
			gadget:AddEntityRelationship(other, self:Disposition(info.team, otherInfo.team), RELATIONSHIP_PRIORITY)
			other:AddEntityRelationship(gadget, self:Disposition(otherInfo.team, info.team), RELATIONSHIP_PRIORITY)
		end
	end
end

-- Gone gadgets are forgotten, spent manhacks removed, and the rest related
-- again to soldiers and players that came since. owner: only that
-- soldier's (which leaves); all: every one (the war ends or the round resets).
function Controller:SweepGadgets(owner, all)
	if not self.gadgets then return end
	local now = CurTime()
	for gadget, info in pairs(self.gadgets) do
		local remove = all or (owner and info.owner == owner and info.kind ~= "grenade") or (info.expires and now >= info.expires)
		if not IsValid(gadget) then
			self.gadgets[gadget] = nil
		elseif remove then
			self.gadgets[gadget] = nil
			gadget:Remove()
		elseif not owner and gadget:IsNPC() then
			self:RelateGadget(gadget)
		end
	end
end

-- The team a damaged entity fights for, or nil.
function Controller:TeamOf(ent)
	if ent:IsPlayer() then return WS.TeamOf(ent) end
	local entry = self.soldiers[ent]
	if entry then return entry.soldier.team end
	local info = self.gadgets and self.gadgets[ent]
	return info and info.team or nil
end

-- Gunfire (nextsoldier.hearing): each soldier in earshot of a shot is
-- told where to look (OnHeard). A shooter is heard once every
-- HEAR_INTERVAL, however fast it fires.
local HEAR_INTERVAL = 0.5

function Controller:HearShot(shooter, data)
	if shooter:IsWeapon() then shooter = shooter:GetOwner() end
	if not IsValid(shooter) then return end
	local now = CurTime()
	if (shooter.NSHeardUntil or 0) > now then return end
	shooter.NSHeardUntil = now + HEAR_INTERVAL
	local shot = { team = self:TeamOf(shooter), pos = Point(shooter:GetPos()), dir = Point(data.Dir:GetNormalized()) }
	for ent, entry in pairs(self.soldiers) do
		if ent ~= shooter and IsValid(ent) then
			local look = Hearing.LookAt({ team = entry.soldier.team, pos = Point(ent:GetPos()) }, shot)
			if look then entry.npc:Event("OnHeard", look) end
		end
	end
end

-- A gadget's damage: its owner's, and none to its own side. Returns true
-- to cancel it.
function Controller:GadgetDamage(target, dmg)
	local gadgets = self.gadgets
	if not gadgets then return false end
	local info = gadgets[dmg:GetInflictor()] or gadgets[dmg:GetAttacker()]
	if not info then return false end
	if IsValid(info.owner) then dmg:SetAttacker(info.owner) end
	return info.team == self:TeamOf(target)
end

-- TF2's NPCs (Sandcastle's base_nextsoldier_npc variants: tf_zombie's skeletons
-- and whatever joins them) take sides by their team: a RED or BLU one is
-- a teammate or an enemy as a player of that team is; any other (the
-- HALLOWEEN team's) is everyone's enemy. Soldiers and their gadgets are
-- related to each one they have not been yet, every relationship pass.
local function IsTFNpc(ent)
	return IsValid(ent) and ent:IsNextBot() and ent.Variant ~= nil and ent.GetTeamNumber ~= nil
end

function Controller:NoteMonster(ent)
	if not IsTFNpc(ent) then return end
	self.monsters = self.monsters or {}
	self.monsters[ent] = true
end

function Controller:MonsterDisposition(team, monster)
	local monsterTeam = monster:GetTeamNumber()
	if monsterTeam == RED or monsterTeam == BLUE then return self:Disposition(team, monsterTeam) end
	return team == self.losers and D_FR or D_HT
end

function Controller:RelateMonsters()
	if not self.monsters then return end
	for monster in pairs(self.monsters) do
		if not IsValid(monster) or monster:Health() <= 0 then
			self.monsters[monster] = nil
		else
			for ent, entry in pairs(self.soldiers) do
				local disposition = IsValid(ent) and not ent:IsPlayer() and self:MonsterDisposition(entry.soldier.team, monster)
				if disposition and entry.soldier.relations[monster] ~= disposition then
					entry.soldier.relations[monster] = disposition
					ent:AddEntityRelationship(monster, disposition, RELATIONSHIP_PRIORITY)
				end
			end
			for gadget, info in pairs(self.gadgets or {}) do
				if IsValid(gadget) and gadget:IsNPC() then
					gadget:AddEntityRelationship(monster, self:MonsterDisposition(info.team, monster), RELATIONSHIP_PRIORITY)
				end
			end
		end
	end
end

-- Players fight beside the faction on their team (the Combine on BLU and
-- the Resistance on RED until the sides trade), and the rest (spectators,
-- the unassigned) are left alone.
function Controller:RelatePlayers()
	for ent, entry in pairs(self.soldiers) do
		if IsValid(ent) and not ent:IsPlayer() then
			for _, ply in ipairs(player.GetAll()) do
				local disposition = self:Disposition(entry.soldier.team, WS.TeamOf(ply))
				if entry.soldier.relations[ply] ~= disposition then
					entry.soldier.relations[ply] = disposition
					ent:AddEntityRelationship(ply, disposition, RELATIONSHIP_PRIORITY)
				end
			end
		end
	end
end

-- Every soldier toward each faction and every player, again (the losers changed).
function Controller:RelateEveryone()
	for ent, entry in pairs(self.soldiers) do
		if IsValid(ent) and not ent:IsPlayer() then
			self:RelateToFactions(ent, entry.soldier.team)
			entry.soldier.relations = {}
		end
	end
	self.nextRelations = 0
end

-- Humiliation ------------------------------------------------------------------------
-- TF2's losers cannot attack while the winners celebrate (for players,
-- WS.RestrictCommand). A losing soldier stops firing (the port's
-- IsDisarmed, which its orders answer ShouldAttack with) and fears its
-- enemies: DrGBase keeps away from what it fears. The winners hunt them.
function Controller:Disarm(ent, entry)
	if entry.disarmed then return end
	entry.disarmed = true
	entry.soldier.disarmed = true
end

function Controller:Rearm(ent, entry)
	if not entry.disarmed then return end
	entry.disarmed = nil
	entry.soldier.disarmed = nil
end

-- losers: the team humiliated, or nil for none.
function Controller:Humiliate(losers)
	self.losers = losers
	for ent, entry in pairs(self.soldiers) do
		if IsValid(ent) then
			if entry.soldier.team == losers then self:Disarm(ent, entry) else self:Rearm(ent, entry) end
		end
	end
	self:RelateEveryone()
end

-- A round won: winner is the team that won it, or none on a stalemate. The
-- winners hunt through the humiliation phase (AiWar.PhaseOf) while the
-- losers are humiliated; RespawnAll ends it with the next round. A
-- defenders' win (AiWar.DefenderWon) has the factions trade sides then.
function Controller:RoundWon(winner, reason)
	local losers = AiWar.LosersOf(winner)
	self.winner = losers and winner or nil
	self:Humiliate(losers)
	local defended = reason == Rounds.WINREASON.DEFEND_UNTIL_TIME_LIMIT
	local field = self.war:Field()
	self.swapFactions = AiWar.DefenderWon(winner, defended, field and field.carts or {})
end

-- Teammates pass through each other ---------------------------------------------------
-- An engine NPC's movement checks (CTraceFilterNav, ai_utils.cpp) skip any
-- entity it is paired with in the engine's collision pair table, which
-- logic_collision_pair fills (as Sandbox's No Collide does), so a teammate
-- in a doorway no longer blocks a soldier's run. Enemies still collide.
-- Each pair goes with either of its soldiers.

function Controller:PassTeammates(ent, team)
	for other, entry in pairs(self.soldiers) do
		if other ~= ent and IsValid(other) and entry.soldier.team == team then PassThrough(ent, other) end
	end
end

-- Marksmanship -----------------------------------------------------------------

local DIFFICULTY = GetConVar("tf_bot_difficulty") -- ws/sh_votes.lua's, replicated for the difficulty vote

local function Skill() return Marksmanship.For(DIFFICULTY:GetInt()) end

-- A soldier's shot (its gun's or its own): turned off its aim and its
-- spread widened by the difficulty. Whether the shot changed.
function Controller:Marksman(ent, data)
	local shooter = ent:IsWeapon() and ent:GetOwner() or ent
	if not self.soldiers[shooter] then return false end
	local skill = Skill()
	if skill.aimError <= 0 and skill.spreadScale == 1 then return false end
	local dir = Marksmanship.Aim(data.Dir:GetNormalized(), skill.aimError, math.random(), math.random())
	data.Dir = Vector(dir.x, dir.y, dir.z)
	local spread = Marksmanship.Spread(data.Spread or vector_origin, skill.spreadScale)
	data.Spread = Vector(spread.x, spread.y, spread.z)
	return true
end

-- A new enemy: no shot at it for the difficulty's reaction time
-- (ws/sh_war_soldier.lua's OnRangeAttack reads NSReactAt).
hook.Add("WSSoldierContact", "ws_aiwar_reaction", function(ent)
	if not Controller.soldiers[ent] then return end
	ent.NSReactAt = CurTime() + Skill().reaction
end)

WS.BulletSteps:Add("ws_aiwar", BulletSteps.AIM, function(ent, data)
	if not Controller.war then return end
	local changed = Controller:Marksman(ent, data)
	Controller:HearShot(ent, data)
	if changed then return BulletSteps.CHANGED end
end)

hook.Add("WSRoundWin", "ws_aiwar", function(winner, reason)
	if Controller.war then Controller:RoundWon(winner, reason) end
end)

-- The match won is a round won to its music: the winners hunt, the losers
-- are humiliated.
hook.Add("WSMatchWin", "ws_aiwar", function(winner)
	if Controller.war then Controller:RoundWon(winner) end
end)
