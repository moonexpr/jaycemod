--[[---------------------------------------------------------

  What a map provides

  An entity adds a controller as it spawns: { type, ent }, the
  game it belongs to and itself; it keeps its own state. Games
  name the types they require (GAME.Requires). A controller
  whose entity is gone drops out as the list is read.

-----------------------------------------------------------]]

local COUNT = "controllers."
local controllers = {}

function GM:AddController (controller)

	local kind = controller.type
	local list = controllers [kind]
	if not list then
		list = {}
		controllers [kind] = list
	end

	list [#list + 1] = controller
	SetGlobal2Int (COUNT .. kind, #list)
	hook.Run ("OnControllerAdded", controller)
	game_manager.RunActive ("ControllerAdded", controller)

	return controller

end

-- An entity's input, for the games being played. Whether one used it.
function GM:ControllerInput (ent, name, value, activator)

	local used = false
	for _, game in ipairs (game_manager.Active ()) do
		if game_manager.RunClass (game, "ControllerInput", ent, name, value, activator) then used = true end
	end

	return used

end

function GM:GetControllers (kind)

	local list = controllers [kind]
	if not list then return {} end

	local count = #list
	for i = count, 1, -1 do
		if not IsValid (list [i].ent) then table.remove (list, i) end
	end
	if #list ~= count then SetGlobal2Int (COUNT .. kind, #list) end

	return list

end

-- On both realms: many of these entities never reach the client.
function GM:HasController (kind)

	return GetGlobal2Int (COUNT .. kind, 0) > 0

end
