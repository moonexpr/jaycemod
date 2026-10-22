-- The MvM mode (features.mvm.model): tf_logic_mann_vs_machine makes the
-- game Mann vs. Machine over every other game type its maps carry (their
-- bombs are item_teamflags, mvm_mannhattan's gates control points). BLU
-- carries its own bomb, a delivery scores nothing (the map's relays end the
-- round), and owning every gate wins nothing. Setup stands in for the
-- ready-up; its end starts the wave, which hands the bomb to an invader in
-- its spawn room, and invaders in their spawn room cannot be hurt.
local T = dofile("tests/harness.lua")
local Mvm = T.require("features.mvm.model")
local Flag = T.require("features.flag.model")
local Teams = T.require("games.gameplay.teams")
local Players = T.require("games.gameplay.players")
local State = T.require("games.gameplay.rounds.state")

local RED, BLUE = Teams.RED, Teams.BLUE
local C = Players.COND

local function P(x, y) return { x = x, y = y, z = 0 } end

T.test("MvM outranks the game types its maps also carry", function()
	T.eq(Mvm.Mode.NAME, "mvm", "named")
	for _, path in ipairs({ "foundation.rounds.control_points", "foundation.rounds.payload", "features.koth.model" }) do
		T.eq(Mvm.Mode.PRIORITY > T.require(path).Mode.PRIORITY, true, "over " .. path)
	end
	T.eq(Mvm.Mode.PRIORITY > Flag.Mode.PRIORITY, true, "over CTF")
end)

T.test("the bomb is BLU's to carry, and a delivery scores no capture", function()
	T.eq(Mvm.Mode.FLAG_OWNERS_CARRY, true, "owners carry")
	T.eq(Mvm.Mode.FLAG_CAPS_SCORE, false, "no tally")
	T.eq(Mvm.Mode.OBJECTIVE, true, "no round limits")
end)

T.test("capturing every gate wins nothing: the map decides", function()
	T.eq(Mvm.Mode:MayWinByPoints(Teams.BLUE, { timerMayExpire = true }), false, "BLU owning every gate")
end)

-- CFuncRespawnRoom::RespawnRoomTouch: in MvM the invaders' spawn rooms
-- drop nothing, so the bomb, which starts in BLU's, stays with its carrier.
T.test("BLU's bomb carrier keeps the bomb in BLU's spawn room; CTF's carriers still drop it", function()
	T.eq(Mvm.Mode.FLAG_INVADERS, BLUE, "BLU invades")
	T.eq(Flag.DropsIn(BLUE, BLUE, Mvm.Mode.FLAG_INVADERS), false, "the invaders' room keeps it")
	T.eq(Flag.DropsIn(RED, RED, Mvm.Mode.FLAG_INVADERS), true, "a defender's own room still drops it")
	T.eq(Flag.DropsIn(BLUE, BLUE, Flag.Mode.FLAG_INVADERS), true, "CTF: its own room drops it")
	T.eq(Flag.DropsIn(RED, BLUE, Mvm.Mode.FLAG_INVADERS), false, "an enemy room never")
end)

-- No bomb is taken before the wave: setup stands in for the ready-up, with
-- no robots on the field yet.
T.test("no bomb is picked up in setup in MvM; CTF's flags are", function()
	T.eq(Mvm.Mode.FLAG_WAITS_FOR_WAVE, true, "MvM waits")
	T.eq(Flag.MayBeCapped(State.RND_RUNNING, true, Mvm.Mode.FLAG_WAITS_FOR_WAVE), false, "MvM in setup")
	T.eq(Flag.MayBeCapped(State.RND_RUNNING, false, Mvm.Mode.FLAG_WAITS_FOR_WAVE), true, "MvM in the wave")
	T.eq(Flag.MayBeCapped(State.RND_RUNNING, true, Flag.Mode.FLAG_WAITS_FOR_WAVE), true, "CTF in setup")
	T.eq(Flag.MayBeCapped(State.PREROUND, false, Mvm.Mode.FLAG_WAITS_FOR_WAVE), false, "never in the pre-round")
end)

T.test("a bomb given to a carrier is carried, as a pickup", function()
	local bomb = Flag.New({ team = BLUE })
	local carrier = {}
	local events = bomb:PickUp(carrier, BLUE, { ownersCarry = true, mayBeCapped = true })
	T.eq(#events, 1, "one event")
	T.eq(events[1].kind, Flag.PICKUP, "a pickup")
	T.eq(bomb:Carrier(), carrier, "carried")
end)

-- The popfiles' StartWaveOutput: the wave's start triggers the map's
-- wave_start_relay.
T.test("the wave's start fires the popfile's StartWaveOutput", function()
	T.eq(#Mvm.WAVE_START_OUTPUTS, 1, "one output")
	T.eq(Mvm.WAVE_START_OUTPUTS[1].target, "wave_start_relay", "its relay")
	T.eq(Mvm.WAVE_START_OUTPUTS[1].input, "Trigger", "triggered")
end)

-- CTFBotFetchFlag: the bomb at home goes to an invader that has just spawned
-- (in its spawn room); Sandcastle picks the nearest the bomb.
T.test("the bomb at home goes to the invader in spawn nearest it", function()
	local home = P(0, 0)
	local near, far = { pos = P(100, 0) }, { pos = P(400, 0) }
	T.eq(Mvm.BombCarrier({ far, near }, home), near, "the nearest")
	T.eq(Mvm.BombCarrier({}, home), nil, "nobody in spawn")
end)

-- CTFBotMainAction::Update: an invading bot in its spawn room gets uber,
-- hidden unless damaged, for half a second, and pushback immunity for one,
-- renewed while it stays.
T.test("invaders in their spawn room are ubered and cannot be pushed", function()
	local want = {
		[C.INVULNERABLE] = 0.5,
		[C.INVULNERABLE_HIDE_UNLESS_DAMAGED] = 0.5,
		[C.INVULNERABLE_WEARINGOFF] = 0.5,
		[C.IMMUNE_TO_PUSHBACK] = 1.0,
	}
	local got = {}
	for _, p in ipairs(Mvm.SPAWN_PROTECTION) do got[p.cond] = p.seconds end
	for cond, seconds in pairs(want) do T.eq(got[cond], seconds, "cond " .. cond) end
	T.eq(#Mvm.SPAWN_PROTECTION, 4, "those four")
	T.eq(Mvm.Protected(BLUE, BLUE, Mvm.Mode.FLAG_INVADERS), true, "an invader in its own room")
	T.eq(Mvm.Protected(RED, RED, Mvm.Mode.FLAG_INVADERS), false, "a defender in its own room")
	T.eq(Mvm.Protected(BLUE, RED, Mvm.Mode.FLAG_INVADERS), false, "a defender in the invaders' room")
end)

T.test("setup, the ready-up's stand-in, lasts SETUP_SECONDS by default", function()
	T.eq(Mvm.SETUP_SECONDS > 0, true, "some setup")
end)

T.test("an MvM game waits for its defenders on RED; BLU's robots do not count", function()
	local Rounds = T.require("games.gameplay.rounds")
	T.defined(Mvm.MIN_DEFENDERS, "Mvm.MIN_DEFENDERS")
	local n = Mvm.MIN_DEFENDERS
	local function Met(r, b)
		local have, need = Rounds.PlayersNeeded(Mvm.Mode.PLAYERS_NEEDED, { [RED] = r, [BLUE] = b, free = 0 })
		return have >= need
	end
	T.eq(Met(n - 1, 100), false, "one defender short")
	T.eq(Met(n, 0), true, "met")
end)

T.finish()
