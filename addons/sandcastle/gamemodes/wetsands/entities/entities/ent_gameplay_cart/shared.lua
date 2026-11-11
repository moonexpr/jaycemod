-- The Trolley tool's cart: a team_train_watcher, its func_tracktrain, the capture
-- area that rides it, and the cart's prop.
local Model = WS.require ("features.builder.model")

ENT.Type = "anim"
ENT.Base = "base_gameplay_piece"
ENT.PrintName = "Trolley"
ENT.Kind = Model.CART
ENT.MarkerModel = "models/props_trainyard/bomb_cart.mdl"
ENT.OwnBox = true
ENT.TRAIN = "train"
ENT.Properties =
{
	{ name = "TeamNum", key = "teamnum", type = "Int", title = "Team (pushes the cart)", default = WS.TEAM_BLUE, values = { RED = WS.TEAM_RED, BLU = WS.TEAM_BLUE } },
	{ name = "StartDisabled", key = "startdisabled", type = "Bool", title = "Start Disabled", default = false },
	{ name = "CanRecede", key = "train_can_recede", type = "Bool", title = "Can the train recede?", default = true },
	{ name = "RecedeTime", key = "train_recede_time", type = "Int", title = "Train recede time (0: tf_escort_recede_time)", default = 0, min = 0, max = 300 },
	{ name = "ForwardModifier", key = "speed_forward_modifier", type = "Float", title = "Speed forward modifier", default = 1, min = 0, max = 1 },
	{ name = "HudLevel1", key = "hud_min_speed_level_1", type = "Float", title = "Min speed for HUD level 1", default = 30, min = 0, max = 1000 },
	{ name = "HudLevel2", key = "hud_min_speed_level_2", type = "Float", title = "Min speed for HUD level 2", default = 60, min = 0, max = 1000 },
	{ name = "HudLevel3", key = "hud_min_speed_level_3", type = "Float", title = "Min speed for HUD level 3", default = 90, min = 0, max = 1000 },
	{ name = "MaxSpeed", key = "startspeed", target = ENT.TRAIN, type = "Float", title = "Max Speed", category = "Train", default = 90, min = 1, max = 1000 },
	{ name = "AccelSpeed", key = "manualaccelspeed", target = ENT.TRAIN, type = "Float", title = "Manual Train Acceleration", category = "Train", default = 70, min = 1, max = 1000 },
	{ name = "DecelSpeed", key = "manualdecelspeed", target = ENT.TRAIN, type = "Float", title = "Manual Train Deceleration", category = "Train", default = 150, min = 1, max = 1000 },
	-- the model's origin stands this far above its wheels
	{ name = "Height", key = "height", target = ENT.TRAIN, type = "Float", title = "Height above track", category = "Train", default = 28, min = 0, max = 256 }
}
ENT.WirePorts = { inputs = { "Enabled", "CanRecede", "SpeedScale" }, outputs = { "Progress", "Speed", "Cappers", "Receding" } }
ENT.WireCommands =
{
	Enabled = Model.WireSwitch ("Enable", "Disable"),
	CanRecede = Model.WireValue ("SetTrainCanRecede"),
	SpeedScale = Model.WireValue ("SetSpeedForwardModifier")
}
