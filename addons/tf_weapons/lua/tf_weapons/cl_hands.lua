-- The player's own hands on a TF2 weapon, each frame: the class arms (the viewmodel) animate hidden,
-- the weapon's c_model rides them by bone merge, and a clientside copy of the player's hands model
-- is posed from the arms' bones by tf_weapons/rig.lua and drawn. Our own model rather than the stock
-- gmod_hands: docs/tf2-hands-spike.md.
--
-- tf_weapons_rebuild reads the rigs again, re-runs the pure modules from disk and remakes the models
-- on the next frame, so an edit is picked up by autorefresh and a rebuild, with no map change and
-- no re-equip.
local Hands = TFWeapons.Hands or {}
TFWeapons.Hands = Hands

local HANDS_FALLBACK = "models/weapons/c_arms_citizen.mdl"
local TAG_COLOR      = Color (120, 200, 255)

local IsValid = IsValid

local function Print (...)
	MsgC (TAG_COLOR, "[tf_weapons] ", color_white, string.format (...), "\n")
end

-- The hands model the gamemode gave the player (PlayerSetHandsModel), else what their player model
-- translates to
local function HandsOf (ply)
	local stock = ply:GetHands ()
	if IsValid (stock) then return stock:GetModel (), stock:GetSkin (), stock end
	local info = player_manager.TranslatePlayerHands (player_manager.TranslateToPlayerModelName (ply:GetModel ()))
	return info.model or HANDS_FALLBACK, info.skin or 0, info.body
end

local function ReadSkeleton (model)
	local data = file.Read (model, "GAME")
	if not data then return nil, "cannot read " .. model .. " from the game's files" end
	local skeleton, why = TFWeapons.Mdl.Read (data)
	if not skeleton then return nil, model .. ": " .. why end

	return skeleton
end

-- The file's bones must be the entity's, in the entity's order
local function SameBones (skeleton, ent, model)
	if ent:GetBoneCount () ~= skeleton.count then
		return false, string.format ("%s has %d bones in game and %d in its file", model, ent:GetBoneCount (), skeleton.count)
	end
	for i = 1, skeleton.count do
		local inGame = ent:GetBoneName (i - 1)
		if inGame ~= skeleton.name [i] then
			local why = "%s's bone %d is %s in game and %s in its file"
			return false, string.format (why, model, i - 1, inGame, skeleton.name [i])
		end
	end

	return true
end

function Hands.Release ()
	local state = Hands.state
	Hands.state = nil
	if not state then return end
	if IsValid (state.hands) then state.hands:Remove () end
	if IsValid (state.gun) then state.gun:Remove () end
end

local function CopyLook (hands, skin, stock)
	hands:SetSkin (skin)
	if isstring (stock) then
		hands:SetBodyGroups (stock)
	elseif IsValid (stock) then
		for group = 0, stock:GetNumBodyGroups () - 1 do hands:SetBodygroup (group, stock:GetBodygroup (group)) end
	end
	function hands:GetPlayerColor ()
		local ply = LocalPlayer ()
		return ply.GetPlayerColor and ply:GetPlayerColor () or nil
	end
end

local function Report (state, missing)
	Print ("arms %s, hands %s: %d bone pairs", state.armsModel, state.handsModel, state.rig.pairCount)
	if #missing > 0 then Print ("missing, those sides left at rest: %s", table.concat (missing, ", ")) end
	local procedural = 0
	for _ in pairs (state.rig.dst.procedural) do procedural = procedural + 1 end
	Print ("%d procedural helper bones solved here", procedural)
end

-- Everything a weapon's frame reads, made once: nil and why if it cannot be
local function Build (weapon, vm, ply)
	local Rig = TFWeapons.Rig
	local armsModel = vm:GetModel ()
	local handsModel, skin, stock = HandsOf (ply)

	local src, why = ReadSkeleton (armsModel)
	if not src then return nil, why end
	local same, mismatch = SameBones (src, vm, armsModel)
	if not same then return nil, mismatch end
	local dst
	dst, why = ReadSkeleton (handsModel)
	if not dst then return nil, why end

	local hands = ClientsideModel (handsModel, RENDERGROUP_VIEWMODEL)
	if not IsValid (hands) then return nil, "cannot make a model of " .. handsModel end
	same, mismatch = SameBones (dst, hands, handsModel)
	if not same then
		hands:Remove ()
		return nil, mismatch
	end
	hands:SetNoDraw (true)
	hands:SetParent (vm)
	hands:SetLocalPos (vector_origin)
	hands:SetLocalAngles (angle_zero)
	CopyLook (hands, skin, stock)
	hands:AddCallback ("BuildBonePositions", function (ent, count) Hands.BuildBones (ent, count) end)

	local gun = ClientsideModel (weapon.TFModel, RENDERGROUP_VIEWMODEL)
	gun:SetNoDraw (true)
	gun:SetParent (vm)
	gun:AddEffects (EF_BONEMERGE)

	local rig, missing = Rig.Build (src, dst)
	local srcBones = {}
	for n = 1, rig.pairCount do srcBones [n] = rig.pairSrc [n] end
	local matrices = {}
	for j = 1, dst.count do matrices [j] = Matrix () end

	local state =
	{
		weapon = weapon, vm = vm, armsModel = armsModel, handsModel = handsModel, handsSkin = skin,
		rig = rig, hands = hands, gun = gun, srcBones = srcBones, matrices = matrices
	}
	Report (state, missing)

	return state
end

local function Current (state, weapon, vm, ply)
	if state.weapon ~= weapon or state.vm ~= vm or state.armsModel ~= vm:GetModel () then return false end
	if not IsValid (state.hands) or not IsValid (state.gun) then return false end
	local handsModel, skin = HandsOf (ply)

	return state.handsModel == handsModel and state.handsSkin == skin
end

-- The state for this frame, built when anything it was made from changed; nil while it cannot be
local function StateFor (weapon, vm, ply)
	local state = Hands.state
	if state and Current (state, weapon, vm, ply) then return state end
	local key = tostring (weapon) .. vm:GetModel () .. tostring ((HandsOf (ply)))
	if Hands.failed == key then return nil end
	Hands.Release ()
	local why
	state, why = Build (weapon, vm, ply)
	if not state then
		Hands.failed = key
		Print ("cannot hold %s in your hands: %s", weapon:GetClass (), why)
		return nil
	end
	Hands.failed = nil
	Hands.state = state
	return state
end

-- Into the rig the TF2 bones the pairs read, from the viewmodel's matrices this frame
local function ReadArms (state, vm)
	local Rig, rig, srcBones = TFWeapons.Rig, state.rig, state.srcBones
	for n = 1, #srcBones do
		local i = srcBones [n]
		local m = vm:GetBoneMatrix (i - 1)
		if m then
			local e11, e12, e13, e14, e21, e22, e23, e24, e31, e32, e33, e34 = m:Unpack ()
			rig.ipx [i], rig.ipy [i], rig.ipz [i] = e14, e24, e34
			rig.iqx [i], rig.iqy [i], rig.iqz [i], rig.iqw [i] = Rig.QuatFromMatrix (e11, e12, e13, e21, e22, e23, e31, e32, e33)
		end
	end
end

local function WriteMatrices (state)
	local MatrixFromQuat, rig, matrices = TFWeapons.Rig.MatrixFromQuat, state.rig, state.matrices
	for j = 1, #matrices do
		local a, b, c, d, e, f, g, h, i = MatrixFromQuat (rig.qx [j], rig.qy [j], rig.qz [j], rig.qw [j])
		matrices [j]:SetUnpacked (a, b, c, rig.px [j], d, e, f, rig.py [j], g, h, i, rig.pz [j], 0, 0, 0, 1)
	end
end

-- The hands' bones, set by the engine's bone setup from what Draw solved this frame
function Hands.BuildBones (ent, count)
	local state = Hands.state
	if not state or state.hands ~= ent then return end
	local matrices = state.matrices
	for i = 1, math.min (count, #matrices) do ent:SetBoneMatrix (i - 1, matrices [i]) end
end

-- SWEP:PreDrawViewModel: the class arms animate but are not seen
function Hands.PreDraw (weapon, vm)
	if Hands.state == nil and Hands.failed then return end
	render.SetBlend (0)
end

-- SWEP:PostDrawViewModel: the viewmodel's bones are this frame's; solve and draw the gun and hands
function Hands.Draw (weapon, vm, ply)
	render.SetBlend (1)
	local state = StateFor (weapon, vm, ply)
	if not state then return end

	vm:SetupBones ()
	ReadArms (state, vm)
	TFWeapons.Rig.Solve (state.rig)
	WriteMatrices (state)

	state.gun:DrawModel ()
	if weapon.ViewModelFlip then render.CullMode (MATERIAL_CULLMODE_CW) end
	state.hands:InvalidateBoneCache ()
	state.hands:DrawModel ()
	render.CullMode (MATERIAL_CULLMODE_CCW)
end

-- The pure modules again from disk, the activity names forgotten, the models remade next frame
function Hands.Rebuild ()
	TFWeapons.Rig = include ("tf_weapons/rig.lua")
	TFWeapons.Mdl = include ("tf_weapons/mdl.lua")
	TFWeapons.Activities = include ("tf_weapons/activities.lua")
	Hands.Release ()
	Hands.failed = nil
	Print ("rebuilding on the next frame")
end

local REBUILD_HELP = "Read the arms and hands rigs again and remake the held TF2 weapon's hands"
concommand.Add ("tf_weapons_rebuild", function () Hands.Rebuild () end, nil, REBUILD_HELP)

hook.Add ("Think", "moonexpr/tf-weapons/release-models", function ()
	local state = Hands.state
	if not state then return end
	local ply = LocalPlayer ()
	if IsValid (ply) and ply:GetActiveWeapon () == state.weapon then return end
	Hands.Release ()
end)
