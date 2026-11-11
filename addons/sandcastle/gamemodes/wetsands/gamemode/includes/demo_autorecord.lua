-- Playtest demos (cl_demo_autorecord, ws/cl_demo_autorecord.lua): what a
-- client does about recording, and what its demo is called, so a playtest's
-- demos sort by map and time.
module (...)

RECORD, STOP = "record", "stop"
STAMP = "%Y%m%d_%H%M%S" -- os.date's format of Name's stamp

function Name (map, stamp) return "playtest_" .. map .. "_" .. stamp end

-- The command that brings a client to what is asked, or nil when it is there.
function Action (enabled, recording)
	if enabled == recording then return nil end
	return enabled and RECORD or STOP
end
