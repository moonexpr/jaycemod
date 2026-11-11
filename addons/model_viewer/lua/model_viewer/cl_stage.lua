-- The model on show: a DModelPanel that plays one sequence by setting its cycle
-- each frame, so pausing, scrubbing and looping a sequence the model does not loop
-- are all the same thing, and whose camera orbits the model under the mouse.
local Catalog = model_viewer_catalog

local FOV = 40
local START_YAW, START_PITCH = 25, 10
local ORBIT_PER_PIXEL, LIFT_PER_PIXEL = 0.5, 0.005 -- the lift, of the camera's distance

local PANEL = {}

function PANEL:Init ()
	self:SetFOV (FOV)
	self.cycle, self.duration, self.rate = 0, 0, 1
	self.loop, self.paused = true, false
	self.last = RealTime ()
end

-- Shows a model at its starting pose, framed, with nothing yet playing.
function PANEL:ShowModel (path)
	self:SetModel (path)
	local ent = self:GetEntity ()
	local mins, maxs = ent:GetRenderBounds ()
	self.center, self.fit = Catalog.Framing (mins, maxs, FOV)
	self.distance, self.yaw, self.pitch, self.lift = self.fit, START_YAW, START_PITCH, 0
	self.cycle, self.duration = 0, 0
	self.poses = Catalog.Poses (ent)
	for _, pose in ipairs (self.poses) do ent:SetPoseParameter (pose.name, pose.value) end
end

function PANEL:Play (entry)
	self:GetEntity ():ResetSequence (entry.sequence)
	self.cycle, self.duration = 0, entry.seconds
end

function PANEL:Seek (cycle) self.cycle = cycle end

function PANEL:Pose (name, value)
	local ent = self:GetEntity ()
	ent:SetPoseParameter (name, value)
	ent:InvalidateBoneCache ()
end

-- What the window answers: whether its slider has the cycle in hand.
function PANEL:IsHeld () return false end
function PANEL:OnCycle () end

-- Each frame, before the model draws (DModelPanel's Paint).
function PANEL:LayoutEntity (ent)
	local now = RealTime ()
	if not self.paused and not self:IsHeld () then
		self.cycle = Catalog.Advance (self.cycle, now - self.last, self.duration, self.rate, self.loop)
	end
	self.last = now
	ent:SetCycle (self.cycle)
	self:OnCycle (self.cycle)

	local center = self.center
	local z = center.z + self.lift
	self:SetLookAt (Vector (center.x, center.y, z))
	local x, y, camZ = Catalog.Orbit ({ x = center.x, y = center.y, z = z }, self.distance, self.yaw, self.pitch)
	self:SetCamPos (Vector (x, y, camZ))
end

function PANEL:OnMousePressed (button)
	self.dragging = button
	self:MouseCapture (true)
end

function PANEL:OnMouseReleased ()
	self.dragging, self.lastX, self.lastY = nil, nil, nil
	self:MouseCapture (false)
end

function PANEL:OnCursorMoved (x, y)
	if not self.dragging then return end
	local dx, dy = x - (self.lastX or x), y - (self.lastY or y)
	self.lastX, self.lastY = x, y
	if self.dragging == MOUSE_LEFT then
		self.yaw = self.yaw - dx * ORBIT_PER_PIXEL
		self.pitch = Catalog.Pitch (self.pitch, dy * ORBIT_PER_PIXEL)
	elseif self.dragging == MOUSE_RIGHT then
		self.lift = self.lift + dy * LIFT_PER_PIXEL * self.distance
	end
end

function PANEL:OnMouseWheeled (wheel)
	self.distance = Catalog.Zoom (self.distance, self.fit, wheel)
end

vgui.Register ("ModelViewerStage", PANEL, "DModelPanel")
