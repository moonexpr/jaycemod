-- Game events v2 research, questions 1 and 6: what a client would pay to
-- check its Lua cache (garrysmod/cache/lua/<name>.lua, name = the first 40
-- hex digits of SHA-256(text .. "\0"), an LZMA body after a 32-byte header;
-- see .devtools/bin/gmod_lua_cache.py), measured on the server with the
-- files it sends: computing the names, looking them up with file.Exists, and
-- util.Decompress of each file's compressed text. Writes
-- data/ws_tests/gev2/out/cachecost.txt. Run by .devtools/bin/gev2_probe.py.
local NAME = "cachecost"
local ROOT = "sandcastle/"
local ROUNDS = 5
local out = {}

local function Say(...)
	local parts = {}
	for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
	out[#out + 1] = table.concat(parts, " | ")
end

local function Walk(dir, list)
	local files, dirs = file.Find(dir .. "*", "LUA")
	for _, f in ipairs(files) do
		if f:sub(-4) == ".lua" then list[#list + 1] = dir .. f end
	end
	for _, d in ipairs(dirs) do Walk(dir .. d .. "/", list) end
	return list
end

local function IsSent(path, text)
	local rel = path:sub(#ROOT + 1)
	if rel == "gamemode/shared.lua" or rel == "gamemode/cl_init.lua" then return true end
	if rel:find("^gamemode/foundation/") then return true end
	if rel:find("^gamemode/features/[^/]+/sh%.lua$") or rel:find("^gamemode/features/[^/]+/cl%.lua$") then return true end
	if rel:find("^gamemode/ws/sh_") or rel:find("^gamemode/ws/cl_") then return true end
	if rel:find("^entities/") and text:find("AddCSLuaFile", 1, true) then return true end
	return false
end

local texts = {}
for _, path in ipairs(Walk(ROOT, {})) do
	local text = file.Read(path, "LUA")
	if IsSent(path, text) then texts[#texts + 1] = text end
end

local function Best(fn)
	local best = math.huge
	for _ = 1, ROUNDS do
		local t0 = SysTime()
		fn()
		best = math.min(best, SysTime() - t0)
	end
	return string.format("%.2f ms", best * 1000)
end

local names, packed, packedBytes = {}, {}, 0
Say("sent files", #texts)
Say("names: SHA256(text..NUL):sub(1,40) for all", Best(function()
	for i, text in ipairs(texts) do names[i] = util.SHA256(text .. "\0"):sub(1, 40) end
end))
Say("file.Exists cache/lua/<name>.lua GAME for all (misses on a server)", Best(function()
	for _, name in ipairs(names) do file.Exists("cache/lua/" .. name .. ".lua", "GAME") end
end))
for i, text in ipairs(texts) do
	packed[i] = util.Compress(text .. "\0")
	packedBytes = packedBytes + #packed[i]
end
Say("compressed bytes of all", packedBytes)
Say("util.Decompress for all", Best(function()
	for _, blob in ipairs(packed) do util.Decompress(blob) end
end))
Say("util.Decompress + util.SHA256 for all", Best(function()
	for _, blob in ipairs(packed) do util.SHA256(util.Decompress(blob)) end
end))

file.CreateDir("ws_tests/gev2/out")
file.Write("ws_tests/gev2/out/" .. NAME .. ".txt", table.concat(out, "\n") .. "\n")
print("ws_tests: gev2 " .. NAME .. " done")
