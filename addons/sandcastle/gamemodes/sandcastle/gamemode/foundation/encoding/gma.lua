-- GMod's addon archive (.gma), as gmad writes it: "GMAD", the version, the
-- author's SteamID and a timestamp (uint64 each), the required content
-- (none: an empty string), name, description and author (NUL-terminated),
-- the addon version (int32), then each file's entry (its number from 1, path,
-- size as int64, CRC32), a 0 to end the list, every file's bytes in order,
-- and the CRC32 of all that.
--
-- Write(name, files) -> bytes; files are { path, data }, in order.
-- Read(bytes) -> { name, files }, refusing what is not an archive.
local Buffer = require("foundation.file.buffer")
local concat, error, find, ipairs, sub = table.concat, error, string.find, ipairs, string.sub
module(...)

MAGIC = "GMAD"
VERSION = 3

local function CString(s) return s .. "\0" end
local function UInt64(n) return Buffer.Int32(n) .. Buffer.Int32(0) end

function Write(name, files)
	local parts = { MAGIC, Buffer.Byte(VERSION), UInt64(0), UInt64(0), CString(""),
		CString(name), CString(""), CString(""), Buffer.Int32(1) }
	for i, f in ipairs(files) do
		parts[#parts + 1] = Buffer.Int32(i) .. CString(f.path) .. UInt64(#f.data) .. Buffer.Int32(Buffer.Crc32(f.data))
	end
	parts[#parts + 1] = Buffer.Int32(0)
	for _, f in ipairs(files) do parts[#parts + 1] = f.data end
	local body = concat(parts)
	return body .. Buffer.Int32(Buffer.Crc32(body))
end

function Read(bytes)
	if sub(bytes, 1, #MAGIC) ~= MAGIC then error("not a GMA archive", 2) end
	local at = #MAGIC + 1 + 1 + 16
	local function Take(n)
		local s = sub(bytes, at, at + n - 1)
		at = at + n
		return s
	end
	local function CStr()
		local stop = find(bytes, "\0", at, true)
		local s = sub(bytes, at, stop - 1)
		at = stop + 1
		return s
	end
	local function Int32() return Buffer.Reader(Take(4)):Int32() % 2 ^ 32 end
	while CStr() ~= "" do end
	local name = CStr()
	CStr()
	CStr()
	Int32()
	local entries = {}
	while Int32() ~= 0 do
		local path = CStr()
		local size = Int32()
		Int32()
		Int32()
		entries[#entries + 1] = { path = path, size = size }
	end
	local files = {}
	for _, e in ipairs(entries) do files[#files + 1] = { path = e.path, data = Take(e.size) } end
	return { name = name, files = files }
end
