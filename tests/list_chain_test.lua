-- foundation.list.chain: whole numbers in an order, linked by arrays.
local T = dofile("tests/harness.lua")
local Chain = list.chain

local function Joined(chain) return table.concat(chain:Ordered(), " ") end

T.test("a chain keeps its members front to back", function()
	local chain = Chain.New()
	T.eq(chain:Front(), nil, "empty: no front")
	T.eq(chain:Back(), nil, "empty: no back")
	chain:PushFront(2)
	chain:PushFront(1)
	chain:PushBack(3)
	T.eq(Joined(chain), "1 2 3", "in order")
	T.eq(chain:Front(), 1, "front")
	T.eq(chain:Back(), 3, "back")
	T.eq(chain:Size(), 3, "three")
	T.eq(chain:After(1), 2, "after the front")
	T.eq(chain:After(3), nil, "nothing after the back")
	T.eq(chain:Before(3), 2, "before the back")
	T.eq(chain:Before(1), nil, "nothing before the front")
end)

T.test("a member unlinks from anywhere and can be linked again", function()
	local chain = Chain.New()
	for i = 1, 4 do chain:PushBack(i) end
	chain:Unlink(2)
	T.eq(Joined(chain), "1 3 4", "middle")
	chain:Unlink(1)
	chain:Unlink(4)
	T.eq(Joined(chain), "3", "both ends")
	T.eq(chain:Has(2), false, "gone")
	chain:PushBack(2)
	T.eq(Joined(chain), "3 2", "back in")
end)

T.test("MoveFront brings a member to the front", function()
	local chain = Chain.New()
	for i = 1, 3 do chain:PushBack(i) end
	chain:MoveFront(3)
	T.eq(Joined(chain), "3 1 2", "from the back")
	chain:MoveFront(3)
	T.eq(Joined(chain), "3 1 2", "already there")
	chain:MoveFront(1)
	T.eq(Joined(chain), "1 3 2", "from the middle")
end)

T.test("a member is linked once, and only a member unlinks", function()
	local chain = Chain.New()
	chain:PushBack(1)
	T.eq(pcall(chain.PushBack, chain, 1), false, "linked twice")
	T.eq(pcall(chain.Unlink, chain, 2), false, "not a member")
	T.eq(pcall(chain.PushBack, chain, 0), false, "not a slot")
end)

T.test("Clear empties the chain", function()
	local chain = Chain.New()
	chain:PushBack(1)
	chain:PushBack(2)
	chain:Clear()
	T.eq(chain:Size(), 0, "empty")
	T.eq(chain:Has(1), false, "no members")
	chain:PushBack(1)
	T.eq(Joined(chain), "1", "usable again")
end)

T.test("calling a chain walks it front to back", function()
	local chain = Chain.New()
	for i = 1, 3 do chain:PushBack(i) end
	local seen = {}
	for slot in chain() do seen[#seen + 1] = slot end
	T.eq(table.concat(seen, " "), "1 2 3", "in order")
	T.eq(getmetatable(chain).__len(chain), 3, "__len is Size")
	T.eq(tostring(chain), "chain: 1 2 3", "its members")
end)

T.finish()
