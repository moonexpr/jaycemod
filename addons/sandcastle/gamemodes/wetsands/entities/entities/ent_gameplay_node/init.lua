AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")
include("shared.lua")

-- GMod clears the global once the file has run.
local ENT = ENT

local Model = WS.require("features.builder.model")

local CLASS = Model.CLASSES[Model.NODE]
local NEAREST_RANGE_SQR = 256 * 256
local MIN_NODES = 2

local function InOrder()
	local nodes = ents.FindByClass(CLASS)
	table.sort(nodes, function(a, b) return a:Id() < b:Id() end)
	return nodes
end

-- Each node knows the next, for the rails drawn along the track.
function ENT.Link()
	local nodes = InOrder()
	for i, node in ipairs(nodes) do node:SetNextNode(nodes[i + 1] or NULL) end
end

-- It stands in a game, in nobody's way.
function ENT:SetInGame(on)
	self:SetNotSolid(on)
end

-- The first brings the cart, and is called for it.
function ENT:OnPlaced(ply)
	ENT.Link()
	if #ents.FindByClass(CLASS) > 1 then return end
	self.broughtCart = true
	return WS.Feature("builder"):Create(ply, Model.CART, self:GetPos(), Angle(0, ply:EyeAngles().y, 0))
end

function ENT:UndoLabel()
	return self.broughtCart and "Trolley" or self.PrintName
end

-- The Trolley tool's right click: a control point on the node clicked or the
-- nearest, which makes it a checkpoint; again takes it off.
function ENT.ToggleHelper(ply, trace)
	local builder = WS.Feature("builder")
	local node, nearest = builder:PieceOf(trace, Model.NODE), NEAREST_RANGE_SQR
	if not node then
		for _, candidate in ipairs(ents.FindByClass(CLASS)) do
			local dist = candidate:GetPos():DistToSqr(trace.HitPos)
			if dist < nearest then node, nearest = candidate, dist end
		end
	end
	if not node then
		ply:ChatPrint("[Gameplay] No track node near there.")
		return false
	end
	if IsValid(node.helper) then
		node.helper:Remove()
		node.helper = nil
		return true
	end
	local helper = builder:Create(ply, Model.POINT, node:GetPos(), angle_zero, nil, { DefaultOwner = Model.CHECKPOINT_OWNER })
	helper:SetNodeId(node:Id())
	helper.nodeEnt = node
	node.helper = helper
	node:DeleteOnRemove(helper)
	return builder:Undoable(ply, "Checkpoint", helper)
end

-- The Trolley tool's reload: the tail goes, its helper with it; with the last
-- node, the cart.
function ENT.RemoveTail(ply)
	local nodes = InOrder()
	local tail = nodes[#nodes]
	if not tail then return false end
	tail:Remove()
	if #nodes == 1 then
		for _, cart in ipairs(ents.FindByClass(Model.CLASSES[Model.CART])) do cart:Remove() end
	else
		nodes[#nodes - 1]:SetNextNode(NULL)
	end
	return true
end

function ENT:Flags()
	local flags = 0
	for _, prop in ipairs(self.Properties) do
		if prop.flag and self["Get" .. prop.name](self) then flags = flags + prop.flag end
	end
	return flags
end

-- The nodes in order with their checkpoints: those with a control point helper,
-- and the goal, which is always one. Their points take the order of the track.
function ENT.CompileAll(nodes, game)
	local cart = game.by[Model.CART][1]
	if #nodes < MIN_NODES or not cart then return end
	local pusher = cart:GetTeamNum()
	local checkpoints, pointOf = {}, {}
	for i, node in ipairs(nodes) do
		local helper = game.helperOf[node:Id()]
		if helper or i == #nodes then
			checkpoints[#checkpoints + 1] = node
			pointOf[node] = helper and helper:CompiledName() or Model.PartName(node:Id(), "cp")
		end
	end
	local nextOf = {}
	for i, node in ipairs(checkpoints) do nextOf[node] = checkpoints[i + 1] and pointOf[checkpoints[i + 1]] end
	for i, node in ipairs(nodes) do
		local outputs
		if pointOf[node] then
			outputs = { Model.OnPass(pointOf[node], "SetOwner", pusher) }
			if nextOf[node] then outputs[2] = Model.OnPass(Model.CART_AREA_NAME, "SetControlPoint", nextOf[node]) end
		end
		local keys = node:Keys()
		keys.target = nodes[i + 1] and nodes[i + 1]:CompiledName() or nil
		keys.spawnflags = tostring(node:Flags())
		game:Add({ class = "path_track", name = node:CompiledName(), pos = node:GetPos(), keys = keys, outputs = outputs })
	end
	for i, node in ipairs(checkpoints) do
		local before = checkpoints[i - 1] and pointOf[checkpoints[i - 1]]
		local helper = game.helperOf[node:Id()]
		local keys = helper and helper:PointKeys("Checkpoint " .. i)
			or { point_default_owner = tostring(Model.EnemyOf(pusher)), point_printname = "Checkpoint " .. i }
		Model.ControlPoint(game, pointOf[node], node:GetPos(), i - 1, keys, before, { pusher })
		Model.PointPlate(game, helper and helper:Id() or node:Id(), node:GetPos())
	end
	game.pointIndex = #checkpoints
	game.track = { nodes = nodes, checkpoints = checkpoints, pointOf = pointOf, pusher = pusher }
end
