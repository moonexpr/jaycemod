-- control_point on the server: the engine's team_control_point given its
-- behaviour: its state from the map's keyvalues, its inputs, its timed
-- unlock, its outputs, its model and its sounds, with nothing above it.
local T = dofile ("tests/harness.lua")

local SOURCE = "addons/sandcastle/gamemodes/sandcastle/gamemode/control_point.lua"
local NOBODY, RED, BLUE = TF_TEAM_UNASSIGNED, TEAM_RED, TEAM_BLUE

local function Entity (class, kv)
	local ent = { class = class, valid = true, kv = kv or {}, emitted = {}, bodygroups = {} }
	function ent:GetClass () return self.class end
	function ent:IsPlayer () return self.class == "player" end
	function ent:IsMarkedForDeletion () return false end
	function ent:GetModel () return self.model end
	function ent:SetModel (model) self.model = model end
	function ent:SetSkin (skin) self.skin = skin end
	function ent:SetBodygroup (group, value) self.bodygroups [group] = value end
	function ent:SetNoDraw (hidden) self.hidden = hidden end
	function ent:EmitSound (sound) self.emitted [#self.emitted + 1] = sound end
	return ent
end

-- A server with the points given, and what they did to it.
local function Server (points)
	local server = { now = 100, hooks = {}, outputs = {}, events = {}, scores = {}, controllers = {}, rules = {} }
	local env
	env = setmetatable (
		{
			SERVER = true,
			control_point = {},
			CurTime = function () return server.now end,
			IsValid = function (ent) return ent ~= nil and ent.valid == true end,
			ents = { FindByClass = function () return points end },
			util = { IsValidModel = function () return true end },
			RecipientFilter = function ()
				return { AddAllPlayers = function () end, AddRecipientsByTeam = function () end }
			end,
			map_io =
			{
				Record = function (class) server.recorded = class end,
				KeyValues = function (ent) return ent.kv end,
				FireOutput = function (ent, name) server.outputs [#server.outputs + 1] = name end
			},
			game_manager =
			{
				Enable = function (name) server.enabled = name end,
				GetCurrentScenario = function () return { GetRules = function () return server.rules end } end
			},
			round_manager = { AddTeamScore = function (info) server.scores [#server.scores + 1] = info end },
			GAMEMODE = { AddController = function (_, c) server.controllers [#server.controllers + 1] = c end },
			hook =
			{
				Add = function (event, id, fn) server.hooks [event] = fn end,
				Run = function (event, ent, e)
					if event == "ControlPointEvent" then server.events [#server.events + 1] = e end
				end
			}
		}, { __index = _G })
	setfenv (assert (loadfile (SOURCE)), env) ()
	server.lib = env.control_point
	function server:Input (ent, name, value, caller)
		return self.hooks.AcceptInput (ent, name, nil, caller, value)
	end
	function server:Outputs ()
		local fired = table.concat (self.outputs, ",")
		self.outputs = {}
		return fired
	end
	return server
end

local function Point (kv) return Entity ("team_control_point", kv) end

T.test ("a point's state is made once from what the map set on it, and the map is told it has a point", function ()
	local ent = Point (
		{
			point_index = "2",
			point_default_owner = "3",
			point_start_locked = "1",
			point_printname = "the Bridge",
			point_capture_start_sound = "My.Start",
			team_capsound_2 = "Cap.Red",
			team_icon_3 = "my/icon"
		}
	)
	local server = Server ({ ent })
	local p = server.lib.Of (ent)
	T.eq (server.recorded,             "team_control_point", "the engine class is recorded")
	T.eq (p.id,                        ent,                  "the entity's")
	T.eq (p.index,                     2,                    "its index")
	T.eq (p.owner,                     BLUE,                 "its default owner")
	T.eq (p.locked,                    true,                 "locked")
	T.eq (p.printName,                 "the Bridge",         "its name")
	T.eq (p.sounds.start,              "My.Start",           "its sound")
	T.eq (p.capSounds [RED],           "Cap.Red",            "RED's capture sound")
	T.eq (p.icons [BLUE],              "my/icon",            "BLU's icon")
	T.eq (server.lib.Of (ent),         p,                    "once")
	T.eq (#server.controllers,         1,                    "one controller")
	T.eq (server.controllers [1].type, "control_point",      "a control point's")
	T.eq (server.controllers [1].ent,  ent,                  "this one's")
	T.eq (ent.skin,                    1,                    "BLU's skin")
	T.eq (ent.bodygroups [0],          BLUE,                 "BLU's hologram")
end)

T.test ("a point the map set nothing on stands as nobody's, with the default hologram", function ()
	local ent = Point ()
	local server = Server ({ ent })
	T.eq (server.lib.Of (ent).owner, NOBODY,                                 "nobody's")
	T.eq (ent.model,                 "models/effects/cappoint_hologram.mdl", "the hologram")
	T.eq (ent.skin,                  2,                                      "the neutral skin")
end)

T.test ("SetOwner from a player captures it: its sound, its model, its outputs, then everyone else is told", function ()
	local ent = Point ({ team_capsound_2 = "Cap.Red", team_model_2 = "models/red.mdl" })
	local server = Server ({ ent })
	local player = Entity ("player")
	T.eq (server:Input (ent, "SetOwner", "2", player), true, "the point's input")
	T.eq (server.lib.Of (ent).owner,                   RED, "RED's")
	T.eq (ent.emitted [1],                             "Cap.Red", "its capture sound, from the point")
	T.eq (ent.model,                                   "models/red.mdl", "RED's model")
	T.eq (ent.skin,                                    0, "RED's skin")
	T.eq (server:Outputs (),                           "OnCapTeam1,OnOwnerChangedToTeam1", "its outputs")
	T.eq (#server.events,                              1, "one event told")
	T.eq (server.events [1].kind,                      "owner", "a change of owner")
	T.eq (server.events [1].team,                      RED, "to RED")
	T.eq (server.scores [1].event,                     "control_point_capture", "reported to the round")
	T.eq (server.scores [1].team,                      RED, "for RED")
	T.eq (server.scores [1].score,                     0, "scoring nothing itself")
end)

T.test ("SetOwner from the map is silent, and one back to nobody resets it", function ()
	local ent = Point ({ team_capsound_2 = "Cap.Red" })
	local server = Server ({ ent })
	server:Input (ent, "setowner", "2", Entity ("logic_relay"))
	T.eq (#ent.emitted,      0,            "no sound")
	T.eq (server:Outputs (), "OnCapTeam1", "captured, the owner's change unannounced")
	server:Input (ent, "SetOwner", "0", Entity ("logic_relay"))
	T.eq (server:Outputs (), "OnCapReset", "reset")
	T.eq (#server.scores,    1,            "a reset is no one's capture")
end)

T.test ("no capture while the scenario says points may not be captured, but a forced owner", function ()
	local ent = Point ()
	local server = Server ({ ent })
	server.rules = { PointsMayBeCaptured = false }
	server:Input (ent, "SetOwner", "2", Entity ("player"))
	T.eq (server.lib.Of (ent).owner, NOBODY, "refused")
	T.eq (server:Outputs (),         "",     "nothing fired")
	server.lib.SetOwner (ent, RED, server.lib.CAUSE_CAPTURE, { "Ann" })
	T.eq (server.lib.Of (ent).owner, NOBODY, "a capture too")
	server.lib.ForceOwner (ent, RED)
	T.eq (server.lib.Of (ent).owner, RED,          "forced")
	T.eq (server:Outputs (),         "OnCapTeam1", "its output")
	T.eq (#server.scores,            0,            "unscored")
end)

T.test ("a capture names its cappers to whoever listens", function ()
	local ent = Point ()
	local server = Server ({ ent })
	server.lib.SetOwner (ent, BLUE, server.lib.CAUSE_CAPTURE, { "Ann", "Bob" })
	T.eq (server.events [1].cappers [2], "Bob",                              "the cappers")
	T.eq (server:Outputs (),             "OnCapTeam2,OnOwnerChangedToTeam2", "BLU's outputs")
end)

T.test ("a locked point unlocks at its time, by its own think, once the scenario lets points unlock", function ()
	local ent = Point ({ point_start_locked = "1" })
	local server = Server ({ ent })
	server:Input (ent, "SetUnlockTime", "10")
	T.eq (server.lib.Of (ent).unlockAt, 110, "in ten seconds")
	server.now = 111
	server.rules = { PointsUnlock = false }
	server.hooks.Think ()
	T.eq (server.lib.Of (ent).locked, true, "not while the round is not running")
	server.rules = {}
	server.now = 112
	server.hooks.Think ()
	T.eq (server.lib.Of (ent).locked, false,        "unlocked")
	T.eq (server:Outputs (),          "OnUnlocked", "its output")
end)

T.test ("the lock, the model and the round's start are the point's inputs; any other is the engine's", function ()
	local ent = Point ({ point_default_owner = "2" })
	local server = Server ({ ent })
	server:Input (ent, "SetLocked", "1")
	T.eq (server.lib.Of (ent).locked, true, "locked")
	server:Input (ent, "SetLocked", "0")
	T.eq (server:Outputs (), "OnUnlocked", "unlocked")
	server:Input (ent, "HideModel")
	T.eq (ent.hidden, true, "hidden")
	server:Input (ent, "ShowModel")
	T.eq (ent.hidden, false, "shown")
	server:Input (ent, "RoundActivate")
	T.eq (server:Outputs (), "OnRoundStartOwnedByTeam1,OnUnlocked", "the round's start")
	T.eq (server:Input (ent, "Kill"), nil, "Kill is the engine's")
	T.eq (server:Input (Entity ("func_door"), "SetOwner", "2"), nil, "another class's input is not ours")
end)

T.test ("a point with its model hidden by spawnflag stays hidden", function ()
	local ent = Point ({ spawnflags = "2" })
	local server = Server ({ ent })
	server.lib.Of (ent)
	T.eq (ent.hidden, true, "hidden")
end)

T.test ("a capture starting is told, with the lines those not capping hear", function ()
	local ent = Point ({ point_default_owner = "2" })
	local server = Server ({ ent })
	server.lib.CaptureStarted (ent, BLUE)
	T.eq (server.events [1].kind,            "capture_started",    "told")
	T.eq (server.events [1].team,            BLUE,                 "who caps")
	T.eq (server.events [1].lines [1].sound, server.lib.CONTESTED, "contested")
end)

T.test ("a map cleaned up under it: the new point starts as the map set it", function ()
	local old = Point ()
	local points = { old }
	local server = Server (points)
	server.lib.ForceOwner (old, RED)
	old.valid = false
	local new = Point ()
	points [1] = new
	server.hooks.Think ()
	T.eq (server.lib.Of (new).owner, NOBODY, "nobody's again")
	T.eq (#server.controllers,       2,      "its own controller")
end)

T.finish ()
