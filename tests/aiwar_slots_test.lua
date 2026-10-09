-- foundation.aiwar.slots: the places each faction keeps for the soldiers the
-- war drafts, which set its size, and the leadership pinned to them.
local T = dofile("tests/harness.lua")
local Slots = T.require("foundation.aiwar.slots")
local Teams = T.require("foundation.teams")

local COMBINE, RESISTANCE = "Combine", "Resistance"

local function Ids(slots)
	local ids = {}
	for i, slot in ipairs(slots) do ids[i] = slot.id end
	return table.concat(ids, " ")
end

T.test("a faction grows to the team size with unpinned slots, each with its own id", function()
	local plan = Slots.New()
	T.eq(#plan:Resize(COMBINE, 3), 0, "nobody dropped")
	T.eq(plan:Size(COMBINE), 3, "three slots")
	T.eq(plan:Size(RESISTANCE), 0, "the other faction untouched")
	plan:Resize(RESISTANCE, 2)
	T.eq(Ids(plan:Slots(COMBINE)) .. " | " .. Ids(plan:Slots(RESISTANCE)), "1 2 3 | 4 5", "ids across factions")
	T.eq(plan:Slots(COMBINE)[1].pin, nil, "unpinned")
end)

T.test("shrinking drops empty slots from the end first, then held ones, and names the soldiers dropped", function()
	local plan = Slots.New()
	plan:Resize(COMBINE, 4)
	plan:Fill(COMBINE, "a")
	plan:Fill(COMBINE, "b")
	plan:Fill(COMBINE, "c")
	T.eq(#plan:Resize(COMBINE, 3), 0, "the empty fourth goes, nobody with it")
	T.eq(Ids(plan:Slots(COMBINE)), "1 2 3", "the first three kept")
	local dropped = plan:Resize(COMBINE, 1)
	T.eq(table.concat(dropped, " "), "c b", "the newest held slots go, their soldiers named")
	T.eq(plan:Slots(COMBINE)[1].holder, "a", "the first soldier keeps its slot")
end)

T.test("a soldier fills the first free slot of its faction, and frees it when it goes", function()
	local plan = Slots.New()
	plan:Resize(COMBINE, 2)
	T.eq(plan:Fill(COMBINE, "a").id, 1, "the first")
	T.eq(plan:Fill(COMBINE, "b").id, 2, "the second")
	T.eq(plan:Fill(COMBINE, "c"), nil, "none free")
	T.eq(plan:Vacate("a").id, 1, "freed")
	T.eq(plan:Fill(COMBINE, "d").id, 1, "taken again")
	T.eq(plan:Vacate("nobody"), nil, "a soldier in no slot")
	T.eq(plan:SlotOf("d").id, 1, "found by its soldier")
end)

T.test("slots are added, removed and pinned by id; an unknown id changes nothing", function()
	local plan = Slots.New()
	plan:Resize(COMBINE, 2)
	local added = plan:Add(RESISTANCE)
	T.eq(added.id, 3, "a fresh id")
	T.eq(plan:Size(RESISTANCE), 1, "one Resistance slot")
	plan:Fill(COMBINE, "a")
	local removed = plan:Remove(1)
	T.eq(removed.holder, "a", "the removed slot's soldier, for the controller to remove")
	T.eq(Ids(plan:Slots(COMBINE)), "2", "one left")
	T.eq(plan:Remove(99), nil, "unknown")
	T.eq(plan:Pin(2, Slots.LEADER).pin, Slots.LEADER, "pinned to lead")
	T.eq(plan:Pin(2, nil).pin, nil, "unpinned")
	T.eq(plan:Pin(99, Slots.MEMBER), nil, "unknown")
	T.eq(plan:FactionOf(3), RESISTANCE, "a slot's faction")
end)

T.test("a resize keeps the pins of the slots that stay", function()
	local plan = Slots.New()
	plan:Resize(COMBINE, 2)
	plan:Pin(1, Slots.LEADER)
	plan:Resize(COMBINE, 5)
	plan:Resize(COMBINE, 1)
	T.eq(plan:Slots(COMBINE)[1].pin, Slots.LEADER, "kept")
end)

T.test("a plan is saved as each faction's pins in order, without its soldiers, and loaded back", function()
	local plan = Slots.New()
	plan:Resize(COMBINE, 3)
	plan:Pin(1, Slots.LEADER)
	plan:Pin(3, Slots.MEMBER)
	plan:Fill(COMBINE, "a")
	local saved = plan:Saved()
	T.eq(table.concat(saved[COMBINE], " "), "leader none member", "pins")
	T.eq(saved[RESISTANCE], nil, "a faction never sized is not saved")
	local loaded = Slots.Load(saved)
	T.eq(loaded:Size(COMBINE), 3, "three slots")
	T.eq(loaded:Slots(COMBINE)[1].pin, Slots.LEADER, "pinned")
	T.eq(loaded:Slots(COMBINE)[1].holder, nil, "empty")
	T.eq(loaded:Add(COMBINE).id, 4, "ids go on after the loaded ones")
end)

T.test("a saved plan that is not one is refused, with why", function()
	local plan, why = Slots.Load({ [COMBINE] = { "leader", "captain" } })
	T.eq(plan, nil, "refused")
	T.eq(why, "Combine's slot 2: 'captain' is not leader, member or none", "why")
	T.eq(select(2, Slots.Load({ [COMBINE] = "leader" })), "Combine: not a list of pins", "not a list")
	T.eq(select(2, Slots.Load("nonsense")), "not a table of factions", "not a table")
end)

T.test("commands name a team as RED or BLU, and slots by their ids", function()
	T.eq(Slots.ParseTeam("red"), Teams.RED, "RED")
	T.eq(Slots.ParseTeam("BLU"), Teams.BLUE, "BLU")
	T.eq(Slots.ParseTeam("green"), nil, "no team")
	T.eq(table.concat(Slots.ParseIds({ "3", "7" }), " "), "3 7", "ids")
	T.eq(select(2, Slots.ParseIds({ "3", "x" })), "x", "the token that is no id")
	T.eq(select(2, Slots.ParseIds({ "0" })), "0", "ids start at 1")
	T.eq(select(2, Slots.ParseIds({})), "", "no ids at all")
end)

T.test("the slot list's tree: squads in the order first met, each with its leader first, then the slots in no squad", function()
	local tree = Slots.Tree({
		{ id = 1, squad = "defend 1", leads = false },
		{ id = 2, squad = "", leads = false },
		{ id = 3, squad = "defend 1", leads = true },
		{ id = 4, squad = "raid 1", leads = true },
		{ id = 5, squad = "defend 1", leads = false },
	})
	T.eq(#tree.squads, 2, "two squads")
	T.eq(tree.squads[1].name .. ": " .. Ids(tree.squads[1].slots), "defend 1: 3 1 5", "the leader, then by slot")
	T.eq(tree.squads[2].name .. ": " .. Ids(tree.squads[2].slots), "raid 1: 4", "the second squad")
	T.eq(Ids(tree.loose), "2", "in no squad")
end)

T.finish()
