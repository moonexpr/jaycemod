-- tf_projectile_spellmirv (CTFProjectile_SpellMirv): the MIRV spell's
-- cannonball, which bursts into pumpkin bomblets (foundation.spells.mirv).
AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "ws_spell_projectile"
ENT.Spawnable = false
ENT.Variant = "foundation.projectile.jar"
ENT.Model = "models/weapons/w_models/w_cannonball.mdl"
ENT.ModelScale = 0.9
ENT.Trails = {
	[WS.TEAM_RED] = "unusual_bubbles_green_fumes",
	[WS.TEAM_BLUE] = "unusual_bubbles_green_fumes",
}
