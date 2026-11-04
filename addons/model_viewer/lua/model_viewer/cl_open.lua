-- What opens the viewer: cl_model_viewer <model>, a model's icon in the spawn menu,
-- and the C menu's icon. One window, which the next model opened takes over.
local Catalog = model_viewer_catalog

-- text -> the path of a model this client has, or nil and why not. By its file:
-- on a client util.IsValidModel knows only a model already loaded.
function ModelViewer.Resolve(text)
	local path = Catalog.ModelPath(text)
	if not path then return nil, "Name a model: cl_model_viewer models/player/scout.mdl" end
	if not file.Exists(path, "GAME") then return nil, "No model at " .. path end
	return path
end

function ModelViewer.Open(text)
	local path, why = ModelViewer.Resolve(text)
	if not path then
		MsgN(why)
		return
	end
	if IsValid(ModelViewer.window) then
		ModelViewer.window:MoveToFront()
	else
		ModelViewer.window = vgui.Create("ModelViewerWindow")
		ModelViewer.window:MakePopup()
	end
	ModelViewer.window:Load(path)
end

concommand.Add("cl_model_viewer", function(_, _, _, text)
	ModelViewer.Open(text ~= "" and text or LocalPlayer():GetModel())
end, nil, "Open the model viewer on a model (your own if none is named)")

hook.Add("SpawnmenuIconMenuOpen", "model_viewer", function(menu, icon, contentType)
	if contentType ~= "model" then return end
	menu:AddOption("Model Viewer", function() ModelViewer.Open(icon:GetModelName()) end):SetIcon("icon16/film.png")
end)

-- The C menu makes each icon a window of its own, which closes with the menu.
-- The viewer's stays: the one it was given goes.
list.Set("DesktopWindows", "ModelViewer", {
	title = "Model Viewer",
	icon = "icon64/playermodel.png",
	width = 1,
	height = 1,
	init = function(_, window)
		window:Remove()
		ModelViewer.Open(LocalPlayer():GetModel())
	end,
})
