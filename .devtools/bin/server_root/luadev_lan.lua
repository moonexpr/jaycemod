-- luadev's access on the dedicated server (server_root.py). luadev's own
-- check (luadev_sh.lua's CanLuaDev) first refuses anyone whose SteamID Steam
-- has not authenticated, but srcds.py runs the server -nosteam with sv_lan 1,
-- where Steam authenticates nobody, so it refuses everyone. On a LAN server
-- this is the rest of luadev's check, without that gate; off one, luadev's
-- own decides. luadev's files share the luadev module table as their
-- environment, so they all find this one.
local sv_lan = GetConVar("sv_lan")
local sv_allowcslua = GetConVar("sv_allowcslua")
local luadevs_own = luadev.CanLuaDev

-- luadev_sh.lua's CanLuaDev after its authentication gate
local function on_lan(ply, script, command, target, target_ply, extra)
	local ret, why = hook.Run("CanLuaDev", ply, script, command, target, target_ply, extra)
	if ret ~= nil then return ret, why end
	ret, why = hook.Run("LuaDevIsPlayerAllowed", ply, script or "")
	if ret ~= nil then return ret, why end
	if ply:IsSuperAdmin() then return true end
	local own_client = target_ply == ply
		or (istable(target_ply) and target_ply[1] == ply and table.Count(target_ply) == 1)
	if target == luadev.TO_CLIENT and own_client and sv_allowcslua:GetBool() then return true end
end

function luadev.CanLuaDev(...)
	if sv_lan:GetBool() then return on_lan(...) end
	return luadevs_own(...)
end
