-- foundation.configstore: named whole-number values, each held to a range
-- and guarded by what the caller names, parsed from text.
local T = dofile("tests/harness.lua")
local ConfigStore = configstore

local function Raises(fn, ...)
	local ok, err = pcall(fn, ...)
	T.eq(ok, false, "raises")
	return tostring(err)
end

local function Has(text, part, what)
	T.eq(text:find(part, 1, true) ~= nil, true, what .. ": " .. text)
end

local function Store()
	local store = ConfigStore.New("the options")
	store:Range("volume", 0, 10, "listener")
	store:Switch("muted", "listener")
	store:Range("offset", -5, 5, "tuner")
	return store
end

local function Holds(...)
	local held = {}
	for _, guard in ipairs({ ... }) do held[guard] = true end
	return function(guard) return held[guard] == true end
end

T.test("a stored key reads as its range and guard; anything else as nothing", function()
	local store = Store()
	local volume = store.volume
	T.eq(volume.min .. "," .. volume.max .. "," .. volume.guard, "0,10,listener", "a range")
	local muted = store:Get("muted")
	T.eq(muted.min .. "," .. muted.max, "0,1", "a switch is 0 or 1")
	T.eq(store.loudness, nil, "not stored")
	T.eq(store:Has("volume"), true, "has")
	T.eq(store:Has("loudness"), false, "has not")
end)

T.test("an entry cannot be changed through the store", function()
	local store = Store()
	Raises(function() store.volume.max = 99 end)
	Raises(function() store.volume = { min = 0, max = 99 } end)
	T.eq(store.volume.max, 10, "unchanged")
end)

T.test("a value in range is the text a setting takes, rounded to a whole number", function()
	local store = Store()
	T.eq(store:Parse("volume", "7"), "7", "whole")
	T.eq(store:Parse("volume", "6.5"), "7", "rounded half up")
	T.eq(store:Parse("offset", "-5"), "-5", "the low end")
end)

T.test("a value outside its range, or not a number, is refused, saying why", function()
	local store = Store()
	local value, why = store:Parse("volume", "11")
	T.eq(value, nil, "too high")
	T.eq(why, "volume takes 0 to 10", "names the range")
	value, why = store:Parse("volume", "loud")
	T.eq(value, nil, "not a number")
	T.eq(why, "volume takes a number, not \"loud\"", "names the text")
	value, why = store:Parse("loudness", "1")
	T.eq(value, nil, "not stored")
	T.eq(why, "loudness is not one of the options", "names the store")
end)

T.test("a holder may change a key only if it holds that key's guard", function()
	local store = Store()
	T.eq(store:Allowed("volume", Holds("listener")), true, "held")
	T.eq(store:Allowed("offset", Holds("listener")), false, "another guard")
	T.eq(store:Allowed("loudness", Holds("listener")), false, "not stored")
end)

T.test("walking a store gives each key and entry in key order, and its length counts them", function()
	local store = Store()
	local keys = {}
	for key, entry in store() do keys[#keys + 1] = key .. ":" .. entry.max end
	T.eq(table.concat(keys, " "), "muted:1 offset:5 volume:10", "sorted")
	T.eq(store:Size(), 3, "size")
	T.eq(tostring(store), "configstore the options (3)", "tostring")
end)

T.test("a key is stored once, with a whole-number range that is not empty", function()
	local store = Store()
	Has(Raises(store.Range, store, "volume", 0, 1, "listener"), "volume", "twice")
	Raises(store.Range, store, "gain", 5, 1, "listener")
	Raises(store.Range, store, "gain", 0.5, 1, "listener")
	Raises(store.Range, store, "gain", 0, 1, nil)
	Raises(store.Range, store, "", 0, 1, "listener")
	Raises(ConfigStore.New, "")
end)

T.finish()
