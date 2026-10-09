-- The editors' actions: right-click entries on an editor (Sandbox's
-- properties), for admins only on both realms. The server runs the action
-- through the editors feature and tells the admin how it went.
--
-- def = { class (the editor's), or match(ent) -> whether the entry shows on
-- ent (a payload cart), title (for the chat line), label, icon,
-- order, choices (optional: { label, value } list, shown as a submenu),
-- run(editors, ent, value) -> true, or false and why, done (the chat line
-- on success) }.
function WETSAND.EditorAction(name, def)
	properties.Add(name, {
		MenuLabel = def.label,
		MenuIcon = def.icon,
		Order = def.order,
		Filter = function(self, ent, ply)
			if not (IsValid(ent) and IsValid(ply) and ply:IsAdmin()) then return false end
			if def.match then return def.match(ent) == true end
			return ent:GetClass() == def.class
		end,
		Action = function(self, ent)
			if not def.choices then self:Send(ent, 0) end
		end,
		MenuOpen = def.choices and function(self, option, ent)
			local submenu = option:AddSubMenu()
			for _, choice in ipairs(def.choices) do
				submenu:AddOption(choice.label, function() self:Send(ent, choice.value) end)
			end
		end or nil,
		Send = function(self, ent, value)
			self:MsgStart()
			net.WriteEntity(ent)
			net.WriteInt(value, 16)
			self:MsgEnd()
		end,
		Receive = function(self, length, ply)
			local ent, value = net.ReadEntity(), net.ReadInt(16)
			if not self:Filter(ent, ply) then return end
			local ok, why = def.run(WETSAND.Feature("editors"), ent, value)
			ply:ChatPrint(def.title .. ": " .. (ok and def.done or why))
		end,
	})
end
