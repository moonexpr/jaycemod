local T = dofile("tests/harness.lua")
local Gma = T.require("foundation.encoding.gma")
local Buffer = T.require("foundation.file.buffer")

local FILES = {
	{ path = "sound/a/one.wav", data = "RIFF one" },
	{ path = "sound/b/two.wav", data = string.rep("\0\255", 40) },
}

T.test("an archive written reads back the same files, in order", function()
	local archive = Gma.Read(Gma.Write("name", FILES))
	T.eq(archive.name, "name", "its name")
	T.eq(#archive.files, 2, "both files")
	for i, f in ipairs(FILES) do
		T.eq(archive.files[i].path, f.path, "path " .. i)
		T.eq(archive.files[i].data, f.data, "data " .. i)
	end
end)

-- gmad's layout: "GMAD", version 3, then the header, the file list and
-- the files' bytes, and the CRC32 of everything before it.
T.test("an archive is gmad's layout, ending in the CRC of what precedes it", function()
	local bytes = Gma.Write("name", FILES)
	T.eq(bytes:sub(1, 4), "GMAD", "magic")
	T.eq(bytes:byte(5), Gma.VERSION, "version")
	local body, tail = bytes:sub(1, -5), bytes:sub(-4)
	T.eq(Buffer.Reader(tail):Int32() % 2 ^ 32, Buffer.Crc32(body), "the trailing CRC")
end)

T.test("an archive of no files reads back empty", function()
	T.eq(#Gma.Read(Gma.Write("empty", {})).files, 0, "none")
end)

T.test("what is not an archive is refused", function()
	local ok = pcall(Gma.Read, "PK\3\4 not a gma")
	T.eq(ok, false, "refused")
end)

T.finish()
