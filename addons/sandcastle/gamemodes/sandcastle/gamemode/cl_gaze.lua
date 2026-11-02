-- Heads turn to what interests them apart from where they aim
-- (nextsoldier.gaze), on each client and only while drawn, as
-- C_HL2MP_Player::UpdateLookAt turns a player's: every player's toward the
-- nearest other player in front of it within reach, else ahead; a
-- NextSoldier soldier's (base_nextsoldier's Draw) also along its aim in a
-- fight and where the server told it to look, and toward teammates alone.
local Gaze = nextsoldier.gaze
local EYE_HEIGHT = Vector(0, 0, 64)
local LOOK_RANGE_SQR = Gaze.LOOK_RANGE * Gaze.LOOK_RANGE

-- The players a head may look at, made once a frame for every head drawn
-- in it: alive and in this client's PVS (not dormant, the client's
-- ents.FindInPVS), each with its origin, eyes and team.
local seen, seenFrame = {}, -1

local function Seen()
	local frame = FrameNumber()
	if frame == seenFrame then return seen end
	seenFrame, seen = frame, {}
	for _, ply in ipairs(player.GetAll()) do
		if not ply:IsDormant() and ply:Alive() then
			seen[#seen + 1] = { ply = ply, pos = ply:GetPos(), eye = ply:EyePos(), team = ply:Team() }
		end
	end
	return seen
end

-- ent's head turned for this frame: facing, the yaw its upper body aims at;
-- fighting, looking along its aim; hint, a point it was told to look at, or
-- nil; team, whose players it looks at (nil: anyone's); urgent, snapping
-- onto its goal rather than turning to it.
function WS.GazeUpdate(ent, facing, fighting, hint, team, urgent)
	local now = CurTime()
	local step = Gaze.Step(now - (ent.wsGazeAt or now), urgent)
	local turned = math.NormalizeAngle(facing - (ent.wsGazeFacing or facing))
	ent.wsGazeAt, ent.wsGazeFacing = now, facing
	local pos = ent:GetPos()
	local people = {}
	for _, other in ipairs(Seen()) do
		if other.ply ~= ent and (team == nil or other.team == team) and other.pos:DistToSqr(pos) <= LOOK_RANGE_SQR then
			people[#people + 1] = other.eye
		end
	end
	local yaw, pitch = Gaze.Goal({ fighting = fighting, eye = pos + EYE_HEIGHT, facing = facing, hint = hint, people = people })
	ent.wsHeadYaw = Gaze.Turn(ent.wsHeadYaw or 0, yaw, step, turned)
	ent.wsHeadPitch = Gaze.Approach(ent.wsHeadPitch or 0, pitch, step)
	ent:SetPoseParameter("head_yaw", ent.wsHeadYaw)
	ent:SetPoseParameter("head_pitch", ent.wsHeadPitch)
	ent:InvalidateBoneCache()
end

hook.Add("PrePlayerDraw", "ws_gaze", function(ply)
	WS.GazeUpdate(ply, ply:EyeAngles().y, false, nil, nil, false)
end)
