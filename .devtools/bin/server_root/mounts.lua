-- The dedicated server's Workshop addons (server_root.py): it runs
-- -noworkshop, so each archive server_root.py links into cache/ is mounted
-- here, and its autorun files run as the Workshop's mount would run them:
-- shared and server ones here, shared and client ones sent to clients,
-- which run the Lua the server sends, not their own Workshop copy. Every
-- archive is mounted before any autorun runs, as the Workshop does: ULib's
-- autorun loads the modules it finds then, ULX's among them.
local autoruns = {}
for _, archive in ipairs(file.Find("cache/*.gma", "GAME")) do
	local ok, files = game.MountGMA("cache/" .. archive)
	if not ok then error("server_root: could not mount cache/" .. archive) end
	for _, path in ipairs(files) do
		if path:match("^lua/autorun/") then autoruns[#autoruns + 1] = path end
	end
	print("server_root: mounted " .. archive .. " (" .. #files .. " files)")
end
table.sort(autoruns)
for _, path in ipairs(autoruns) do
	local shared = path:match("^lua/(autorun/[^/]+%.lua)$")
	local server = path:match("^lua/(autorun/server/[^/]+%.lua)$")
	local client = path:match("^lua/(autorun/client/[^/]+%.lua)$")
	if shared or client then AddCSLuaFile(shared or client) end
	if shared or server then include(shared or server) end
end
