AddCSLuaFile ("shared.lua")
AddCSLuaFile ("cl_init.lua")
include ("shared.lua")

local Model = WS.require ("features.builder.model")

local TRAIN_NAME, WATCHER_NAME, PROP_NAME = "build_train", "build_watcher", "build_cart_prop"
local NO_USER_CONTROL = "2"
local WHEELS = "50"
-- prop_dynamic's solid keyvalue: none, as the train is what collides.
local SOLID_NONE = "0"
local AREA_MINS, AREA_MAXS = Vector (-100, -100, 0), Vector (100, 100, 128)
-- The area is what counts pushers: the cart, not a timer, reaches a point.
local AREA_CAP_TIME = "99999"

function ENT:CompiledName ()
	return WATCHER_NAME
end

function ENT:Compile (game)
	local track = game.track
	if not track then
		game:ProblemOnce ("The track needs at least 2 nodes")
		return
	end
	local first, pusher = track.nodes [1], track.pusher
	local pos = first:GetPos ()
	local train = self:Keys (self.TRAIN)
	train.target = first:CompiledName ()
	train.speed = "0"
	train.spawnflags = NO_USER_CONTROL
	train.wheels = WHEELS
	train.orientationtype = "1"
	train.velocitytype = "2"
	game:Add ({ class = "func_tracktrain", name = TRAIN_NAME, pos = pos, model = self.MarkerModel, hidden = true, keys = train })
	game:Add ({ class = "prop_dynamic", name = PROP_NAME, pos = pos, model = self.MarkerModel, parent = TRAIN_NAME, onParent = true, keys = { solid = SOLID_NONE } })
	game:Add (
		{
			class = "trigger_capture_area",
			name = Model.CART_AREA_NAME,
			pos = pos,
			parent = TRAIN_NAME,
			mins = AREA_MINS,
			maxs = AREA_MAXS,
			keys =
			{
				area_cap_point = track.pointOf [track.checkpoints [1]],
				area_time_to_cap = AREA_CAP_TIME,
				team_cancap_2 = pusher == WS.TEAM_RED and "1" or "0",
				team_cancap_3 = pusher == WS.TEAM_BLUE and "1" or "0"
			}
		}
	)
	local watcher = self:Keys ()
	watcher.train = TRAIN_NAME
	watcher.start_node = first:CompiledName ()
	watcher.goal_node = track.nodes [#track.nodes]:CompiledName ()
	watcher.handle_train_movement = "1"
	for i, node in ipairs (track.checkpoints) do
		watcher ["linked_pathtrack_" .. i] = node:CompiledName ()
		watcher ["linked_cp_" .. i] = track.pointOf [node]
	end
	game:Add ({ class = "team_train_watcher", name = WATCHER_NAME, pos = pos, keys = watcher })
end

function ENT:WireStatus (watcher)
	if not watcher:IsActive () then return {} end
	local hud = watcher:HudState ()
	return
	{
		Progress = hud.progress,
		Speed = hud.speed,
		Cappers = hud.cappers,
		Receding = watcher.receding and 1 or 0
	}
end
