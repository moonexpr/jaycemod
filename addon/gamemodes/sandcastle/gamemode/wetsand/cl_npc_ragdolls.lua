-- The client half of NPC death ragdolls (wetsand/sv_npc_ragdolls.lua):
-- every NPC's ragdoll is built here, from the pose the server sent or from
-- this client's copy of the dead body, and fades by the player's own
-- setting. Always loaded, on every map, as its server half is.
local NET = "wetsand_npc_ragdoll_create"
local BYTE_BITS = 8

-- After cl_npc_ragdoll_lifetime seconds (0 keeps them) the engine's own
-- fade (at g_ragdoll_fadespeed) removes an NPC's ragdoll; g_ragdoll_maxcount
-- caps how many stay, as for any clientside ragdoll.
local RAGDOLL_LIFETIME = CreateClientConVar("cl_npc_ragdoll_lifetime", "20", true, false,
	"Seconds a dead NPC's ragdoll stays before fading away (0: until g_ragdoll_maxcount pushes it out)", 0, 600)

function WETSAND.FadeRagdollLater(ragdoll)
	if ragdoll.wetsandFading then return end
	ragdoll.wetsandFading = true
	local lifetime = RAGDOLL_LIFETIME:GetFloat()
	if lifetime <= 0 then return end
	timer.Simple(lifetime, function()
		if IsValid(ragdoll) then ragdoll:SetSaveValue("m_bFadingOut", true) end
	end)
end

local function PoseFromMessage(ragdoll, pose)
	for i, bone in ipairs(pose) do
		local phys = ragdoll:GetPhysicsObjectNum(i - 1)
		if IsValid(phys) then
			phys:SetPos(bone.pos)
			phys:SetAngles(bone.ang)
			phys:SetVelocity(bone.vel)
			phys:Wake()
		end
	end
end

local function PoseFromBody(ragdoll, body)
	body:SetupBones()
	for i = 0, ragdoll:GetPhysicsObjectCount() - 1 do
		local phys = ragdoll:GetPhysicsObjectNum(i)
		local matrix = IsValid(phys) and body:GetBoneMatrix(ragdoll:TranslatePhysBoneToBone(i))
		if matrix then
			phys:SetPos(matrix:GetTranslation())
			phys:SetAngles(matrix:GetAngles())
			phys:Wake()
		end
	end
end

-- The dead body and what it carries (a soldier's weapon) stop drawing once
-- its ragdoll stands in for it.
local function Hide(body)
	body:SetNoDraw(true)
	for _, child in ipairs(body:GetChildren()) do child:SetNoDraw(true) end
end

net.Receive(NET, function()
	local body = net.ReadEntity()
	local model = net.ReadString()
	local skin = net.ReadUInt(BYTE_BITS)
	local groups = {}
	for id = 0, net.ReadUInt(BYTE_BITS) - 1 do groups[id] = net.ReadUInt(BYTE_BITS) end
	local force = net.ReadVector()
	local pose
	if net.ReadBool() then
		pose = {}
		for i = 1, net.ReadUInt(BYTE_BITS) do
			pose[i] = {
				pos = net.ReadVector(),
				ang = net.ReadAngle(),
				vel = net.ReadVector(),
			}
		end
	elseif not IsValid(body) then
		return -- the body never reached this client: nothing to take a pose from
	end

	local ragdoll = ClientsideRagdoll(model)
	if not IsValid(ragdoll) then return end
	ragdoll:SetNoDraw(false)
	ragdoll:DrawShadow(true)
	ragdoll:SetSkin(skin)
	for id, value in pairs(groups) do ragdoll:SetBodygroup(id, value) end
	if pose then PoseFromMessage(ragdoll, pose) else PoseFromBody(ragdoll, body) end
	local count = ragdoll:GetPhysicsObjectCount()
	for i = 0, count - 1 do
		local phys = ragdoll:GetPhysicsObjectNum(i)
		if IsValid(phys) then phys:ApplyForceCenter(force / count) end
	end
	if IsValid(body) then Hide(body) end
	WETSAND.FadeRagdollLater(ragdoll)
end)
