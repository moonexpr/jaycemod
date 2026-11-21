-- Wetsands' games (wetsands/gamemode/gamerules/): Sandcastle's, but for the map
-- they patch. Wetsands' rounds and capture features run the round, the timers,
-- the points and the spawns through its own bindings of TF2's entities, which
-- take the place of Sandcastle's ports; so its games add none of Sandcastle's
-- systems (the logic_sc_* proxies, which ask what only the ports answer), and
-- keep the rest of what Sandcastle's say.
local T = dofile ("tests/harness.lua")

local SANDCASTLE = "addons/sandcastle/gamemodes/sandcastle/gamemode/"
local WETSANDS = "addons/sandcastle/gamemodes/wetsands/gamemode/"

-- What a map patched asked for: the systems made, the entities proxied.
local asked

local function Rules ()
	return
	{
		EnsureSystem = function (_, class)
			asked [#asked + 1] = class
			return { WireRules = function () end, StoreOutput = function () end, GetName = function () return class end }
		end
	}
end

-- The games as the gamemode registers them: Sandcastle's, then Wetsands'.
local function Games (wetsands)
	asked = {}
	-- GMod's baseclass.Set: a name set again merges the new table into the one
	-- first set, which takes the new one's metatable (lua/includes/modules/baseclass.lua)
	local stored = {}
	baseclass =
	{
		Set = function (name, tab)
			if not stored [name] then stored [name] = tab return end
			for key, value in pairs (tab) do stored [name] [key] = value end
			setmetatable (stored [name], getmetatable (tab))
		end
	}
	GetGlobal2String = function (_, default) return default end
	GetGlobal2Bool = function () return true end
	SetGlobal2Bool = function () end
	SERVER = true
	ents = { FindByClass = function () return { {} } end }
	scripted_ents =
	{
		GetMember = function (class, member)
			if member == "All" then return function () return { { GetSpawnTeam = function () return TEAM_RED end } } end end
			return function () asked [#asked + 1] = class end
		end
	}
	TEAM_RED = TEAM_RED or 2
	package.loaded.game_manager, game_manager = nil, nil
	dofile (SANDCASTLE .. "includes/modules/game_manager.lua")
	for _, name in ipairs ({ "game_default", "game_teamplay", "game_control_points" }) do
		dofile (SANDCASTLE .. "gamerules/" .. name .. ".lua")
	end
	local sandcastle =
	{
		game_teamplay = game_manager.GetClass ("game_teamplay"),
		game_control_points = game_manager.GetClass ("game_control_points")
	}
	if wetsands then
		for _, name in ipairs ({ "game_teamplay", "game_control_points" }) do
			dofile (WETSANDS .. "gamerules/" .. name .. ".lua")
		end
	end
	return game_manager, sandcastle
end

T.test ("Sandcastle's games add their systems to the map, as Wetsands' must not", function ()
	local Manager = Games (false)
	Manager.RunClass ("game_teamplay",       "PatchMap", Rules ())
	Manager.RunClass ("game_control_points", "PatchMap", Rules ())
	T.eq (#asked > 0, true, "Sandcastle's patch the map")
end)

T.test ("Wetsands' games add none of Sandcastle's systems to the map", function ()
	local Manager = Games (true)
	Manager.RunClass ("game_teamplay",       "PatchMap", Rules ())
	Manager.RunClass ("game_control_points", "PatchMap", Rules ())
	T.eq (table.concat (asked, ", "), "", "no proxy and no system")
end)

T.test ("Wetsands' games take Sandcastle's places and keep the rest of what they say", function ()
	local Manager, sandcastle = Games (true)
	for name, theirs in pairs (sandcastle) do
		local ours = Manager.GetClass (name)
		T.eq (ours ~= theirs,  true,              name .. ": replaced")
		T.eq (ours:Applies (), theirs:Applies (), name .. ": played where Sandcastle's is")
		T.eq (ours.PRIORITY,   theirs.PRIORITY,   name .. ": as decisive")
		T.eq (ours.GetRules,   theirs.GetRules,   name .. ": asking the same of the map")
		T.eq (ours.Standing,   theirs.Standing,   name .. ": the same standing")
	end
end)

T.test ("every game being played answers once Wetsands' replace Sandcastle's, as on the server", function ()
	local Manager = Games (true)
	local ok, err = pcall (Manager.Active)
	T.eq (ok,                        true, "the games played: " .. tostring (err))
	T.eq (Manager.Current () ~= nil, true, "one decides the round")
	for _, name in ipairs ({ "game_default", "game_teamplay", "game_control_points" }) do
		T.eq (pcall (Manager.RunClass, name, "GetRules"), true, name .. " asks its rules of the map")
	end
end)

T.finish ()
