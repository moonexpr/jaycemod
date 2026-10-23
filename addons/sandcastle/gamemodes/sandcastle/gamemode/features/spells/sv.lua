-- The spells feature's controller. It owns the features.spells.model Library
-- (one SpellBook per caster: a player, or an NPC an AI layer grants one to)
-- and a Shot per spell projectile or spawner, implements the caster port
-- over any caster entity, hands living RED and BLU players
-- tf_weapon_spellbook while spells are on (and a book to anyone who equips
-- the weapon otherwise), casts on TF2's
-- +use_action_slot_item, networks a player's book to the weapon, and
-- applies the conditions only spells give. The holiday controller loads
-- this feature when spells turn on; the players' books follow its
-- UsingSpells() from then on.
local Spells = WS.require("features.spells.model")
local SpellSet = WS.require("features.spells.halloween")

local P = WS.PlayerRules
local C = P.COND

local holiday = WS.Feature("holiday")
local combat = WS.Feature("combat")

local WEAPON = "tf_weapon_spellbook"
local CAST_COMMAND = "+use_action_slot_item"
local CAST_RELEASE = "-use_action_slot_item"
local THINK_TIMER = "ws_spells_think"
local THINK_INTERVAL = 0.1

-- What the weapon networks; the spells view reads the same names.
local NW_SELECTED = "ws_spell_selected"
local NW_CHARGES = "ws_spell_charges"
local NW_ROLLING_UNTIL = "ws_spell_rolling_until"
local NOT_ROLLING = 0

-- The conditions only spells give (CTFPlayerShared::OnAddHalloweenTiny's
-- scale; stealth draws nothing).
local TINY_SCALE = 0.5
local NORMAL_SCALE = 1

-- CTFPlayerShared::IsInvulnerable
local INVULNERABLE_CONDS = {
	C.INVULNERABLE,
	C.INVULNERABLE_USER_BUFF,
	C.INVULNERABLE_HIDE_UNLESS_DAMAGED,
	C.INVULNERABLE_CARD_EFFECT,
}

-- The teleport spell's flash (UTIL_ScreenFade( pThrower, {255,255,255,100}, 0.25, 0.4, FFADE_IN )).
local FADE_COLOR = Color(255, 255, 255, 100)
local FADE_TIME, FADE_HOLD = 0.25, 0.4

-- MASK_SHOT & ~CONTENTS_HITBOX: what the spells' sight traces stop at.
local SIGHT_MASK = bit.band(MASK_SHOT, bit.bnot(CONTENTS_HITBOX))
-- The spawn boss's sweep: MASK_SOLID | CONTENTS_PLAYERCLIP, past players and NPCs.
local ROOM_MASK = bit.bor(MASK_SOLID, CONTENTS_PLAYERCLIP)
local NO_ATTACHMENT = -1

local function IsCharacter(ent)
	return ent:IsPlayer() or ent:IsNPC() or ent:IsNextBot()
end

local function OnlyWorld(ent)
	return ent:IsWorld()
end

local function NotCharacter(ent)
	return not IsCharacter(ent)
end

local function IsAlive(ent)
	if ent:IsPlayer() then return WS.IsAliveInGame(ent) end
	return ent:Health() > 0
end

-------------------------------------------------------------------------------
-- The caster port (features.spells.caster) over a caster entity

local Caster = {}
Caster.__index = Caster

local function NewCaster(ent)
	return setmetatable({ ent = ent }, Caster)
end

function Caster:Now() return CurTime() end
function Caster:RandomFloat(lo, hi) return math.Rand(lo, hi) end
function Caster:RandomInt(lo, hi) return math.random(lo, hi) end
function Caster:Vector(x, y, z) return Vector(x, y, z) end

function Caster:Owner() return self.ent end
function Caster:TeamOf(t) return combat:TeamOf(t) end
function Caster:IsAlive(t) return IsAlive(t) end
function Caster:IsPlayer(t) return t:IsPlayer() end
function Caster:IsOnGround(t) return t:IsOnGround() end
function Caster:Origin(t) return t:GetPos() end
function Caster:Center(t) return t:WorldSpaceCenter() end
function Caster:EyePosition(t) return t:EyePos() end

function Caster:InCond(t, cond)
	return WS.InCondition(t, cond)
end

function Caster:IsInvulnerable(t)
	for _, cond in ipairs(INVULNERABLE_CONDS) do
		if WS.InCondition(t, cond) then return true end
	end
	return false
end

-- Players and engine NPCs have a weapon's shoot position; a nextbot
-- throws from its eyes.
function Caster:ShootPosition()
	local ent = self.ent
	if ent:IsPlayer() or ent:IsNPC() then return ent:GetShootPos() end
	return ent:EyePos()
end

function Caster:EyeVectors()
	local angles = self.ent:EyeAngles()
	return angles:Forward(), angles:Right(), angles:Up()
end

function Caster:TraceHull(from, to, mins, maxs)
	local tr = util.TraceHull({
		start = from,
		endpos = to,
		mins = mins,
		maxs = maxs,
		mask = ROOM_MASK,
		filter = NotCharacter,
	})
	return {
		startSolid = tr.StartSolid,
		endPos = tr.HitPos,
	}
end

function Caster:TraceLine(from, to)
	local tr = util.TraceLine({
		start = from,
		endpos = to,
		mask = SIGHT_MASK,
	})
	return {
		hit = tr.Hit,
		endPos = tr.HitPos,
		normal = tr.HitNormal,
	}
end

-- CTraceFilterIgnorePlayers and DidHitWorld: only the world blocks.
function Caster:IsVisible(from, to)
	return not util.TraceLine({
		start = from,
		endpos = to,
		mask = SIGHT_MASK,
		filter = OnlyWorld,
	}).HitWorld
end

-- The teleport's check: t's hull at pos, clear of the world and the other
-- team.
function Caster:Fits(t, pos)
	local mins, maxs = t:OBBMins(), t:OBBMaxs()
	if t:IsPlayer() then mins, maxs = t:GetHull() end
	local team = combat:TeamOf(t)
	local tr = util.TraceHull({
		start = pos,
		endpos = pos,
		mins = mins,
		maxs = maxs,
		mask = MASK_PLAYERSOLID,
		filter = function(ent) return ent ~= t and not (IsCharacter(ent) and combat:TeamOf(ent) == team) end,
	})
	return not (tr.Hit or tr.StartSolid)
end

function Caster:EntitiesInSphere(center, radius)
	local found = {}
	for _, ent in ipairs(ents.FindInSphere(center, radius)) do
		if IsCharacter(ent) then found[#found + 1] = ent end
	end
	return found
end

-- TakeHealth: up to max health.
function Caster:Heal(t, amount)
	local max = t:GetMaxHealth()
	if t:Health() < max then t:SetHealth(math.min(max, t:Health() + amount)) end
end

function Caster:AddCond(t, cond, duration)
	WS.AddCondition(t, cond, duration)
end

function Caster:Stun(t, duration, reduction)
	WS.StunPlayer(t, duration, reduction, P.STUN.MOVEMENT)
end

function Caster:GetVelocity(t)
	return t:GetVelocity()
end

-- A player's SetVelocity adds to its velocity; a nextbot moves by its
-- locomotor.
function Caster:SetVelocity(t, v)
	if t:IsPlayer() then
		t:SetVelocity(v - t:GetVelocity())
	elseif t.loco then
		t.loco:SetVelocity(v)
	else
		t:SetVelocity(v)
	end
end

-- ApplyGenericPushbackImpulse: off the ground, then the impulse.
function Caster:Push(t, v)
	if t:IsPlayer() then
		t:SetGroundEntity(NULL)
		t:SetVelocity(v)
	else
		self:SetVelocity(t, t:GetVelocity() + v)
	end
end

function Caster:Damage(t, amount, dmgType, inflictor)
	local dmg = DamageInfo()
	dmg:SetDamage(amount)
	dmg:SetDamageType(dmgType)
	dmg:SetAttacker(self.ent)
	dmg:SetInflictor(IsValid(inflictor) and inflictor or self.ent)
	dmg:SetDamagePosition(t:WorldSpaceCenter())
	t:TakeDamageInfo(dmg)
end

function Caster:Explode(config)
	combat:Explode(config)
end

-- Every spell entity takes its config through Configure and belongs to
-- its caster.
local function Create(caster, class, config, pos)
	local ent = ents.Create(class)
	ent:SetOwner(caster)
	ent:Configure(config)
	ent:SetPos(pos)
	ent:Spawn()
	return ent
end

function Caster:LaunchProjectile(class, config)
	return Create(self.ent, class, config, config.position)
end

function Caster:Spawn(class, config, pos)
	return Create(self.ent, class, config, pos)
end

function Caster:SpawnNPC(class, config, pos)
	return WS.Feature("npc"):Spawn(class, config, pos, angle_zero)
end

function Caster:Teleport(t, pos) t:SetPos(pos) end

function Caster:ScreenFade(t)
	if t:IsPlayer() then t:ScreenFade(SCREENFADE.IN, FADE_COLOR, FADE_TIME, FADE_HOLD) end
end

function Caster:Particle(name, pos) ParticleEffect(name, pos, angle_zero) end
function Caster:AttachParticle(name, t) ParticleEffectAttach(name, PATTACH_ABSORIGIN_FOLLOW, t, 0) end
function Caster:Tracer(name, from, to) util.ParticleTracerEx(name, from, to, false, 0, NO_ATTACHMENT) end

function Caster:EmitSound(name, source)
	local from = self.ent
	if IsValid(source) then from = source end
	from:EmitSound(name)
end

-------------------------------------------------------------------------------
-- The controller

local Controller = {
	library = Spells.Library.New(SpellSet),
	shots = {}, -- spell entity -> Shot
}

local function Candidate(ply)
	return {
		holder = ply,
		team = ply:Team(),
		alive = WS.IsAliveInGame(ply),
	}
end

function Controller:BookOf(caster)
	return self.library:BookOf(caster)
end

-- A player's book, State() on its weapon.
function Controller:Publish(caster)
	if not caster:IsPlayer() then return end
	local book, weapon = self:BookOf(caster), caster:GetWeapon(WEAPON)
	if book == nil or not IsValid(weapon) then return end
	local state = book:State()
	weapon:SetNW2Int(NW_SELECTED, state.selected)
	weapon:SetNW2Int(NW_CHARGES, state.charges)
	weapon:SetNW2Float(NW_ROLLING_UNTIL, state.rollingUntil or NOT_ROLLING)
end

-- A player holds the book as its weapon; an NPC holds it bare.
local function Equip(caster)
	if caster:IsPlayer() then caster:Give(WEAPON) end
end

-- Gives a caster a book (any caster: the players' are handed out by Sync).
function Controller:Grant(caster)
	self.library:Grant(caster)
	Equip(caster)
	self:Publish(caster)
end

function Controller:Revoke(caster)
	self.library:Revoke(caster)
	if caster:IsPlayer() then caster:StripWeapon(WEAPON) end
end

-- The weapon equipped: a caster without a book (one given the weapon from
-- the spawn menu, whether or not spells are on) holds one while it holds the
-- weapon. One the rules armed keeps its book.
function Controller:Arm(caster)
	if self.library:Arm(caster) then self:Publish(caster) end
end

-- The weapon dropped or removed.
function Controller:Disarm(caster)
	self.library:Disarm(caster)
end

-- Players' books follow who may cast: deaths, team changes and spells
-- turning on or off.
function Controller:Sync()
	local candidates = {}
	for i, ply in ipairs(player.GetAll()) do candidates[i] = Candidate(ply) end
	local granted, revoked = self.library:Sync(holiday:UsingSpells(), candidates)
	for _, ply in ipairs(granted) do
		Equip(ply)
		self:Publish(ply)
	end
	for _, ply in ipairs(revoked) do ply:StripWeapon(WEAPON) end
end

-- PlayerLoadout: TF2 regenerates items on spawn, so the book starts over.
function Controller:Respawned(ply)
	if not self.library:Respawn(holiday:UsingSpells(), Candidate(ply)) then return end
	Equip(ply)
	self:Publish(ply)
end

-- tf_spell_pickup, touched by anything: returns whether the pickup is taken
-- (by a living caster holding a book) and whether a spell rolls for it.
function Controller:Pickup(caster, tier)
	if not IsAlive(caster) then return false, false end
	local taken, rolled = self.library:Pickup(caster, tier, CurTime(), math.random)
	if rolled then self:Publish(caster) end
	return taken, rolled
end

-- +use_action_slot_item, the weapon's attack, or an NPC's decision. A
-- refused cast plays the deny sound to a player, as TF2's client does.
function Controller:Cast(caster)
	local book = self:BookOf(caster)
	if book == nil or not IsAlive(caster) then return false end
	local now = CurTime()
	if book:Cast(NewCaster(caster), now) then
		self:Publish(caster)
		return true
	end
	if book:Deny(now) and caster:IsPlayer() then WS.PlaySoundTo(caster, caster, SpellSet.DENY_SOUND) end
	return false
end

-- A spell projectile or spawner of spell `index`; its config is the one
-- its spell launched it with.
function Controller:BindSpellProjectile(ent, index, config)
	local shot = self.library:Shot(index, ent:GetClass(), config, CurTime())
	self.shots[ent] = shot
	return shot
end

function Controller:Unbind(ent)
	self.shots[ent] = nil
end

-- A shot acts through its caster; one whose caster is gone ends (TF2's
-- would fly on doing nothing).
local function Thrower(ent)
	local owner = ent:GetOwner()
	if IsValid(owner) then return owner end
	return nil
end

-- Returns whether the shot is finished and its entity should go.
function Controller:ThinkShot(ent)
	local owner = Thrower(ent)
	if owner == nil then return true end
	local shot = self.shots[ent]
	return shot:Tick(NewCaster(owner), {
		position = ent:GetPos(),
		team = shot.config.team,
		projectile = ent,
	}, CurTime()) == Spells.DONE
end

-- The shot lands: trace is what it hit (a touch) or the trace down from it
-- (a fuse); a surface pulls the burst 1 unit off it.
function Controller:Impact(ent, trace)
	local owner = Thrower(ent)
	if owner == nil then return end
	local shot = self.shots[ent]
	local position = ent:GetPos()
	if trace.Hit then position = trace.HitPos + trace.HitNormal end
	self.library:Impact(owner, shot, NewCaster(owner), {
		position = position,
		hitPosition = trace.HitPos,
		normal = trace.HitNormal,
		team = shot.config.team,
		projectile = ent,
	})
	self:Publish(owner)
end

-- The conditions only spells give, as GMod can show them: tiny casters are
-- half size, stealthed ones are not drawn. Each is undone only by this.
local function ShowConditions(ent)
	local tiny = WS.InCondition(ent, C.HALLOWEEN_TINY)
	if tiny ~= (ent.wsSpellTiny == true) then
		ent.wsSpellTiny = tiny
		ent:SetModelScale(tiny and TINY_SCALE or NORMAL_SCALE, 0)
	end
	local hidden = WS.InCondition(ent, C.STEALTHED_USER_BUFF)
	if hidden ~= (ent.wsSpellHidden == true) then
		ent.wsSpellHidden = hidden
		ent:SetNoDraw(hidden)
		-- Players and engine NPCs carry a weapon; a nextbot draws its own.
		if ent:IsPlayer() or ent:IsNPC() then
			local weapon = ent:GetActiveWeapon()
			if IsValid(weapon) then weapon:SetNoDraw(hidden) end
		end
	end
end

function Controller:Think(now)
	self:Sync()
	for _, caster in ipairs(self.library:Tick(now)) do self:Publish(caster) end
	for _, ply in ipairs(player.GetAll()) do ShowConditions(ply) end
	for _, caster in ipairs(self.library:Holders()) do
		if not caster:IsPlayer() then ShowConditions(caster) end
	end
end

hook.Add("PlayerLoadout", "ws_spells_loadout", function(ply)
	Controller:Respawned(ply)
end)

-- A caster gone from the game (a player leaving, an NPC removed).
hook.Add("EntityRemoved", "ws_spells_forget", function(ent)
	if Controller:BookOf(ent) then Controller.library:Forget(ent) end
end)

-- INVULNERABLE_USER_BUFF (the overheal's): no damage.
hook.Add("EntityTakeDamage", "ws_spells_invulnerable", function(target)
	if IsCharacter(target) and WS.InCondition(target, C.INVULNERABLE_USER_BUFF) then return true end
end)

concommand.Add(CAST_COMMAND, function(ply)
	if IsValid(ply) then Controller:Cast(ply) end
end, nil, "Cast the spell in your spellbook")
concommand.Add(CAST_RELEASE, function() end)

timer.Create(THINK_TIMER, THINK_INTERVAL, 0, function()
	Controller:Think(CurTime())
end)

Controller:Sync()

return Controller
