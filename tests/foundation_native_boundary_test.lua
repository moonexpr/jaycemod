-- The boundary between Lua and native/foundation: what the bindings rely on
-- when a call fails, whichever twin the rest of the suite runs.
local T = dofile ("tests/harness.lua")

local native = T.native ("foundation")

T.test ("a Lua error raised in native code drops the Rust values it unwinds past", function ()
	local before = native.probe.Dropped ()
	local ok, err = pcall (native.probe.RaiseDropping)
	T.eq (ok,                      false,                       "raised")
	T.eq (err,                     "raised with a value alive", "its message")
	T.eq (native.probe.Dropped (), before + 1,                  "the value dropped")
end)

T.test ("a native object refused mid-call is not left held: the next call takes it", function ()
	local store = native.configstore.New ("the options")
	store:Range ("volume", 0, 10, "listener")
	local ok, err = pcall (store.Range, store, "volume", 0, 10, "listener")
	T.eq (ok,                                    false, "a key stored twice is refused")
	T.eq (tostring (err):find ("in use") == nil, true,  "refused for what it is: " .. tostring (err))
	store:Range ("offset", -5, 5, "tuner")
	T.eq (store:Has ("offset"), true, "the store takes the next key")
end)

T.test ("one native object handed to its own method twice is read twice, not refused", function ()
	local m = native.math.matrix.New ({ { 1, 2 }, { 3, 4 } })
	local square = m:Multiply (m)
	T.eq (square:Get (1, 1), 7,  "m by itself, first")
	T.eq (square:Get (2, 2), 22, "m by itself, last")
end)

T.finish ()
