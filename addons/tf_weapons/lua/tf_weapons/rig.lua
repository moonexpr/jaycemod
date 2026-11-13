-- The retarget of a TF2 class's arms onto a ValveBiped hands model, in plain numbers: no GMod
-- global, so the tests hold it to .devtools/bin/mdl_rig.py.
--
-- A skeleton is what tf_weapons/mdl.lua reads from a model: `count` bones, each by its Lua index
-- (the engine's bone + 1) in flat arrays `name`, `parent` (0 for none), rest offset `px`, `py`,
-- `pz` and rest rotation `qx`, `qy`, `qz`, `qw` (parent space), and `procedural` (index ->
-- { control, triggers }). Rig.Build pairs two skeletons and works out a rotation C per pair from
-- each bone's own axes in its rest pose (its length toward its child, then its bend axis); each
-- frame, Rig.Solve turns every hands bone as its TF2 bone is turned, times C, anchored at the upper
-- arm, each child placed by the hands' own rest offsets: rotations only, the hands' proportions
-- kept. docs/tf2-hands-spike.md has why the rest poses' difference cannot be the correction.
local Rig = {}

Rig.MIN_BEND = math.rad (3)
Rig.EPSILON  = 1e-9

local MIN_BEND = Rig.MIN_BEND
local EPSILON  = Rig.EPSILON

-- Bones a hands bone gets its world transform from
Rig.MAPPED     = 1 -- turned as its TF2 bone
Rig.ABOVE      = 2 -- an ancestor of a mapped bone: held to it by its rest offset
Rig.PROCEDURAL = 3 -- a quaternion-interpolation helper, solved as the engine solves it
Rig.REST       = 4 -- anything else: its parent's, by its rest offset

local MAPPED, ABOVE, PROCEDURAL, REST = Rig.MAPPED, Rig.ABOVE, Rig.PROCEDURAL, Rig.REST

local abs, acos, sqrt, max = math.abs, math.acos, math.sqrt, math.max

-- Quaternions are (x, y, z, w), as Source stores them

local function Mul (ax, ay, az, aw, bx, by, bz, bw)
	local x = aw * bx + ax * bw + ay * bz - az * by
	local y = aw * by - ax * bz + ay * bw + az * bx
	local z = aw * bz + ax * by - ay * bx + az * bw
	return x, y, z, aw * bw - ax * bx - ay * by - az * bz
end

local function Rotate (qx, qy, qz, qw, vx, vy, vz)
	local cx, cy, cz    = qy * vz - qz * vy, qz * vx - qx * vz, qx * vy - qy * vx
	local ccx, ccy, ccz = qy * cz - qz * cy, qz * cx - qx * cz, qx * cy - qy * cx
	return vx + 2 * (qw * cx + ccx), vy + 2 * (qw * cy + ccy), vz + 2 * (qw * cz + ccz)
end

local function Normalize (x, y, z, w)
	local length = sqrt (x * x + y * y + z * z + w * w)
	if length < EPSILON then return 0, 0, 0, 1 end
	return x / length, y / length, z / length, w / length
end

Rig.Mul       = Mul
Rig.Rotate    = Rotate
Rig.Normalize = Normalize

-- The rotation of a 3x3 matrix given by rows (Source's: column 0 the x axis), and back
function Rig.QuatFromMatrix (m00, m01, m02, m10, m11, m12, m20, m21, m22)
	local trace = m00 + m11 + m22
	if trace > 0 then
		local s = sqrt (trace + 1) * 2
		return (m21 - m12) / s, (m02 - m20) / s, (m10 - m01) / s, s / 4
	elseif m00 > m11 and m00 > m22 then
		local s = sqrt (1 + m00 - m11 - m22) * 2
		return s / 4, (m01 + m10) / s, (m02 + m20) / s, (m21 - m12) / s
	elseif m11 > m22 then
		local s = sqrt (1 + m11 - m00 - m22) * 2
		return (m01 + m10) / s, s / 4, (m12 + m21) / s, (m02 - m20) / s
	end
	local s = sqrt (1 + m22 - m00 - m11) * 2
	return (m02 + m20) / s, (m12 + m21) / s, s / 4, (m10 - m01) / s
end

function Rig.MatrixFromQuat (x, y, z, w)
	local xx, yy, zz = x * x, y * y, z * z
	local xy, xz, yz = x * y, x * z, y * z
	local wx, wy, wz = w * x, w * y, w * z
	local m00, m01, m02 = 1 - 2 * (yy + zz), 2 * (xy - wz), 2 * (xz + wy)
	local m10, m11, m12 = 2 * (xy + wz), 1 - 2 * (xx + zz), 2 * (yz - wx)
	local m20, m21, m22 = 2 * (xz - wy), 2 * (yz + wx), 1 - 2 * (xx + yy)
	return m00, m01, m02, m10, m11, m12, m20, m21, m22
end

local QuatFromMatrix = Rig.QuatFromMatrix

-- A world transform (p, q) in the axes of a frame (o, r): its position and rotation seen from the frame
function Rig.ToLocal (ox, oy, oz, rx, ry, rz, rw, px, py, pz, qx, qy, qz, qw)
	local lx, ly, lz = Rotate (-rx, -ry, -rz, rw, px - ox, py - oy, pz - oz)
	local ax, ay, az, aw = Mul (-rx, -ry, -rz, rw, qx, qy, qz, qw)
	return lx, ly, lz, ax, ay, az, aw
end

-- The axis and angle (radians, 0..pi) of a rotation
local function AxisAngle (x, y, z, w)
	if w < 0 then x, y, z, w = -x, -y, -z, -w end
	local s = sqrt (max (0, 1 - w * w))
	if s < EPSILON then return 1, 0, 0, 0 end
	return x / s, y / s, z / s, 2 * acos (math.min (1, w))
end

local function Cross (ax, ay, az, bx, by, bz)
	return ay * bz - az * by, az * bx - ax * bz, ax * by - ay * bx
end

local function Unit (x, y, z)
	local length = sqrt (x * x + y * y + z * z)
	if length < EPSILON then error ("a zero-length axis", 3) end
	return x / length, y / length, z / length
end

-- The rotation whose columns are the primary axis, the secondary made orthogonal to it, and their cross
local function FrameQuat (ax, ay, az, bx, by, bz)
	ax, ay, az = Unit (ax, ay, az)
	local along = bx * ax + by * ay + bz * az
	bx, by, bz = Unit (bx - along * ax, by - along * ay, bz - along * az)
	local cx, cy, cz = Cross (ax, ay, az, bx, by, bz)
	return QuatFromMatrix (ax, bx, cx, ay, by, cy, az, bz, cz)
end

Rig.FrameQuat = FrameQuat

-- The bones paired, TF2's to ValveBiped's, a side's parents before their children: names to look
-- for on the real models, which Rig.Build reports when absent
local FINGERS = { { "thumb", "0" }, { "index", "1" }, { "middle", "2" }, { "ring", "3" }, { "pinky", "4" } }
local JOINT_SUFFIXES = { "", "1", "2" }

Rig.SIDES = { "R", "L" }

function Rig.Pairs (side)
	local pairs =
	{
		{ "bip_upperArm_" .. side, "ValveBiped.Bip01_" .. side .. "_UpperArm" },
		{ "bip_lowerArm_" .. side, "ValveBiped.Bip01_" .. side .. "_Forearm" },
		{ "bip_hand_" .. side, "ValveBiped.Bip01_" .. side .. "_Hand" }
	}
	for _, finger in ipairs (FINGERS) do
		for joint = 1, 3 do
			pairs [#pairs + 1] =
			{
				"bip_" .. finger [1] .. "_" .. (joint - 1) .. "_" .. side,
				"ValveBiped.Bip01_" .. side .. "_Finger" .. finger [2] .. JOINT_SUFFIXES [joint]
			}
		end
	end
	return pairs
end

function Rig.IndexOf (skeleton)
	local index = {}
	for i = 1, skeleton.count do index [skeleton.name [i]] = i end
	return index
end

-- Each paired bone's canonical frame in its own local axes, as a quaternion: chain is a side's bones
-- of one skeleton in Rig.Pairs' order (upper arm, forearm, hand, then three joints a finger,
-- thumb first). Returns bone index -> { x, y, z, w }.
local function Canonical (s, chain)
	local frames = {}
	local upper, fore, hand = chain [1], chain [2], chain [3]
	local index0, middle0, pinky0 = chain [7], chain [10], chain [16]
	local acrossX, acrossY = s.px [pinky0] - s.px [index0], s.py [pinky0] - s.py [index0]
	local acrossZ = s.pz [pinky0] - s.pz [index0]
	local lengthX, lengthY, lengthZ = s.px [middle0], s.py [middle0], s.pz [middle0]
	local ux, uy, uz = Unit (lengthX, lengthY, lengthZ)
	local vx, vy, vz = Unit (acrossX, acrossY, acrossZ)
	local palmX, palmY, palmZ = Cross (ux, uy, uz, vx, vy, vz)
	frames [hand] = { FrameQuat (lengthX, lengthY, lengthZ, acrossX, acrossY, acrossZ) }

	local ex, ey, ez, bend = AxisAngle (s.qx [fore], s.qy [fore], s.qz [fore], s.qw [fore])
	if bend < MIN_BEND then
		-- straight at rest: the elbow bends across the palm, brought into the forearm's axes
		ex, ey, ez = Rotate (s.qx [hand], s.qy [hand], s.qz [hand], s.qw [hand], acrossX, acrossY, acrossZ)
	end
	frames [upper] = { FrameQuat (s.px [fore], s.py [fore], s.pz [fore], ex, ey, ez) }
	frames [fore]  = { FrameQuat (s.px [hand], s.py [hand], s.pz [hand], ex, ey, ez) }

	for finger = 1, 5 do
		local ax, ay, az, aw = 0, 0, 0, 1
		local lx, ly, lz
		for joint = 1, 3 do
			local i = chain [3 + (finger - 1) * 3 + joint]
			ax, ay, az, aw = Mul (ax, ay, az, aw, s.qx [i], s.qy [i], s.qz [i], s.qw [i])
			if joint < 3 then
				local child = chain [4 + (finger - 1) * 3 + joint]
				lx, ly, lz = s.px [child], s.py [child], s.pz [child]
			end
			local bent = chain [3 + (finger - 1) * 3 + math.min (joint + 1, 3)]
			local hx, hy, hz, angle = AxisAngle (s.qx [bent], s.qy [bent], s.qz [bent], s.qw [bent])
			if finger == 1 or angle < MIN_BEND then
				-- the thumb bends toward the palm, not with the fingers
				local rx, ry, rz = acrossX, acrossY, acrossZ
				if finger == 1 then rx, ry, rz = palmX, palmY, palmZ end
				hx, hy, hz = Rotate (-ax, -ay, -az, aw, rx, ry, rz)
			end
			frames [i] = { FrameQuat (lx, ly, lz, hx, hy, hz) }
		end
	end

	return frames
end

-- Which hands bone the derivation of an ancestor starts from: its child on the way to a mapped bone
local function Kinds (dst, mapped)
	local kind, child = {}, {}
	for j = dst.count, 1, -1 do
		if mapped [j] then kind [j] = MAPPED end
		local parent = dst.parent [j]
		if parent > 0 and (kind [j] == MAPPED or kind [j] == ABOVE) and not child [parent] then
			kind [parent], child [parent] = ABOVE, j
		end
	end
	for j = 1, dst.count do
		if kind [j] == nil then
			kind [j] = dst.procedural [j] and PROCEDURAL or REST
		end
	end
	return kind, child
end

-- A retarget of src's (TF2's) bones onto dst's (the hands'). Returns the rig and the names of the
-- paired bones missing from either skeleton (a side missing any is left out whole).
function Rig.Build (src, dst)
	local srcIndex, dstIndex = Rig.IndexOf (src), Rig.IndexOf (dst)
	local rig =
	{
		src = src, dst = dst,
		pairCount = 0, pairSrc = {}, pairDst = {}, pairAnchor = {},
		cx = {}, cy = {}, cz = {}, cw = {},
		-- the TF2 bones' world transforms the caller writes each frame, by src index
		ipx = {}, ipy = {}, ipz = {}, iqx = {}, iqy = {}, iqz = {}, iqw = {},
		-- the hands bones' world transforms Rig.Solve writes, by dst index
		px = {}, py = {}, pz = {}, qx = {}, qy = {}, qz = {}, qw = {},
		weights = {}
	}
	local missing, mapped = {}, {}
	for _, side in ipairs (Rig.SIDES) do
		local pairs = Rig.Pairs (side)
		local srcChain, dstChain, whole = {}, {}, true
		for k, pair in ipairs (pairs) do
			srcChain [k], dstChain [k] = srcIndex [pair [1]], dstIndex [pair [2]]
			if not srcChain [k] then missing [#missing + 1], whole = pair [1], false end
			if not dstChain [k] then missing [#missing + 1], whole = pair [2], false end
		end
		if whole then
			local srcFrames, dstFrames = Canonical (src, srcChain), Canonical (dst, dstChain)
			for k = 1, #pairs do
				local s, d = srcChain [k], dstChain [k]
				local a, b = srcFrames [s], dstFrames [d]
				local n = rig.pairCount + 1
				rig.pairCount, rig.pairSrc [n], rig.pairDst [n], rig.pairAnchor [n] = n, s, d, k == 1
				rig.cx [n], rig.cy [n], rig.cz [n], rig.cw [n] = Mul (a [1], a [2], a [3], a [4], -b [1], -b [2], -b [3], b [4])
				mapped [d] = true
			end
		end
	end
	rig.kind, rig.aboveChild = Kinds (dst, mapped)
	for j = 1, dst.count do
		rig.px [j], rig.py [j], rig.pz [j] = dst.px [j], dst.py [j], dst.pz [j]
		rig.qx [j], rig.qy [j], rig.qz [j], rig.qw [j] = dst.qx [j], dst.qy [j], dst.qz [j], dst.qw [j]
	end
	for i = 1, src.count do
		rig.ipx [i], rig.ipy [i], rig.ipz [i] = 0, 0, 0
		rig.iqx [i], rig.iqy [i], rig.iqz [i], rig.iqw [i] = 0, 0, 0, 1
	end
	return rig, missing
end

-- The parent's world transform times a local one, into bone j
local function Place (rig, j, parent, lx, ly, lz, qx, qy, qz, qw)
	local pqx, pqy, pqz, pqw = rig.qx [parent], rig.qy [parent], rig.qz [parent], rig.qw [parent]
	local rx, ry, rz = Rotate (pqx, pqy, pqz, pqw, lx, ly, lz)
	rig.px [j], rig.py [j], rig.pz [j] = rig.px [parent] + rx, rig.py [parent] + ry, rig.pz [parent] + rz
	rig.qx [j], rig.qy [j], rig.qz [j], rig.qw [j] = Mul (pqx, pqy, pqz, pqw, qx, qy, qz, qw)
end

-- DoQuatInterpBone (bone_setup.cpp): the control bone's rotation against its parent picks a blend of
-- the triggers' local transforms
local function Procedural (rig, j)
	local dst, proc = rig.dst, rig.dst.procedural [j]
	local c = proc.control
	local cp = dst.parent [c]
	local sx, sy, sz, sw = rig.qx [c], rig.qy [c], rig.qz [c], rig.qw [c]
	if cp > 0 then
		sx, sy, sz, sw = Mul (-rig.qx [cp], -rig.qy [cp], -rig.qz [cp], rig.qw [cp], sx, sy, sz, sw)
	end
	local triggers, weights, scale = proc.triggers, rig.weights, 0
	for t = 1, #triggers do
		local trigger = triggers [t]
		local dot = abs (trigger [2] * sx + trigger [3] * sy + trigger [4] * sz + trigger [5] * sw)
		local weight = max (0, 1 - 2 * acos (math.min (1, dot)) * trigger [1])
		weights [t], scale = weight, scale + weight
	end
	local parent = dst.parent [j]
	if scale <= 0.001 then
		local first = triggers [1]
		Place (rig, j, parent, first [6], first [7], first [8], first [9], first [10], first [11], first [12])
		return
	end
	local ax, ay, az, aw, lx, ly, lz = 0, 0, 0, 0, 0, 0, 0
	for t = 1, #triggers do
		local weight = weights [t]
		if weight > 0 then
			local trigger, s = triggers [t], weight / scale
			-- QuaternionAccumulate: aligned to the sum so far
			if ax * trigger [9] + ay * trigger [10] + az * trigger [11] + aw * trigger [12] < 0 then s = -s end
			ax, ay, az, aw = ax + s * trigger [9], ay + s * trigger [10], az + s * trigger [11], aw + s * trigger [12]
			local p = weight / scale
			lx, ly, lz = lx + p * trigger [6], ly + p * trigger [7], lz + p * trigger [8]
		end
	end
	ax, ay, az, aw = Normalize (ax, ay, az, aw)
	Place (rig, j, parent, lx, ly, lz, ax, ay, az, aw)
end

Rig.Procedural = Procedural

-- The hands' world transforms from the TF2 bones' (rig.ip*, rig.iq*), into rig.p*, rig.q*. Allocates
-- nothing.
function Rig.Solve (rig)
	local dst = rig.dst
	for n = 1, rig.pairCount do
		local s, d = rig.pairSrc [n], rig.pairDst [n]
		local qx, qy, qz, qw = rig.iqx [s], rig.iqy [s], rig.iqz [s], rig.iqw [s]
		qx, qy, qz, qw = Mul (qx, qy, qz, qw, rig.cx [n], rig.cy [n], rig.cz [n], rig.cw [n])
		if rig.pairAnchor [n] then
			rig.px [d], rig.py [d], rig.pz [d] = rig.ipx [s], rig.ipy [s], rig.ipz [s]
			rig.qx [d], rig.qy [d], rig.qz [d], rig.qw [d] = qx, qy, qz, qw
		else
			local parent = dst.parent [d]
			local pqx, pqy, pqz, pqw = rig.qx [parent], rig.qy [parent], rig.qz [parent], rig.qw [parent]
			local rx, ry, rz = Rotate (pqx, pqy, pqz, pqw, dst.px [d], dst.py [d], dst.pz [d])
			rig.px [d], rig.py [d], rig.pz [d] = rig.px [parent] + rx, rig.py [parent] + ry, rig.pz [parent] + rz
			rig.qx [d], rig.qy [d], rig.qz [d], rig.qw [d] = qx, qy, qz, qw
		end
	end
	local kind = rig.kind
	for j = dst.count, 1, -1 do
		if kind [j] == ABOVE then
			-- world(j) = world(child) * inverse(rest local of child)
			local c = rig.aboveChild [j]
			local qx, qy, qz, qw = rig.qx [c], rig.qy [c], rig.qz [c], rig.qw [c]
			qx, qy, qz, qw = Mul (qx, qy, qz, qw, -dst.qx [c], -dst.qy [c], -dst.qz [c], dst.qw [c])
			local rx, ry, rz = Rotate (qx, qy, qz, qw, dst.px [c], dst.py [c], dst.pz [c])
			rig.px [j], rig.py [j], rig.pz [j] = rig.px [c] - rx, rig.py [c] - ry, rig.pz [c] - rz
			rig.qx [j], rig.qy [j], rig.qz [j], rig.qw [j] = qx, qy, qz, qw
		end
	end
	for j = 1, dst.count do
		local k = kind [j]
		if k == PROCEDURAL then
			Procedural (rig, j)
		elseif k == REST and dst.parent [j] > 0 then
			Place (rig, j, dst.parent [j], dst.px [j], dst.py [j], dst.pz [j], dst.qx [j], dst.qy [j], dst.qz [j], dst.qw [j])
		end
	end
end

return Rig
