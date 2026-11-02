-- ws_jit_enabled: LuaJIT's compiler on the server, on (the engine's default)
-- or off, when every Lua function runs in the interpreter. Turning it off
-- also flushes the compiled traces. On the AI war its defaults thrash
-- (docs/ns-performance-baseline.md), so this is a switch to measure with.
local ENABLED = CreateConVar("ws_jit_enabled", "1", FCVAR_ARCHIVE,
	"LuaJIT's compiler on the server (0: every Lua function interpreted)", 0, 1)

local function Apply(on)
	if on then
		jit.on()
	else
		jit.off()
		jit.flush()
	end
end

cvars.AddChangeCallback("ws_jit_enabled", function(_, _, value) Apply(value ~= "0") end, "ws_jit")
Apply(ENABLED:GetBool())
