-- tf_projectile_spellpumpkin (CTFProjectile_SpellPumpkin): a MIRV bomblet,
-- blind to touches for its first second, that leaves a spell pumpkin bomb
-- (foundation.spells.mirv).
AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "ws_spell_projectile"
ENT.Spawnable = false
ENT.Variant = "games.gameplay.projectile.jar"
ENT.Model = "models/weapons/w_models/w_cannonball.mdl"
ENT.ModelScale = 0.75
ENT.Trails = {
	[WS.TEAM_RED] = "unusual_bubbles_green_fumes",
	[WS.TEAM_BLUE] = "unusual_bubbles_green_fumes",
}
