-- foundation.world.bucket: a token bucket, for limiting how often something
-- may happen: `capacity` at most, refilled at capacity per `seconds`.
local T = dofile("tests/harness.lua")
local Bucket = world.bucket

T.test("a bucket starts full and gives its capacity at once, then refuses", function()
	local bucket = Bucket.New(3, 1, 10)
	T.eq(bucket:Take(10), true, "first")
	T.eq(bucket:Take(10), true, "second")
	T.eq(bucket:Take(10), true, "third")
	T.eq(bucket:Take(10), false, "the fourth is refused")
end)

T.test("it refills at capacity per seconds, a token a take", function()
	local bucket = Bucket.New(3, 1, 0)
	for _ = 1, 3 do bucket:Take(0) end
	T.eq(bucket:Take(0.2), false, "0.6 of a token is not one")
	T.eq(bucket:Take(0.4), true, "1.2 tokens: one spent")
	T.eq(bucket:Take(0.4), false, "0.2 left")
	T.near(bucket:Tokens(0.4), 0.2, 1e-9, "as it should be")
end)

T.test("it never holds more than its capacity, however long it sat", function()
	local bucket = Bucket.New(2, 10, 0)
	T.eq(bucket:Tokens(1000), 2, "full, no more")
	T.eq(bucket:Take(1000), true, "one")
	T.eq(bucket:Take(1000), true, "two")
	T.eq(bucket:Take(1000), false, "no third")
end)

T.test("a refusal spends nothing, and asking how many spends nothing", function()
	local bucket = Bucket.New(1, 4, 0)
	T.eq(bucket:Take(0), true, "the one")
	T.eq(bucket:Take(1), false, "a quarter")
	T.eq(bucket:Take(2), false, "a half")
	T.near(bucket:Tokens(2), 0.5, 1e-9, "still counting up")
	T.near(bucket:Tokens(2), 0.5, 1e-9, "asking changes nothing")
	T.eq(bucket:Take(4), true, "a whole one at last")
end)

T.test("a bucket is made with a capacity of at least 1 and seconds above 0", function()
	T.eq(pcall(Bucket.New, 0, 1, 0), false, "no capacity")
	T.eq(pcall(Bucket.New, 3, 0, 0), false, "no time")
	T.eq(pcall(Bucket.New, "3", 1, 0), false, "a string")
	T.eq(pcall(Bucket.New, 3, 1), false, "no start time")
end)

T.finish()
