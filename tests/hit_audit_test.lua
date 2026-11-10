-- hit_audit: what a client's shot hit against what the server's did.
local T = dofile("tests/harness.lua")

dofile("addons/sandcastle/gamemodes/sandcastle/gamemode/includes/modules/hit_audit.lua")
local HitAudit = package.loaded.hit_audit

local function Pos(x) return { x = x, y = 0, z = 0 } end

-- An audit over a port recording what it reports; time is the test's.
local function Audit()
	local port = { now = 0, results = {} }
	port.Now = function() return port.now end
	port.Distance = function(a, b) return math.abs(a.x - b.x) end
	port.Result = function(ply, result) port.results[#port.results + 1] = { ply = ply, result = result } end

	return HitAudit.New(port), port
end

local function Claim(cmd, hits)
	return { cmd = cmd, weapon = "gun", hits = hits }
end

T.test("a shot both realms saw alike agrees, its position error kept", function()
	local audit, port = Audit()
	audit:ServerHit("p", 10, "gun", "target", Pos(100))
	audit:Claim("p", Claim(10, { { ent = "target", pos = Pos(103) } }))
	local stats = audit:Stats().gun
	T.eq(stats.shots, 1, "one shot")
	T.eq(stats.agree, 1, "agreed")
	T.eq(stats.worstError, 3, "three units apart")
	T.eq(#port.results, 0, "nothing to show")
end)

T.test("each way of disagreeing is counted apart and reported", function()
	local audit, port = Audit()
	audit:ServerHit("p", 1, "gun", nil, Pos(0))
	audit:Claim("p", Claim(1, { { ent = "target", pos = Pos(5) } }))
	audit:ServerHit("p", 2, "gun", "target", Pos(0))
	audit:Claim("p", Claim(2, { { pos = Pos(5) } }))
	audit:ServerHit("p", 3, "gun", "other", Pos(0))
	audit:Claim("p", Claim(3, { { ent = "target", pos = Pos(5) } }))
	local stats = audit:Stats().gun
	T.eq(stats.clientOnly, 1, "the client hit what the server missed")
	T.eq(stats.serverOnly, 1, "the server hit what the client missed")
	T.eq(stats.different, 1, "they hit different things")
	T.eq(stats.agree, 0, "none agreed")
	T.eq(#port.results, 3, "each reported")
	T.eq(port.results[1].ply, "p", "to the shooter")
	T.eq(port.results[1].result.pellets[1].outcome, HitAudit.CLIENT_ONLY, "with its outcome")
	T.eq(port.results[1].result.pellets[1].client.x, 5, "where the client saw it")
	T.eq(port.results[1].result.pellets[1].server.x, 0, "where the server did")
end)

T.test("a second claim of one command is refused", function()
	local audit = Audit()
	T.eq(audit:Claim("p", Claim(3, { { pos = Pos(0) } })), true, "the first is held")
	T.eq(audit:Claim("p", Claim(3, { { ent = "target", pos = Pos(0) } })), false, "the second refused")
	audit:ServerHit("p", 3, "gun", nil, Pos(0))
	audit:Think()
	T.eq(audit:Stats().gun.agree, 1, "the first stands")
end)

T.test("a claim may come before the server's shot", function()
	local audit = Audit()
	audit:Claim("p", Claim(7, { { ent = "target", pos = Pos(1) } }))
	T.eq(audit:Stats().gun, nil, "held until the server fires")
	audit:ServerHit("p", 7, "gun", "target", Pos(1))
	audit:Think()
	T.eq(audit:Stats().gun.agree, 1, "then compared")
end)

T.test("a shotgun's pellets are compared in order, and a count apart is its own outcome", function()
	local audit = Audit()
	audit:ServerHit("p", 4, "shotgun", "a", Pos(0))
	audit:ServerHit("p", 4, "shotgun", "b", Pos(0))
	audit:Claim("p", Claim(4, { { ent = "a", pos = Pos(0) }, { ent = "x", pos = Pos(0) } }))
	local stats = audit:Stats().shotgun
	T.eq(stats.pellets, 2, "two pellets")
	T.eq(stats.agree, 1, "the first")
	T.eq(stats.different, 1, "the second")
	audit:ServerHit("p", 5, "shotgun", "a", Pos(0))
	audit:Claim("p", { cmd = 5, weapon = "shotgun", hits = {} })
	T.eq(audit:Stats().shotgun.count, 1, "a count apart")
end)

T.test("a shot one realm never reports is counted unmatched once it is old", function()
	local audit, port = Audit()
	audit:ServerHit("p", 1, "gun", "target", Pos(0))
	audit:Claim("p", Claim(2, { { ent = "target", pos = Pos(0) } }))
	port.now = HitAudit.HOLD_SECONDS + 1
	audit:Think()
	T.eq(audit:Unmatched().server, 1, "the server's shot with no claim")
	T.eq(audit:Unmatched().client, 1, "the claim with no shot")
	audit:Claim("p", Claim(1, { { ent = "target", pos = Pos(0) } }))
	T.eq(audit:Stats().gun, nil, "and is not compared late")
end)

T.test("a claim that is not a claim is refused, and one player's cannot crowd the audit", function()
	local audit = Audit()
	for _, bad in ipairs({
		{},
		{ cmd = "1", weapon = "gun", hits = {} },
		{ cmd = 1, weapon = 5, hits = {} },
		{ cmd = 1, weapon = "gun", hits = "x" },
		{ cmd = 1, weapon = "gun", hits = { 5 } },
		{ cmd = 1, weapon = "gun", hits = { { pos = "here" } } },
		{ cmd = 1, weapon = ("w"):rep(HitAudit.WEAPON_BYTES + 1), hits = {} },
	}) do
		T.eq(audit:Claim("p", bad), false, "refused")
	end
	local many = {}
	for i = 1, HitAudit.PELLETS + 1 do many[i] = { pos = Pos(0) } end
	T.eq(audit:Claim("p", Claim(1, many)), false, "too many pellets")
	for cmd = 1, HitAudit.HELD + 5 do audit:Claim("p", Claim(cmd, { { pos = Pos(0) } })) end
	T.eq(audit:Held("p") <= HitAudit.HELD, true, "what is held for one player is capped")
end)

T.test("a player who leaves is forgotten, and Reset clears the counts", function()
	local audit = Audit()
	audit:ServerHit("p", 1, "gun", "target", Pos(0))
	audit:Forget("p")
	T.eq(audit:Held("p"), 0, "nothing held")
	audit:ServerHit("q", 1, "gun", "target", Pos(0))
	audit:Claim("q", Claim(1, { { ent = "target", pos = Pos(0) } }))
	audit:Reset()
	T.eq(next(audit:Stats()), nil, "no counts")
end)

T.test("the client gathers a command's pellets and claims them once", function()
	local claims = {}
	local shots = HitAudit.Shots(function(claim) claims[#claims + 1] = claim end)
	shots:Hit(9, "gun", "target", Pos(1))
	shots:Hit(9, "gun", nil, Pos(2))
	shots:Hit(10, "gun", "target", Pos(3))
	shots:Flush()
	T.eq(#claims, 2, "one a command")
	T.eq(claims[1].cmd, 9, "in order")
	T.eq(#claims[1].hits, 2, "its pellets")
	T.eq(claims[1].hits[2].ent, nil, "a miss carries no entity")
	shots:Flush()
	T.eq(#claims, 2, "once")
end)

T.finish()
