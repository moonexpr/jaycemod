-- The boundary between Lua and the native foundation: what the bindings rely on
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

T.test ("a panic in native code is a Lua error naming a foundation bug, and the server lives", function ()
	local ok, err = pcall (native.probe.Panic)
	T.eq (ok,                                                                            false, "raised")
	T.eq (tostring (err):find ("foundation bug: the probe's own panic", 1, true) ~= nil, true,  "named ours: " .. tostring (err))
	T.eq (native.probe.Add (1, 2),                                                       3,     "the next call answers")
end)

T.test ("a job its clock cancels while it is woken stays cancelled, in both twins", function ()
	for _, Calendar in ipairs ({ list.calendar, native.list.calendar }) do
		local clock, cancelling = { t = 0 }, nil
		local calendar
		function clock:Now ()
			if cancelling then calendar:Cancel (cancelling) end
			return self.t
		end
		local timer = { Now = function () return 0 end }
		calendar = Calendar.New (clock, timer)
		calendar:System ("war", 1)
		local runs = 0
		local job = calendar:Every ("war", 5, function () runs = runs + 1 end, 10)
		cancelling = job
		calendar:Wake (job)
		cancelling = nil
		clock.t = 20
		calendar:Run (1)
		T.eq (runs, 0, "the cancelled job never runs")
	end
end)

T.finish ()
