-- Part of the AI war controller (sv.lua): enlisting, kits, medics, discharge, spawning, waves and seats.
local Controller, Map = ...
local AiWar = WS.require("foundation.aiwar")
local Teams = WS.require("foundation.teams")
local Orders = WS.require("foundation.aiwar.orders")
local NpcSystem = WS.require("foundation.npc")
local SPAWN_LIFT, RED, BLUE = Map.SPAWN_LIFT, Map.RED, Map.BLUE
local Point, Masks, SpawnSpots, ClearSpotNear = Map.Point, Map.Masks, Map.SpawnSpots, Map.ClearSpotNear

-- Enlisting ---------------------------------------------------------------------

-- fixed: the job it only ever does (a drafted medic); by default its
-- class's (the vortigaunt's).
function Controller:Enlist(ent, team, drafted, fixed)
	local member = self.war:Enlist(ent, team, drafted, fixed or AiWar.FixedRole(ent:GetClass()))
	-- a drafted soldier fills a slot of its faction, and leads or follows as it is pinned
	if drafted then member.pin = self:SlotPlan():Fill(self:FactionName(team), ent).pin end
	if self.paused then ent:SetAIDisabled(true) end
	-- a NextBot's locomotion moves under its solid mask; an HL2 NPC's mask is the engine's
	if ent:IsNextBot() then ent:SetSolidMask(Masks().solid) end
	local soldier = self.Soldier.New(ent, self, team)
	self.soldiers[ent] = {
		soldier = soldier,
		npc = NpcSystem.Npc.New(Orders, { war = self.war, member = member }, soldier),
	}
	-- DrGBase's hooks ask and tell the orders (ws_drg_soldier's bridge)
	ent.NSBrain = self.soldiers[ent].npc
	WS.SetTeamMember(ent, team)
	self:RelateToFactions(ent, team)
	self:PassTeammates(ent, team)
	self:JoinSquad(ent, member)
	if team == self.losers then self:Disarm(ent, self.soldiers[ent]) end
	self.nextRelations = 0
end

-- The member's fire team, for the report; DrGBase has no squads of its
-- own, so fire teams are the orders' alone.
function Controller:JoinSquad(ent, member)
	ent.wsSquad = member and member.fireTeam and member.fireTeam.squad or nil
end

-- Kits (ws_drg_soldier's NSKit), by side and role: blockers and
-- a point's holders carry the shotgun, hit harder and charge faster;
-- raiders carry the crossbow (the Resistance) and throw grenades; the
-- Combine's support are
-- metrocops who deploy a turret and send manhacks, the Resistance's are its
-- heroes, who hit hard; the rest leave those weapons to them. Soldier:UseGadget
-- uses a kit's gadgets.
local BLOCKER_KIT = { name = "shotgunner", weapons = { "weapon_shotgun" }, damage = 1.5, runSpeed = 260 }
local KITS = {
	[RED] = {
		[AiWar.BLOCK] = BLOCKER_KIT,
		[AiWar.HOLD] = BLOCKER_KIT,
		[AiWar.RAID] = { name = "grenadier", weapons = { "weapon_ar2" }, gadgets = { "grenade" } },
		[AiWar.SUPPORT] = {
			name = "metrocop", model = "models/player/police.mdl", weapons = { "weapon_smg1", "weapon_pistol" },
			gadgets = { "turret", "manhack" },
		},
		default = { avoid = { weapon_shotgun = true, weapon_pistol = true } },
	},
	[BLUE] = {
		[AiWar.BLOCK] = BLOCKER_KIT,
		[AiWar.HOLD] = BLOCKER_KIT,
		[AiWar.RAID] = { name = "crossbow", weapons = { "weapon_crossbow" }, gadgets = { "grenade" } },
		default = { avoid = { weapon_shotgun = true, weapon_crossbow = true, weapon_357 = true } },
	},
}
-- Medics: the Combine's are metrocops, the Resistance's vortigaunts (their
-- own class, AiWar.FixedRole). They speak on taking a patient: HL2's lines,
-- those of the list the game has (MedicLines keeps only files that exist,
-- so a missing episode costs lines, not errors).
local MEDIC_KITS = {
	[RED] = {
		name = "metrocop medic", model = "models/player/police.mdl", weapons = { "weapon_pistol" },
		voice = {
			"npc/metropolice/vo/administer.wav", "npc/metropolice/vo/affirmative.wav",
			"npc/metropolice/vo/affirmative2.wav", "npc/metropolice/vo/tenfour.wav",
			"npc/metropolice/vo/ten8standingby.wav", "npc/metropolice/vo/copy.wav",
			"npc/metropolice/vo/rodgerthat.wav", "npc/metropolice/vo/officerneedshelp.wav",
		},
	},
	[BLUE] = {
		name = "vortigaunt medic",
		voice = {
			"vo/npc/vortigaunt/vques01.wav", "vo/npc/vortigaunt/vques02.wav", "vo/npc/vortigaunt/vques03.wav",
			"vo/npc/vortigaunt/vanswer01.wav", "vo/npc/vortigaunt/vanswer02.wav", "vo/npc/vortigaunt/vanswer03.wav",
			"vo/npc/vortigaunt/vanswer04.wav", "vo/npc/vortigaunt/vanswer05.wav",
			"vo/npc/vortigaunt/allowme.wav", "vo/npc/vortigaunt/certainly.wav",
		},
		-- the vortigaunt's charge as the beam starts
		beamSound = "npc/vort/attack_charge.wav",
	},
}

local medicLines = {}

local function MedicLines(kit)
	if medicLines[kit] == nil then
		local found = {}
		for _, path in ipairs(kit.voice or {}) do
			if file.Exists("sound/" .. path, "GAME") then found[#found + 1] = path end
		end
		medicLines[kit] = found
		print(string.format("AI war: %s voice: %d of %d lines found", kit.name, #found, #(kit.voice or {})))
	end
	return medicLines[kit]
end

-- The Resistance's heroes, one of each alive at a time; support beyond them
-- are veterans.
local HEROES = {
	{ name = "Alyx", hero = true, model = "models/player/alyx.mdl", weapons = { "weapon_357" }, health = 250, damage = 2 },
	{ name = "Barney", hero = true, model = "models/player/barney.mdl", weapons = { "weapon_ar2" }, health = 300, damage = 1.75 },
}
local VETERAN = { name = "veteran", weapons = { "weapon_ar2" }, health = 200, damage = 1.5 }

function Controller:HeroKit(ent)
	self.heroes = self.heroes or {}
	for _, hero in ipairs(HEROES) do
		local holder = self.heroes[hero.name]
		if holder == ent or not (IsValid(holder) and self.soldiers[holder]) then
			self.heroes[hero.name] = ent
			return hero
		end
	end
	return VETERAN
end

function Controller:Equip(ent, entry, member)
	local role = member and member.role or false
	if entry.equipped == role or not ent.NSKit then return end
	entry.equipped = role
	local team = entry.soldier.team
	if self.heroes then
		for name, holder in pairs(self.heroes) do
			if holder == ent then self.heroes[name] = nil end
		end
	end
	local kits = KITS[team] or {}
	local kit = (role == AiWar.MEDIC and MEDIC_KITS[team]) or kits[role] or (team == BLUE and role == AiWar.SUPPORT and self:HeroKit(ent)) or kits.default or {}
	entry.soldier.kit = kit
	-- a hero leads its squad (foundation.aiwar.squad)
	if member then member.hero = kit.hero == true or nil end
	ent:NSKit(kit)
end

-- A soldier died: OnOtherKilled(victim, its team) to every soldier within
-- OTHER_KILLED_RANGE (TF2's tactical monitor hears of every death).
local OTHER_KILLED_RANGE = 1500

function Controller:TellKilled(ent, entry)
	if not IsValid(ent) or ent:Health() > 0 then return end
	local pos = ent:GetPos()
	for other, otherEntry in pairs(self.soldiers) do
		if IsValid(other) and other:GetPos():DistToSqr(pos) <= OTHER_KILLED_RANGE * OTHER_KILLED_RANGE then
			otherEntry.npc:Event("OnOtherKilled", ent, entry.soldier.team)
		end
	end
end

function Controller:Discharge(ent)
	local entry = self.soldiers[ent]
	if not entry then return end
	entry.soldier:Stand()
	self.soldiers[ent] = nil
	if IsValid(ent) then ent.NSBrain = nil end
	self:TellKilled(ent, entry)
	self:SweepGadgets(ent)
	entry.soldier:Unpose()
	entry.soldier:RemoveScript()
	if IsValid(ent) then self:Rearm(ent, entry) end
	self.war:Discharge(ent)
	self:SlotPlan():Vacate(ent)
	entry.npc:Destroy()
	WS.SetTeamMember(ent, nil)
end

-- A Combine or Resistance NPC that appeared on its own (a player spawned
-- it) joins its side, once its spawn has finished.
function Controller:Consider(ent)
	if not self.war or self.soldiers[ent] or not IsValid(ent) or not (ent:IsNPC() or ent:IsNextBot()) then return end
	local team = self.war:FactionTeam(ent:GetClass())
	if team and ent:Health() > 0 then self:Enlist(ent, team, false) end
end

-- Spawning ------------------------------------------------------------------------

-- A recruit: a body the reserve kept, revived (sv_reserve.lua), else a new
-- entity.
function Controller:Draft(team, pos, ang)
	local draft = self.war:Draft(team)
	local recruit = draft.recruit
	local ent = self:Revive(team, recruit.class, pos + SPAWN_LIFT, ang)
	if ent == nil then
		ent = ents.Create(recruit.class)
		if not IsValid(ent) then return end
		ent:SetPos(pos + SPAWN_LIFT)
		ent:SetAngles(ang)
		ent:Spawn()
		ent:Activate()
	end
	self:Enlist(ent, team, true, draft.role)
end

-- TF2's respawn wave for the team (0 during setup, when TF2 respawns at
-- once), or none without gamerules. With respawns stopped by an admin, or in
-- sudden death, the last wave was the last.
local function WaveLength(team)
	if not IsValid(WS.Rules) then return 0 end
	if WS.Rules:RespawnsDisabled() or WS.State() == WS.STATE.STALEMATE then return math.huge end
	if WS.InSetup() then return 0 end
	return WS.Rules:GetRespawnWaveMaxLength(team, true)
end

function Controller:Reinforce(now)
	for team, count in pairs(self.war:Reinforcements(now, self:Sizes(), WaveLength)) do
		local spots = SpawnSpots(team)
		for i = 1, #spots > 0 and count or 0 do
			local spot = spots[(i - 1) % #spots + 1]
			local pos = ClearSpotNear(spot:GetPos())
			if pos then self:Draft(team, pos, spot:GetAngles()) end
		end
	end
end

-- A new round or stage: every soldier starts again from its side's spawn,
-- as TF2 respawns every player (RoundRespawn). The war's own soldiers are
-- replaced by a fresh wave; the ones players spawned are healed, rearmed
-- and moved to a spawn point (on a stage of a multi-stage map, the new
-- stage's), and their orders start over. The round's winner, the bases and
-- the posts are the last round's, and the scenario starts the round afresh.
function Controller:RespawnAll()
	self:DisbandReserve()
	self:SweepGadgets(nil, true)
	self.lanePlans, self.laneSets = nil, nil
	self.roomExits = nil
	self.gates = nil
	self.shutDoors = nil
	self.zones = nil
	self.postCache = nil
	self.baseCache = nil
	self.losers = nil
	self.winner = nil
	if self.swapFactions then
		self.swapFactions = nil
		self.war:SwapFactions()
	end
	self.scenario:Reset()
	local entries = {}
	for ent, entry in pairs(self.soldiers) do entries[#entries + 1] = { ent = ent, entry = entry } end
	local spots, used = {}, {}
	for _, e in ipairs(entries) do
		local ent = e.ent
		if IsValid(ent) then
			-- a soldier a player spawned follows its faction to its side
			local team = self.war:FactionTeam(ent:GetClass()) or e.entry.soldier.team
			local drafted = self.war:Member(ent).drafted
			e.entry.soldier:Release()
			self:Discharge(ent)
			if drafted then
				ent:Remove()
			else
				spots[team] = spots[team] or SpawnSpots(team)
				used[team] = (used[team] or 0) + 1
				local spot = spots[team][(used[team] - 1) % math.max(#spots[team], 1) + 1]
				local pos = spot and ClearSpotNear(spot:GetPos())
				if pos then
					ent:SetPos(pos + SPAWN_LIFT)
					ent:SetAngles(spot:GetAngles())
				end
				ent:SetHealth(ent:GetMaxHealth())
				self:Enlist(ent, team, false)
			end
		end
	end
	self:RelateEveryone()
	self.war:ResetWaves()
end

-- Each tick, a moving soldier's pace and the door watchdog.
-- A medic's beam: HEAL_RATE health a second (TF2's medigun) to its target
-- while it is alive, in reach (HEAL_REACH) and in sight, up to its most.
-- The beam is shown while it heals ("WSHealing", drawn on clients),
-- and the medic speaks on taking a new patient, at most every HEAL_VOICE.
local HEAL_RATE, HEAL_REACH, HEAL_VOICE = 24, 520, 10

function Controller:ApplyHeal(ent, entry, dt)
	local soldier, target = entry.soldier, entry.soldier.healTarget
	local member = self.war:Member(ent)
	local healing = IsValid(target) and target:Health() > 0 and member and member.role == AiWar.MEDIC
		and not soldier.disarmed and ent:GetPos():Distance(target:GetPos()) <= HEAL_REACH
	if healing then
		local tr = util.TraceLine({ start = ent:WorldSpaceCenter(), endpos = target:WorldSpaceCenter(), mask = MASK_SOLID_BRUSHONLY })
		healing = not tr.Hit
	end
	local shown = ent:GetNW2Entity("WSHealing")
	if not healing then
		if IsValid(shown) then ent:SetNW2Entity("WSHealing", NULL) end
		soldier.healCarry = 0
		return
	end
	if shown ~= target then
		ent:SetNW2Entity("WSHealing", target)
		local kit = soldier.kit or {}
		if kit.beamSound then ent:EmitSound(kit.beamSound, 70, 110) end
		local lines = MedicLines(kit)
		if #lines > 0 and CurTime() >= (soldier.voiceAt or 0) then
			soldier.voiceAt = CurTime() + HEAL_VOICE
			ent:EmitSound(lines[math.random(#lines)], 80)
		end
	end
	local most = target:GetMaxHealth()
	if target:Health() >= most then return end
	soldier.healCarry = (soldier.healCarry or 0) + HEAL_RATE * dt
	local whole = math.floor(soldier.healCarry)
	if whole > 0 then
		soldier.healCarry = soldier.healCarry - whole
		target:SetHealth(math.min(most, target:Health() + whole))
	end
end

-- Every seated soldier gets off beside its cart (Stand does nothing to one
-- on foot).
function Controller:StandSeated()
	for _, entry in pairs(self.soldiers) do entry.soldier:Stand() end
end

cvars.AddChangeCallback("ws_aiwar_sitting_enabled", function(_, _, value)
	if value == "0" then Controller:StandSeated() end
end, "ws_aiwar")

-- A seated soldier rides its seat: moved with the cart every tick, facing
-- out over its side; a cart gone, it stands.
function Controller:CarrySeated(ent, soldier)
	local seat = soldier.seat
	if not IsValid(seat.train) then
		soldier:Stand()
		return
	end
	ent:SetPos(seat.train:LocalToWorld(seat.offset))
	ent:SetAngles(Angle(0, seat.train:GetAngles().y + 90 * seat.side, 0))
	if ent.loco then ent.loco:SetVelocity(vector_origin) end
end

hook.Add("Tick", "ws_aiwar_move", function()
	if not Controller.war then return end
	local dt = engine.TickInterval()
	for ent, entry in pairs(Controller.soldiers) do
		if IsValid(ent) and entry.soldier.seat then Controller:CarrySeated(ent, entry.soldier) end
		if IsValid(ent) then
			if entry.soldier.moveTarget then entry.soldier:Move(dt) end
			if entry.soldier.healTarget or IsValid(ent:GetNW2Entity("WSHealing")) then Controller:ApplyHeal(ent, entry, dt) end
		end
	end
end)

hook.Add("OnEntityCreated", "ws_aiwar", function(ent)
	if not Controller.war then return end
	timer.Simple(0, function()
		if not Controller.war or not IsValid(ent) then return end
		if AiWar.FactionTeam(ent:GetClass()) then Controller:Consider(ent) else Controller:NoteMonster(ent) end
	end)
end)

hook.Add("EntityRemoved", "ws_aiwar", function(ent)
	if Controller.war then Controller:Discharge(ent) end
end)

hook.Add("EntityTakeDamage", "ws_aiwar", function(target, dmg)
	local soldier = Controller.war and Controller.soldiers[target]
	if soldier then
		local train = Controller:CartTrigger(dmg)
		if train then
			-- a rider sits over the cart's kill trigger: no harm, no rescue
			if not soldier.soldier.seat then Controller:EjectFromCart(target, soldier, train) end
			return true
		end
	end
	if Controller.war and Controller:GadgetDamage(target, dmg) then return true end
	local entry = Controller.war and Controller.soldiers[target]
	if entry and dmg:GetDamage() > 0 then entry.soldier.hurtAt = CurTime() end
end)

-- A soldier's squad investigates its death (War:Fallen): its killer's
-- place when an enemy killed it, else where it fell.
function Controller:Fallen(ent, attacker)
	local entry = self.soldiers[ent]
	if not entry then return end
	local killer = IsValid(attacker) and attacker ~= ent and WS.LastTeamNumber(attacker) == Teams.EnemyOf(entry.soldier.team)
	self.war:Fallen(ent, Point(ent:GetPos()), killer and Point(attacker:GetPos()) or nil, CurTime())
end

hook.Add("OnNPCKilled", "ws_aiwar", function(ent, attacker)
	if not Controller.war then return end
	Controller:Fallen(ent, attacker)
	local entry = Controller.soldiers[ent]
	if entry then Controller:Retire(ent, WaveLength(entry.soldier.team)) end
	Controller:Discharge(ent)
end)

-- Every round and every stage of a multi-stage map (pl_dustbowl,
-- pl_goldrush) starts with everyone back at spawn: a stage keeps the map
-- as it is, so without this the soldiers would stay where the last stage
-- left them.
hook.Add("WSRoundActivate", "ws_aiwar", function()
	if Controller.war then Controller:RespawnAll() end
end)
