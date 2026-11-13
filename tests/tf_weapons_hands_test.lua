-- tf_weapons (addons/tf_weapons): the client's hands driver, cl_hands.lua, run against fakes of the
-- GMod API it calls: the viewmodel's bone matrices in, the hands' bone matrices out, held to the
-- fixture .devtools/bin/mdl_rig.py made (the Scout's arms onto c_arms_citizen).
local T = dofile ("tests/harness.lua")
local Rig = dofile ("addons/tf_weapons/lua/tf_weapons/rig.lua")
local FIXTURE = dofile ("tests/fixtures/tf_weapons_scout_citizen.lua")

local POSITION_EPSILON = 1e-3
local ROTATION_EPSILON = 1e-4
local ARMS_MODEL = FIXTURE.arms.model
local HANDS_MODEL = FIXTURE.hands.model
local GUN_MODEL = "models/weapons/c_models/c_scattergun.mdl"

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

local SKELETONS = { [ARMS_MODEL] = Skeleton (FIXTURE.arms.bones), [HANDS_MODEL] = Skeleton (FIXTURE.hands.bones) }

-- The GMod API, as far as cl_hands.lua reaches into it

local function NewMatrix ()
	local m = { e = { 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1 } }
	function m:SetUnpacked (...) self.e = { ... } end
	function m:Unpack () return unpack (self.e) end
	return m
end

local function MatrixOf (w)
	local m = NewMatrix ()
	local a, b, c, d, e, f, g, h, i = Rig.MatrixFromQuat (w [4], w [5], w [6], w [7])
	m:SetUnpacked (a, b, c, w [1], d, e, f, w [2], g, h, i, w [3], 0, 0, 0, 1)
	return m
end

local made, removed, hooks, commands, printed = {}, 0, {}, {}, {}

local function Entity (model)
	local skeleton = SKELETONS [model]
	local ent = { model = model, valid = true, callbacks = {}, set = {}, setups = 0 }
	function ent:GetModel () return self.model end
	function ent:GetBoneCount () return skeleton and skeleton.count or 0 end
	function ent:GetBoneName (i) return skeleton.name [i + 1] end
	function ent:SetNoDraw () end
	function ent:SetParent (parent) self.parent = parent end
	function ent:SetLocalPos () end
	function ent:SetLocalAngles () end
	function ent:SetSkin (skin) self.skin = skin end
	function ent:SetBodyGroups (body) self.body = body end
	function ent:AddEffects (effects) self.effects = effects end
	function ent:AddCallback (name, fn) self.callbacks [name] = fn end
	function ent:InvalidateBoneCache () self.stale = true end
	function ent:SetBoneMatrix (i, m) self.set [i] = { m:Unpack () } end
	function ent:DrawModel ()
		self.drawn = (self.drawn or 0) + 1
		local build = self.callbacks.BuildBonePositions
		if build and self.stale then build (self, self:GetBoneCount ()) end
		self.stale = false
	end
	function ent:Remove ()
		self.valid = false
		removed = removed + 1
	end
	return ent
end

local FakeMdl = { Read = function (data) return SKELETONS [data] end }

local function Install ()
	_G.IsValid = function (ent) return ent ~= nil and ent.valid == true end
	_G.isstring = function (v) return type (v) == "string" end
	_G.Color = function (r, g, b) return { r = r, g = g, b = b } end
	_G.color_white, _G.vector_origin, _G.angle_zero = {}, {}, {}
	_G.MsgC = function (...)
		local parts = {}
		for _, v in ipairs ({ ... }) do if type (v) == "string" then parts [#parts + 1] = v end end
		printed [#printed + 1] = table.concat (parts)
	end
	_G.Matrix = NewMatrix
	_G.ClientsideModel = function (model)
		local ent = Entity (model)
		made [#made + 1] = ent
		return ent
	end
	_G.file = { Read = function (path) return SKELETONS [path] and path or nil end }
	_G.render = { SetBlend = function (b) _G.render.blend = b end, CullMode = function () end }
	_G.concommand = { Add = function (name, fn) commands [name] = fn end }
	_G.hook = { Add = function (event, id, fn) hooks [event .. " " .. id] = fn end }
	_G.player_manager =
	{
		TranslateToPlayerModelName = function () return "kleiner" end,
		TranslatePlayerHands = function () return { model = HANDS_MODEL, skin = 0, body = "0000000" } end
	}
	-- a rebuild includes the pure modules again: the reader stays the fake handing out skeletons
	_G.include = function (path)
		if path == "tf_weapons/mdl.lua" then return FakeMdl end
		return dofile ("addons/tf_weapons/lua/" .. path)
	end
	_G.EF_BONEMERGE, _G.RENDERGROUP_VIEWMODEL = 1, 2
	_G.MATERIAL_CULLMODE_CCW, _G.MATERIAL_CULLMODE_CW = 0, 1
	-- the pure modules on the real code; the reader handed the fixture's skeletons by path
	_G.TFWeapons =
	{
		Rig = Rig,
		Mdl = FakeMdl,
		Activities = dofile ("addons/tf_weapons/lua/tf_weapons/activities.lua")
	}
	dofile ("addons/tf_weapons/lua/tf_weapons/cl_hands.lua")
end

Install ()
local Hands = TFWeapons.Hands

local function Viewmodel (frame)
	local vm = Entity (ARMS_MODEL)
	vm.valid = true
	function vm:SetupBones () self.setups = self.setups + 1 end
	function vm:GetBoneMatrix (i) return MatrixOf (frame.arms [i + 1]) end
	return vm
end

local function Player (handsModel)
	local stock = Entity (handsModel or HANDS_MODEL)
	function stock:GetSkin () return 1 end
	function stock:GetNumBodyGroups () return 0 end
	local ply = { valid = true }
	function ply:GetHands () return stock end
	function ply:GetModel () return "models/player/kleiner.mdl" end
	function ply:GetActiveWeapon () return self.weapon end
	return ply
end

local function Weapon ()
	return { valid = true, TFModel = GUN_MODEL, GetClass = function () return "tf_weapon_scattergun" end }
end

local function HandsMade ()
	for i = #made, 1, -1 do
		if made [i].model == HANDS_MODEL and made [i].valid then return made [i] end
	end
end

T.test ("the hands drawn carry the bones the oracle solves, in the engine's matrices", function ()
	for _, frame in ipairs (FIXTURE.frames) do
		Hands.Release ()
		local vm, ply, weapon = Viewmodel (frame), Player (), Weapon ()
		Hands.PreDraw (weapon, vm)
		T.eq (render.blend, 0, "the class arms hidden")
		Hands.Draw (weapon, vm, ply)
		T.eq (render.blend, 1, "the blend given back")
		local hands = HandsMade ()
		T.eq (hands.drawn, 1, "drawn once")
		for j, expected in ipairs (frame.hands) do
			local e = hands.set [j - 1]
			local what = frame.label .. "@" .. frame.frame .. " " .. FIXTURE.hands.bones [j] [1]
			T.near (e [4],  expected [1], POSITION_EPSILON, what .. " x")
			T.near (e [8],  expected [2], POSITION_EPSILON, what .. " y")
			T.near (e [12], expected [3], POSITION_EPSILON, what .. " z")
			local qx, qy, qz, qw = Rig.QuatFromMatrix (e [1], e [2], e [3], e [5], e [6], e [7], e [9], e [10], e [11])
			local dot = qx * expected [4] + qy * expected [5] + qz * expected [6] + qw * expected [7]
			T.near (math.abs (dot), 1, ROTATION_EPSILON, what)
		end
	end
end)

T.test ("the gun rides the viewmodel by bone merge, and the hands look like the player's", function ()
	Hands.Release ()
	local vm, ply, weapon = Viewmodel (FIXTURE.frames [1]), Player (), Weapon ()
	Hands.Draw (weapon, vm, ply)
	local state = Hands.state
	T.eq (state.gun.model,                   GUN_MODEL,    "the c_model")
	T.eq (state.gun.parent,                  vm,           "on the viewmodel")
	T.eq (state.gun.effects,                 EF_BONEMERGE, "bone-merged")
	T.eq (state.gun.drawn,                   1,            "drawn")
	T.eq (state.hands.skin,                  1,            "the stock hands' skin")
	T.eq (type (state.hands.GetPlayerColor), "function",   "the player's colour for the PlayerColor proxy")
end)

T.test ("the models are made once and kept frame to frame", function ()
	Hands.Release ()
	local vm, ply, weapon = Viewmodel (FIXTURE.frames [1]), Player (), Weapon ()
	local before = #made
	for _ = 1, 3 do Hands.Draw (weapon, vm, ply) end
	T.eq (#made - before,          2, "the hands and the gun, once")
	T.eq (Hands.state.hands.drawn, 3, "drawn each frame")
end)

T.test ("other hands, another weapon or a rebuild remake the models", function ()
	Hands.Release ()
	local vm, ply, weapon = Viewmodel (FIXTURE.frames [1]), Player (), Weapon ()
	Hands.Draw (weapon, vm, ply)
	local first = Hands.state.hands
	Hands.Draw (Weapon (), vm, ply)
	T.eq (first.valid, false, "another weapon: the old hands removed")
	local second = Hands.state.hands
	commands.tf_weapons_rebuild ()
	T.eq (second.valid, false, "a rebuild removes them at once")
	T.eq (Hands.state,  nil,   "and remakes them on the next frame")
	Hands.Draw (weapon, vm, ply)
	T.eq (Hands.state.hands.valid, true, "remade")
end)

T.test ("a model the reader cannot read is said once, and the class arms are left showing", function ()
	Hands.Release ()
	local vm, ply, weapon = Viewmodel (FIXTURE.frames [1]), Player ("models/weapons/c_arms_missing.mdl"), Weapon ()
	local said = #printed
	Hands.Draw (weapon, vm, ply)
	Hands.Draw (weapon, vm, ply)
	T.eq (Hands.state,                                                nil,  "nothing built")
	T.eq (#printed - said,                                            1,    "said once")
	T.eq (printed [#printed]:find ("c_arms_missing", 1, true) ~= nil, true, "naming the model")
	render.blend = nil
	Hands.PreDraw (weapon, vm)
	T.eq (render.blend, nil, "the class arms not hidden")
end)

T.test ("putting the weapon away lets the models go", function ()
	Hands.Release ()
	local vm, ply, weapon = Viewmodel (FIXTURE.frames [1]), Player (), Weapon ()
	_G.LocalPlayer = function () return ply end
	ply.weapon = weapon
	Hands.Draw (weapon, vm, ply)
	local think = hooks ["Think moonexpr/tf-weapons/release-models"]
	think ()
	T.eq (Hands.state ~= nil, true, "kept while held")
	ply.weapon = Weapon ()
	think ()
	T.eq (Hands.state, nil, "let go")
end)

T.test ("loading the driver again keeps what it holds", function ()
	Hands.Release ()
	local vm, ply, weapon = Viewmodel (FIXTURE.frames [1]), Player (), Weapon ()
	Hands.Draw (weapon, vm, ply)
	local state = Hands.state
	dofile ("addons/tf_weapons/lua/tf_weapons/cl_hands.lua")
	T.eq (TFWeapons.Hands.state, state, "the state survives an autorefresh")
	T.eq (TFWeapons.Hands,       Hands, "one table")
end)

T.finish ()
