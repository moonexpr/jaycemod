-- base_gameplay_piece: a helper placed with the Gameplay tools, one class a kind.
-- A helper is a thing in the world that does its own work: its properties are
-- those of the Hammer entity it stands for, edited through the context menu's
-- Edit Properties and kept as network variables, so saves and dupes carry them;
-- it makes its game's entities (Compile), which a cleanup removes and it makes
-- again; and, outliving them, it is what wires connect to, with the ports its
-- class names where Wiremod is installed.
--
-- A class gives Kind, PrintName, MarkerModel, Properties (each { name, key
-- (Hammer's), target (of the entities it makes; its main one if nil), type,
-- title, category, default, values (a combo's), min, max, auto (a value setting
-- no key), help (Hammer's words, on the row's tooltip) }), WirePorts and
-- WireCommands.
local Model = WS.require ("features.builder.model")

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.Spawnable = false
ENT.Editable = true
ENT.Properties = {}
ENT.WirePorts = { inputs = {}, outputs = {} }
ENT.WireCommands = {}

local EDIT_TYPES = { Bool = "Boolean", Int = "Int", Float = "Float", String = "Generic" }
-- Help's width on its tooltip, in characters: a tooltip does not wrap its own.
local HELP_WIDTH = 60

function ENT:SetupDataTables ()
	self:NetworkVar ("Int", 0, "PieceId")
	self:NetworkVar ("Int", 1, "NodeId")
	self:NetworkVar ("String", 0, "BodyModel")
	self:NetworkVar ("Vector", 0, "BoxMins")
	self:NetworkVar ("Vector", 1, "BoxMaxs")
	self:NetworkVar ("Entity", 0, "NextNode")
	local slots = { Int = 2, String = 1, Bool = 0, Float = 0 }
	for order, prop in ipairs (self.Properties) do
		local netType = Model.NETWORK_TYPES [prop.type]
		local editType = prop.values and "Combo" or EDIT_TYPES [prop.type]
		self:NetworkVar (netType, slots [netType], prop.name,
			{
				KeyName = string.lower (prop.name),
				Edit =
				{
					type = prop.help and "Help" .. editType or editType,
					help = prop.help and Model.WrapHelp (prop.help, HELP_WIDTH),
					title = prop.title,
					category = prop.category or self.PrintName,
					min = prop.min,
					max = prop.max,
					values = prop.values,
					order = order
				}
			}
		)
		slots [netType] = slots [netType] + 1
		if SERVER then self:NetworkVarNotify (prop.name, self.OnPropertyEdited) end
	end
end

function ENT:CanEditVariables ()
	return GetGlobal2Bool ("ws_builder_available", false) and (not WS.Active () or WS.GameplayStopped ())
end
