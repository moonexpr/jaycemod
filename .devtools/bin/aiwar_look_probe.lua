-- What each part of a war bot's look costs (features/aiwar/sv_bots.lua's Controller:Look), for a
-- window and then put back, run through dt lua:
--
--   dt lua -f .devtools/bin/aiwar_look_probe.lua    defines LookProbe
--   dt lua 'return LookProbe.Start(15)'             its look swapped for a timed copy for 15 s
--   dt lua 'return LookProbe.Report()'              each part's ms/s and µs a look
--   dt lua 'return LookProbe.Ablate(8)'             each part left out for 8 s in turn
--   dt lua 'return LookProbe.Ablations()'           what a look costs the calendar without each
--
-- Timing between lines charges a part with whatever ran in it (a collector's step); an ablation
-- reads only the calendar's own measure of its looks, so the difference is what the part costs.
-- A part left out leaves its bots without it meanwhile (blind, standing, not firing).
--
-- The copy is the look as written; keep it in step with Controller:Look. WarProbe
-- (aiwar_tick_probe.lua) times the methods; this times the lines between them.
LookProbe = LookProbe or {}
local P = LookProbe
local SysTime = SysTime

local function Upvalues (fn)
	local found, i = {}, 1
	while true do
		local name, value = debug.getupvalue (fn, i)
		if not name then break end
		found [name] = value
		i = i + 1
	end
	return found
end

local PARTS = { "none", "steer", "vision", "pick", "area", "ammo", "feel", "orders" }

-- skip: the part left out, or nil for none.
local function Look (Controller, skip, Add)
	local u = Upvalues (Controller.Look)
	local NpcSystem, Arms, HL2Path, DriveOrders = u.NpcSystem, u.Arms, u.HL2Path, u.DriveOrders
	local AMMO_FLOOR, AMMO_RESERVE = u.AMMO_FLOOR, u.AMMO_RESERVE
	return function (self, ply, entry, now)
		local soldier = entry.soldier
		local t = SysTime ()
		if skip ~= "steer" then soldier:Steer (now) end
		t = Add ("steer", t)
		if skip ~= "vision" then soldier.vision:Look () end
		t = Add ("vision", t)
		self:TellSight (ply, entry, soldier.vision:Events ())
		t = Add ("events", t)
		local contact = soldier:Enemy ()
		soldier.mayFire = contact ~= nil and not soldier.disarmed
			and entry.npc:Query ("ShouldAttack", contact) ~= NpcSystem.ANSWER_NO
		t = Add ("query", t)
		if skip ~= "area" then
			local area = navmesh.GetNavArea (ply:GetPos (), HL2Path.LIMITS.stepHeight * 2)
			if area ~= soldier.navArea then
				entry.npc:Event ("OnNavAreaChanged", soldier.navArea, area)
				soldier.navArea = area
				local attributes = IsValid (area) and area:GetAttributes () or 0
				soldier.crouchArea = HL2Path.MustCrouch (attributes)
				soldier.jumpArea = bit.band (attributes, HL2Path.NAV_MESH_JUMP) ~= 0
			end
		end
		t = Add ("area", t)
		if skip ~= "pick" then self:Arm (ply, soldier, contact) end
		t = Add ("pick", t)
		if skip ~= "ammo" then
			for _, weapon in ipairs (ply:GetWeapons ()) do
				local ammo = weapon:GetPrimaryAmmoType ()
				if ammo >= 0 and ply:GetAmmoCount (ammo) < AMMO_FLOOR then ply:GiveAmmo (AMMO_RESERVE, ammo, true) end
			end
		end
		t = Add ("ammo", t)
		if soldier.driven then soldier.heading = DriveOrders.Heading (ply:GetPos (), self:Sent (soldier, now)) end
		if skip ~= "feel" then self:FeelAhead (ply, soldier) end
		t = Add ("feel", t)
		if soldier.driven and skip ~= "orders" then self:SendOrders (ply, entry, now) end
		Add ("orders", t)
	end
end

local function Controller () return Upvalues (hook.GetTable ().Think.ws_aiwar_bots).Controller end

local function Untimed (_, t) return t end

-- Each part left out for seconds in turn ("none" first and last, the baseline), the calendar's
-- looks read over each.
function P.Ablate (seconds)
	if P.running then return "running" end
	local controller = Controller ()
	local calendar, original = controller.calendar, controller.Look
	local order = table.Copy (PARTS)
	order [#order + 1] = "none"
	P.ablations, P.running = {}, true
	local step = 0
	local function Next ()
		if step > 0 then
			local looks = calendar:Report (true).looks
			P.ablations [#P.ablations + 1] = { part = order [step], runs = looks.runs, spent = looks.spent }
		end
		step = step + 1
		if step > #order then
			controller.Look = original
			P.running = false
			return
		end
		controller.Look = Look (controller, order [step] ~= "none" and order [step] or nil, Untimed)
		calendar:Report (true)
		timer.Simple (seconds, Next)
	end
	Next ()
	return string.format ("%d parts, %d s each", #order, seconds)
end

function P.Ablations ()
	if P.running then return "measuring" end
	if not P.ablations then return "nothing measured" end
	local lines, base, n = {}, 0, 0
	for _, a in ipairs (P.ablations) do
		if a.part == "none" then base, n = base + a.spent / a.runs, n + 1 end
	end
	base = base / n
	for _, a in ipairs (P.ablations) do
		local each = a.spent / a.runs
		lines [#lines + 1] = string.format ("%-7s %5d looks %7.1f us a look, %+7.1f us against the baseline", a.part,
			a.runs, each * 1e6, (base - each) * 1e6)
	end
	return table.concat (lines, "\n")
end

function P.Start (seconds)
	if P.running then return "running" end
	local Controller = Controller ()
	local spent = {}
	local function Add (part, from)
		local now = SysTime ()
		spent [part] = (spent [part] or 0) + now - from
		return now
	end
	P.spent, P.looks, P.seconds, P.original, P.running = spent, 0, seconds, Controller.Look, true
	local look = Look (Controller, nil, Add)
	Controller.Look = function (self, ply, entry, now)
		P.looks = P.looks + 1
		look (self, ply, entry, now)
	end
	timer.Simple (seconds, function ()
		Controller.Look = P.original
		P.running = false
	end)
	return "measuring " .. seconds .. " s"
end

function P.Report ()
	if P.running then return "measuring" end
	if not P.spent then return "nothing measured" end
	local lines, total = {}, 0
	for _, seconds in pairs (P.spent) do total = total + seconds end
	for part, seconds in SortedPairsByValue (P.spent, true) do
		lines [#lines + 1] = string.format ("%-7s %6.1f ms/s %7.1f us", part, seconds * 1000 / P.seconds, seconds * 1e6 / P.looks)
	end
	lines [#lines + 1] = string.format ("total   %6.1f ms/s %7.1f us  %d looks", total * 1000 / P.seconds,
		total * 1e6 / P.looks, P.looks)
	return table.concat (lines, "\n")
end
