-- The dedicated server's gamemode_entities.lua (.devtools/bin/server_root/):
-- once every entity is registered, a gamemode entity that a mounted addon
-- also defines (lua/entities/<name>) is registered again from the
-- gamemode's file, so the gamemode's wins. Run against fakes of the GMod
-- file, include and scripted_ents globals.
local T = dofile("tests/harness.lua")

local GM_DIR = "sandcastle/entities/entities/"

-- files: LUA paths that exist (folders end in "/"); bodies: path -> fn(ENT)
local function load(files, bodies, realm)
	local hooks, registered = {}, {}
	local env
	env = setmetatable({
		SERVER = realm ~= "client", CLIENT = realm == "client", AddCSLuaFile = function() end,
		engine = { ActiveGamemode = function() return "sandcastle" end },
		hook = { Add = function(name, _, fn) hooks[name] = fn end },
		file = {
			Find = function(pattern)
				local dir = pattern:gsub("%*$", "")
				local found, folders = {}, {}
				for path in pairs(files) do
					local rest = path:sub(1, #dir) == dir and path:sub(#dir + 1)
					if rest and rest ~= "" then
						local name = rest:match("^([^/]+)/$")
						if name then folders[#folders + 1] = name
						elseif not rest:find("/") then found[#found + 1] = rest end
					end
				end
				table.sort(found)
				table.sort(folders)
				return found, folders
			end,
			Exists = function(path) return files[path] ~= nil or files[path .. "/"] ~= nil end,
		},
		include = function(path) bodies[path](env.ENT) end,
		scripted_ents = { Register = function(ent, name) registered[name] = ent end },
	}, { __index = _G })
	setfenv(assert(loadfile(".devtools/bin/server_root/gamemode_entities.lua")), env)()
	hooks.Initialize()
	return registered, env
end

T.test("a gamemode entity an addon also defines is registered again from the gamemode", function()
	local files = {
		[GM_DIR .. "tf_projectile_rocket.lua"] = true,
		["entities/tf_projectile_rocket.lua"] = true,
	}
	local bodies = { [GM_DIR .. "tf_projectile_rocket.lua"] = function(ENT) ENT.Variant = "ours" end }
	local registered, env = load(files, bodies)
	T.eq(registered.tf_projectile_rocket.Variant, "ours")
	T.eq(registered.tf_projectile_rocket.Folder, "entities/tf_projectile_rocket")
	T.eq(env.ENT, nil, "ENT is cleared after")
end)

T.test("gamemode entities no addon defines are left alone", function()
	local files = { [GM_DIR .. "wetsand_point.lua"] = true, ["entities/other.lua"] = true }
	local registered = load(files, {})
	T.eq(next(registered), nil)
end)

T.test("a clash with an addon's entity folder counts too", function()
	local files = { [GM_DIR .. "tf_projectile_pipe.lua"] = true, ["entities/tf_projectile_pipe/"] = true }
	local bodies = { [GM_DIR .. "tf_projectile_pipe.lua"] = function(ENT) ENT.Variant = "ours" end }
	T.eq(load(files, bodies).tf_projectile_pipe.Variant, "ours")
end)

T.test("a gamemode entity folder includes init on the server and cl_init on clients", function()
	local files = { [GM_DIR .. "crate/"] = true, ["entities/crate.lua"] = true }
	local bodies = {
		[GM_DIR .. "crate/init.lua"] = function(ENT) ENT.Side = "server" end,
		[GM_DIR .. "crate/cl_init.lua"] = function(ENT) ENT.Side = "client" end,
	}
	T.eq(load(files, bodies, "server").crate.Side, "server")
	T.eq(load(files, bodies, "client").crate.Side, "client")
end)

T.finish()
