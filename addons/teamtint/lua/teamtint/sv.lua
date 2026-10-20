-- Team Tint's server half: the override a player sets on a body (the tool,
-- teamtint_paint), kept through the duplicator, and the A/B pair the tool
-- spawns beside a body for comparing RED and BLU.
local Resolve = TeamTint.Resolve

-- Whether ply may set an override on ent: false only when a
-- TeamTintCanOverride hook says so (a gamemode where it would show a
-- false team in a live match); the tool's own prop protection ran first.
function TeamTint.CanOverride(ply, ent)
	return hook.Run("TeamTintCanOverride", ply, ent) ~= false
end

-- rep: teamtint_resolve's RED, BLU, ORIGINAL, or nil to clear.
function TeamTint.SetOverride(ent, rep)
	ent:SetNW2Int(TeamTint.NW, Resolve.ToNetwork(rep))
	if rep then
		duplicator.StoreEntityModifier(ent, "teamtint", { rep = rep })
	else
		duplicator.ClearEntityModifier(ent, "teamtint")
	end
end

duplicator.RegisterEntityModifier("teamtint", function(_, ent, data)
	if IsValid(ent) and istable(data) then TeamTint.SetOverride(ent, Resolve.FromNetwork(Resolve.ToNetwork(data.rep))) end
end)

-- The pair stands this far to each side of the body, facing as it does.
local PAIR_SPACING = 48
-- A player model's idle, else the model's first sequence.
local PAIR_SEQUENCES = { "idle_all_01", "idle_passive", "idle" }

local function PairCopy(ply, ent, rep, offset)
	local copy = ents.Create("prop_dynamic")
	if not IsValid(copy) then return nil end
	copy:SetModel(ent:GetModel())
	copy:SetPos(ent:GetPos() + ent:GetRight() * offset)
	copy:SetAngles(Angle(0, ent:GetAngles().y, 0))
	copy:SetSkin(ent:GetSkin())
	for _, group in ipairs(ent:GetBodyGroups()) do copy:SetBodygroup(group.id, ent:GetBodygroup(group.id)) end
	copy:Spawn()
	copy:SetSolid(SOLID_BBOX)
	copy:SetCollisionBounds(ent:OBBMins(), ent:OBBMaxs())
	for _, name in ipairs(PAIR_SEQUENCES) do
		local seq = copy:LookupSequence(name)
		if seq and seq >= 0 then
			copy:ResetSequence(seq)
			break
		end
	end
	TeamTint.SetOverride(copy, rep)
	if IsValid(ply) then ply:AddCleanup("teamtint", copy) end
	return copy
end

-- A RED copy to ent's left and a BLU one to its right, posed and frozen,
-- undone together.
function TeamTint.SpawnPair(ply, ent)
	local red = PairCopy(ply, ent, Resolve.RED, -PAIR_SPACING)
	local blu = PairCopy(ply, ent, Resolve.BLU, PAIR_SPACING)
	undo.Create("Team Tint pair")
	if red then undo.AddEntity(red) end
	if blu then undo.AddEntity(blu) end
	undo.SetPlayer(ply)
	undo.Finish()
end

-- teamtint_paint red|blu|original|clear: the tool's override on the body
-- the player looks at, for modes that give no toolgun; admins only.
local PAINT = { red = Resolve.RED, blu = Resolve.BLU, original = Resolve.ORIGINAL, clear = false }

concommand.Add("teamtint_paint", function(ply, _, args)
	if not IsValid(ply) or not ply:IsAdmin() then return end
	local rep = PAINT[string.lower(args[1] or "")]
	if rep == nil then
		ply:ChatPrint("teamtint_paint red|blu|original|clear")
		return
	end
	local ent = ply:GetEyeTrace().Entity
	if not IsValid(ent) or ent:IsPlayer() or not TeamTint.CanOverride(ply, ent) then return end
	TeamTint.SetOverride(ent, rep or nil)
end, nil, "Team Tint: set (or clear) the team the body you look at shows: red, blu, original or clear")
