-- Team Tint's debug tools: the views (teamtint_view; the materials' part is
-- teamtint_tuning's MaterialParams, the rest is here), the overlay
-- labelling each body, the census of what the war's materials carry, the
-- export of the tuning, and the $softwareskin bench.
local Tuning, Catalog = TeamTint.Tuning, TeamTint.Catalog

-- Views ---------------------------------------------------------------------------

local function Flags() return Tuning.ViewFlags(TeamTint.VIEW:GetInt()) end

hook.Add("PreRender", "teamtint_view", function()
	if Flags().fullbright then render.SetLightingMode(1) end
end)

-- unlit drawing must end before the HUD, or the HUD draws unlit too
local function Relight()
	if Flags().fullbright then render.SetLightingMode(0) end
end
hook.Add("PreDrawHUD", "teamtint_view", Relight)
hook.Add("PostRender", "teamtint_view", Relight)

local GREYSCALE = {
	["$pp_colour_addr"] = 0, ["$pp_colour_addg"] = 0, ["$pp_colour_addb"] = 0,
	["$pp_colour_brightness"] = 0, ["$pp_colour_contrast"] = 1, ["$pp_colour_colour"] = 0,
	["$pp_colour_mulr"] = 0, ["$pp_colour_mulg"] = 0, ["$pp_colour_mulb"] = 0,
}

hook.Add("RenderScreenspaceEffects", "teamtint_view", function()
	if Flags().greyscale then DrawColorModify(GREYSCALE) end
end)

-- Overlay -------------------------------------------------------------------------

-- Bodies further than this are not labelled.
local OVERLAY_RANGE = 2000
local REP_COLORS = { red = Color(255, 110, 110), blu = Color(120, 180, 255), original = Color(220, 220, 220) }
local MISS = Color(255, 80, 80)
local DIM = Color(200, 200, 200)

local function Short(path)
	return string.match(path, "[^/\\]*$") or path
end

hook.Add("HUDPaint", "teamtint_overlay", function()
	if not TeamTint.OVERLAY:GetBool() then return end
	local eye = LocalPlayer():EyePos()
	for _, ent in ipairs(ents.GetAll()) do
		local report = IsValid(ent) and ent.TeamTintReport
		if report and ent:GetPos():Distance(eye) < OVERLAY_RANGE then
			local screen = ent:LocalToWorld(ent:OBBCenter()):ToScreen()
			if screen.visible then
				local x, y = screen.x, screen.y
				draw.SimpleTextOutlined(string.format("%s (%s)", string.upper(report.rep), report.source), "DermaDefaultBold",
					x, y, REP_COLORS[report.rep] or DIM, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 1, color_black)
				for _, m in ipairs(report.materials) do
					y = y + 13
					local text, color
					if m.entry then
						local unbaked = m.entry.strategy == Catalog.SHADE and Catalog.CLASSES[m.entry.class].tint
						text = string.format("%s: %s %s%s", Short(m.path), m.entry.class, m.entry.strategy, unbaked and " (unbaked)" or "")
						color = unbaked and MISS or DIM
					elseif m.rule then
						text, color = Short(m.path) .. ": " .. m.rule.class .. " left alone", DIM
					else
						text, color = Short(m.path) .. ": not in the catalog", MISS
					end
					draw.SimpleTextOutlined(text, "DermaDefault", x, y, color, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 1, color_black)
				end
			end
		end
	end
end)

-- Census --------------------------------------------------------------------------

-- The AI war's bodies, and HL2's NPCs that share their sheets.
TeamTint.CENSUS_MODELS = {
	"models/player/combine_soldier.mdl", "models/player/combine_soldier_prisonguard.mdl", "models/player/police.mdl",
	"models/player/group03/male_01.mdl", "models/player/group03/male_07.mdl", "models/player/group03/female_01.mdl",
	"models/player/alyx.mdl", "models/player/barney.mdl", "models/vortigaunt.mdl",
	"models/combine_soldier.mdl", "models/combine_soldier_prisonguard.mdl", "models/police.mdl",
	"models/humans/group03/male_01.mdl", "models/humans/group03/female_01.mdl", "models/alyx.mdl", "models/barney.mdl",
}

local function VmtText(path)
	return string.lower(file.Read("materials/" .. path .. ".vmt", "GAME") or "")
end

local function Has(text, word) return string.find(text, word, 1, true) ~= nil end

-- Per material the models use: who uses it, its shader, and the facts the
-- catalog's strategy turns on; to the console and data/teamtint/census.txt.
concommand.Add("teamtint_census", function()
	local users, order = {}, {}
	for _, model in ipairs(TeamTint.CENSUS_MODELS) do
		if util.IsValidModel(model) then
			local ent = ClientsideModel(model)
			if IsValid(ent) then
				for _, path in ipairs(ent:GetMaterials()) do
					if not users[path] then
						users[path] = {}
						order[#order + 1] = path
					end
					table.insert(users[path], model)
				end
				ent:Remove()
			end
		end
	end
	table.sort(order)
	local lines = { "# teamtint_census: material | shader | class | playercolor proxy | blendtintbybasealpha | basemapalphaphongmask | phong | rimlight | lightwarp | exponent texture | used by" }
	for _, path in ipairs(order) do
		local mat, vmt = Material(path), VmtText(path)
		local rule = Catalog.Classify(path)
		lines[#lines + 1] = table.concat({
			path, mat:IsError() and "MISSING" or mat:GetShader(), rule and rule.class or "-",
			Has(vmt, "playercolor") and "yes" or "no",
			mat:GetInt("$blendtintbybasealpha") == 1 and "yes" or "no",
			mat:GetInt("$basemapalphaphongmask") == 1 and "yes" or "no",
			mat:GetInt("$phong") == 1 and "yes" or "no",
			mat:GetInt("$rimlight") == 1 and "yes" or "no",
			mat:GetString("$lightwarptexture") or "-",
			mat:GetString("$phongexponenttexture") or "-",
			table.concat(users[path], ", "),
		}, " | ")
	end
	local text = table.concat(lines, "\n") .. "\n"
	file.CreateDir("teamtint")
	file.Write("teamtint/census.txt", text)
	print(text)
	print("teamtint_census: written to data/teamtint/census.txt")
end, nil, "Team Tint: list the AI war's materials with what decides how each is themed")

-- Export --------------------------------------------------------------------------

-- data/teamtint/export/: the tuning, and each themed material as the VMT it
-- is now (its source's parameters and the tuning's, in the normal view).
-- GMod writes only .txt and .json to data/: rename .vmt.txt to .vmt to ship.
concommand.Add("teamtint_export", function()
	file.CreateDir("teamtint/export")
	file.Write("teamtint/export/tuning.json", util.TableToJSON(Tuning.Encode(TeamTint.tuning), true))
	local count = 0
	for _, entry in ipairs(TeamTint.MaterialEntries()) do
		local params = {}
		for k, v in pairs(entry.sourceKeyValues) do params[k] = v end
		for k, v in pairs(TeamTint.MaterialParamsOf(entry, Tuning.VIEW_NORMAL)) do params[k] = v end
		params["$softwareskin"] = nil
		file.CreateDir("teamtint/export/" .. entry.team)
		file.Write("teamtint/export/" .. entry.team .. "/" .. string.gsub(Catalog.Normalize(entry.path), "/", "__") .. ".vmt.txt",
			Tuning.VmtText("VertexLitGeneric", params))
		count = count + 1
	end
	print(string.format("teamtint_export: the tuning and %d materials written to data/teamtint/export/", count))
end, nil, "Team Tint: write the tuning and every themed material's VMT to data/teamtint/export/")
