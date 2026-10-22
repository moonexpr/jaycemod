-- TF2's damage numbers (hud_combattext): the damage an attacker dealt rises
-- from where it hit and fades out. Hits on one victim within the batching
-- window (hud_combattext_batching_window; 0 with hud_combattext_batching
-- off) add into one number, showing the strongest hit in it
-- (games.gameplay.players' HIT_*). ws/cl_hits.lua draws what Live answers.
local floor, ipairs, setmetatable, tostring = math.floor, ipairs, setmetatable, tostring
module(...)

LIFETIME = 1.5 -- seconds a number shows
RISE = 40 -- units it rises over its life

local Texts = {}
Texts.__index = Texts

-- window: seconds; hits on one victim within it of the first add up.
function New(window)
	return setmetatable({ entries = {}, window = window }, Texts)
end

-- A hit of amount on victim (any key), at pos, now.
function Texts:Add(victim, amount, kind, pos, now)
	for _, entry in ipairs(self.entries) do
		if entry.victim == victim and now - entry.at < self.window then
			entry.amount = entry.amount + amount
			if kind > entry.kind then entry.kind = kind end
			entry.pos = pos
			return
		end
	end
	self.entries[#self.entries + 1] = { victim = victim, amount = amount, kind = kind, pos = pos, at = now }
end

-- The numbers showing now, oldest first: amount, text, kind, pos, rise
-- (units above pos), alpha (1 to 0 over the number's life). Spent ones go.
function Texts:Live(now)
	local live, shown = {}, {}
	for _, entry in ipairs(self.entries) do
		local t = (now - entry.at) / LIFETIME
		if t < 1 then
			live[#live + 1] = entry
			shown[#shown + 1] = {
				amount = entry.amount,
				text = "-" .. tostring(floor(entry.amount + 0.5)),
				kind = entry.kind,
				pos = entry.pos,
				rise = RISE * t,
				alpha = 1 - t,
			}
		end
	end
	self.entries = live
	return shown
end
