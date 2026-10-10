-- The map's Halloween is on and its Halloween entities bind: the
-- tf_logic_holiday made the holiday feature's Halloween active; each
-- Halloween class the BSP places (not counting boss templates) has a Lua
-- entity (a stub only where args.stubs says so) and live entities; every
-- NPC among them is bound to the npc controller.
-- Gift spawn locations hand their origin to the holiday controller and
-- remove themselves, so they are counted there; classes in args.engine are
-- the engine's own (no Lua entity expected).
-- args: { holiday = the map's holiday_type, classes = { [class] = count placed in the BSP },
--         stubs = { class... },
--         engine = { class... } }
local STUB_BASE = "ws_stub_point"
local GIFT_LOCATION = "tf_halloween_gift_spawn_location"

return function(t)
	local holiday = t:Feature("holiday")
	t:Check("the holiday feature is loaded", holiday ~= nil, table.concat(WS.FeatureLoader:Loaded(), ", "))
	if holiday then
		local Holiday = WS.require("foundation.holiday")
		local wanted = t.args.holiday or Holiday.HALLOWEEN
		t:Check("the holiday the map's tf_logic_holiday names (" .. wanted .. ") is active", holiday:HolidayActive(wanted), "")
		t:Info("halloween_active", holiday:HolidayActive(Holiday.HALLOWEEN))
		t:Info("holiday_mode", holiday.mode and holiday.mode.HOLIDAY or "none")
		t:Info("spells_on", holiday.holiday:UsingSpells() and true or false)
	end

	local stubs, engine = {}, {}
	for _, class in ipairs(t.args.stubs or {}) do stubs[class] = true end
	for _, class in ipairs(t.args.engine or {}) do engine[class] = true end
	local npc = t:Feature("npc")
	local counts = {}
	for class, placed in SortedPairs(t.args.classes or {}) do
		local live = ents.FindByClass(class)
		local stored = scripted_ents.GetStored(class) ~= nil
		local isStub = stored and scripted_ents.IsBasedOn(class, STUB_BASE)
		counts[class] = string.format("placed %d, live %d%s%s", placed, #live, stored and "" or ", no Lua entity",
			isStub and ", stub" or "")
		if not engine[class] then
			t:Check(class .. " has a Lua entity", stored, counts[class])
			t:Check(class .. (stubs[class] and " is a stub, as expected" or " is not a stub"),
				isStub == (stubs[class] == true), counts[class])
		end
		if class == GIFT_LOCATION then
			local handed = holiday and #holiday.giftLocations or 0
			counts[class] = counts[class] .. ", " .. handed .. " handed to the holiday controller"
			t:Check("every gift spawn location reached the holiday controller", handed == placed, counts[class])
		else
			t:Check(class .. " entities exist on the map", #live > 0, counts[class])
		end
		local unbound = 0
		for _, ent in ipairs(live) do
			if ent.Variant and ent:IsNextBot() and not (npc and npc.npcs[ent]) then unbound = unbound + 1 end
		end
		if unbound > 0 then t:Check(class .. " NPCs are bound", false, unbound .. " unbound") end
	end
	t:Info("entities", counts)
end
