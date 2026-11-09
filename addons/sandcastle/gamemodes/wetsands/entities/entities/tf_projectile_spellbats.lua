-- tf_projectile_spellbats (CTFProjectile_SpellBats): the bats spell's jar,
-- invisible but for its swarm (features.spells.bats).
AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "ws_spell_projectile"
ENT.Spawnable = false
ENT.Variant = "games.gameplay.projectile.jar"
ENT.ModelScale = 0.01 -- GetModelScale
ENT.Trails = {
	[WS.TEAM_RED] = "spell_batball_throw_red",
	[WS.TEAM_BLUE] = "spell_batball_throw_blue",
}
