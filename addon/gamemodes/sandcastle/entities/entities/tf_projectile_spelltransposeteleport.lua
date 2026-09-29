-- tf_projectile_spelltransposeteleport (CTFProjectile_SpellTransposeTeleport):
-- the teleport spell's jar, which remembers where it has been
-- (foundation.spells.teleport).
AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "wetsand_spell_projectile"
ENT.Spawnable = false
ENT.Variant = "foundation.projectile.jar"
ENT.ModelScale = 0.01
ENT.Trails = {
	[WETSAND.TEAM_RED] = "spell_teleport_red",
	[WETSAND.TEAM_BLUE] = "spell_teleport_blue",
}
