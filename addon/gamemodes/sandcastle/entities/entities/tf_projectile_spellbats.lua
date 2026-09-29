-- tf_projectile_spellbats (CTFProjectile_SpellBats): the bats spell's jar,
-- invisible but for its swarm (foundation.spells.bats).
AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "wetsand_spell_projectile"
ENT.Spawnable = false
ENT.Variant = "foundation.projectile.jar"
ENT.ModelScale = 0.01 -- GetModelScale
ENT.Trails = {
	[WETSAND.TEAM_RED] = "spell_batball_throw_red",
	[WETSAND.TEAM_BLUE] = "spell_batball_throw_blue",
}
