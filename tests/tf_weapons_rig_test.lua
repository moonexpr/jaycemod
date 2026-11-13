-- tf_weapons (addons/tf_weapons): the TF2 class arms retargeted onto a ValveBiped hands model,
-- held to .devtools/bin/mdl_rig.py, which made the fixture from the Scout's arms and
-- c_arms_citizen (docs/tf2-hands-spike.md), and the .mdl reader on bytes made here.
local T = dofile ("tests/harness.lua")
local Rig = dofile ("addons/tf_weapons/lua/tf_weapons/rig.lua")
local Mdl = dofile ("addons/tf_weapons/lua/tf_weapons/mdl.lua")
local FIXTURE = dofile ("tests/fixtures/tf_weapons_scout_citizen.lua")

local POSITION_EPSILON = 1e-3
local ROTATION_EPSILON = 1e-4

-- A fixture's bones as the skeleton tf_weapons/mdl.lua reads
local function Skeleton (bones)
	local s =
	{
		count = #bones, name = {}, parent = {}, procedural = {},
		px = {}, py = {}, pz = {}, qx = {}, qy = {}, qz = {}, qw = {}
	}
	for i, b in ipairs (bones) do
		s.name [i], s.parent [i] = b [1], b [2]
		s.px [i], s.py [i], s.pz [i] = b [3], b [4], b [5]
		s.qx [i], s.qy [i], s.qz [i], s.qw [i] = b [6], b [7], b [8], b [9]
		if b.control then s.procedural [i] = { control = b.control, triggers = b.triggers } end
	end
	return s
end

local ARMS, HANDS = Skeleton (FIXTURE.arms.bones), Skeleton (FIXTURE.hands.bones)

-- The same rotation, whichever sign the quaternion has
local function SameRotation (ax, ay, az, aw, b, what)
	local dot = ax * b [4] + ay * b [5] + az * b [6] + aw * b [7]
	T.near (math.abs (dot), 1, ROTATION_EPSILON, what)
end

local function Feed (rig, arms)
	for i, w in ipairs (arms) do
		rig.ipx [i], rig.ipy [i], rig.ipz [i] = w [1], w [2], w [3]
		rig.iqx [i], rig.iqy [i], rig.iqz [i], rig.iqw [i] = w [4], w [5], w [6], w [7]
	end
end

T.test ("every Scout arm and finger bone pairs with one of the hands'", function ()
	local rig, missing = Rig.Build (ARMS, HANDS)
	T.eq (#missing,      0,  "missing")
	T.eq (rig.pairCount, 36, "two sides of 18")
end)

T.test ("the upper arm and forearm corrections are the axes permuted: 120 degrees about (1, 1, 1)", function ()
	local rig = Rig.Build (ARMS, HANDS)
	for n = 1, 2 do
		T.near (math.abs (rig.cw [n]), 0.5, 1e-5, HANDS.name [rig.pairDst [n]])
	end
end)

T.test ("each hands bone lands where the oracle puts it, every frame of the fixture", function ()
	local rig = Rig.Build (ARMS, HANDS)
	for _, frame in ipairs (FIXTURE.frames) do
		Feed (rig, frame.arms)
		Rig.Solve (rig)
		for j, expected in ipairs (frame.hands) do
			local what = frame.label .. "@" .. frame.frame .. " " .. HANDS.name [j]
			T.near (rig.px [j], expected [1], POSITION_EPSILON, what .. " x")
			T.near (rig.py [j], expected [2], POSITION_EPSILON, what .. " y")
			T.near (rig.pz [j], expected [3], POSITION_EPSILON, what .. " z")
			SameRotation (rig.qx [j], rig.qy [j], rig.qz [j], rig.qw [j], expected, what)
		end
	end
end)

-- An ancestor of both arms (the spine) follows the one arm it is derived from; the other clavicle
-- follows its own upper arm, so only that link may stretch.
T.test ("the hands keep their own lengths: a child sits at its rest offset from its parent", function ()
	local rig = Rig.Build (ARMS, HANDS)
	Feed (rig, FIXTURE.frames [1].arms)
	Rig.Solve (rig)
	for j = 1, HANDS.count do
		local parent = HANDS.parent [j]
		local otherBranch = parent > 0 and rig.kind [parent] == Rig.ABOVE and rig.aboveChild [parent] ~= j
		if parent > 0 and not HANDS.procedural [j] and not otherBranch then
			local dx, dy, dz = rig.px [j] - rig.px [parent], rig.py [j] - rig.py [parent], rig.pz [j] - rig.pz [parent]
			local rest = math.sqrt (HANDS.px [j] ^ 2 + HANDS.py [j] ^ 2 + HANDS.pz [j] ^ 2)
			T.near (math.sqrt (dx * dx + dy * dy + dz * dz), rest, POSITION_EPSILON, HANDS.name [j])
		end
	end
end)

T.test ("a helper bone takes its trigger's transform when its control sits on that trigger", function ()
	local rig = Rig.Build (ARMS, HANDS)
	local wrist = Rig.IndexOf (HANDS) ["ValveBiped.Bip01_R_Wrist"]
	local proc = HANDS.procedural [wrist]
	local control, controlParent, parent = proc.control, HANDS.parent [proc.control], HANDS.parent [wrist]
	for _, j in ipairs ({ controlParent, parent }) do
		rig.px [j], rig.py [j], rig.pz [j] = 0, 0, 0
		rig.qx [j], rig.qy [j], rig.qz [j], rig.qw [j] = 0, 0, 0, 1
	end
	for t, trigger in ipairs (proc.triggers) do
		rig.qx [control], rig.qy [control] = trigger [2], trigger [3]
		rig.qz [control], rig.qw [control] = trigger [4], trigger [5]
		Rig.Procedural (rig, wrist)
		local what = "trigger " .. t
		T.near (rig.px [wrist], trigger [6], POSITION_EPSILON, what .. " x")
		local expected = { 0, 0, 0, trigger [9], trigger [10], trigger [11], trigger [12] }
		SameRotation (rig.qx [wrist], rig.qy [wrist], rig.qz [wrist], rig.qw [wrist], expected, what)
	end
end)

T.test ("a side missing a bone is left out whole, and the missing names reported", function ()
	local hands = Skeleton (FIXTURE.hands.bones)
	local index = Rig.IndexOf (hands)
	hands.name [index ["ValveBiped.Bip01_L_Finger42"]] = "ValveBiped.Bip01_L_Finger42_gone"
	local rig, missing = Rig.Build (ARMS, hands)
	T.eq (rig.pairCount,                                    18,                            "the right side alone")
	T.eq (missing [1],                                      "ValveBiped.Bip01_L_Finger42", "named")
	T.eq (rig.kind [index ["ValveBiped.Bip01_L_UpperArm"]], Rig.REST,                      "the left arm stays at rest")
end)

T.test ("Solve allocates nothing once warm", function ()
	-- one table a solve would be hundreds of kilobytes over these; the JIT's own side traces, a few
	local WARM, MEASURED, SLACK_KB = 2000, 10000, 4
	local rig = Rig.Build (ARMS, HANDS)
	Feed (rig, FIXTURE.frames [2].arms)
	-- the JIT's traces are recorded over the first calls, and that allocates
	for _ = 1, WARM do Rig.Solve (rig) end
	collectgarbage ("collect")
	collectgarbage ("stop")
	local before = collectgarbage ("count")
	for _ = 1, MEASURED do Rig.Solve (rig) end
	local grown = collectgarbage ("count") - before
	collectgarbage ("restart")
	T.eq (grown < SLACK_KB, true, "kilobytes allocated over " .. MEASURED .. " solves: " .. grown)
end)

T.test ("a quaternion survives the trip through a matrix", function ()
	local x, y, z, w = Rig.Normalize (0.3, -0.5, 0.2, 0.7)
	local qx, qy, qz, qw = Rig.QuatFromMatrix (Rig.MatrixFromQuat (x, y, z, w))
	SameRotation (qx, qy, qz, qw, { 0, 0, 0, x, y, z, w }, "round trip")
end)

-- The .mdl reader, on a model made here: the header, one plain bone and one helper with a trigger

local function Bytes32 (value)
	if value < 0 then value = value + 0x100000000 end
	local b2, b3, b4 = math.floor (value / 0x100), math.floor (value / 0x10000), math.floor (value / 0x1000000)
	return string.char (value % 0x100, b2 % 0x100, b3 % 0x100, b4 % 0x100)
end

-- Exact for the small binary fractions used here
local function Float32 (value)
	if value == 0 then return Bytes32 (0) end
	local sign = value < 0 and 0x80000000 or 0
	value = math.abs (value)
	local exponent = math.floor (math.log (value) / math.log (2))
	local mantissa = math.floor ((value / 2 ^ exponent - 1) * 0x800000 + 0.5)
	return Bytes32 (sign + (exponent + 127) * 0x800000 + mantissa)
end

local function Model (version)
	local HEADER, BONES = 400, 2
	local base = HEADER
	local names = base + BONES * Mdl.BONE_SIZE
	local procAt = names + 32
	local parts = { "IDST", Bytes32 (version), string.rep ("\0", 148), Bytes32 (BONES), Bytes32 (base) }
	local header = table.concat (parts)
	header = header .. string.rep ("\0", HEADER - #header)
	local function Bone (i, name, parent, x, procIndex)
		local o = base + (i - 1) * Mdl.BONE_SIZE
		local nameAt = names + (i - 1) * 16
		local b = Bytes32 (nameAt - o) .. Bytes32 (parent) .. string.rep ("\0", 24)
			.. Float32 (x) .. Float32 (0.5) .. Float32 (-2)
			.. Float32 (0) .. Float32 (0) .. Float32 (0) .. Float32 (1)
		local procType, procAt = procIndex and Mdl.PROC_QUATINTERP or 0, procIndex and procIndex - o or 0
		b = b .. string.rep ("\0", 164 - #b) .. Bytes32 (procType) .. Bytes32 (procAt)
		return b .. string.rep ("\0", Mdl.BONE_SIZE - #b), name
	end
	local b1, n1 = Bone (1, "root", -1, 1)
	local b2, n2 = Bone (2, "helper", 0, 4, procAt)
	local nameBlock = n1 .. "\0" .. string.rep ("\0", 15 - #n1) .. n2 .. "\0" .. string.rep ("\0", 15 - #n2)
	local trigger = Float32 (0.5) .. Float32 (0) .. Float32 (0) .. Float32 (0) .. Float32 (1)
		.. Float32 (2) .. Float32 (0) .. Float32 (0) .. Float32 (0) .. Float32 (0) .. Float32 (0) .. Float32 (1)
	local proc = Bytes32 (0) .. Bytes32 (1) .. Bytes32 (12) .. trigger
	return header .. b1 .. b2 .. nameBlock .. proc
end

T.test ("the reader gives a model's bones, rest pose and helpers' triggers", function ()
	local s = assert (Mdl.Read (Model (48)))
	T.eq (s.count,                           2,        "bones")
	T.eq (s.name [1],                        "root",   "first name")
	T.eq (s.name [2],                        "helper", "second name")
	T.eq (s.parent [1],                      0,        "the root has no parent")
	T.eq (s.parent [2],                      1,        "parents count from 1")
	T.eq (s.px [2],                          4,        "x")
	T.eq (s.py [2],                          0.5,      "y")
	T.eq (s.pz [2],                          -2,       "z")
	T.eq (s.qw [1],                          1,        "w")
	T.eq (s.procedural [1],                  nil,      "a plain bone")
	T.eq (s.procedural [2].control,          1,        "the control, from 1")
	T.eq (#s.procedural [2].triggers,        1,        "one trigger")
	T.eq (s.procedural [2].triggers [1] [1], 0.5,      "its inverse tolerance")
	T.eq (s.procedural [2].triggers [1] [6], 2,        "its position")
end)

T.test ("the reader refuses what it cannot read, saying why", function ()
	T.eq (select (2, Mdl.Read ("nope")),                          "not a studio model",            "not a model")
	T.eq (select (2, Mdl.Read (Model (44))),                      "studio version 44 is not read", "an old version")
	T.eq (select (2, Mdl.Read (string.sub (Model (48), 1, 402))), "the model ends early",          "cut short")
end)

T.test ("the reader decodes IEEE singles", function ()
	T.eq (Mdl.Float (Float32 (-0.75), 0), -0.75, "negative fraction")
	T.eq (Mdl.Float (Float32 (1024), 0),  1024,  "power of two")
	T.eq (Mdl.Int32 (Bytes32 (-5), 0),    -5,    "signed")
end)

T.finish ()
