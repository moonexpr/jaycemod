-- The helpers (base_gameplay_piece and its classes) under stubbed GMod
-- globals: their Hammer-named properties, edited through Sandbox's Edit
-- Properties and saved by its duplicator; Wiremod's ports where it is
-- installed, and no need of it where it is not. And the tools, whose every
-- click goes through the builder.
local T = dofile ("tests/harness.lua")
local Fake = dofile ("tests/fake_builder.lua")
local Builder = Fake.Builder
local Classes = Fake.classes

local ENTITIES = "addons/sandcastle/gamemodes/sandcastle/entities/"
local TOOLS = { "build_spawn", "build_trolley", "build_point", "build_flag", "build_sign" }

local function Load (path, global, value)
	local chunk = assert (loadfile (path))
	setfenv (chunk, setmetatable ({ [global] = value }, { __index = _G }))
	chunk ()
	return value
end

local function NewPiece (kind, fields)
	return Fake.Piece (1, kind, fields)
end

local compiled = {}
local builder = { compiled = compiled, Adopt = function (self, piece) self.adopted = piece end }
WS.Feature = function () return builder end

T.test ("every kind's helper is a folder entity on the base", function ()
	for _, kind in ipairs (Builder.KINDS) do
		local class = Classes [kind]
		T.eq (class.Base, "base_gameplay_piece", kind)
		T.eq (class.Kind, kind,                  kind .. "'s kind")
		for _, file in ipairs ({ "shared.lua", "init.lua", "cl_init.lua" }) do
			T.eq (assert (loadfile (ENTITIES .. "entities/" .. Builder.CLASSES [kind] .. "/" .. file)) ~= nil, true, file)
		end
	end
end)

T.test ("the base is editable, as Sandbox's editors are", function ()
	T.eq (Fake.base.Editable, true, "Edit Properties")
end)

T.test ("a helper declares its properties as edited network variables", function ()
	local piece = NewPiece (Builder.POINT)
	local declared = {}
	piece.NetworkVar = function (_, netType, slot, name, options)
		declared [name] = { netType = netType, slot = slot, options = options }
	end
	piece.NetworkVarNotify = function () end
	piece:SetupDataTables ()
	local seen = {}
	for _, prop in ipairs (Classes [Builder.POINT].Properties) do
		local var = declared [prop.name]
		T.eq (var ~= nil,             true,                              prop.name)
		T.eq (var.netType,            Builder.NETWORK_TYPES [prop.type], prop.name .. " type")
		T.eq (var.options.Edit.title, prop.title,                        prop.name .. " title")
		local slotKey = var.netType .. var.slot
		T.eq (seen [slotKey], nil, prop.name .. " has a slot of its own")
		seen [slotKey] = true
	end
	T.eq (declared.PieceId.options, nil, "its id is no property to edit")
end)

T.test ("a property with help has it on its row, wrapped, and a row type that shows it", function ()
	local piece = NewPiece (Builder.SCENARIO)
	local edits = {}
	piece.NetworkVar = function (_, _, _, name, options) edits [name] = options and options.Edit end
	piece.NetworkVarNotify = function () end
	piece:SetupDataTables ()
	T.eq (edits.CapLayout.type,                             "HelpGeneric", "a text field")
	T.eq (edits.ScoreStyle.type,                            "HelpCombo",   "a choice")
	T.eq (edits.SwitchTeams.type,                           "HelpBoolean", "a switch")
	T.eq (edits.TimerLength.type,                           "HelpInt",     "a whole number")
	T.eq (edits.PartialCapRate.type,                        "HelpFloat",   "a number")
	T.eq (edits.CapLayout.help:find ("\n", 1, true) ~= nil, true,          "wrapped")
end)

T.test ("a property without help keeps the plain row", function ()
	local piece = NewPiece (Builder.SPAWN)
	local edits = {}
	piece.NetworkVar = function (_, _, _, name, options) edits [name] = options and options.Edit end
	piece.NetworkVarNotify = function () end
	piece:SetupDataTables ()
	T.eq (edits.TeamNum.type,       "Combo",   "a choice")
	T.eq (edits.StartDisabled.type, "Boolean", "a switch")
end)

T.test ("a new helper takes its properties' defaults", function ()
	local piece, vars = NewPiece (Builder.POINT)
	vars.TimeToCap = 99
	piece:Initialize ()
	for _, prop in ipairs (Classes [Builder.POINT].Properties) do T.eq (vars [prop.name], prop.default, prop.name) end
end)

T.test ("a volume is given its box", function ()
	local piece, vars = NewPiece (Builder.ROOM)
	local mins, maxs = Vector (-1, -2, 0), Vector (1, 2, 3)
	piece:Configure (4, { mins = mins, maxs = maxs })
	T.eq (piece:Id (),  4,    "its id")
	T.eq (vars.BoxMins, mins, "mins")
	T.eq (vars.BoxMaxs, maxs, "maxs")
end)

T.test ("updating a helper sets the properties it is given and keeps the rest", function ()
	local piece, vars = NewPiece (Builder.FLAG)
	piece:Initialize ()
	local returnTime = vars.ReturnTime
	piece:Update ({ TeamNum = 3 })
	T.eq (vars.TeamNum,    3,          "the team")
	T.eq (vars.ReturnTime, returnTime, "what it was not given")
end)

T.test ("a helper shows its team, a control point its owner", function ()
	local flag, flagVars = NewPiece (Builder.FLAG, { team = 3 })
	flag:Settle ()
	T.eq (flagVars.Color.b, 255, "BLU's colour")
	local point, pointVars = NewPiece (Builder.POINT, { team = 2 })
	point:Settle ()
	T.eq (pointVars.Color.r, 255, "RED's colour")
end)

T.test ("a sign's model follows its properties, its skin too", function ()
	local sign, vars = NewPiece (Builder.SIGN, { props = { Arrow = "right", Small = true, SignSkin = 4 } })
	sign:Settle ()
	T.eq (vars.Model, "models/props_gameplay/sign_gameplay01_witharrow_r_sm.mdl", "the model")
	T.eq (vars.Skin,  4,                                                          "the skin")
end)

T.test ("a spawner shows the model picked, or the first", function ()
	local spawner, vars = NewPiece (Builder.SPAWN)
	spawner:Settle ()
	T.eq (vars.Model, Builder.SPAWN_MODELS [1], "the first")
	spawner:Update ({ BodyModel = Builder.SPAWN_MODELS [3] })
	T.eq (vars.Model, Builder.SPAWN_MODELS [3], "as picked")
end)

T.test ("properties may be edited only on a builder's map, outside a game", function ()
	local piece = NewPiece (Builder.SPAWN)
	WS.Active = function () return true end
	WS.GameplayStopped = function () return true end
	T.eq (piece:CanEditVariables (), true, "a stopped game")
	WS.GameplayStopped = function () return false end
	T.eq (piece:CanEditVariables (), false, "a running game")
	WS.GameplayStopped = function () return true end
	local available = GetGlobal2Bool
	GetGlobal2Bool = function () return false end
	T.eq (piece:CanEditVariables (), false, "a scenario's map")
	GetGlobal2Bool = available
end)

T.test ("the duplicator knows every class, and hands the paste to the builder", function ()
	for _, kind in ipairs (Builder.KINDS) do T.eq (Fake.registered [Builder.CLASSES [kind]], true, kind) end
	local piece = NewPiece (Builder.SPAWN)
	piece:OnDuplicated ({ nodeIndex = 12 })
	T.eq (builder.adopted,      piece, "adopted")
	T.eq (piece.savedNodeIndex, 12,    "its node's old index kept for the paste's end")
end)

T.test ("a pasted helper finds its node among what was pasted", function ()
	local node = Fake.Piece (31, Builder.NODE)
	local helper, vars = NewPiece (Builder.POINT)
	helper.savedNodeIndex = 12
	local deleted
	node.DeleteOnRemove = function (_, ent) deleted = ent end
	helper:PostEntityPaste (nil, helper, { [12] = node })
	T.eq (vars.NodeId,             31,     "its node's id now")
	T.eq (rawget (node, "helper"), helper, "the node knows it")
	T.eq (deleted,                 helper, "and takes it along when removed")
end)

T.test ("copying leaves out what cannot be saved, and notes a helper's node", function ()
	local node = NewPiece (Builder.NODE)
	node.EntIndex = function () return 12 end
	local helper = NewPiece (Builder.POINT)
	helper.nodeEnt = node
	helper:PreEntityCopy ()
	T.eq (helper.nodeIndex, 12, "by its entity index, as the duplicator keys them")
	local data = { Inputs = {}, Outputs = {}, nodeEnt = node, helper = node }
	helper:OnEntityCopyTableFinish (data)
	T.eq (data.Inputs,  nil, "wire's inputs")
	T.eq (data.Outputs, nil, "wire's outputs")
	T.eq (data.nodeEnt, nil, "an entity")
	T.eq (data.helper,  nil, "an entity")
end)

T.test ("wires are saved, and restored with what was pasted", function ()
	local stored, applied = {}, nil
	duplicator.ClearEntityModifier = function () end
	duplicator.StoreEntityModifier = function (_, name, info) stored [name] = info end
	WireLib =
	{
		BuildDupeInfo = function () return "links" end,
		ApplyDupeInfo = function (_, ent, info, lookup) applied = { ent = ent, info = info, lookup = lookup } end
	}
	local piece = NewPiece (Builder.POINT)
	piece:PreEntityCopy ()
	T.eq (stored.WireDupeInfo, "links", "stored")
	piece.EntityMods = { WireDupeInfo = "links" }
	piece:PostEntityPaste ("ply", piece, { [5] = "five" })
	T.eq (applied.info,               "links", "applied")
	T.eq (applied.lookup (5),         "five",  "found among those pasted")
	T.eq (applied.lookup (6, "none"), "none",  "or the default")
	WireLib = nil
end)

T.test ("with Wiremod a helper has its class's ports", function ()
	local created = {}
	WireLib =
	{
		CreateInputs = function (_, names) created.inputs = names return "in" end,
		CreateOutputs = function (_, names) created.outputs = names return "out" end
	}
	local piece = NewPiece (Builder.POINT)
	piece:Initialize ()
	T.eq (created.inputs,            Classes [Builder.POINT].WirePorts.inputs,  "inputs")
	T.eq (created.outputs,           Classes [Builder.POINT].WirePorts.outputs, "outputs")
	T.eq (rawget (piece, "Inputs"),  "in",                                      "held where the wire tool looks")
	T.eq (rawget (piece, "Outputs"), "out",                                     "held where the wire tool looks")
	WireLib = nil
end)

T.test ("an input fires at the entity its game has for it", function ()
	local fired = {}
	local piece = NewPiece (Builder.FLAG)
	compiled [piece:CompiledName ()] = { Fire = function (_, input, param) fired [#fired + 1] = { input, param } end }
	piece:TriggerInput ("Team", 3)
	T.eq (fired [1] [1], "SetTeam", "the input")
	T.eq (fired [1] [2], "3",       "the value")
	piece:TriggerInput ("Reset", 0)
	T.eq (#fired, 1, "a pulse's off asks nothing")
	compiled [piece:CompiledName ()] = nil
end)

T.test ("an input with no game does nothing", function ()
	NewPiece (Builder.FLAG):TriggerInput ("Team", 3)
end)

T.test ("a sign's inputs act on the sign", function ()
	local sign, vars = NewPiece (Builder.SIGN)
	sign:TriggerInput ("Skin", 4)
	T.eq (vars.Skin, 4, "its skin")
	sign:TriggerInput ("Visible", 0)
	T.eq (vars.NoDraw, true, "hidden")
end)

T.test ("the scenario's inputs go to the gamerules", function ()
	local fired
	WS.Rules = { Fire = function (_, input, param) fired = { input, param } end }
	NewPiece (Builder.SCENARIO):TriggerInput ("RedRespawnTime", 6)
	T.eq (fired [1], "SetRedTeamRespawnWaveTime", "the input")
	T.eq (fired [2], "6",                         "the value")
	WS.Rules = nil
end)

T.test ("the entity's values reach the outputs", function ()
	local told, nextThink = {}, nil
	WireLib = { TriggerOutput = function (_, port, value) told [port] = value end }
	local piece = NewPiece (Builder.POINT)
	compiled [piece:CompiledName ()] = {}
	piece.WireStatus = function () return { Owner = 3 } end
	piece.NextThink = function (_, at) nextThink = at end
	T.eq (piece:Think (),   true,     "thinks on")
	T.eq (told.Owner,       3,        "told")
	T.eq (type (nextThink), "number", "its next think")
	compiled [piece:CompiledName ()] = nil
	WireLib = nil
end)

T.test ("without Wiremod a helper makes no ports and asks nothing", function ()
	WireLib = nil
	local piece = NewPiece (Builder.SPAWN)
	piece:Initialize ()
	T.eq (rawget (piece, "Inputs"), nil, "no inputs")
	T.eq (piece:Think (),           nil, "no think")
	piece:PreEntityCopy ()
	piece:OnRemove ()
end)

T.test ("removing a wired helper tells Wiremod", function ()
	local removed
	WireLib = { Remove = function (ent) removed = ent end }
	local piece = NewPiece (Builder.ZONE)
	piece:OnRemove ()
	T.eq (removed, piece, "told")
	WireLib = nil
end)

T.test ("in a game a helper goes, a track stays underfoot, a sign stands", function ()
	local flag, vars = NewPiece (Builder.FLAG)
	flag:SetInGame (true)
	T.eq (vars.NoDraw,   true, "hidden")
	T.eq (vars.NotSolid, true, "stops no bullet")
	local node, nodeVars = NewPiece (Builder.NODE)
	node:SetInGame (true)
	T.eq (nodeVars.NoDraw,   nil,  "its rails show")
	T.eq (nodeVars.NotSolid, true, "stops no bullet")
	local sign, signVars = NewPiece (Builder.SIGN)
	sign:SetInGame (true)
	T.eq (signVars.NoDraw,   nil, "a sign shows")
	T.eq (signVars.NotSolid, nil, "a sign stands")
end)

T.test ("every tool is in the Gameplay category and clicks through the builder", function ()
	for _, name in ipairs (TOOLS) do
		local calls = {}
		local feature = WS.Feature
		WS.Feature = function (asked)
			T.eq (asked, "builder", name .. " asks the builder")
			return { Do = function (_, method) calls [#calls + 1] = method return true end }
		end
		local TOOL =
		{
			GetOwner = function () return "player" end,
			GetClientNumber = function () return 2 end,
			GetClientInfo = function () return "left" end
		}
		Load (ENTITIES .. "weapons/gmod_tool/stools/" .. name .. ".lua", "TOOL", TOOL)
		T.eq (TOOL.Category,           "Gameplay", name .. " category")
		T.eq (TOOL:LeftClick ({}),     true,       name .. " left")
		T.eq (TOOL:RightClick ({}),    true,       name .. " right")
		T.eq (TOOL:Reload ({}),        true,       name .. " reload")
		T.eq (#calls,                  3,          name .. " three actions")
		T.eq (type (TOOL.BuildCPanel), "function", name .. " panel")
		WS.Feature = feature
	end
end)

T.test ("each tool's action is one the builder or the helper's class has", function ()
	local source = assert (io.open ("addons/sandcastle/gamemodes/sandcastle/gamemode/features/builder/sv.lua")):read ("*a")
	for _, name in ipairs (TOOLS) do
		local text = assert (io.open (ENTITIES .. "weapons/gmod_tool/stools/" .. name .. ".lua")):read ("*a")
		for method in text:gmatch ('Run%s*%(self, "(%w+)"') do
			T.eq (source:find ("function Controller:" .. method .. "%s*%(") ~= nil, true, name .. " uses " .. method)
		end
		for kind, action in text:gmatch ('Run%s*%(self, "Act", Builder%.(%u+), "(%w+)"') do
			T.eq (type (Classes [Builder [kind]] [action]), "function", name .. " acts " .. action)
		end
	end
end)

T.finish ()
