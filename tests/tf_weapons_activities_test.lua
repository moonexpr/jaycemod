-- tf_weapons (addons/tf_weapons): a viewmodel's sequences found by the activity names its model
-- gives them, as the Scout's arms name the Scattergun's (docs/tf2-hands-spike.md).
local T = dofile ("tests/harness.lua")
local Activities = dofile ("addons/tf_weapons/lua/tf_weapons/activities.lua")

-- An entity answering for its sequences: { activity name, activity id }s numbered from 0, and the
-- weighted pick the engine makes, here the first sequence of an activity
local function Viewmodel (model, sequences)
	local ent, asked = {}, 0
	function ent:GetModel () return model end
	function ent:GetSequenceCount ()
		asked = asked + 1
		return #sequences
	end
	function ent:GetSequenceActivityName (i) return sequences [i + 1] [1] end
	function ent:GetSequenceActivity (i) return sequences [i + 1] [2] end
	function ent:SelectWeightedSequence (id)
		for i, s in ipairs (sequences) do
			if s [2] == id then return i - 1 end
		end
		return -1
	end
	function ent:Asked () return asked end
	return ent
end

local SCOUT =
{
	{ "", -1 },
	{ "ACT_PRIMARY_VM_DRAW", 2001 },
	{ "ACT_PRIMARY_VM_IDLE", 2002 },
	{ "ACT_BALL_VM_CATCH", 2003 },
	{ "ACT_BALL_VM_CATCH", 2003 }
}

T.test ("a sequence is found by its activity's name", function ()
	Activities.Forget ()
	local vm = Viewmodel ("models/weapons/c_models/c_scout_arms.mdl", SCOUT)
	T.eq (Activities.Sequence (vm, "ACT_PRIMARY_VM_DRAW"), 1, "draw")
	T.eq (Activities.Sequence (vm, "ACT_PRIMARY_VM_IDLE"), 2, "idle")
	T.eq (Activities.Sequence (vm, "ACT_BALL_VM_CATCH"),   3, "the engine picks among several")
end)

T.test ("an activity the model has not is no sequence", function ()
	Activities.Forget ()
	local vm = Viewmodel ("models/weapons/c_models/c_scout_arms.mdl", SCOUT)
	T.eq (Activities.Sequence (vm, "ACT_VM_DRAW"), nil, "GMod's own name")
	T.eq (Activities.Sequence (vm, ""),            nil, "a sequence with no activity")
end)

T.test ("a model's names are read once, until forgotten", function ()
	Activities.Forget ()
	local vm = Viewmodel ("models/weapons/c_models/c_scout_arms.mdl", SCOUT)
	Activities.Sequence (vm, "ACT_PRIMARY_VM_DRAW")
	Activities.Sequence (vm, "ACT_PRIMARY_VM_IDLE")
	T.eq (vm:Asked (), 1, "once")
	Activities.Forget ()
	Activities.Sequence (vm, "ACT_PRIMARY_VM_DRAW")
	T.eq (vm:Asked (), 2, "again after Forget")
end)

T.test ("each model is read for itself", function ()
	Activities.Forget ()
	local scout = Viewmodel ("models/weapons/c_models/c_scout_arms.mdl", SCOUT)
	local soldier = Viewmodel ("models/weapons/c_models/c_soldier_arms.mdl", { { "ACT_PRIMARY_VM_DRAW", 3001 } })
	T.eq (Activities.Sequence (scout, "ACT_PRIMARY_VM_DRAW"),   1, "the scout's")
	T.eq (Activities.Sequence (soldier, "ACT_PRIMARY_VM_DRAW"), 0, "the soldier's")
end)

T.finish ()
