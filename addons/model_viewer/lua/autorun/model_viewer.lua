-- Model Viewer: a client's window on a model, to click through its acts and watch
-- each animation. cl_model_viewer <model> opens it, and so does a model's right-click
-- menu in the spawn menu, or the C menu's icon. Any gamemode (the two menus are
-- Sandbox's). model_viewer_catalog holds what it shows and how it plays, as values;
-- cl_stage the model, cl_window the window, cl_open what opens it.
AddCSLuaFile ()

local MODULE = "includes/modules/model_viewer_catalog.lua"
local CLIENT_FILES = { "model_viewer/cl_stage.lua", "model_viewer/cl_window.lua", "model_viewer/cl_open.lua" }

if SERVER then
	AddCSLuaFile (MODULE)
	for _, path in ipairs (CLIENT_FILES) do AddCSLuaFile (path) end
	return
end

ModelViewer = ModelViewer or {}
require ("model_viewer_catalog")
for _, path in ipairs (CLIENT_FILES) do include (path) end
