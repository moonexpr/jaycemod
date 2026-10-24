-- An ordered map of number keys on an AVL tree: inserted, found and removed
-- in O(log n). This is the Lua twin; a server with native/foundation has it
-- replaced in place by the native tree, which runs this algorithm node for
-- node (so heights agree too).
--   Avl() (New()) -> an empty tree
--   tree:Insert(key, value) (a key inserted again takes the new value),
--   tree:Get(key), tree:Remove(key) -> whether it was there, tree:Size(),
--   tree:Min(), tree:Max(), tree:Floor(key), tree:Ceiling(key) -> the
--   nearest key at or below, at or above (and its value), or nil,
--   tree:Pairs() -> an iterator in order (key, value), not to be run across
--   a change to the tree, tree:Height()
local max, setmetatable = math.max, setmetatable
module(...)

local Tree = {}
Tree.__index = Tree

function New()
	return setmetatable({
		root = nil,
		size = 0,
	}, Tree)
end

setmetatable(_M, { __call = function() return New() end })

local function HeightOf(node)
	return node and node.height or 0
end

local function Update(node)
	node.height = max(HeightOf(node.left), HeightOf(node.right)) + 1
end

local function RotateRight(node)
	local left = node.left
	node.left, left.right = left.right, node
	Update(node)
	Update(left)
	return left
end

local function RotateLeft(node)
	local right = node.right
	node.right, right.left = right.left, node
	Update(node)
	Update(right)
	return right
end

local function Balance(node)
	Update(node)
	local skew = HeightOf(node.left) - HeightOf(node.right)
	if skew > 1 then
		if HeightOf(node.left.left) < HeightOf(node.left.right) then node.left = RotateLeft(node.left) end
		return RotateRight(node)
	end
	if skew < -1 then
		if HeightOf(node.right.right) < HeightOf(node.right.left) then node.right = RotateRight(node.right) end
		return RotateLeft(node)
	end
	return node
end

-- Returns the subtree with key set, and whether the key is new.
local function Insert(node, key, value)
	if not node then
		return {
			key = key,
			value = value,
			height = 1,
		}, true
	end
	local added
	if key < node.key then
		node.left, added = Insert(node.left, key, value)
	elseif node.key < key then
		node.right, added = Insert(node.right, key, value)
	else
		node.value = value
		return node, false
	end
	return Balance(node), added
end

local function RemoveMin(node)
	if not node.left then return node.right end
	node.left = RemoveMin(node.left)
	return Balance(node)
end

local function MinNode(node)
	while node.left do node = node.left end
	return node
end

-- Returns the subtree without key, and whether it was there.
local function Remove(node, key)
	if not node then return nil, false end
	local removed
	if key < node.key then
		node.left, removed = Remove(node.left, key)
	elseif node.key < key then
		node.right, removed = Remove(node.right, key)
	else
		if not node.left then return node.right, true end
		if not node.right then return node.left, true end
		local successor = MinNode(node.right)
		successor.right = RemoveMin(node.right)
		successor.left = node.left
		return Balance(successor), true
	end
	return Balance(node), removed
end

function Tree:Insert(key, value)
	local added
	self.root, added = Insert(self.root, key, value)
	if added then self.size = self.size + 1 end
end

function Tree:Remove(key)
	local removed
	self.root, removed = Remove(self.root, key)
	if removed then self.size = self.size - 1 end
	return removed
end

function Tree:Get(key)
	local node = self.root
	while node do
		if key < node.key then
			node = node.left
		elseif node.key < key then
			node = node.right
		else
			return node.value
		end
	end
	return nil
end

function Tree:Size()
	return self.size
end

function Tree:Height()
	return HeightOf(self.root)
end

function Tree:Min()
	if not self.root then return nil end
	local node = MinNode(self.root)
	return node.key, node.value
end

function Tree:Max()
	local node = self.root
	if not node then return nil end
	while node.right do node = node.right end
	return node.key, node.value
end

function Tree:Floor(key)
	local node, best = self.root, nil
	while node do
		if key < node.key then
			node = node.left
		else
			best = node
			if not (node.key < key) then break end
			node = node.right
		end
	end
	if best then return best.key, best.value end
	return nil
end

function Tree:Ceiling(key)
	local node, best = self.root, nil
	while node do
		if node.key < key then
			node = node.right
		else
			best = node
			if not (key < node.key) then break end
			node = node.left
		end
	end
	if best then return best.key, best.value end
	return nil
end

function Tree:Pairs()
	local stack, node = {}, self.root
	return function()
		while node do
			stack[#stack + 1] = node
			node = node.left
		end
		local top = stack[#stack]
		if not top then return nil end
		stack[#stack] = nil
		node = top.right
		return top.key, top.value
	end
end
