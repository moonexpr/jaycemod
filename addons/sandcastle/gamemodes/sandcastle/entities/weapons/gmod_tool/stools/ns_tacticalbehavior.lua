AddCSLuaFile()

-- The war's own soldiers, in the running AI war, under the war's own orders, with their feet
-- held: each one's path to the target its orders give it is planned and drawn, not walked. The
-- tool sets the conditions: who is in the squad, its job, whether it takes lanes and missions,
-- a contact, a recall. The AI war's overlay (ws_aiwar_debug) tells what each is doing.
TOOL.Category = "NextSoldier"
TOOL.Name = "#tool.ns_tacticalbehavior.name"
TOOL.Command = nil
TOOL.ConfigName = ""
TOOL.ClientConVar = {
	hold = "1",
	lanes = "1",
	missions = "1",
}

TOOL.Information = {
	{ name = "left" },
	{ name = "right" },
	{ name = "reload" },
}

-- The jobs a squad may be given; the war refuses one its scenario has not.
local JOBS = {
	"push", "escort", "block", "defend", "raid", "support", "capture", "assault", "hold", "explore",
	"courier", "ctf_defend", "operative",
}

if CLIENT then
	language.Add("tool.ns_tacticalbehavior.name", "Tactical Behavior Tool")
	language.Add("tool.ns_tacticalbehavior.desc", "Hold the war's soldiers in place and see where its orders send them")
	language.Add("tool.ns_tacticalbehavior.left", "Draft a soldier of your team here, or add/remove a soldier of the war from your selection")
	language.Add("tool.ns_tacticalbehavior.right", "Report an enemy contact here to the selected soldiers' squads")
	language.Add("tool.ns_tacticalbehavior.reload", "Release your selection: drafted soldiers are dismissed, others walk again")

	local TARGET_COLOR, SELECTED_COLOR = Color(255, 220, 60), Color(90, 220, 255)
	local CROSS_SIZE, SELECTED_RADIUS, RING_STEPS = 16, 22, 32

	hook.Add("PostDrawTranslucentRenderables", "ns_tacticalbehavior", function(_, sky)
		if sky then return end
		for _, ent in ipairs(ents.GetAll()) do
			if ent:GetNW2Bool("NSFeetHeld", false) then
				local at = ent:GetNW2Vector("NSHeldTarget", vector_origin)
				if at ~= vector_origin then
					render.DrawLine(at - Vector(CROSS_SIZE, 0, 0), at + Vector(CROSS_SIZE, 0, 0), TARGET_COLOR)
					render.DrawLine(at - Vector(0, CROSS_SIZE, 0), at + Vector(0, CROSS_SIZE, 0), TARGET_COLOR)
					render.DrawLine(at, at + Vector(0, 0, CROSS_SIZE * 2), TARGET_COLOR)
				end
			end
			if ent:GetNW2Bool("NSTacticalSelected", false) then
				local feet, last = ent:GetPos() + Vector(0, 0, 3), nil
				for i = 0, RING_STEPS do
					local angle = i / RING_STEPS * 2 * math.pi
					local point = feet + Vector(math.cos(angle) * SELECTED_RADIUS, math.sin(angle) * SELECTED_RADIUS, 0)
					if last then render.DrawLine(last, point, SELECTED_COLOR) end
					last = point
				end
			end
		end
	end)
end

local selections = setmetatable({}, { __mode = "k" })

local function Selection(ply)
	local selected = selections[ply]
	if not selected then
		selected = { soldiers = {}, drafted = {}, applied = {} }
		selections[ply] = selected
	end
	return selected
end

-- The war's controller while a war runs, else nil and the player told.
local function War(ply)
	local controller = WS.Feature("aiwar")
	if controller and controller.war then return controller end
	ply:ChatPrint("[Tactical Behavior] No AI war is running: start one first (mp_aiwar_start).")
	return nil
end

-- The selected soldiers still in the war, in the order they were picked.
local function Soldiers(ply, controller)
	local selected = Selection(ply)
	local list = {}
	for i = #selected.soldiers, 1, -1 do
		local ent = selected.soldiers[i]
		if not (IsValid(ent) and controller.soldiers[ent]) then table.remove(selected.soldiers, i) end
	end
	for i, ent in ipairs(selected.soldiers) do list[i] = ent end
	return list
end

-- Their squads, each once.
local function FireTeams(controller, soldiers)
	local seen, list = {}, {}
	for _, ent in ipairs(soldiers) do
		local member = controller.war:Member(ent)
		local fireTeam = member and member.fireTeam
		if fireTeam and not seen[fireTeam] then seen[fireTeam], list[#list + 1] = true, fireTeam end
	end
	return list
end

local function Select(ply, ent, on)
	local selected = Selection(ply)
	for i, other in ipairs(selected.soldiers) do
		if other == ent then table.remove(selected.soldiers, i) break end
	end
	if on then selected.soldiers[#selected.soldiers + 1] = ent end
	ent:SetNW2Bool("NSTacticalSelected", on)
	if ent.NSHoldFeet then ent:NSHoldFeet(on and ply:GetInfoNum("ns_tacticalbehavior_hold", 1) ~= 0) end
end

local function Tell(ply, lines)
	for _, line in ipairs(lines or {}) do ply:ChatPrint("[Tactical Behavior] " .. line) end
end

function TOOL:LeftClick(trace)
	if CLIENT then return true end
	local ply = self:GetOwner()
	if not IsValid(ply) then return false end
	local controller = War(ply)
	if not controller then return false end

	local hit = trace.Entity
	if IsValid(hit) and controller.soldiers[hit] then
		local selected = Selection(ply)
		local on = not hit:GetNW2Bool("NSTacticalSelected", false)
		Select(ply, hit, on)
		if not on and selected.drafted[hit] then selected.drafted[hit] = nil end
		return true
	end
	if not trace.Hit or trace.HitSky then return false end
	local team = WS.TeamOf(ply)
	if team ~= WS.TEAM_RED and team ~= WS.TEAM_BLUE then
		ply:ChatPrint("[Tactical Behavior] Join RED or BLU first: soldiers are drafted to your team.")
		return false
	end
	local ent = controller:Draft(team, trace.HitPos, Angle(0, ply:EyeAngles().y, 0))
	if not IsValid(ent) then
		ply:ChatPrint("[Tactical Behavior] The war could not draft a soldier here.")
		return false
	end
	Selection(ply).drafted[ent] = true
	Select(ply, ent, true)
	return true
end

function TOOL:RightClick(trace)
	if CLIENT then return true end
	local ply = self:GetOwner()
	if not IsValid(ply) or not trace.Hit or trace.HitSky then return false end
	local controller = War(ply)
	if not controller then return false end
	local fireTeams = FireTeams(controller, Soldiers(ply, controller))
	if #fireTeams == 0 then
		ply:ChatPrint("[Tactical Behavior] Select soldiers in a squad first.")
		return false
	end
	local at = trace.HitPos
	for _, fireTeam in ipairs(fireTeams) do
		wartactics.fireteam.Report(fireTeam, { x = at.x, y = at.y, z = at.z }, CurTime())
	end
	return true
end

function TOOL:Reload()
	if CLIENT then return true end
	local ply = self:GetOwner()
	if not IsValid(ply) then return false end
	local controller = WS.Feature("aiwar")
	local selected = Selection(ply)
	for _, ent in ipairs(selected.soldiers) do
		if IsValid(ent) then
			Select(ply, ent, false)
			if selected.drafted[ent] then
				if controller and controller.soldiers[ent] then controller:Discharge(ent) end
				ent:Remove()
			end
		end
	end
	selections[ply] = nil
	return true
end

-- The boxes reach the selected soldiers and their squads as they change.
function TOOL:Think()
	if CLIENT then return end
	local ply = self:GetOwner()
	local selected = selections[ply]
	local controller = WS.Feature("aiwar")
	if not (selected and controller and controller.war) then return end
	local hold = self:GetClientNumber("hold") ~= 0
	local lanesOff, missionsOff = self:GetClientNumber("lanes") == 0, self:GetClientNumber("missions") == 0
	local applied = selected.applied
	local changed = applied.hold ~= hold or applied.lanesOff ~= lanesOff or applied.missionsOff ~= missionsOff
	local soldiers = Soldiers(ply, controller)
	if not changed and applied.count == #soldiers then return end
	for _, ent in ipairs(soldiers) do
		if ent.NSHoldFeet then ent:NSHoldFeet(hold) end
	end
	for _, fireTeam in ipairs(FireTeams(controller, soldiers)) do
		fireTeam.lanesOff, fireTeam.missionsOff = lanesOff or nil, missionsOff or nil
	end
	applied.hold, applied.lanesOff, applied.missionsOff, applied.count = hold, lanesOff, missionsOff, #soldiers
end

if SERVER then
	-- A console command on the player's selection: fn(ply, controller, soldiers, args) -> lines.
	local function SelectionCommand(name, fn, help)
		concommand.Add(name, function(ply, _, args)
			if not IsValid(ply) or not ply:IsSuperAdmin() then return end
			local controller = War(ply)
			if not controller then return end
			local soldiers = Soldiers(ply, controller)
			if #soldiers == 0 then
				ply:ChatPrint("[Tactical Behavior] Select soldiers with the tool first.")
				return
			end
			Tell(ply, fn(ply, controller, soldiers, args))
			-- the boxes are applied again to what changed
			Selection(ply).applied = {}
		end, nil, help)
	end

	local function Indexes(soldiers)
		local list = {}
		for i, ent in ipairs(soldiers) do list[i] = ent:EntIndex() end
		return list
	end

	SelectionCommand("ns_tacticalbehavior_squad", function(_, controller, soldiers)
		return controller:FormSquadOf(Indexes(soldiers))
	end, "Form the Tactical Behavior Tool's selection into one squad, the first picked leading")

	SelectionCommand("ns_tacticalbehavior_job", function(_, controller, soldiers, args)
		if args[1] == "war" then return controller:ReleaseJob(Indexes(soldiers)) end
		return controller:AssignJob(string.lower(args[1] or ""), Indexes(soldiers))
	end, "Give the Tactical Behavior Tool's selection a job (war: the war's own again)")

	SelectionCommand("ns_tacticalbehavior_recall", function(_, controller, soldiers)
		local lines = {}
		for _, fireTeam in ipairs(FireTeams(controller, soldiers)) do
			wartactics.mission.Recall(fireTeam, wartactics.mission.CASUALTIES)
			lines[#lines + 1] = "a squad was recalled to regroup"
		end
		return lines
	end, "Recall the selection's squads to regroup, as heavy casualties do")
end

function TOOL.BuildCPanel(panel)
	panel:Help("The war's own soldiers under its own orders, held in place: a yellow cross is where its orders send each one, and its path there is drawn. Left-click drafts a soldier of your team or selects one of the war's (a cyan ring); right-click reports an enemy contact at the aim to their squads; reload releases them.")
	panel:CheckBox("Hold their feet (uncheck: they walk)", "ns_tacticalbehavior_hold")
	panel:CheckBox("Lanes (uncheck: their squads go straight)", "ns_tacticalbehavior_lanes")
	panel:CheckBox("Missions (uncheck: their squads ask for none)", "ns_tacticalbehavior_missions")
	panel:Button("Form one squad of the selection", "ns_tacticalbehavior_squad")
	local jobs = panel:ComboBox("Job")
	jobs:AddChoice("the war's own", "war")
	for _, job in ipairs(JOBS) do jobs:AddChoice(job, job) end
	function jobs:OnSelect(_, _, job) RunConsoleCommand("ns_tacticalbehavior_job", job) end
	panel:Button("Recall their squads to regroup", "ns_tacticalbehavior_recall")
	panel:Button("Toggle the AI war's overlay", "ws_aiwar_debug")
end
