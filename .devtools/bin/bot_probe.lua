-- What a player bot (player.CreateNextBot) can be made to do from
-- StartCommand alone: runs on the dev server (dt lua -f), spawns one bot on
-- the largest flat nav area, tries each input in turn and logs what the
-- engine did with it. Results: BotProbe.log, and a Watch "bot_probe" event
-- when the run ends (dt watch --until bot_probe). BotProbe.Stop() kicks the
-- bot and removes the hooks.
--
-- Each step resets the bot to the area's centre, holds one input for HOLD
-- seconds, then reads velocity, eye angles, weapon state and the hooks seen.

local HOLD = 0.5
-- Long enough to see a jump's rise and fall; how many ticks it holds IN_JUMP.
local JUMP_WATCH, JUMP_TICKS = 1.0, 3
-- How long a body in a teleport trigger is given to be sent elsewhere, and
-- how far it must then be from where it was put to count as sent.
local TELEPORT_WAIT, TELEPORT_MOVED = 0.5, 1024
local BOT_NAME = "probe"

if BotProbe and BotProbe.Stop then BotProbe.Stop() end
BotProbe = { log = {}, done = false }
local P = BotProbe

local function Log(fmt, ...) P.log[#P.log + 1] = string.format(fmt, ...) end
local function Yaw(v) return math.NormalizeAngle(v:Angle().y) end
local function Fmt(a) return string.format("(%.0f %.0f %.0f)", a.p, a.y, a.r) end

-- The bot's state: program(bot, cmd) sets its input every StartCommand.
local state = { calls = 0, cost = 0, hooks = {}, keys = {}, bullets = {}, firstCmd = nil }
P.state = state

hook.Add("StartCommand", "bot_probe", function(ply, cmd)
	if ply ~= P.bot then return end
	if GetConVarNumber("bot_mimic") ~= 0 then return end
	state.calls = state.calls + 1
	state.rawButtons = cmd:GetButtons()
	if not state.firstCmd then
		state.firstCmd = string.format("view %s fwd %d side %d buttons %d cmdnum %d tick %d",
			Fmt(cmd:GetViewAngles()), cmd:GetForwardMove(), cmd:GetSideMove(), cmd:GetButtons(), cmd:CommandNumber(), cmd:TickCount())
	end
	if state.program then
		local t = SysTime()
		state.program(ply, cmd)
		state.cost = state.cost + (SysTime() - t)
	end
end)

for _, name in ipairs({ "SetupMove", "Move", "FinishMove", "PlayerTick", "PlayerPostThink" }) do
	hook.Add(name, "bot_probe_count", function(ply)
		if ply == P.bot then state.hooks[name] = (state.hooks[name] or 0) + 1 end
	end)
end
hook.Add("KeyPress", "bot_probe_keys", function(ply, key)
	if ply == P.bot then state.keys[key] = (state.keys[key] or 0) + 1 end
end)
hook.Add("PlayerUse", "bot_probe_use", function(ply, ent)
	if ply == P.bot then state.used = tostring(ent) end
end)
hook.Add("EntityFireBullets", "bot_probe_bullets", function(ent, data)
	if ent == P.bot or (IsValid(ent) and ent:GetOwner() == P.bot) then
		state.bullets[#state.bullets + 1] = { dir = data.Dir:Angle(), eye = P.bot:EyeAngles() }
	end
end)

function P.Stop()
	timer.Remove("bot_probe_run")
	hook.Remove("StartCommand", "bot_probe")
	for _, name in ipairs({ "SetupMove", "Move", "FinishMove", "PlayerTick", "PlayerPostThink" }) do hook.Remove(name, "bot_probe_count") end
	hook.Remove("KeyPress", "bot_probe_keys")
	hook.Remove("PlayerUse", "bot_probe_use")
	hook.Remove("EntityFireBullets", "bot_probe_bullets")
	if IsValid(P.bot) then P.bot:Kick("probe done") end
end

-- The floor at the largest nav area's centre, where a short run meets no
-- wall. Standing on it, not dropped onto it: a bot in the air ignores a jump.
local function OpenSpot(bot)
	local best, bestSize
	for _, area in ipairs(navmesh.GetAllNavAreas()) do
		local size = math.min(area:GetSizeX(), area:GetSizeY())
		if not area:IsUnderwater() and (not bestSize or size > bestSize) then best, bestSize = area, size end
	end
	local center = best:GetCenter()
	local tr = util.TraceHull({ start = center + Vector(0, 0, 32), endpos = center - Vector(0, 0, 256), mins = bot:OBBMins(), maxs = bot:OBBMaxs(), filter = bot, mask = MASK_PLAYERSOLID })
	return tr.HitPos, bestSize
end

-- An enabled trigger_teleport that only clients touch, or nil.
local SF_TRIGGER_ALLOW_CLIENTS, SF_TRIGGER_ALLOW_NPCS = 1, 2
local function ClientsOnlyTeleport()
	for _, t in ipairs(ents.FindByClass("trigger_teleport")) do
		local flags = t:GetSpawnFlags()
		if bit.band(flags, SF_TRIGGER_ALLOW_CLIENTS) ~= 0 and bit.band(flags, SF_TRIGGER_ALLOW_NPCS) == 0
			and tostring(t:GetKeyValues().StartDisabled) ~= "1" then return t end
	end
end

-- After SetPos the bot is not yet on the ground: a jump pressed at once is
-- lost. Reset lets it stand this long, its buttons cleared.
local SETTLE = 0.3

local function Still(_, cmd) cmd:ClearButtons(); cmd:ClearMovement() end

local spot
local function Reset(bot, eye)
	bot:SetPos(spot)
	bot:SetLocalVelocity(vector_origin)
	bot:SetEyeAngles(eye or angle_zero)
	state.program = Still
	coroutine.yield(SETTLE)
	state.program = nil
end

-- Holds program for seconds, then reports the bot's horizontal motion.
local function Hold(bot, program, seconds)
	state.program = program
	coroutine.yield(seconds or HOLD)
	local v = bot:GetVelocity()
	local report = { speed = v:Length2D(), yaw = Yaw(v), eye = bot:EyeAngles(), z = bot:GetPos().z - spot.z, vz = v.z }
	state.program = nil
	return report
end

local function Steps(bot)
	coroutine.yield(1)
	Log("joined: team %d alive %s model %s weapon %s", bot:Team(), tostring(bot:Alive()), bot:GetModel(), tostring(bot:GetActiveWeapon()))
	if bot:Team() ~= WS.TEAM_RED then WS.SetPlayerTeam(bot, WS.TEAM_RED) end
	coroutine.yield(0.5)
	if not bot:Alive() then bot:Spawn() end
	coroutine.yield(0.5)
	local size
	spot, size = OpenSpot(bot)
	Log("after team: team %d alive %s model %s weapons %d active %s; open spot %s (area %.0f units)", bot:Team(), tostring(bot:Alive()), bot:GetModel(), #bot:GetWeapons(), tostring(bot:GetActiveWeapon()), tostring(spot), size)
	Log("first cmd the engine made: %s", state.firstCmd or "none")

	-- Does it run every tick, and which movement hooks run for it?
	Reset(bot)
	state.calls, state.hooks = 0, {}
	local tick0 = engine.TickCount()
	coroutine.yield(1)
	local ticks = engine.TickCount() - tick0
	local hooks = {}
	for name, n in SortedPairs(state.hooks) do hooks[#hooks + 1] = name .. " " .. n end
	Log("cadence over %d ticks: StartCommand %d; %s", ticks, state.calls, table.concat(hooks, ", "))

	-- Idle: no input at all.
	Reset(bot)
	local r = Hold(bot, function(_, cmd) end)
	Log("no input: speed %.0f, buttons in the engine's command %d, crouching %s", r.speed, state.rawButtons or -1, tostring(bot:Crouching()))

	-- Move angles from the command, eye angles left alone.
	Reset(bot, Angle(0, 0, 0))
	r = Hold(bot, function(_, cmd) cmd:ClearMovement(); cmd:SetViewAngles(Angle(0, 90, 0)); cmd:SetForwardMove(10000) end)
	Log("cmd view yaw 90 + forward: speed %.0f move yaw %.0f eye %s", r.speed, r.yaw, Fmt(r.eye))

	-- Eye angles set every tick, command angles somewhere else.
	Reset(bot, Angle(0, 0, 0))
	r = Hold(bot, function(ply, cmd) cmd:ClearMovement(); ply:SetEyeAngles(Angle(0, 0, 0)); cmd:SetViewAngles(Angle(0, 90, 0)); cmd:SetForwardMove(10000) end)
	Log("eye yaw 0 each tick, cmd yaw 90 + forward: move yaw %.0f eye %s", r.yaw, Fmt(r.eye))

	-- Command angles only from eye angles: does forward follow the eye?
	Reset(bot, Angle(0, -45, 0))
	r = Hold(bot, function(ply, cmd) cmd:ClearMovement(); cmd:SetForwardMove(10000) end)
	Log("eye yaw -45, no cmd angles + forward: move yaw %.0f eye %s", r.yaw, Fmt(r.eye))

	-- Strafing.
	Reset(bot)
	r = Hold(bot, function(_, cmd) cmd:ClearMovement(); cmd:SetViewAngles(Angle(0, 0, 0)); cmd:SetSideMove(10000) end)
	Log("side move at yaw 0: speed %.0f move yaw %.0f", r.speed, r.yaw)
	Reset(bot)
	r = Hold(bot, function(_, cmd) cmd:ClearMovement(); cmd:SetViewAngles(Angle(0, 0, 0)); cmd:SetForwardMove(10000); cmd:SetSideMove(-10000) end)
	Log("forward + left at yaw 0: speed %.0f move yaw %.0f", r.speed, r.yaw)

	-- Gaits, each held long enough to take (a duck needs most of a second)
	-- and short enough not to run off the area into a wall.
	for _, gait in ipairs({ { "walk", IN_WALK, 0.4 }, { "sprint", IN_SPEED, 0.4 }, { "duck", IN_DUCK, 1 } }) do
		Reset(bot)
		local crouched = false
		r = Hold(bot, function(ply, cmd)
			cmd:ClearButtons(); cmd:ClearMovement(); cmd:SetViewAngles(Angle(0, 0, 0)); cmd:SetForwardMove(10000); cmd:AddKey(gait[2])
			crouched = ply:Crouching()
		end, gait[3])
		Log("forward + %s: speed %.0f crouching %s", gait[1], r.speed, tostring(crouched))
	end

	-- A jump: IN_JUMP for JUMP_TICKS ticks from the ground, then watch the rise.
	Reset(bot)
	local peak, ticks = 0, 0
	state.program = function(ply, cmd)
		cmd:ClearButtons(); cmd:ClearMovement()
		ticks = ticks + 1
		if ticks <= JUMP_TICKS then cmd:AddKey(IN_JUMP) end
		peak = math.max(peak, ply:GetPos().z - spot.z)
	end
	coroutine.yield(JUMP_WATCH)
	state.program = nil
	Log("jump: peak %.1f units, on ground after %s, KeyPress IN_JUMP seen %d", peak, tostring(bot:OnGround()), state.keys[IN_JUMP] or 0)

	-- Weapons: give one, select it from the command, fire it.
	Reset(bot)
	local gun = bot:Give("weapon_smg1")
	if not IsValid(gun) then gun = bot:GetWeapon("weapon_smg1") end
	Log("gave weapon_smg1: %s; active %s", tostring(gun), tostring(bot:GetActiveWeapon()))
	if IsValid(gun) then
		state.program = function(_, cmd) cmd:ClearMovement(); cmd:SelectWeapon(gun) end
		coroutine.yield(0.6)
		Log("after cmd:SelectWeapon: active %s", tostring(bot:GetActiveWeapon()))
		bot:GiveAmmo(200, gun:GetPrimaryAmmoType(), true)

		-- Fire with the eye set and the command matching it.
		state.bullets = {}
		local clip0 = gun:Clip1()
		Reset(bot, Angle(10, 30, 0))
		Hold(bot, function(ply, cmd) cmd:ClearMovement(); cmd:SetViewAngles(Angle(10, 30, 0)); cmd:AddKey(IN_ATTACK) end, 0.4)
		local first = state.bullets[1]
		Log("fire, eye = cmd (10 30): bullets %d, clip %d -> %d, first dir %s eye %s", #state.bullets, clip0, gun:Clip1(), first and Fmt(first.dir) or "-", first and Fmt(first.eye) or "-")

		-- Fire with the eye one way and the command another: which aims?
		state.bullets = {}
		Reset(bot, Angle(10, 30, 0))
		Hold(bot, function(ply, cmd) cmd:ClearMovement(); ply:SetEyeAngles(Angle(10, 30, 0)); cmd:SetViewAngles(Angle(-20, 150, 0)); cmd:AddKey(IN_ATTACK) end, 0.4)
		first = state.bullets[1]
		Log("fire, eye (10 30) each tick, cmd (-20 150): bullets %d, first dir %s eye %s", #state.bullets, first and Fmt(first.dir) or "-", first and Fmt(first.eye) or "-")

		-- Reload.
		local clip1 = gun:Clip1()
		Hold(bot, function(_, cmd) cmd:ClearMovement(); cmd:AddKey(IN_RELOAD) end, 2)
		Log("reload: clip %d -> %d", clip1, gun:Clip1())
	end

	-- Mouse deltas, impulses, +use.
	Reset(bot, Angle(0, 0, 0))
	local r2 = Hold(bot, function(_, cmd) cmd:ClearMovement(); cmd:SetMouseX(200) end, 0.3)
	Log("SetMouseX 200 without view angles: eye %s", Fmt(r2.eye))
	local lit = bot:FlashlightIsOn()
	local sent = false
	Hold(bot, function(_, cmd) if not sent then cmd:SetImpulse(100); sent = true end end, 0.3)
	Log("impulse 100: flashlight %s -> %s", tostring(lit), tostring(bot:FlashlightIsOn()))
	bot:Flashlight(false)
	Hold(bot, function(_, cmd) cmd:AddKey(IN_USE) end, 0.3)
	Log("IN_USE: KeyPress seen %d, PlayerUse %s", state.keys[IN_USE] or 0, state.used or "nothing in reach")

	-- Cost of the hook as the probe runs it.
	Log("StartCommand calls %d, program time %.1f us a call", state.calls, state.calls > 0 and state.cost / state.calls * 1e6 or 0)

	-- A trigger only clients touch: the bot, then an engine NPC, put inside.
	local teleport = ClientsOnlyTeleport()
	if teleport then
		local mins, maxs = teleport:WorldSpaceAABB()
		local inside = (mins + maxs) / 2
		Reset(bot)
		bot:SetPos(inside)
		coroutine.yield(TELEPORT_WAIT)
		local botMoved = bot:GetPos():Distance(inside)
		local npc = ents.Create("npc_citizen")
		npc:SetPos(inside)
		npc:Spawn()
		coroutine.yield(TELEPORT_WAIT)
		local npcMoved = IsValid(npc) and npc:GetPos():Distance(inside) or -1
		if IsValid(npc) then npc:Remove() end
		Log("clients-only %s: bot sent %s (%.0f units), npc_citizen sent %s (%.0f units)", tostring(teleport),
			tostring(botMoved > TELEPORT_MOVED), botMoved, tostring(npcMoved > TELEPORT_MOVED), npcMoved)
	else
		Log("no enabled clients-only trigger_teleport on this map")
	end

	-- Console commands run as the bot.
	if not bot:Alive() then bot:Spawn(); coroutine.yield(0.5) end
	bot:ConCommand("kill")
	coroutine.yield(0.5)
	Log("ConCommand kill: alive %s", tostring(bot:Alive()))
end

local function Run()
	local bot = player.CreateNextBot(BOT_NAME)
	if not IsValid(bot) then Log("CreateNextBot returned NULL (no slot)"); P.done = true; return end
	P.bot = bot
	local co = coroutine.create(Steps)
	local resumeAt = 0
	timer.Create("bot_probe_run", 0, 0, function()
		if CurTime() < resumeAt then return end
		local ok, wait = coroutine.resume(co, bot)
		if not ok then
			Log("ERROR %s", tostring(wait))
		end
		if not ok or coroutine.status(co) == "dead" then
			timer.Remove("bot_probe_run")
			P.done = true
			return
		end
		resumeAt = CurTime() + (wait or 0)
	end)
end

Run()
Watch.Until("bot_probe", 0.5, 60, function() return P.done, #P.log .. " lines" end)
return "probe started"
