-- The dev workbench's ULX commands, in both realms (ULX loads lua/ulx/modules/sh/ there):
--
--   ulx thirdperson (!thirdperson), ulx firstperson (!firstperson): the caller's view from behind
--   them, to see their own model; anyone may.
--   ulx give <players> <class> (!give): a weapon to each player, admins only; completes the
--   spawn menu's weapons.
local THIRD_PERSON = "sandcastle_dev_thirdperson" -- on a player: whether their view is third person

-- The view from behind: this far back, this far to the right, a hull this big kept off walls.
local VIEW_BACK, VIEW_RIGHT, VIEW_HULL = 100, 20, 4

local thirdperson = ulx.command (
	"Utility",
	"ulx thirdperson",
	function (caller, off)
		caller:SetNW2Bool (THIRD_PERSON, not off)
		ULib.tsay (caller, "Third person " .. (off and "off" or "on") .. ".")
	end,
	"!thirdperson",
	true
)
thirdperson:addParam ({ type = ULib.cmds.BoolArg, invisible = true })
thirdperson:defaultAccess (ULib.ACCESS_ALL)
thirdperson:help ("See yourself from behind.")
thirdperson:setOpposite ("ulx firstperson", { nil, true }, "!firstperson", true)

-- The weapons the spawn menu lists, by class: what give completes. Filled again once every
-- weapon is registered, the list being ULib's own.
local weaponClasses = {}

local function ListWeapons ()
	table.Empty (weaponClasses)
	for class in pairs (list.Get ("Weapon")) do weaponClasses [#weaponClasses + 1] = class end
	table.sort (weaponClasses)
end

ListWeapons ()
hook.Add ("InitPostEntity", "sandcastle_dev_give", ListWeapons)

local give = ulx.command (
	"Utility",
	"ulx give",
	function (caller, targets, class)
		local given = {}
		for _, target in ipairs (targets) do
			if IsValid (target:Give (class)) or target:HasWeapon (class) then given [#given + 1] = target end
		end

		if #given == 0 then
			ULib.tsayError (caller, "No one was given " .. class .. ": is it a weapon?", true)
			return
		end

		ulx.fancyLogAdmin (caller, "#A gave #T " .. class, given)
	end,
	"!give"
)
give:addParam ({ type = ULib.cmds.PlayersArg })
give:addParam ({ type = ULib.cmds.StringArg, hint = "weapon class", completes = weaponClasses })
give:defaultAccess (ULib.ACCESS_ADMIN)
give:help ("Give players a weapon.")

if CLIENT then
	hook.Add ("ShouldDrawLocalPlayer", THIRD_PERSON, function (ply)
		if ply:GetNW2Bool (THIRD_PERSON) then return true end
	end)

	hook.Add ("CalcView", THIRD_PERSON, function (ply, origin, angles, fov)
		if not ply:GetNW2Bool (THIRD_PERSON) or not ply:Alive () then return end

		local hull = Vector (VIEW_HULL, VIEW_HULL, VIEW_HULL)
		local tr   = util.TraceHull (
			{
				start  = origin,
				endpos = origin - angles:Forward () * VIEW_BACK + angles:Right () * VIEW_RIGHT,
				mins   = -hull,
				maxs   = hull,
				filter = ply
			}
		)

		return { origin = tr.HitPos, angles = angles, fov = fov, drawviewer = true }
	end)
end
