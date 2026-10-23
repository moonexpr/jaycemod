-- TF2's own copies of the files HL2 hides under the same paths (GMod
-- searches HL2's content first), read from this client's own tf mount,
-- packed into an addon archive (foundation.encoding.gma) under data/ and
-- mounted, so what names them plays or draws TF2's from under
-- ws.sound_paths' RELOCATED. Nothing comes from the server. An archive is
-- named by its files' paths and sizes, so a client writes each once.
--   Sounds: the footsteps and the rest WS.HiddenTFSounds lists
--     (ws/sh_soundscripts.lua), once.
--   Textures: on each map, the textures its world's TF2 materials name
--     (ws.tf_materials): a material HL2 hides gets all of TF2's textures,
--     shader flags and drawing values, any texture HL2 hides comes from its
--     copy. A map's patched materials
--     (its cubemaps') take those of the material they include.
local Gma = encoding.gma
local SoundPaths = WS.require("ws.sound_paths")
local Materials = WS.require("ws.tf_materials")

local DIR = "sandcastle"

-- Whether HL2 hides tf's file at path (file.Size answers 0 for none; copies
-- of a size alike are taken for the same file).
local function Hidden(path)
	local own = file.Size(path, "tf")
	return own > 0 and file.Size(path, "GAME") ~= own
end

-- Packs and mounts tf's files at paths (game paths, "sound/..." or
-- "materials/..."), each under RELOCATED in its own root folder, in an
-- archive named for kind.
local function MountCopies(kind, paths)
	if #paths == 0 then return end
	table.sort(paths)
	local listing = {}
	for i, path in ipairs(paths) do listing[i] = path .. ":" .. file.Size(path, "tf") end
	local stored = DIR .. "/tf_" .. kind .. "_" .. util.CRC(table.concat(listing, "\n")) .. ".dat"
	if not file.Exists(stored, "DATA") then
		local files = {}
		for i, path in ipairs(paths) do
			local root, rest = string.match(path, "^([^/]+)/(.*)$")
			files[i] = { path = root .. "/" .. SoundPaths.RELOCATED .. rest, data = file.Read(path, "tf") }
		end
		file.CreateDir(DIR)
		file.Write(stored, Gma.Write("Sandcastle: TF2's own " .. kind, files))
	end
	if not game.MountGMA("data/" .. stored) then error("could not mount TF2's own " .. kind .. " from data/" .. stored) end
end

local sounds = {}
for name in pairs(WS.HiddenTFSounds) do sounds[#sounds + 1] = "sound/" .. name end
MountCopies("sounds", sounds)

-- The TF2 material a world material draws as: itself, or for a map's
-- patched one, the material it includes; nil for one TF2 lacks.
local function TFMaterial(name)
	if not string.find(name, "^maps/") then return name end
	local patch = file.Read("materials/" .. name .. ".vmt", "GAME")
	return patch and Materials.Included(util.KeyValuesToTable(patch))
end

local function ApplyMaterials()
	local plans, copies, seen = {}, {}, {}
	for _, name in ipairs(game.GetWorld():GetMaterials()) do
		local base = TFMaterial(name)
		local text = base and file.Read("materials/" .. base .. ".vmt", "tf")
		if text then
			local plan = Materials.Plan(util.KeyValuesToTable(text), Hidden("materials/" .. base .. ".vmt"),
				function(texture) return Hidden("materials/" .. texture .. ".vtf") end)
			if next(plan.textures) or plan.flags then plans[name] = plan end
			for _, texture in ipairs(plan.copies) do
				if not seen[texture] then
					seen[texture] = true
					copies[#copies + 1] = "materials/" .. texture .. ".vtf"
				end
			end
		end
	end
	MountCopies("textures_" .. game.GetMap(), copies)
	for name, plan in pairs(plans) do
		local material = Material(name)
		for param, texture in pairs(plan.textures) do material:SetTexture(param, texture) end
		if plan.flags then material:SetInt("$flags", Materials.Flags(material:GetInt("$flags"), plan.flags)) end
		for param, value in pairs(plan.values or {}) do
			if istable(value) then material:SetVector(param, Vector(value[1], value[2], value[3])) else material:SetFloat(param, value) end
		end
		material:Recompute()
	end
end

hook.Add("InitPostEntity", "ws_tf_content", ApplyMaterials)
-- a Lua refresh after the map has loaded
if IsValid(LocalPlayer()) then ApplyMaterials() end
