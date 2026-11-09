-- The hostages' voice: TF2 Classic's Civilian, Benjamoose's lines
-- (sound/vo/civilian_benjamoose/, mounted from the server's
-- hostage_civilian_voice pack: .devtools/bin/server_root.py SERVER_PACKS). For
-- each thing that happens to a hostage, the categories of the pack it says a
-- line from, each with how many lines it has (<category>(1..n).wav). Paths
-- are under sound/, as EmitSound takes them.
local error, format, ipairs, tostring = error, string.format, ipairs, tostring
module(...)

-- taken by a rescuer; following one (now and then); left behind (its rescuer
-- died); held, a rescuer near; led into the rescue zone
TAKEN, FOLLOWING, LEFT, CALLING, RESCUED = "taken", "following", "left", "calling", "rescued"

local DIR = "vo/civilian_benjamoose/"

local EVENTS = {
	[TAKEN] = { { "civ_thanks", 19 }, { "civ_go_go_go", 13 } },
	[FOLLOWING] = { { "civ_go_moveup", 12 }, { "civ_go_proceed", 6 } },
	[LEFT] = { { "civ_calling_for_help", 22 } },
	[CALLING] = { { "civ_calling_for_help", 22 } },
	[RESCUED] = { { "civ_success", 17 } },
}
local ORDER = { TAKEN, FOLLOWING, LEFT, CALLING, RESCUED }

-- A hostage says a line at most once in SPEAK_GAP seconds; following, one
-- now and then, no sooner than FOLLOW_CHATTER after its last.
SPEAK_GAP = 4
FOLLOW_CHATTER = 12

local lines = {}
for _, event in ipairs(ORDER) do
	local list = {}
	for _, c in ipairs(EVENTS[event]) do
		for i = 1, c[2] do list[#list + 1] = format("%s%s(%d).wav", DIR, c[1], i) end
	end
	lines[event] = list
end

-- The event's lines, in order.
function Lines(event)
	local list = lines[event]
	if not list then error("no hostage voice event " .. tostring(event), 2) end
	return list
end

-- The line for a number the caller draws, wrapping past the last.
function Pick(event, n)
	local list = Lines(event)
	return list[(n - 1) % #list + 1]
end

-- Every line any event says, once: what clients fetch and the server precaches.
function All()
	local all, seen = {}, {}
	for _, event in ipairs(ORDER) do
		for _, path in ipairs(lines[event]) do
			if not seen[path] then
				seen[path] = true
				all[#all + 1] = path
			end
		end
	end
	return all
end

-- Whether a hostage that last spoke at `last` (nil: never) may speak at now.
function MaySpeak(last, now)
	return last == nil or now - last >= SPEAK_GAP
end
