-- The dev server's mark (server_root.py): DEBUG, which every dev-only piece
-- requires, and the dev workbench (addons/sandcastle_dev), which has no
-- autorun of its own. A release server has neither this file nor DEBUG.
--
-- dev.load(path, ...) runs a file of the workbench's lua/ folder;
-- dev.require(name) loads its lua/includes/modules/<name>.lua once, as
-- GMod's require would. Both read the mounted addon, or, when the addon was
-- linked after the server started (addons mount only at start), the link
-- in the server's own root.
DEBUG = true

local LINKED = "garrysmod/addons/sandcastle_dev/lua/"

dev = dev or {}

local function Source(path)
	if file.Exists(path, "LUA") then return file.Read(path, "LUA"), "mounted" end
	if file.Exists(LINKED .. path, "BASE_PATH") then return file.Read(LINKED .. path, "BASE_PATH"), "linked" end
	error("dev workbench: no " .. path .. " in the mounted addon or at " .. LINKED, 2)
end

function dev.load(path, ...)
	local code, from = Source(path)
	dev.loadedFrom = from
	local chunk = CompileString(code, "addons/sandcastle_dev/lua/" .. path)
	return chunk(...)
end

function dev.require(name)
	if package.loaded[name] == nil then dev.load("includes/modules/" .. name .. ".lua", name) end
	return package.loaded[name]
end

dev.load("sandcastle_dev/sv.lua")
print("dev workbench loaded from the " .. dev.loadedFrom .. " addon")
