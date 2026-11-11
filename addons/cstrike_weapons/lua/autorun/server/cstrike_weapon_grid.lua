if not SERVER then return end

local CATEGORY = "Counter-Strike: Source"
local COLUMNS, SPACING, FORWARD_DISTANCE = 7, 110, 420

concommand.Add ("cstrike_weapon_grid", function (ply)
	if not IsValid (ply) or not ply:IsPlayer () then
		print ("Run cstrike_weapon_grid from an in-game admin console.")
		return
	end
	if not ply:IsAdmin () then
		ply:PrintMessage (HUD_PRINTCONSOLE, "cstrike_weapon_grid is admin-only.")
		return
	end

	local classes = {}
	for _, definition in ipairs (weapons.GetList ()) do
		if definition.CStrikeWeapon and definition.Spawnable and definition.Category == CATEGORY then
			classes [#classes + 1] = definition.ClassName
		end
	end
	table.sort (classes)
	if #classes == 0 then
		ply:PrintMessage (HUD_PRINTCONSOLE, "No spawnable CS:S weapons are registered; check that cstrike_weapons is mounted.")
		return
	end

	local yaw = ply:EyeAngles ().y
	local facing = Angle (0, yaw, 0)
	local forward, right = facing:Forward (), facing:Right ()
	local rows = math.ceil (#classes / COLUMNS)
	local center = ply:GetPos () + forward * FORWARD_DISTANCE
	local spawned, failed = 0, {}

	for index, class in ipairs (classes) do
		local column = (index - 1) % COLUMNS
		local row = math.floor ((index - 1) / COLUMNS)
		local target = center
			+ right * ((column - (COLUMNS - 1) / 2) * SPACING)
			+ forward * ((row - (rows - 1) / 2) * SPACING)
		local trace = util.TraceLine (
			{
				start = target + Vector (0, 0, 512),
				endpos = target - Vector (0, 0, 4096),
				mask = MASK_SOLID_BRUSHONLY
			}
		)
		if not trace.Hit or trace.HitSky then
			failed [#failed + 1] = class .. " (no ground)"
		else
			local weapon = ents.Create (class)
			if not IsValid (weapon) then
				failed [#failed + 1] = class .. " (creation failed)"
			else
				weapon:SetPos (trace.HitPos)
				weapon:SetAngles (Angle (0, yaw, 0))
				weapon:Spawn ()
				if IsValid (weapon) then
					local mins = weapon:OBBMins ()
					weapon:SetPos (trace.HitPos + Vector (0, 0, math.max (1, -mins.z)))
					local physics = weapon:GetPhysicsObject ()
					if IsValid (physics) then physics:EnableMotion (false) end
					spawned = spawned + 1
				else
					failed [#failed + 1] = class .. " (spawn failed)"
				end
			end
		end
	end

	ply:PrintMessage (HUD_PRINTCONSOLE, "Spawned " .. spawned .. " CS:S weapons in a ground-traced grid.")
	if #failed > 0 then
		ply:PrintMessage (HUD_PRINTCONSOLE, "Skipped: " .. table.concat (failed, ", "))
	end
end, nil, "Spawn all registered CS:S weapons in a ground-traced grid.")
