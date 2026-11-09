-- The Signage tool's sign: TF2's gameplay sign, pointing the way to the objective.
-- It is its own prop, and stands through the game.
local Model = WS.require("features.builder.model")

ENT.Type = "anim"
ENT.Base = "base_gameplay_piece"
ENT.PrintName = "Sign"
ENT.Kind = Model.SIGN
ENT.OwnBox = true
ENT.ARROW_LEFT, ENT.ARROW_RIGHT, ENT.ARROW_NONE = "left", "right", "none"
-- sign_gameplay01's skins.
ENT.SKINS = 12
ENT.Properties = {
	{ name = "Arrow", type = "String", title = "Arrow", default = ENT.ARROW_LEFT, values = { Left = ENT.ARROW_LEFT, Right = ENT.ARROW_RIGHT, None = ENT.ARROW_NONE } },
	{ name = "Small", type = "Bool", title = "Small", default = false },
	{ name = "SignSkin", type = "Int", title = "Skin", default = 0, min = 0, max = ENT.SKINS - 1 },
}
ENT.WirePorts = { inputs = { "Visible", "Skin" }, outputs = {} }
ENT.WireCommands = { Visible = Model.WireOwn("SetVisible"), Skin = Model.WireOwn("SetSkin") }
