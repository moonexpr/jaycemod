-- games.system.permissions: every admin control is a named privilege with a
-- default rank, registered with CAMI so an admin mod can hand it to any rank.
-- Who holds a privilege is the admin mod's answer (the holds port); the
-- model adds only the rules a rank cannot express: everyone spawns in
-- Sandbox mode, and switching tampering off refuses it to every player.
local T = dofile("tests/harness.lua")
local Permissions = system.permissions
local PlayMode = system.play_mode

local RANKS = {
	[Permissions.RANK_PLAYER] = true,
	[Permissions.RANK_ADMIN] = true,
	[Permissions.RANK_SUPERADMIN] = true,
}

-- A holds port that answers from a set of privilege names.
local function Holding(...)
	local held = {}
	for _, name in ipairs({ ... }) do held[name] = true end
	return function(name) return held[name] == true end
end

local function Facts(over)
	local facts = {
		mode = PlayMode.GAMEPLAY,
		tamperingEnabled = true,
	}
	for k, v in pairs(over or {}) do facts[k] = v end
	return facts
end

T.test("every privilege is registered once, with a known default rank and a description", function()
	T.eq(#Permissions.PRIVILEGES > 0, true, "Permissions.PRIVILEGES lists the privileges")
	local seen = {}
	for _, p in ipairs(Permissions.PRIVILEGES) do
		T.eq(seen[p.name], nil, "registered once: " .. p.name)
		seen[p.name] = true
		T.eq(RANKS[p.rank], true, "a known rank: " .. p.name)
		T.eq(type(p.description) == "string" and #p.description > 0, true, "described: " .. p.name)
	end
	for _, name in ipairs({
		Permissions.ROUND, Permissions.MATCH, Permissions.TAMPER, Permissions.NEXTSOLDIER,
		Permissions.RULES, Permissions.PLAYERS, Permissions.SERVER_OPTIONS, Permissions.ECONOMY,
		Permissions.GAMEPLAY, Permissions.NPC_DEBUG, Permissions.SPAWN, Permissions.BUILD,
	}) do
		T.eq(seen[name], true, "registered: " .. tostring(name))
	end
end)

T.test("the superadmin toggles default to superadmins, the rest to admins", function()
	for _, p in ipairs(Permissions.PRIVILEGES) do
		local superOnly = p.name == Permissions.ECONOMY or p.name == Permissions.GAMEPLAY or p.name == Permissions.NPC_DEBUG
		T.eq(p.rank, superOnly and Permissions.RANK_SUPERADMIN or Permissions.RANK_ADMIN, p.name)
	end
end)

T.test("a held privilege is allowed; one not held is refused for rank", function()
	T.eq(Permissions.Allows(Permissions.MATCH, Holding(Permissions.MATCH), Facts()), true)
	local ok, why = Permissions.Allows(Permissions.MATCH, Holding(), Facts())
	T.eq(ok, false)
	T.eq(why, Permissions.REASON_RANK)
end)

T.test("everyone spawns in Sandbox mode; in Gameplay mode only holders do", function()
	T.eq(Permissions.Allows(Permissions.SPAWN, Holding(), Facts({ mode = PlayMode.SANDBOX })), true)
	for _, mode in ipairs({ PlayMode.GAMEPLAY, PlayMode.AIWAR, PlayMode.ARENA }) do
		T.eq(Permissions.Allows(Permissions.SPAWN, Holding(), Facts({ mode = mode })), false, mode)
		T.eq(Permissions.Allows(Permissions.SPAWN, Holding(Permissions.SPAWN), Facts({ mode = mode })), true, mode)
	end
end)

T.test("building is held-only in every mode", function()
	T.eq(Permissions.Allows(Permissions.BUILD, Holding(), Facts({ mode = PlayMode.SANDBOX })), false)
	T.eq(Permissions.Allows(Permissions.BUILD, Holding(Permissions.BUILD), Facts({ mode = PlayMode.SANDBOX })), true)
end)

T.test("only admins and superadmins tamper, even with tampering on", function()
	local tamper
	for _, p in ipairs(Permissions.PRIVILEGES) do
		if p.name == Permissions.TAMPER then tamper = p end
	end
	T.eq(tamper.rank, Permissions.RANK_ADMIN, "admins and up hold it by default")
	local ok, why = Permissions.Allows(Permissions.TAMPER, Holding(), Facts())
	T.eq(ok, false, "a player")
	T.eq(why, Permissions.REASON_RANK)
end)

T.test("tampering switched off refuses everyone, superadmins too", function()
	local off = Facts({ tamperingEnabled = false })
	T.eq(Permissions.Allows(Permissions.TAMPER, Holding(Permissions.TAMPER), Facts()), true, "on: the tamper privilege is enough")
	local ok, why = Permissions.Allows(Permissions.TAMPER, Holding(Permissions.TAMPER), off)
	T.eq(ok, false, "off: an admin with only the tamper privilege")
	T.eq(why, Permissions.REASON_TAMPERING_OFF)
	ok, why = Permissions.Allows(Permissions.TAMPER, Holding(Permissions.TAMPER, Permissions.GAMEPLAY), off)
	T.eq(ok, false, "off: a superadmin, who may switch it back on")
	T.eq(why, Permissions.REASON_TAMPERING_OFF)
	local _, notHeld = Permissions.Allows(Permissions.TAMPER, Holding(Permissions.GAMEPLAY), off)
	T.eq(notHeld, Permissions.REASON_RANK, "the gameplay toggles alone do not grant tampering")
end)

T.test("switching tampering off touches nothing but tampering", function()
	local off = Facts({ tamperingEnabled = false })
	T.eq(Permissions.Allows(Permissions.ROUND, Holding(Permissions.ROUND), off), true)
	T.eq(Permissions.Allows(Permissions.MATCH, Holding(Permissions.MATCH), off), true)
end)

T.test("asking about an unknown privilege is our bug, not a refusal", function()
	T.eq(pcall(Permissions.Allows, "sandcastle.nonsense", Holding(), Facts()), false)
end)

T.finish()
