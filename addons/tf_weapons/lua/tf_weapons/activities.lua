-- A viewmodel's sequences by the activity names its model gives them. TF2's arms name theirs
-- ACT_PRIMARY_VM_DRAW and the like, which GMod may know by other ids or not at all, so a SWEP asks
-- by name: the entity reports each sequence's activity name and id, and its own weighted pick does
-- the rest.
local Activities = {}

local ACT_NONE = -1

-- model -> activity name -> activity id, read once a model
local byModel = {}

function Activities.Of (ent)
	local model = ent:GetModel ()
	local names = byModel [model]
	if names then return names end

	names = {}
	for sequence = 0, ent:GetSequenceCount () - 1 do
		local id = ent:GetSequenceActivity (sequence)
		local name = ent:GetSequenceActivityName (sequence)
		if id ~= ACT_NONE and names [name] == nil then names [name] = id end
	end
	byModel [model] = names
	return names
end

-- A sequence playing the named activity, the model's weights choosing among several; nil if none
function Activities.Sequence (ent, name)
	local id = Activities.Of (ent) [name]
	if id == nil then return nil end
	local sequence = ent:SelectWeightedSequence (id)
	if sequence < 0 then return nil end

	return sequence
end

function Activities.Forget ()
	byModel = {}
end

return Activities
