-- foundation.core.parsers.cvarfile: convar values saved as cfg text, one
-- `name "value"` a line, and read back only for the names asked for.
local T = dofile("tests/harness.lua")
local CvarFile = T.require("foundation.core.parsers.cvarfile")

T.test("values are written one a line, quoted, in the order given", function()
	local text = CvarFile.Write({ "b", "a" }, { a = "1", b = "ui/hit sound.wav" })
	T.eq(text, 'b "ui/hit sound.wav"\na "1"\n')
end)

T.test("what was written reads back the same", function()
	local names = { "tf_dingalingaling", "tf_dingaling_volume", "tf_dingaling_wav_override" }
	local values = { tf_dingalingaling = "0", tf_dingaling_volume = "0.35", tf_dingaling_wav_override = "" }
	local back = CvarFile.Read(CvarFile.Write(names, values), names)
	for _, name in ipairs(names) do T.eq(back[name], values[name], name) end
end)

T.test("only the names asked for are read; anything else in the file is left", function()
	local back = CvarFile.Read('volume "0.5"\nrcon_password "x"\nbind "k" "kill"\n', { "volume" })
	T.eq(back.volume, "0.5", "asked for")
	T.eq(back.rcon_password, nil, "not asked for")
	T.eq(back.bind, nil, "nor a command")
end)

T.test("comments, blank lines, unquoted values and chained commands", function()
	local back = CvarFile.Read('// saved\n\nvolume 0.5\npitch "90"; kill\n', { "volume", "pitch" })
	T.eq(back.volume, "0.5", "unquoted")
	T.eq(back.pitch, nil, "a chained line is refused")
end)

T.finish()
