-- tf_projectile_lightningorb (CTFProjectile_SpellLightningOrb): the
-- lightning spell's orb. It collides with the world only (SetSolid(
-- SOLID_NONE)), bouncing off it, and zaps as it goes
-- (foundation.spells.lightning).
AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "wetsand_spell_projectile"
ENT.Spawnable = false
ENT.Variant = "foundation.projectile.orb"
ENT.Model = "models/weapons/w_models/w_rocket.mdl"
ENT.ModelScale = 0.01
ENT.CollisionGroup = COLLISION_GROUP_DEBRIS
ENT.Trails = {
	[WETSAND.TEAM_RED] = "spell_lightningball_parent_red",
	[WETSAND.TEAM_BLUE] = "spell_lightningball_parent_blue",
}
