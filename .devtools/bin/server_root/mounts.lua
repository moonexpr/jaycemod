-- The dedicated server's Workshop addons (server_root.py): it runs
-- -noworkshop, so each archive server_root.py links into cache/ is mounted
-- here, and its autorun files run as the Workshop's mount would run them.
for _, archive in ipairs(file.Find("cache/*.gma", "GAME")) do
	local ok, files = game.MountGMA("cache/" .. archive)
	if not ok then error("server_root: could not mount cache/" .. archive) end
	for _, path in ipairs(files) do
		local lua = path:match("^lua/(autorun/[^/]+%.lua)$") or path:match("^lua/(autorun/server/[^/]+%.lua)$")
		if lua then include(lua) end
	end
	print("server_root: mounted " .. archive .. " (" .. #files .. " files)")
end
