-- The gamemode's entities win on the dedicated server (server_root.py). GMod
-- registers an addon's lua/entities/<name> after the gamemode's
-- entities/entities/<name>, so a Workshop archive the server mounts that
-- ships an entity of the same name replaces the gamemode's (the TF2 Weapon
-- Pack's tf_projectile_rocket and tf_projectile_pipe). Once every entity is
-- registered, each such clash is registered again from the gamemode's own
-- file, on the server and on each client.
if SERVER then AddCSLuaFile() end

hook.Add("Initialize", "server_root_gamemode_entities", function()
	local dir = engine.ActiveGamemode() .. "/entities/entities/"
	local files, folders = file.Find(dir .. "*", "LUA")
	local entities = {}
	for _, f in ipairs(files) do
		local name = f:match("^(.+)%.lua$")
		if name then entities[#entities + 1] = { name = name, path = dir .. f } end
	end
	for _, name in ipairs(folders) do
		local side = SERVER and "init.lua" or "cl_init.lua"
		entities[#entities + 1] = { name = name, path = dir .. name .. "/" .. side }
	end
	for _, e in ipairs(entities) do
		if file.Exists("entities/" .. e.name .. ".lua", "LUA") or file.Exists("entities/" .. e.name, "LUA") then
			ENT = { Folder = "entities/" .. e.name }
			include(e.path)
			scripted_ents.Register(ENT, e.name)
			ENT = nil
		end
	end
end)
