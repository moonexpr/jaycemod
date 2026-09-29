-- tf_projectile_spellspawnboss (CTFProjectile_SpellSpawnBoss): the spawn
-- boss spell's skull, which summons a MONOCULUS where it lands
-- (foundation.spells.spawn_boss).
AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "wetsand_spell_projectile"
ENT.Spawnable = false
ENT.Variant = "foundation.projectile.jar"
ENT.Model = "models/props_mvm/mvm_human_skull_collide.mdl"
ENT.ModelScale = 1.5
ENT.Trails = {
	[WETSAND.TEAM_RED] = "unusual_bubbles_green_fumes",
	[WETSAND.TEAM_BLUE] = "unusual_bubbles_green_fumes",
}
