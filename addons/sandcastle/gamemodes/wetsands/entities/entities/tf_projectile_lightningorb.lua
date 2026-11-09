-- tf_projectile_lightningorb (CTFProjectile_SpellLightningOrb): the
-- lightning spell's orb. It collides with the world only (SetSolid(
-- SOLID_NONE)), bouncing off it, and zaps as it goes
-- (features.spells.lightning).
AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "ws_spell_projectile"
ENT.Spawnable = false
ENT.Variant = "features.spells.orb"
ENT.Model = "models/weapons/w_models/w_rocket.mdl"
ENT.ModelScale = 0.01
ENT.CollisionGroup = COLLISION_GROUP_DEBRIS
ENT.Trails = {
	[WS.TEAM_RED] = "spell_lightningball_parent_red",
	[WS.TEAM_BLUE] = "spell_lightningball_parent_blue",
}
