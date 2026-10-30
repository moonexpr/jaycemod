-- What the stuck census (.devtools/bin/stuck_census.lua) has seen, for
-- `dt lua [--instance N] -f .devtools/bin/stuck_report.lua`: as JSON, the
-- minutes it has run, the rounds begun, and each time someone stayed stuck,
-- longest first.
local census = StuckCensus
if not census then return "no census running" end
local events = {}
for _, e in ipairs(census.events) do
	events[#events + 1] = { kind = e.kind, name = e.name, seconds = math.Round(e.until_ - e.from), pos = e.pos, area = e.area }
end
table.sort(events, function(a, b) return a.seconds > b.seconds end)
local hostage = WS.Feature("hostage")
local pistol = hostage.pistol
return util.TableToJSON({
	map = census.map,
	minutes = math.Round((CurTime() - census.started) / 60, 1),
	rounds = census.rounds,
	state = WS.Feature("rounds"):State(),
	pistol = pistol and { holder = pistol:Holder(), lying = pistol:Lying() } or nil,
	pistols = census.pistols,
	killed = hostage.round and hostage.round:Killed() or nil,
	rescued = census.rescued,
	events = events,
})
