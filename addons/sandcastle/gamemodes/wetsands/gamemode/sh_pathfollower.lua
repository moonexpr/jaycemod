local Events = WS.Events

Events.Define("game_ns_pathfollower_debug", {
	follower = Events.Entity(),
	path = Events.List(Events.Vector(), 12),
	lane = Events.List(Events.Vector(), 12),
})
WS.PathFollowerDebugEventReady = true

if CLIENT then
	Events.Listen("game_ns_pathfollower_debug", "ws_pathfollower_debug", function(fields)
		if not IsValid(fields.follower) then return end
		fields.follower.nsDebugPathPoints = fields.path
		fields.follower.nsDebugLanePoints = fields.lane
	end)
end
