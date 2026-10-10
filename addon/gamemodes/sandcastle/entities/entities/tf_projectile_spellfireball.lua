-- tf_projectile_spellfireball (CTFProjectile_SpellFireball): the fireball
-- spell's rocket, and each meteor of a meteor shower. Invisible but for its
-- flame; it bursts on the first thing it touches (foundation.spells.fireball).
AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "ws_spell_projectile"
ENT.Spawnable = false
ENT.Variant = "foundation.projectile.rocket"
ENT.Model = "models/weapons/w_models/w_rocket.mdl"
ENT.ModelScale = 0.01 -- GetFireballScale
ENT.Trails = {
	[WS.TEAM_RED] = "spell_fireball_small_red",
	[WS.TEAM_BLUE] = "spell_fireball_small_blue",
}
