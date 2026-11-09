-- Vendored from Foohy's Jazztronauts (github.com/Foohy/jazztronauts, 1a813ade43b6b2aabac6bd9e5b8985066eaf9379,
-- gamemodes/jazztronauts/gamemode/lib/sh_camera.lua); code by Foohy and the
-- Jazztronauts team. Unmodified; see docs/vendor.md.
if SERVER then AddCSLuaFile("sh_camera.lua") end
if SERVER then return end

Camera = nil
IsCamera = nil

module( "camera", package.seeall )

local meta = {}
meta.__index = meta

IsCamera = function(camera)

	return getmetatable(camera) == meta

end

function meta:Init( pos, angle, fov, near, far )

	self.pos = pos or EyePos()
	self.angle = angle or EyeAngles()
	self.fov = fov or nil
	self.near = near or nil
	self.far = far or nil
	self.enable = false

	return self

end

function meta:Start3D( rect )

	if not IsRect(rect) then error("Expected Rectangle") end

	local x,y,w,h = rect:Unpack()
	if w < 1 or h < 1 then return end

	if self.enable then return end
	self.enable = true
	cam.Start3D( self.pos, self.angle, self.fov, x, y, w, h )

end

function meta:End3D()

	if not self.enable then return end
	cam.End3D()
	self.enable = false

end

function New(...)

	return setmetatable({}, meta):Init(...)

end

_G["Camera"] = New