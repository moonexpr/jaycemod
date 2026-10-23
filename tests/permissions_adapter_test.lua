-- ws/sh_permissions.lua: registers every privilege with CAMI at its default
-- rank, and answers WS.Can(ply, privilege) by asking CAMI synchronously and
-- applying games.system.permissions. Run against a fake CAMI and fake
-- replicated state.
local T = dofile("tests/harness.lua")
local Permissions = system.permissions
local PlayMode = system.play_mode

local function Load(state)
	local registered, asked = {}, {}
	local convars = {}
	local env = setmetatable({
		WS = {
			require = T.require,
			Active = function() return state.roundsActive end,
			GameplayStopped = function() return state.gameplayStopped end,
			AiWarActive = function() return state.aiwar end,
		},
		CAMI = {
			RegisterPrivilege = function(p) registered[#registered + 1] = p end,
			PlayerHasAccess = function(ply, name, callback)
				asked[#asked + 1] = { ply = ply, name = name, callback = callback }
				return ply.held[name] == true, "fake"
			end,
		},
		CreateConVar = function(name, default)
			local c = { value = default }
			function c:GetBool() return state[name] == nil and self.value ~= "0" or state[name] end
			convars[name] = c
			return c
		end,
		GetGlobal2Bool = function(name, default)
			if name == "ws_round_arena" then return state.arena end
			return default
		end,
		IsValid = function(v) return v ~= nil end,
		FCVAR_REPLICATED = 1,
		FCVAR_NOTIFY = 2,
		FCVAR_ARCHIVE = 4,
	}, { __index = _G })
	setfenv(assert(loadfile("addons/sandcastle/gamemodes/sandcastle/gamemode/ws/sh_permissions.lua")), env)()
	return env.WS, registered, asked, convars
end

local function State(over)
	local s = {
		roundsActive = true,
		gameplayStopped = false,
		aiwar = false,
		arena = false,
	}
	for k, v in pairs(over or {}) do s[k] = v end
	return s
end

local function Ply(...)
	local held = {}
	for _, name in ipairs({ ... }) do held[name] = true end
	return { held = held }
end

T.test("every privilege is registered with CAMI at its default rank", function()
	local _, registered = Load(State())
	T.eq(#registered, #Permissions.PRIVILEGES)
	for i, p in ipairs(Permissions.PRIVILEGES) do
		T.eq(registered[i].Name, p.name)
		T.eq(registered[i].MinAccess, p.rank, p.name)
		T.eq(registered[i].Description, p.description, p.name)
	end
end)

T.test("WS.Can asks CAMI synchronously, for the privilege named", function()
	local W, _, asked = Load(State())
	T.eq(W.Can(Ply(Permissions.MATCH), Permissions.MATCH), true)
	T.eq(W.Can(Ply(), Permissions.MATCH), false)
	T.eq(asked[1].name, Permissions.MATCH)
	T.eq(asked[1].callback, nil, "no callback: CAMI answers at once")
end)

T.test("the server console may do anything", function()
	local W, _, asked = Load(State())
	T.eq(W.Can(nil, Permissions.ECONOMY), true)
	T.eq(#asked, 0, "nothing to ask an admin mod about")
end)

T.test("mp_tampering_enabled 0 refuses tampering to every player, superadmins too", function()
	local state = State({ mp_tampering_enabled = false })
	local W, _, _, convars = Load(state)
	T.eq(convars.mp_tampering_enabled ~= nil, true, "the switch is a convar")
	T.eq(W.Can(Ply(Permissions.TAMPER), Permissions.TAMPER), false, "an admin")
	T.eq(W.Can(Ply(Permissions.TAMPER, Permissions.GAMEPLAY), Permissions.TAMPER), false, "a superadmin")
	T.eq(W.Can(nil, Permissions.TAMPER), true, "the server console")
	state.mp_tampering_enabled = true
	T.eq(W.Can(Ply(Permissions.TAMPER), Permissions.TAMPER), true)
end)

T.test("WS.PlayMode reads the replicated state; everyone spawns in Sandbox mode", function()
	local state = State({ roundsActive = false })
	local W = Load(state)
	T.eq(W.PlayMode(), PlayMode.SANDBOX)
	T.eq(W.Can(Ply(), Permissions.SPAWN), true)
	state.roundsActive = true
	T.eq(W.PlayMode(), PlayMode.GAMEPLAY)
	T.eq(W.Can(Ply(), Permissions.SPAWN), false)
	state.aiwar = true
	T.eq(W.PlayMode(), PlayMode.AIWAR)
	state.aiwar, state.arena = false, true
	T.eq(W.PlayMode(), PlayMode.ARENA)
end)

T.finish()
