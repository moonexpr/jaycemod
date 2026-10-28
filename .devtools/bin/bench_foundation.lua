-- Bench of the foundation modules the hand-rolled-code epic (#12) built,
-- each against the code it replaced, copied here as it was.
--   luajit .devtools/bin/bench_foundation.lua              the Lua twins
--   WS_NATIVE=1 luajit .devtools/bin/bench_foundation.lua  the native twins
-- from the repo root. Prints the best of five runs, in ns an operation. The
-- JIT is on (LuaJIT's default); a server's numbers differ (docs/ns-performance-baseline.md, H12).
-- On the dedicated server: `dt lua --file .devtools/bin/bench_foundation.lua`
-- (the globals are there already; BENCH_SCALE, a global, shortens the runs).
local harness = io and io.open and io.open("tests/harness.lua")
if harness then
	harness:close()
	dofile("tests/harness.lua")
end

local clock = SysTime or os.clock
local scale = BENCH_SCALE or 1
local mode = (debug.getinfo(list.select.Lowest, "S").what == "C") and "native" or "lua"
local lines = {}

local seed = 987654321
local function Random(n)
	seed = (seed * 1103515245 + 12345) % 2147483648
	return seed % n
end

local function Time(name, fn, iterations)
	for _ = 1, 3 do fn() end
	collectgarbage()
	iterations = math.max(1, math.floor(iterations * scale))
	local best = math.huge
	for _ = 1, 5 do
		local t0 = clock()
		for _ = 1, iterations do fn() end
		local per = (clock() - t0) / iterations * 1e9
		if per < best then best = per end
	end
	local line = string.format("%-6s %-44s %11.1f", mode, name, best)
	lines[#lines + 1] = line
	print(line)
end

local function Points(n, span)
	local points = {}
	for i = 1, n do points[i] = { x = Random(span), y = Random(span), z = Random(200) } end
	return points
end

local Distance = math.geometry.Distance
local Select, Grid = list.select, world.grid

-- Nearest ---------------------------------------------------------------------
local function OldNearest(points, here)
	local best, bestDistance
	for _, p in ipairs(points) do
		local d = Distance(p, here)
		if not bestDistance or d < bestDistance then best, bestDistance = p, d end
	end
	return best
end

for _, n in ipairs({ 16, 128, 2000 }) do
	local points, here = Points(n, 8000), { x = 4000, y = 4000, z = 50 }
	local iterations = n >= 2000 and 400 or 20000
	Time("Nearest n=" .. n .. " old loop", function() return OldNearest(points, here) end, iterations)
	Time("Nearest n=" .. n .. " Select.Nearest", function() return Select.Nearest(points, here) end, iterations)
end

-- Lowest with a score function --------------------------------------------------
do
	local items = {}
	for i = 1, 128 do items[i] = { dist = Random(5000), alive = Random(4) > 0 } end
	local function OldLowest()
		local best, bestDist
		for i, c in ipairs(items) do
			if c.alive and (not bestDist or c.dist < bestDist) then best, bestDist = i, c.dist end
		end
		return best
	end
	local function Dist(c) return c.dist end
	local function Alive(c) return c.alive end
	Time("Lowest n=128 old loop", OldLowest, 20000)
	Time("Lowest n=128 Select.Lowest", function() return Select.Lowest(items, Dist, Alive) end, 20000)
end

-- TopK, Order ---------------------------------------------------------------------
do
	local items = {}
	for i = 1, 1000 do items[i] = { score = Random(100000) } end
	local function After(a, b) return a.score > b.score end
	Time("top 5 of 1000 old sort+take", function()
		local sorted = {}
		for i, c in ipairs(items) do sorted[i] = c end
		table.sort(sorted, After)
		return sorted[5]
	end, 300)
	Time("top 5 of 1000 Select.TopK", function() return Select.TopK(items, 5, After) end, 300)
	local small = {}
	for i = 1, 200 do small[i] = { score = Random(100000) } end
	Time("order 200 old sort of places", function()
		local order = {}
		for i = 1, #small do order[i] = i end
		table.sort(order, function(a, b)
			if small[a].score ~= small[b].score then return small[a].score > small[b].score end
			return a < b
		end)
		return order
	end, 1000)
	Time("order 200 Select.Order", function() return Select.Order(small, After) end, 1000)
end

-- Spread, Isolated ----------------------------------------------------------------
do
	local candidates = Points(300, 3000)
	local spacing, limit = 200, 24
	local function OldSpread(points, count)
		local picked = {}
		for _, p in ipairs(points) do
			if #picked >= count then break end
			local free = true
			for _, q in ipairs(picked) do
				if Distance(p, q) < spacing then free = false break end
			end
			if free then picked[#picked + 1] = p end
		end
		return picked
	end
	Time("spread 300 pts, 24 posts old loop", function() return OldSpread(candidates, limit) end, 2000)
	Time("spread 300 pts, 24 posts Grid.Spread", function() return Grid.Spread(candidates, spacing, limit) end, 2000)
	local many = Points(2000, 12000)
	Time("spread 2000 pts, unlimited old loop", function() return OldSpread(many, math.huge) end, 30)
	Time("spread 2000 pts, unlimited Grid.Spread", function() return Grid.Spread(many, spacing) end, 30)
	local areas = Points(150, 4000)
	Time("isolated 150 old pairwise loop", function()
		local kept = {}
		for i, a in ipairs(areas) do
			local near = false
			for j = 1, i - 1 do
				if Distance(a, areas[j]) < spacing then near = true break end
			end
			if not near then kept[#kept + 1] = a end
		end
		return kept
	end, 2000)
	Time("isolated 150 Grid.Isolated", function() return Grid.Isolated(areas, spacing) end, 2000)
end

-- Window (the bosses' damage per second) -----------------------------------------------
do
	local span, dt = 5, 1 / 60
	local old = { samples = {} }
	local window = list.window.New(span)
	local now = 0
	for _ = 1, 300 do
		now = now + dt
		old.samples[#old.samples + 1] = { damage = 1, at = now }
		window:Add(now, 1)
	end
	Time("dps window 300 live, old rebuild a tick", function()
		now = now + dt
		old.samples[#old.samples + 1] = { damage = 1, at = now }
		local kept, total = {}, 0
		for _, s in ipairs(old.samples) do
			if now - s.at <= span then
				kept[#kept + 1] = s
				total = total + s.damage
			end
		end
		old.samples = kept
		return total / span
	end, 20000)
	Time("dps window 300 live, list.window", function()
		now = now + dt
		window:Add(now, 1)
		return window:Sum(now) / span
	end, 20000)
end

-- Bucket -----------------------------------------------------------------------------
do
	local allowance, now = { tokens = 5, at = 0 }, 0
	local bucket = world.bucket.New(5, 1, 0)
	Time("rate limit old table arithmetic", function()
		now = now + 0.25
		allowance.tokens = math.min(5, allowance.tokens + (now - allowance.at) * 5 / 1)
		allowance.at = now
		if allowance.tokens < 1 then return false end
		allowance.tokens = allowance.tokens - 1
		return true
	end, 200000)
	Time("rate limit world.bucket Take", function()
		now = now + 0.25
		return bucket:Take(now)
	end, 200000)
end

-- Pair sets ---------------------------------------------------------------------------
do
	local ids = {}
	for i = 1, 512 do ids[i] = Random(20000) end
	Time("seen-pair set old 'min:max' strings", function()
		local seen = {}
		for i = 1, 511 do
			local a, b = ids[i], ids[i + 1]
			local key = math.min(a, b) .. ":" .. math.max(a, b)
			if not seen[key] then seen[key] = true end
		end
		return seen
	end, 400)
	Time("seen-pair set pairmap.Unordered", function()
		local seen = world.pairmap.Unordered()
		for i = 1, 511 do
			local a, b = ids[i], ids[i + 1]
			if not seen:Get(a, b) then seen:Set(a, b, true) end
		end
		return seen
	end, 400)
end

-- Ring ---------------------------------------------------------------------------------
do
	local log, ring, n = {}, list.ring.New(64), 0
	for i = 1, 64 do log[i] = i; ring:Push(i) end
	Time("bounded log 64, old append+remove(1)", function()
		n = n + 1
		log[#log + 1] = n
		if #log > 64 then table.remove(log, 1) end
	end, 100000)
	Time("bounded log 64, list.ring Push", function()
		n = n + 1
		ring:Push(n)
	end, 100000)
end

-- Draw ---------------------------------------------------------------------------------
do
	local pool = {}
	for i = 1, 30 do pool[i] = i end
	local function Dice(low, high) return low + Random(high - low + 1) end
	Time("draw 8 of 30 old swap-remove", function()
		local candidates = {}
		for i, v in ipairs(pool) do candidates[i] = v end
		local targets = {}
		while #candidates > 0 and #targets ~= 8 do
			local which = Dice(1, #candidates)
			targets[#targets + 1] = candidates[which]
			candidates[which] = candidates[#candidates]
			candidates[#candidates] = nil
		end
		return targets
	end, 20000)
	Time("draw 8 of 30 math.choice.Draw", function() return math.choice.Draw(pool, 8, Dice) end, 20000)
end

-- The crossing's floor: tiny operations ---------------------------------------------------
do
	local a, b = { x = 0, y = 0, z = 0 }, { x = 10, y = 10, z = 10 }
	local c, d = { x = 5, y = 5, z = 5 }, { x = 15, y = 15, z = 15 }
	local v = 0.5
	Time("scalar clamp inline min/max", function() return math.min(1, math.max(0, v)) end, 500000)
	Time("scalar Saturate", function() return math.scalar.Saturate(v) end, 500000)
	Time("box overlap inline compare", function()
		return a.x <= d.x and c.x <= b.x and a.y <= d.y and c.y <= b.y and a.z <= d.z and c.z <= b.z
	end, 500000)
	Time("box Overlaps", function() return math.box.Overlaps(a, b, c, d) end, 500000)
end

return table.concat(lines, "\n")
