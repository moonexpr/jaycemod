-- Capture and restore of the gameplay state, in place, without a map change.
--   dev.capture() -> a versioned, plain table (JSON-ready): the gamemode's
--     mode, gameplay convars, the rounds (round, timers, HUD timer, scores,
--     goals), control points, flags, payload carts, the map's enabled and
--     disabled entities, the players and the AI war's soldiers
--   dev.apply(state) -> a report: what each section restored, and every key
--     it could not resolve and every note, never a silent skip
--   dev.state([{ verbose = true }]) -> a compact summary, or the capture
--   dev.check_roundtrip() -> capture, apply, capture, diff
-- The rounds, capture and flag controllers take and restore their own state
-- (Controller:Snapshot/Restore); the rest goes through the gamemode's
-- public functions. Entities are keyed by the refs below: map entities by
-- their map creation id, which a cleanup keeps, players by SteamID64.
local Diff = dev.require("sandcastle_dev_diff")

local SCHEMA = 1
dev.SCHEMA = SCHEMA

-- Entity keys -------------------------------------------------------------------------

local Refs = {}

function Refs:Encode(ent, path)
	if not isentity(ent) then
		dev.Fail((path or "a value") .. " holds " .. tostring(ent) .. ", neither plain data nor an entity")
	end
	if not IsValid(ent) then return "null" end
	if ent:IsPlayer() then return ent:IsBot() and ("bot:" .. ent:Nick()) or ("player:" .. ent:SteamID64()) end
	local id = ent:MapCreationID()
	if id >= 0 then return "map:" .. id end
	local name, class = ent:GetName(), ent:GetClass()
	if name ~= "" and #ents.FindByName(name) == 1 then return "named:" .. class .. ":" .. name end
	return "ent:" .. ent:EntIndex() .. ":" .. class
end

-- The entity a key names now, or nil.
function Refs:Decode(key)
	if key == "null" then return NULL end
	local kind, rest = string.match(key, "^(%a+):(.*)$")
	if kind == "map" then
		local ent = ents.GetMapCreatedEntity(tonumber(rest))
		return IsValid(ent) and ent or nil
	elseif kind == "player" then
		return player.GetBySteamID64(rest) or nil
	elseif kind == "bot" then
		for _, ply in ipairs(player.GetBots()) do
			if ply:Nick() == rest then return ply end
		end
	elseif kind == "named" then
		local class, name = string.match(rest, "^([^:]+):(.*)$")
		for _, ent in ipairs(ents.FindByName(name)) do
			if ent:GetClass() == class then return ent end
		end
	elseif kind == "ent" then
		local index, class = string.match(rest, "^(%d+):(.*)$")
		local ent = Entity(tonumber(index))
		if IsValid(ent) and ent:GetClass() == class then return ent end
	end
	return nil
end

dev.Refs = Refs

local function Vec(v) return { x = v.x, y = v.y, z = v.z } end
local function ToVector(t) return Vector(t.x, t.y, t.z) end
local function Ang(a) return { p = a.p, y = a.y, r = a.r } end
local function ToAngle(t) return Angle(t.p, t.y, t.r) end

-- Sections ----------------------------------------------------------------------------
-- Each: capture(now) -> data or nil (nothing of it on this map);
-- apply(data, now, report) -> a short summary; report:Missing(key),
-- report:Note(text) for what it could not do.

local GAMEPLAY_CONVARS = {
	"sv_gameplay_enabled",
	"mp_capstyle",
	"mp_blockstyle",
	"mp_capdeteriorate_time",
	"tf_caplinear",
	"mp_respawnwavetime",
	"mp_bonusroundtime",
	"mp_enableroundwaittime",
	"mp_stalemate_enable",
	"mp_stalemate_timelimit",
	"mp_deathmatch_enable",
	"mp_winlimit",
	"mp_maxrounds",
	"mp_timelimit",
	"mp_match_end_at_timelimit",
	"mp_friendlyfire",
	"tf_flag_caplimit",
	"tf_player_movement_restart_freeze",
	"mp_aiwar_team_size",
	"ns_soldiers_enabled",
	"ns_soldiers_paused",
	"ns_squads_auto_enabled",
	"ns_squads_max",
	"ns_squads_min",
}

-- Controllers that take and restore their own state, by feature name.
local CONTROLLERS = { "rounds", "capture", "flag" }

local SECTIONS = {}
local ORDER = {}

local function Section(name, capture, apply)
	SECTIONS[name] = {
		capture = capture,
		apply = apply,
	}
	ORDER[#ORDER + 1] = name
end

Section("convars", function()
	local values = {}
	for _, name in ipairs(GAMEPLAY_CONVARS) do
		local cv = GetConVar(name)
		if cv then values[name] = cv:GetString() end
	end
	return values
end, function(values, _, report)
	local changed = 0
	for name, value in pairs(values) do
		local cv = GetConVar(name)
		if not cv then
			report:Note("convar " .. name .. " does not exist here")
		elseif cv:GetString() ~= value then
			cv:SetString(value)
			changed = changed + 1
		end
	end
	return { changed = changed }
end)

for _, feature in ipairs(CONTROLLERS) do
	Section(feature, function(now)
		if not WS.FeatureLoaded(feature) then return nil end
		local controller = WS.Feature(feature)
		if not controller.Snapshot then
			dev.Fail("the " .. feature .. " controller has no Snapshot: the server runs older code; changelevel to load it")
		end
		return controller:Snapshot(now, Refs)
	end, function(data, now, report)
		if not WS.FeatureLoaded(feature) then
			report:Note("the " .. feature .. " feature is not loaded on this map; its state was not restored")
			return { restored = false }
		end
		local result = WS.Feature(feature):Restore(data, now, Refs)
		for _, key in ipairs(result.missing or {}) do report:Missing(feature, key) end
		for _, text in ipairs(result.notes or {}) do report:Note(feature .. ": " .. text) end
		return { restored = true }
	end)
end

local WATCHER = "team_train_watcher"

Section("payload", function(now)
	local carts = {}
	for _, ent in ipairs(ents.FindByClass(WATCHER)) do
		carts[Refs:Encode(ent)] = {
			pathIndex = ent.pathIndex,
			disabled = ent.disabled,
			team = ent.team,
			receding = ent.receding,
			waitingToRecede = ent.waitingToRecede,
			recedeIn = ent.recedeAt - now,
		}
	end
	return next(carts) and carts or nil
end, function(carts, now, report)
	local moved = 0
	for key, cart in pairs(carts) do
		local ent = Refs:Decode(key)
		if not IsValid(ent) then
			report:Missing("payload", key)
		else
			if ent.disabled ~= cart.disabled then ent:Input(cart.disabled and "Disable" or "Enable") end
			ent.team, ent.receding, ent.waitingToRecede = cart.team, cart.receding, cart.waitingToRecede
			ent.recedeAt = now + cart.recedeIn
			if cart.pathIndex and ent.pathIndex ~= cart.pathIndex and IsValid(ent.train) then
				ent:TeleportTo(cart.pathIndex)
				ent:ResumeSpeed()
				moved = moved + 1
			end
		end
	end
	return { moved = moved }
end)

-- Map entities switched by Enable and Disable that no section above owns.
local OWNED_TOGGLES = {
	team_round_timer = true,
	team_train_watcher = true,
	item_teamflag = true,
	func_capturezone = true,
	func_respawnflag = true,
	trigger_capture_area = true,
	team_control_point_master = true,
}

Section("toggles", function()
	local toggles = {}
	for _, ent in ipairs(ents.GetAll()) do
		if ent:MapCreationID() >= 0 and not OWNED_TOGGLES[ent:GetClass()] then
			local t = ent:GetTable()
			if type(t.disabled) == "boolean" then
				toggles[Refs:Encode(ent)] = not t.disabled
			elseif type(t.enabled) == "boolean" then
				toggles[Refs:Encode(ent)] = t.enabled
			end
		end
	end
	return toggles
end, function(toggles, _, report)
	local switched = 0
	for key, enabled in pairs(toggles) do
		local ent = Refs:Decode(key)
		if not IsValid(ent) then
			report:Missing("toggles", key)
		else
			local t = ent:GetTable()
			local now = type(t.disabled) == "boolean" and not t.disabled or t.enabled
			if now ~= enabled then
				ent:Input(enabled and "Enable" or "Disable")
				switched = switched + 1
				local after = type(t.disabled) == "boolean" and not t.disabled or t.enabled
				if after ~= enabled then report:Note("toggles: " .. dev.Describe(ent) .. " did not take " .. (enabled and "Enable" or "Disable")) end
			end
		end
	end
	return { switched = switched }
end)

-- A list, not a name-keyed table: JSON turns a key like "357" back into a
-- number, and the name would no longer be found.
local function AmmoOf(ply)
	local ammo = {}
	for _, name in pairs(game.GetAmmoTypes()) do
		local count = ply:GetAmmoCount(name)
		if count > 0 then
			ammo[#ammo + 1] = {
				name = name,
				count = count,
			}
		end
	end
	table.sort(ammo, function(a, b) return a.name < b.name end)
	return ammo
end

local function ConditionsOf(ent, now)
	local conds = {}
	for cond, ends in pairs(WS.ConditionsOf(ent)) do
		if ends == math.huge then
			conds[cond] = "permanent"
		elseif ends > now then
			conds[cond] = ends - now
		end
	end
	return conds
end

Section("players", function(now)
	local players = {}
	for _, ply in ipairs(player.GetAll()) do
		local owned, equipped
		if WS.Loadouts[ply] then owned, equipped = WS.Loadouts[ply]:State() end
		players[Refs:Encode(ply)] = {
			name = ply:Nick(),
			team = ply:Team(),
			alive = ply:Alive(),
			pos = Vec(ply:GetPos()),
			eyes = Ang(ply:EyeAngles()),
			health = ply:Health(),
			armor = ply:Armor(),
			ammo = AmmoOf(ply),
			loadout = owned and {
				owned = owned,
				equipped = equipped,
			} or nil,
			conditions = ConditionsOf(ply, now),
			money = WS.Money(ply),
		}
	end
	return players
end, function(players, _, report)
	local Loadout = WS.require("games.gameplay.loadout")
	local Players = WS.require("games.gameplay.players")
	local restored = 0
	for key, p in pairs(players) do
		local ply = Refs:Decode(key)
		if not IsValid(ply) then
			report:Missing("players", key .. " (" .. p.name .. ")")
		else
			if ply:Team() ~= p.team then WS.SetPlayerTeam(ply, p.team, true) end
			if p.alive and not ply:Alive() then ply:Spawn() end
			if not p.alive and ply:Alive() then ply:KillSilent() end
			if p.loadout then
				WS.Loadouts[ply] = Loadout.FromState(WS.LoadoutCatalog, p.loadout.owned, p.loadout.equipped)
				if p.alive then
					ply:StripWeapons()
					WS.GiveLoadout(ply)
				end
			end
			if p.alive then
				ply:SetPos(ToVector(p.pos))
				ply:SetEyeAngles(ToAngle(p.eyes))
				ply:SetLocalVelocity(vector_origin)
				ply:SetHealth(p.health)
				ply:SetArmor(p.armor)
				local wanted = {}
				for _, a in ipairs(p.ammo) do wanted[a.name] = a.count end
				for _, name in pairs(game.GetAmmoTypes()) do
					if ply:GetAmmoCount(name) ~= (wanted[name] or 0) then ply:SetAmmo(wanted[name] or 0, name) end
				end
			end
			WS.RemoveAllConditions(ply)
			for cond, left in pairs(p.conditions) do
				WS.AddCondition(ply, tonumber(cond) or cond, left == "permanent" and Players.PERMANENT or left)
			end
			local money = WS.Money(ply)
			if money < p.money then WS.GrantMoney(ply, p.money - money) elseif money > p.money then WS.SpendMoney(ply, money - p.money) end
			restored = restored + 1
		end
	end
	return { restored = restored }
end)

Section("aiwar", function()
	if not WS.FeatureLoaded("aiwar") then return nil end
	local A = WS.Feature("aiwar")
	local soldiers = {}
	if A.war then
		for ent, member in pairs(A.war.members) do
			if IsValid(ent) and ent:Health() > 0 then
				soldiers[Refs:Encode(ent)] = {
					class = ent:GetClass(),
					team = member.team,
					role = member.role,
					roleByHand = member.roleByHand == true,
					drafted = member.drafted == true,
					pos = Vec(ent:GetPos()),
					angles = Ang(ent:GetAngles()),
					health = ent:Health(),
				}
			end
		end
	end
	return {
		active = A:Active(),
		paused = A.paused == true,
		soldiers = soldiers,
	}
end, function(data, _, report)
	if not WS.FeatureLoaded("aiwar") then
		report:Note("the aiwar feature is not loaded on this map; its soldiers were not restored")
		return { restored = false }
	end
	local A = WS.Feature("aiwar")
	if data.active and not A:Active() then A:Start() end
	if not data.active and A:Active() then A:End() end
	if A.paused ~= data.paused then A:SetPaused(data.paused) end
	if next(data.soldiers) and not A.war then
		report:Note("aiwar: no war to enlist soldiers in (started: " .. tostring(A:Active()) .. "; the gamemode may not be in Gameplay yet); "
			.. table.Count(data.soldiers) .. " soldiers not restored, load again once it is")
		return { restored = false }
	end
	local kept, made, removed = 0, 0, 0
	local wanted = {}
	for key, s in pairs(data.soldiers) do
		local ent = Refs:Decode(key)
		local member = IsValid(ent) and A.war and A.war.members[ent]
		if member and ent:Health() > 0 then
			wanted[ent] = true
			if member.role ~= s.role and s.role then
				-- a role set by hand stays the soldier's; any other is the war's to change again
				local ok, why = true, nil
				if s.roleByHand then
					ok, why = A.war:SetRole(member, s.role)
				elseif member.fixed then
					ok, why = false, "it only ever does " .. tostring(member.fixed)
				else
					A.war:ChangeRole(member, s.role)
				end
				if not ok then report:Note("aiwar: " .. dev.Describe(ent) .. " kept " .. tostring(member.role) .. ": " .. tostring(why)) end
			end
			kept = kept + 1
		else
			ent = ents.Create(s.class)
			if not IsValid(ent) then
				report:Note("aiwar: could not make a " .. s.class)
			else
				ent:SetPos(ToVector(s.pos))
				ent:SetAngles(ToAngle(s.angles))
				ent:Spawn()
				ent:Activate()
				A:Enlist(ent, s.team, s.drafted, s.drafted and s.role or nil)
				wanted[ent] = true
				made = made + 1
			end
		end
		if IsValid(ent) then
			ent:SetPos(ToVector(s.pos))
			ent:SetAngles(ToAngle(s.angles))
			ent:SetHealth(s.health)
		end
	end
	if A.war then
		for ent in pairs(A.war.members) do
			if IsValid(ent) and not wanted[ent] then
				A:Discharge(ent)
				ent:Remove()
				removed = removed + 1
			end
		end
	end
	return {
		kept = kept,
		made = made,
		removed = removed,
	}
end)

-- Capture, apply ----------------------------------------------------------------------

function dev.capture()
	local now = CurTime()
	local state = {
		schema = SCHEMA,
		map = game.GetMap(),
		sections = {},
	}
	for _, name in ipairs(ORDER) do state.sections[name] = SECTIONS[name].capture(now) end
	return state
end

local Report = {}
Report.__index = Report

function Report:Missing(section, key)
	self.missing[#self.missing + 1] = section .. ": " .. key
end

function Report:Note(text)
	self.notes[#self.notes + 1] = text
end

-- The state put back in place. A state of another map or schema is refused
-- (scenarios migrate theirs first: dev.scenario).
function dev.apply(state)
	if type(state) ~= "table" or type(state.sections) ~= "table" then dev.Fail("apply takes a state from dev.capture()") end
	if state.schema ~= SCHEMA then
		dev.Fail("the state's schema is " .. tostring(state.schema) .. ", this workbench's " .. SCHEMA .. "; load it as a scenario to migrate it")
	end
	if state.map ~= game.GetMap() then
		dev.Fail("the state is of " .. tostring(state.map) .. ", the server is on " .. game.GetMap() .. "; changelevel " .. tostring(state.map) .. " first")
	end
	local now = CurTime()
	local report = setmetatable({
		sections = {},
		missing = {},
		notes = {},
	}, Report)
	for _, name in ipairs(ORDER) do
		local data = state.sections[name]
		if data ~= nil then report.sections[name] = SECTIONS[name].apply(data, now, report) end
	end
	return {
		sections = report.sections,
		missing = report.missing,
		notes = report.notes,
		ok = #report.missing == 0 and #report.notes == 0,
	}
end

-- Summary -----------------------------------------------------------------------------

local STATE_NAMES = {}

local function StateName(n)
	if not next(STATE_NAMES) then
		for name, value in pairs(WS.STATE) do
			if type(value) == "number" then STATE_NAMES[value] = name end
		end
	end
	return STATE_NAMES[n] or tostring(n)
end

-- A compact summary: what an agent needs to know where the game stands.
function dev.state(opts)
	if opts and opts.verbose then return dev.capture() end
	local rounds = dev.Rounds()
	local hud = rounds:HudTimer()
	local summary = {
		map = game.GetMap(),
		round = StateName(rounds.round:State()),
		setup = rounds.round:InSetup(),
		winner = rounds.round:Winner(),
		timer = IsValid(hud) and math.Round(rounds.timers[hud]:TimeRemaining(CurTime()), 1) or nil,
		scores = {
			red = team.GetScore(WS.TEAM_RED),
			blue = team.GetScore(WS.TEAM_BLUE),
		},
		gameplay = GetConVar("sv_gameplay_enabled"):GetInt(),
		frozen = dev.harness and dev.harness.live.frozen or false,
		harness = dev.harness and dev.harness.live.on or false,
		players = {},
	}
	for _, ply in ipairs(player.GetAll()) do
		summary.players[#summary.players + 1] = string.format("%s team %d %s hp %d", ply:Nick(), ply:Team(), ply:Alive() and "alive" or "dead", ply:Health())
	end
	if WS.FeatureLoaded("capture") and WS.Feature("capture").set then
		local set = WS.Feature("capture").set
		summary.points = {}
		for _, point in ipairs(set:Ids()) do
			if IsValid(point) then summary.points[point:GetName()] = set:Owner(point) .. (set:Locked(point) and " locked" or "") end
		end
	end
	if WS.FeatureLoaded("flag") then
		summary.flags = {}
		for ent, flag in pairs(WS.Feature("flag").flags) do
			if IsValid(ent) then summary.flags[ent:GetName() ~= "" and ent:GetName() or tostring(ent:EntIndex())] = flag:State() end
		end
	end
	if WS.FeatureLoaded("aiwar") then
		local A = WS.Feature("aiwar")
		local count = { [WS.TEAM_RED] = 0, [WS.TEAM_BLUE] = 0 }
		if A.war then
			for ent, member in pairs(A.war.members) do
				if IsValid(ent) and ent:Health() > 0 then count[member.team] = (count[member.team] or 0) + 1 end
			end
		end
		summary.soldiers = {
			active = A:Active(),
			red = count[WS.TEAM_RED],
			blue = count[WS.TEAM_BLUE],
		}
	end
	return summary
end

-- Round trip ------------------------------------------------------------------------------

-- Paths whose difference after a round trip is a known limit (path -> why),
-- left out of the diff and listed in its result.
local KNOWN = {}
local IGNORED = {}
for path in pairs(KNOWN) do IGNORED[#IGNORED + 1] = path end

local POSITION_GRID = 1 -- units: a soldier made again stands where it stood, to the unit

-- A state to compare: a soldier made again is a new entity under a new key,
-- so soldiers compare as a sorted list of what they are, not by key.
function dev.comparable(state)
	local copy = table.Copy(state)
	local war = copy.sections and copy.sections.aiwar
	if war and war.soldiers then
		local list = {}
		for _, s in pairs(war.soldiers) do
			list[#list + 1] = string.format("%s team %d %s%s at %d %d %d hp %d", s.class, s.team, tostring(s.role),
				s.drafted and " drafted" or "", math.Round(s.pos.x / POSITION_GRID), math.Round(s.pos.y / POSITION_GRID),
				math.Round(s.pos.z / POSITION_GRID), s.health)
		end
		table.sort(list)
		war.soldiers = list
	end
	return copy
end

-- The differences between two states, as dev.comparable sees them.
function dev.diff(a, b)
	return Diff.Of(dev.comparable(a), dev.comparable(b), 1e-3, IGNORED)
end

-- capture -> apply -> capture -> diff, in one tick. ok is an empty diff and
-- an apply that resolved everything.
function dev.check_roundtrip()
	local first = dev.capture()
	local report = dev.apply(first)
	local second = dev.capture()
	local differences = dev.diff(first, second)
	return {
		ok = #differences == 0 and report.ok,
		differences = Diff.Text(differences),
		count = #differences,
		apply = report,
		known_limits = KNOWN,
	}
end

local SOLDIERS_TO_KILL = 3
local CART_PUSH_NODES = 3
local PLAYER_NUDGE = Vector(0, 0, 64)

local function Other(t) return t == WS.TEAM_RED and WS.TEAM_BLUE or WS.TEAM_RED end

-- One point given to the other side, chosen so that no team then owns them
-- all: owning them all is a real win, whose outputs and cleanup no restore
-- undoes. Returns the point, or nil when every flip would win.
local function FlipWithoutWin(C)
	local set = C:Set()
	local ids = set:Ids()
	for _, point in ipairs(ids) do
		if IsValid(point) then
			local to = Other(set:Owner(point))
			local owners = {}
			for _, other in ipairs(ids) do owners[other == point and to or set:Owner(other)] = true end
			if table.Count(owners) > 1 then
				C:ForceOwner(point, to)
				return point
			end
		end
	end
	return nil
end

-- The game knocked off its state in every section it has, so a restore has
-- something to do: points flipped and locked, the HUD timer halved, scores
-- and the red wave time changed, soldiers killed, players hurt, moved and
-- stripped of ammo. Returns what it did.
local function Disturb()
	local done = {}
	if WS.FeatureLoaded("capture") then
		local C = WS.Feature("capture")
		local flipped = FlipWithoutWin(C)
		if flipped then done[#done + 1] = "flipped " .. flipped:GetName() end
		for _, point in ipairs(C:Set():Ids()) do
			if IsValid(point) and point ~= flipped then
				C:SetPointLocked(point, true)
				done[#done + 1] = "locked " .. point:GetName()
				break
			end
		end
	end
	local rounds = dev.Rounds()
	local hud = rounds:HudTimer()
	if IsValid(hud) and not rounds.timers[hud]:Disabled() then
		rounds:TimerInput(hud, "settime", tostring(rounds.timers[hud]:TimeRemaining(CurTime()) / 2))
		done[#done + 1] = "halved the HUD timer"
	end
	for _, t in ipairs({ WS.TEAM_RED, WS.TEAM_BLUE }) do team.AddScore(t, 3) end
	rounds.round:SetTeamWaveTime(WS.TEAM_RED, 23)
	done[#done + 1] = "scores +3, red wave 23 s"
	if WS.FeatureLoaded("aiwar") and WS.Feature("aiwar").war then
		local killed = 0
		for ent in pairs(WS.Feature("aiwar").war.members) do
			if killed < SOLDIERS_TO_KILL and IsValid(ent) and ent:Health() > 0 then
				ent:TakeDamage(ent:Health() * 10, game.GetWorld(), game.GetWorld())
				killed = killed + 1
			end
		end
		done[#done + 1] = "killed " .. killed .. " soldiers"
	end
	if WS.FeatureLoaded("flag") then
		local F = WS.Feature("flag")
		for ent, flag in pairs(F.flags) do
			if IsValid(ent) and flag:State() ~= "carried" then
				for _, ply in ipairs(player.GetAll()) do
					if ply:Alive() and F:Give(ent, ply) then
						done[#done + 1] = ply:Nick() .. " took " .. dev.Describe(ent)
						break
					end
				end
			end
		end
	end
	for _, watcher in ipairs(ents.FindByClass(WATCHER)) do
		if watcher.pathIndex and watcher.nodes and IsValid(watcher.train) then
			local to = math.min(watcher.pathIndex + CART_PUSH_NODES, #watcher.nodes)
			if to ~= watcher.pathIndex then
				watcher:TeleportTo(to)
				done[#done + 1] = "pushed " .. dev.Describe(watcher) .. "'s cart to node " .. to
			end
		end
	end
	for _, ply in ipairs(player.GetAll()) do
		if ply:Alive() then
			ply:SetHealth(math.max(1, math.floor(ply:Health() / 2)))
			ply:SetPos(ply:GetPos() + PLAYER_NUDGE)
			ply:RemoveAllAmmo()
			done[#done + 1] = "hurt, moved and disarmed " .. ply:Nick()
		end
	end
	return done
end

-- The harder round trip: capture (through JSON, as a scenario file holds
-- it), disturb, apply, capture, diff. The saved state is applied a tick
-- after the disturbance, so deaths have happened. Asynchronous: returns at
-- once; the result is dev.last_check_restore, and printed.
function dev.check_restore()
	local saved = util.JSONToTable(util.TableToJSON(dev.capture()))
	local disturbed = Disturb()
	dev.last_check_restore = { pending = true }
	timer.Simple(0.2, function()
		local report = dev.apply(saved)
		local differences = dev.diff(saved, dev.capture())
		dev.last_check_restore = {
			ok = #differences == 0 and report.ok,
			disturbed = disturbed,
			count = #differences,
			differences = Diff.Text(differences),
			apply = report,
		}
		print("dev_check_restore: " .. (dev.last_check_restore.ok and "ok" or (#differences .. " differences")))
	end)
	return {
		pending = true,
		disturbed = disturbed,
		result = "dev.last_check_restore",
	}
end

dev.Command("dev_check_restore", function() return dev.check_restore() end, "capture, disturb, apply, diff (result in dev.last_check_restore)")
dev.Command("dev_state", function(args) return dev.state({ verbose = args[1] == "verbose" }) end, "dev_state [verbose]")
dev.Command("dev_check_roundtrip", function() return dev.check_roundtrip() end, "capture, apply, capture, diff")
