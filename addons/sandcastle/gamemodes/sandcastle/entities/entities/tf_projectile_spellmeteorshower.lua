-- tf_projectile_spellmeteorshower (CTFProjectile_SpellMeteorShower): the
-- meteor spell's jar, which lands a tf_spell_meteorshowerspawner
-- (features.spells.meteor).
AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "ws_spell_projectile"
ENT.Spawnable = false
ENT.Variant = "games.gameplay.projectile.jar"
ENT.ModelScale = 0.01
ENT.Trails = {
	[TEAM_RED] = "spell_fireball_small_red",
	[TEAM_BLUE] = "spell_fireball_small_blue",
}
