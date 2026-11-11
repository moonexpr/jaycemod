-- base_obj: what a support unit builds (CBaseObject, tf/baseobject_shared.cpp), the base of
-- obj_sentrygun, obj_teleporter, obj_dispenser and obj_door. Its builder sets its team and itself before Spawn
-- (SetObjTeam, SetBuilder); it goes up over its kind's construction time (gameplay.buildings), its
-- model's build animation paced to that, and does its work only once built (IsBuilt). It is harmed
-- by its enemies and the world, never its own team, and is destroyed at no health:
-- WSObjectDestroyed(object, attacker, inflictor) is run, then it is gone.
-- It is in its team's faction (GetFactions), so a soldier knows it for a friend or a foe, and a
-- combatant (NSCombatant): soldiers look at it as at each other, the enemy's to fight it. A subclass names its
-- Kind and Model (and BuildModel, where another model holds the animation; HullMins and HullMaxs, to
-- be a solid box where its model has no collision shape), and works in ObjThink once built.
AddCSLuaFile ()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.Spawnable = false
ENT.RenderGroup = RENDERGROUP_BOTH
ENT.AutomaticFrameAdvance = true
-- The enemy's soldiers fight it as they fight each other.
ENT.NSCombatant = true

local Buildings = gameplay.buildings
local Factions = WS.require ("includes.factions")

-- TF2's buildables are skinned RED 0, BLU 1.
local SKINS = { [TEAM_RED] = 0, [TEAM_BLUE] = 1 }
-- Why its placer's building was not set down, sent their client to word: its name (a TF2 token)
-- and the price they could not pay, or no price where there was no room.
local REFUSED = "ws_obj_refused"
-- How far above its origin the space it needs starts.
local FLOOR_CLEAR = 2

function ENT:SetupDataTables ()
	self:NetworkVar ("Int",    0, "ObjTeam")
	self:NetworkVar ("Float",  0, "BuiltAt")
	self:NetworkVar ("Entity", 0, "Builder")
	-- Its health, which the engine keeps from clients, for a teammate's target id.
	self:NetworkVar ("Int", 1, "ObjHealth")
	self:NetworkVar ("Int", 2, "ObjMaxHealth")
	self:ObjDataTables ()
end

-- A subclass's own network vars, after the base's: Int from 3, Float and Entity from 1.
function ENT:ObjDataTables () end

-- Its team's faction, for a NextBot's disposition toward it.
function ENT:GetFactions ()
	local _, join = Factions.Change (self:GetObjTeam ())
	return { join }
end

-- How far up it is, 0..1, and whether it is whole.
function ENT:Constructed () return Buildings.Constructed (self.Kind, self:GetBuiltAt (), CurTime ()) end
function ENT:IsBuilt () return self:Constructed () >= 1 end

if SERVER then
	-- From the spawn menu, a class it lists: its spawner's, on their team, facing as they face, where
	-- it fits; paid for once it stands, and free with the economy off, when nothing can be bought.
	function ENT:SpawnFunction (ply, tr, class)
		if not (tr.Hit and scripted_ents.GetMember (class, "Spawnable")) then return end
		local charged = WS.EconomyEnabled ()
		local price = Buildings.SPAWN_PRICE [self.Kind]
		if charged and not WS.Affords (WS.Money (ply), price) then
			net2.Send (REFUSED, { name = self.PrintName, price = price }, { to = ply })
			return
		end
		local ent = ents.Create (class)
		ent:SetPos (tr.HitPos)
		ent:SetAngles (Angle (0, ply:EyeAngles ().y, 0))
		ent:SetObjTeam (WS.TeamNumber (ply))
		ent:SetBuilder (ply)
		ent:ObjSpawnMenu (ply)
		ent:Spawn ()
		ent:Activate ()
		if not ent:Fits () then
			ent:Remove ()
			net2.Send (REFUSED, { name = self.PrintName }, { to = ply })
			return
		end
		if charged then WS.SpendMoney (ply, price) end
		return ent
	end

	-- What a subclass sets from its spawner before Spawn.
	function ENT:ObjSpawnMenu (ply) end

	-- Plays what its model does for activity, over seconds or at its own speed. A model without one
	-- (the door's) is left as it is.
	local function Play (self, activity, seconds)
		local sequence = self:SelectWeightedSequence (activity)
		if sequence < 0 then return end
		self:ResetSequence (sequence)
		self:SetPlaybackRate (seconds and self:SequenceDuration (sequence) / seconds or 1)
	end

	-- Puts it on model; the engine sizes it to each model it is given, so its box is set after.
	local function Wear (self, model)
		self:SetModel (model)
		if self.HullMins then self:SetCollisionBounds (self.HullMins, self.HullMaxs) end
	end

	function ENT:Initialize ()
		if self.HullMins then self:SetSolid (SOLID_BBOX) end
		Wear (self, self.BuildModel or self.Model)
		self:SetSkin (SKINS [self:GetObjTeam ()] or 0)
		if not self.HullMins then self:PhysicsInit (SOLID_VPHYSICS) end
		self:SetMoveType (MOVETYPE_NONE)
		local phys = self:GetPhysicsObject ()
		if IsValid (phys) then phys:EnableMotion (false) end
		self:SetMaxHealth (self:ObjMaxHealth ())
		self:SetObjMaxHealth (self:GetMaxHealth ())
		self:SetHealth (self:GetMaxHealth ())
		self:SetObjHealth (self:Health ())
		self:SetBuiltAt (CurTime ())
		Play (self, ACT_OBJ_ASSEMBLING, Buildings.BUILD_TIME [self.Kind])
		self:ObjInitialize ()
	end

	function ENT:ObjInitialize () end

	-- Its health whole: its kind's, unless a subclass says otherwise (a sentry's by its level).
	function ENT:ObjMaxHealth () return Buildings.HEALTH [self.Kind] end

	-- Whether it stands clear where it was set down: nothing solid within its bounds above FLOOR_CLEAR
	-- (a model may sink a little into the floor it stands on), its builder included: whoever stands
	-- there would be stuck inside it.
	function ENT:Fits ()
		local pos, mins = self:GetPos (), self:OBBMins ()
		local tr = util.TraceHull (
			{
				start = pos, endpos = pos, mins = Vector (mins.x, mins.y, FLOOR_CLEAR), maxs = self:OBBMaxs (),
				mask = MASK_SOLID, filter = self
			}
		)
		return not tr.Hit
	end

	function ENT:OnTakeDamage (dmg)
		local attacker = dmg:GetAttacker ()
		local team = IsValid (attacker) and WS.TeamNumber (attacker) or TF_TEAM_UNASSIGNED
		if not Buildings.Harms (self:GetObjTeam (), team) then return 0 end
		self:SetHealth (self:Health () - dmg:GetDamage ())
		self:SetObjHealth (self:Health ())
		if self:Health () <= 0 and not self.objDestroyed then
			self.objDestroyed = true
			local effect = EffectData ()
			effect:SetOrigin (self:WorldSpaceCenter ())
			util.Effect ("Explosion", effect)
			hook.Run ("WSObjectDestroyed", self, attacker, dmg:GetInflictor ())
			self:Remove ()
		end
		return dmg:GetDamage ()
	end

	-- A wrench's hit from wielder: a teammate's hurries it going up and mends it once built. Whether it
	-- did either.
	function ENT:Wrench (wielder)
		if not Buildings.Tends (self:GetObjTeam (), WS.TeamNumber (wielder)) then return false end
		if not self:IsBuilt () then
			self:SetBuiltAt (Buildings.Hurried (self.Kind, self:GetBuiltAt (), CurTime ()))
			return true
		end
		if self:Health () >= self:GetMaxHealth () then return false end
		self:SetHealth (Buildings.Repaired (self:Health (), self:GetMaxHealth ()))
		self:SetObjHealth (self:Health ())
		return true
	end

	function ENT:Think ()
		if self:IsBuilt () then
			if not self.objUp then
				self.objUp = true
				Wear (self, self.Model)
				Play (self, ACT_OBJ_RUNNING)
				self:ObjBuilt ()
			end
			self:ObjThink ()
		end
		self:NextThink (CurTime ())
		return true
	end

	function ENT:ObjThink () end

	-- What a subclass does as it is built, once.
	function ENT:ObjBuilt () end
end

if CLIENT then
	-- A TF2 token in the player's language (WS.Localize, Wetsands'), or as it is.
	local function Word (token) return WS.Localize and WS.Localize (token) or token end

	net2.Receive (REFUSED, function (refusal)
		local name = Word (refusal.name)
		if refusal.price then
			chat.AddText ("A " .. name .. " costs $" .. refusal.price)
		else
			chat.AddText ("There is no room for a " .. name .. " here")
		end
	end)

	-- The names the spawn menu shows are TF2's tokens: worded before it is built.
	if WS and WS.Localize then WS.Localize ("#TF_Object_Sentry") end
end
