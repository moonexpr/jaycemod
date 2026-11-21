-- TF2 weapons held in the player's own c_arms hands, the TF2 class arms retargeted onto them each
-- frame (docs/tf2-hands-spike.md). The tuning and drawing are the client's alone.
TFWeapons = TFWeapons or {}

AddCSLuaFile ("tf_weapons/rig.lua")
AddCSLuaFile ("tf_weapons/mdl.lua")
AddCSLuaFile ("tf_weapons/activities.lua")
AddCSLuaFile ("tf_weapons/cl_hands.lua")

TFWeapons.Activities = include ("tf_weapons/activities.lua")

if CLIENT then
	TFWeapons.Rig = include ("tf_weapons/rig.lua")
	TFWeapons.Mdl = include ("tf_weapons/mdl.lua")
	include ("tf_weapons/cl_hands.lua")
end
