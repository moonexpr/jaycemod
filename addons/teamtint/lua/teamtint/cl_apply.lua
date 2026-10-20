-- Team Tint on bodies: each NPC, NextBot and ragdoll (and anything the tool
-- painted) wears, in place of each material the catalog themes, its
-- team's copy (SetSubMaterial on this client only: a name the server set
-- could arrive before the client had made the material). A sweep keeps it
-- so: a team given or changed, a model swapped (an AI war kit), a full
-- update that reset the sub-materials.
local Resolve = TeamTint.Resolve

-- How often the sweep looks at every body.
local SWEEP_SECONDS = 0.5

local function Candidate(ent)
	if ent:IsPlayer() or ent:IsWeapon() then return false end
	return ent:IsNPC() or ent:IsNextBot() or ent:IsRagdoll() or ent.TeamTintGiven ~= nil
		or ent:GetNW2Int(TeamTint.NW, Resolve.NO_OVERRIDE) ~= Resolve.NO_OVERRIDE
end

-- What decides ent's team: { override, given, team }.
function TeamTint.Says(ent)
	return {
		override = TeamTint.Override(ent),
		given = ent.TeamTintGiven,
		team = hook.Run("TeamTintTeamOf", ent),
	}
end

local function Representation(ent)
	if not TeamTint.ENABLED:GetBool() then return Resolve.ORIGINAL end
	return Resolve.Representation(TeamTint.Says(ent))
end

local function Reset(ent)
	if ent.TeamTintApplied then ent:SetSubMaterial() end
	ent.TeamTintApplied = nil
	ent.TeamTintReport = nil
end

-- Puts on ent the materials of its representation; a report of what each
-- material became, for the overlay.
function TeamTint.Apply(ent)
	local rep = Representation(ent)
	local bench = TeamTint.BENCH:GetBool()
	local model = ent:GetModel() or ""
	local key = rep .. "|" .. model .. (bench and "|ss" or "")
	local applied = ent.TeamTintApplied
	-- unchanged, and its first themed material still on it (a full update clears them)
	if ent.TeamTintKey == key and (not applied or ent:GetSubMaterial(applied.index) == applied.name) then return end
	Reset(ent)
	ent.TeamTintKey = key
	if rep == Resolve.ORIGINAL then return end
	local report = { rep = rep, source = Resolve.Source(TeamTint.Says(ent)), materials = {} }
	for i, path in ipairs(ent:GetMaterials()) do
		local entry = TeamTint.Material(rep, path, bench)
		report.materials[i] = { path = path, entry = entry, rule = TeamTint.Catalog.Classify(path) }
		if entry then
			ent:SetSubMaterial(i - 1, "!" .. entry.name)
			ent.TeamTintApplied = ent.TeamTintApplied or { index = i - 1, name = "!" .. entry.name }
		end
	end
	ent.TeamTintReport = report
end

-- Every body looked at again (the bench or the switch changed).
function TeamTint.Refresh()
	for _, ent in ipairs(ents.GetAll()) do
		if IsValid(ent) and Candidate(ent) then
			ent.TeamTintKey = nil
			TeamTint.Apply(ent)
		end
	end
end

-- A team given in code, as Sandcastle gives a death ragdoll its body's.
function TeamTint.Give(ent, rep)
	ent.TeamTintGiven = rep
	ent.TeamTintKey = nil
	TeamTint.Apply(ent)
end

-- A ragdoll shows what its body showed.
function TeamTint.CopyTo(body, ragdoll)
	if not (IsValid(body) and IsValid(ragdoll)) then return end
	local rep = Resolve.Representation(TeamTint.Says(body))
	if rep ~= Resolve.ORIGINAL then TeamTint.Give(ragdoll, rep) end
end

hook.Add("CreateClientsideRagdoll", "teamtint", function(owner, ragdoll) TeamTint.CopyTo(owner, ragdoll) end)

-- The override arrives before GetNW2Int returns it: look the next tick.
hook.Add("EntityNetworkedVarChanged", "teamtint", function(ent, name)
	if name ~= TeamTint.NW then return end
	timer.Simple(0, function()
		if IsValid(ent) then
			ent.TeamTintKey = nil
			TeamTint.Apply(ent)
		end
	end)
end)

timer.Create("teamtint_sweep", SWEEP_SECONDS, 0, function()
	for _, ent in ipairs(ents.GetAll()) do
		if IsValid(ent) and not ent:IsDormant() and Candidate(ent) then TeamTint.Apply(ent) end
	end
end)

cvars.AddChangeCallback("teamtint_enable", function() TeamTint.Refresh() end, "teamtint_apply")
cvars.AddChangeCallback("teamtint_bench_softwareskin", function() TeamTint.Refresh() end, "teamtint_apply")
