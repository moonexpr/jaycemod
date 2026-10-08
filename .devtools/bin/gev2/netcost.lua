-- Game events v2 research, question 4: what each net.Write costs in bits
-- (net.BytesWritten before and after), and what happens at the message size
-- limit, on the server with no client connected. Writes
-- data/wetsand_tests/gev2/out/netcost.txt. Run by .devtools/bin/gev2_probe.py.
local NAME = "netcost"
local MSG = "wetsand_tests_gev2_probe"
local out = {}

local function Say(...)
	local parts = {}
	for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
	out[#out + 1] = table.concat(parts, " | ")
end

util.AddNetworkString(MSG)

local function Bits()
	local bytes, bits = net.BytesWritten()
	return bits or bytes * 8, bytes
end

net.Start(MSG)
local emptyBits, emptyBytes = Bits()
Say("empty message", "bits=" .. tostring(emptyBits), "bytes=" .. tostring(emptyBytes))

local CASES = {
	{ "WriteDouble(0.1)", function() net.WriteDouble(0.1) end },
	{ "WriteDouble(1e300)", function() net.WriteDouble(1e300) end },
	{ "WriteFloat(0.1)", function() net.WriteFloat(0.1) end },
	{ "WriteUInt(5, 8)", function() net.WriteUInt(5, 8) end },
	{ "WriteUInt(5, 3)", function() net.WriteUInt(5, 3) end },
	{ "WriteInt(-5, 32)", function() net.WriteInt(-5, 32) end },
	{ "WriteBool(true)", function() net.WriteBool(true) end },
	{ "WriteString('')", function() net.WriteString("") end },
	{ "WriteString('cpname')", function() net.WriteString("cpname") end },
	{ "WriteEntity(world)", function() net.WriteEntity(game.GetWorld()) end },
	{ "WriteEntity(NULL)", function() net.WriteEntity(NULL) end },
	{ "WriteVector(Vector(1,2,3))", function() net.WriteVector(Vector(1, 2, 3)) end },
	{ "WriteVector(Vector(10000.123,-5,0))", function() net.WriteVector(Vector(10000.123, -5, 0)) end },
	{ "WriteAngle(Angle(10,20,30))", function() net.WriteAngle(Angle(10, 20, 30)) end },
	{ "WriteNormal(Vector(0,0,1))", function() net.WriteNormal(Vector(0, 0, 1)) end },
	{ "WriteData(16 bytes)", function() net.WriteData(string.rep("x", 16), 16) end },
}
for _, case in ipairs(CASES) do
	local before = Bits()
	case[2]()
	Say(case[1], "bits=" .. (Bits() - before))
end
Say("MAX_EDICT_BITS", tostring(MAX_EDICT_BITS), "MAX_PLAYER_BITS", tostring(MAX_PLAYER_BITS))
net.Broadcast()

-- The size limit: write up to the documented 65533 bytes, and past it.
local function Fill(totalBytes, unreliable)
	net.Start(MSG, unreliable)
	local _, bytes0 = Bits()
	local chunk = string.rep("a", 1024)
	local want = totalBytes - bytes0
	local okWrite, errWrite = pcall(function()
		while want >= 1024 do
			net.WriteData(chunk, 1024)
			want = want - 1024
		end
		if want > 0 then net.WriteData(string.rep("a", want), want) end
	end)
	local bits, bytes = Bits()
	local okSend, errSend = pcall(net.Broadcast)
	Say("fill to " .. totalBytes .. (unreliable and " unreliable" or " reliable"),
		"write ok=" .. tostring(okWrite) .. (errWrite and (" err=" .. tostring(errWrite)) or ""),
		"BytesWritten=" .. tostring(bytes) .. " bits=" .. tostring(bits),
		"Broadcast ok=" .. tostring(okSend) .. (errSend and (" err=" .. tostring(errSend)) or ""))
end
for _, n in ipairs({ 1200, 65533, 65534, 65536, 70000 }) do Fill(n, false) end
for _, n in ipairs({ 1200, 4000, 65533 }) do Fill(n, true) end

file.CreateDir("wetsand_tests/gev2/out")
file.Write("wetsand_tests/gev2/out/" .. NAME .. ".txt", table.concat(out, "\n") .. "\n")
print("wetsand_tests: gev2 " .. NAME .. " done")
