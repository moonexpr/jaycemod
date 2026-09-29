-- tf_projectile_spellmeteorshower (CTFProjectile_SpellMeteorShower): the
-- meteor spell's jar, which lands a tf_spell_meteorshowerspawner
-- (foundation.spells.meteor).
AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "wetsand_spell_projectile"
ENT.Spawnable = false
ENT.Variant = "foundation.projectile.jar"
ENT.ModelScale = 0.01
ENT.Trails = {
	[WETSAND.TEAM_RED] = "spell_fireball_small_red",
	[WETSAND.TEAM_BLUE] = "spell_fireball_small_blue",
}
