-- tf_projectile_spellspawnhorde (CTFProjectile_SpellSpawnHorde): the
-- skeleton horde spell's skull, which bursts into three skull grenades
-- (foundation.spells.skeleton_horde).
AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "ws_spell_projectile"
ENT.Spawnable = false
ENT.Variant = "games.gameplay.projectile.jar"
ENT.Model = "models/props_mvm/mvm_human_skull_collide.mdl"
ENT.ModelScale = 1
ENT.Trails = {
	[WS.TEAM_RED] = "unusual_bubbles_green_fumes",
	[WS.TEAM_BLUE] = "unusual_bubbles_green_fumes",
}
