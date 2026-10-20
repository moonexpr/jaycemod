-- Team Tint's panel, the same in the tool's menu and under Utilities >
-- Team Tint (where a mode without a toolgun can still tune): the view,
-- the scope being edited, every knob of teamtint_tuning's SCHEMA, and the
-- debug commands.
local Tuning, Catalog = TeamTint.Tuning, TeamTint.Catalog

local function ColorKnob(panel, p)
	local cvar = TeamTint.knobs[p.name]
	panel:Help(p.label)
	local mixer = vgui.Create("DColorMixer", panel)
	mixer:SetPalette(false)
	mixer:SetAlphaBar(false)
	mixer:SetTall(120)
	local c = Tuning.Parse(p.name, cvar:GetString()) or p.default
	mixer:SetColor(Color(c[1], c[2], c[3]))
	function mixer:ValueChanged(color)
		cvar:SetString(Tuning.Format(p.name, { color.r, color.g, color.b }))
	end
	panel:AddItem(mixer)
end

local function Knob(panel, p)
	local name = TeamTint.CONVAR_PREFIX .. p.name
	if p.kind == "number" then
		panel:NumSlider(p.label, name, p.min, p.max, 2)
	elseif p.kind == "flag" then
		panel:CheckBox(p.label, name)
	elseif p.kind == "color" then
		ColorKnob(panel, p)
	else
		panel:TextEntry(p.label, name)
	end
end

local function Scopes()
	local list = { Tuning.ALL }
	for class, kind in SortedPairs(Catalog.CLASSES) do
		if not kind.untouched then list[#list + 1] = class end
	end
	return list
end

function TeamTint.BuildPanel(panel)
	panel:Help("Paint a body RED (left click) or BLU (right click); reload clears. Shift + left click spawns a RED and a BLU copy beside it. Without a toolgun: teamtint_paint red|blu|original|clear.")
	panel:CheckBox("Theme bodies by team", "teamtint_enable")
	panel:CheckBox("Overlay: team and materials", "teamtint_overlay")

	local view = panel:ComboBox("View", "teamtint_view")
	for i, label in ipairs(Tuning.VIEWS) do view:AddChoice(label, i - 1) end

	local scope = panel:ComboBox("Editing", "teamtint_scope")
	for _, s in ipairs(Scopes()) do scope:AddChoice(s, s) end

	for _, p in ipairs(Tuning.SCHEMA) do Knob(panel, p) end

	panel:Button("Reset this scope", "teamtint_reset_scope")
	local copy = panel:Button("Copy knobs to clipboard")
	function copy:DoClick() SetClipboardText(TeamTint.ConvarText()) end
	panel:Button("Export tuning and VMTs", "teamtint_export")
	panel:Button("Census of the war's materials", "teamtint_census")
	panel:CheckBox("Bench: $softwareskin on themed bodies", "teamtint_bench_softwareskin")
	panel:Help("Tuning is saved to data/teamtint/tuning.json. Views: albedo and silhouette draw unlit; value is greyscale, and RED and BLU must still differ in it.")
end

hook.Add("PopulateToolMenu", "teamtint", function()
	spawnmenu.AddToolMenuOption("Utilities", "Team Tint", "teamtint_panel", "Team Tint", "", "", TeamTint.BuildPanel)
end)
