-- The dev workbench's diff of two captured states (sandcastle_dev_diff):
-- every path where they differ, as text an agent can read.
local T = dofile("tests/harness.lua")
local Diff = T.require("sandcastle_dev_diff")

T.test("equal trees have no differences", function()
	T.eq(#Diff.Of({ a = 1, b = { c = "x" } }, { a = 1, b = { c = "x" } }), 0, "none")
end)

T.test("each difference names its path and both values", function()
	local list = Diff.Of({ a = 1, b = { c = "x", d = true } }, { a = 2, b = { c = "x" } })
	T.eq(#list, 2, "two")
	T.eq(list[1].path, "a", "sorted by path")
	T.eq(list[1].a, 1, "the first's value")
	T.eq(list[1].b, 2, "the second's value")
	T.eq(list[2].path, "b.d", "a key only in the first")
	T.eq(list[2].b, nil, "absent in the second")
end)

T.test("numbers within the tolerance are equal", function()
	T.eq(#Diff.Of({ t = 1.0 }, { t = 1.0 + 1e-9 }, 1e-6), 0, "within")
	T.eq(#Diff.Of({ t = 1.0 }, { t = 1.01 }, 1e-6), 1, "beyond")
end)

T.test("a table against a value is one difference at that path", function()
	local list = Diff.Of({ a = { b = 1 } }, { a = 5 })
	T.eq(#list, 1, "one")
	T.eq(list[1].path, "a", "at a")
end)

T.test("ignored paths are left out, a * matching any one key", function()
	local list = Diff.Of({ meta = { at = 1 }, p = { x = { pos = 1, hp = 1 } } }, { meta = { at = 2 }, p = { x = { pos = 2, hp = 2 } } }, 0, { "meta", "p.*.pos" })
	T.eq(#list, 1, "only hp")
	T.eq(list[1].path, "p.x.hp", "hp")
end)

T.test("Text renders differences one a line", function()
	local text = Diff.Text(Diff.Of({ a = 1 }, { a = 2 }))
	T.eq(text, "a: 1 -> 2", "text")
end)

T.finish()
