-- Game events v2 research, question 6: the cost of reading and hashing the
-- gamemode's Lua files with util.CRC, util.MD5, util.SHA1 and util.SHA256,
-- on the server. Two sets: the 191 files init.lua and the entities send
-- clients today, and every .lua file under the gamemode (269). Writes
-- data/wetsand_tests/gev2/out/hashing.txt. Run by .devtools/bin/gev2_probe.py.
local NAME = "hashing"
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

-- What init.lua sends (shared.lua, cl_init.lua, foundation/, features' sh/cl,
-- wetsand's sh_/cl_) and the entities that call AddCSLuaFile themselves.
local function IsSent(path, text)
	local rel = path:sub(#ROOT + 1)
	if rel == "gamemode/shared.lua" or rel == "gamemode/cl_init.lua" then return true end
	if rel:find("^gamemode/foundation/") then return true end
	if rel:find("^gamemode/features/[^/]+/sh%.lua$") or rel:find("^gamemode/features/[^/]+/cl%.lua$") then return true end
	if rel:find("^gamemode/wetsand/sh_") or rel:find("^gamemode/wetsand/cl_") then return true end
	if rel:find("^entities/") and text:find("AddCSLuaFile", 1, true) then return true end
	return false
end

local all = Walk(ROOT, {})
local texts, sent = {}, {}
local readStart = SysTime()
for i, path in ipairs(all) do texts[i] = file.Read(path, "LUA") end
local readTime = SysTime() - readStart
local bytesAll, bytesSent = 0, 0
for i, path in ipairs(all) do
	bytesAll = bytesAll + #texts[i]
	if IsSent(path, texts[i]) then
		sent[#sent + 1] = texts[i]
		bytesSent = bytesSent + #texts[i]
	end
end
Say("files all", #all, "bytes", bytesAll, "file.Read all (ms)", string.format("%.2f", readTime * 1000))
Say("files sent", #sent, "bytes", bytesSent)

local HASHES = {
	{ "util.CRC", util.CRC },
	{ "util.MD5", util.MD5 },
	{ "util.SHA1", util.SHA1 },
	{ "util.SHA256", util.SHA256 },
}

local function Time(fn, list)
	local best, total = math.huge, 0
	for _ = 1, ROUNDS do
		local t0 = SysTime()
		for _, text in ipairs(list) do fn(text) end
		local dt = SysTime() - t0
		best = math.min(best, dt)
		total = total + dt
	end
	return best * 1000, total / ROUNDS * 1000
end

for _, set in ipairs({ { "sent", sent }, { "all", texts } }) do
	for _, h in ipairs(HASHES) do
		local best, mean = Time(h[2], set[2])
		Say("set " .. set[1], h[1], string.format("best %.2f ms", best), string.format("mean %.2f ms", mean))
	end
end

-- One read-and-hash pass over the sent files, as a join would do it.
local t0 = SysTime()
for i, path in ipairs(all) do
	local text = file.Read(path, "LUA")
	if IsSent(path, text) then util.SHA256(text) end
end
Say("read + SHA256 of sent files, one pass (ms)", string.format("%.2f", (SysTime() - t0) * 1000))

Say("sample outputs", "CRC=" .. util.CRC("teamplay_point_captured"), "SHA256 len=" .. #util.SHA256("x"),
	"MD5 len=" .. #util.MD5("x"), "SHA1 len=" .. #util.SHA1("x"))
Say("SysTime resolution probe", string.format("%.9f", SysTime() - SysTime()))

file.CreateDir("wetsand_tests/gev2/out")
file.Write("wetsand_tests/gev2/out/" .. NAME .. ".txt", table.concat(out, "\n") .. "\n")
print("wetsand_tests: gev2 " .. NAME .. " done")
