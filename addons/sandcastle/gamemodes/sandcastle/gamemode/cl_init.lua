
--[[---------------------------------------------------------

	Sandbox Gamemode

	This is GMod's default gamemode

-----------------------------------------------------------]]

include( "shared.lua" )
include( "cl_spawnmenu.lua" )
include( "cl_notice.lua" )
include( "cl_hints.lua" )
include( "cl_worldtips.lua" )
include( "cl_search_models.lua" )
include( "gui/IconEditor.lua" )

--
-- Make BaseClass available
--
DEFINE_BASECLASS( "gamemode_base" )


local physgun_halo = CreateConVar( "physgun_halo", "1", { FCVAR_ARCHIVE }, "Draw the Physics Gun grab effect?" )

function GM:Initialize()

	BaseClass.Initialize( self )

end

function GM:LimitHit( name )

	local str = "#SBoxLimit_" .. name
	local translated = language.GetPhrase( str )
	if ( str == translated ) then
		-- No translation available, apply our own
		translated = language.FormatPhrase( "hint.hitXlimit", language.GetPhrase( name ) )
	end

	self:AddNotify( translated, NOTIFY_ERROR, 6 )
	surface.PlaySound( "buttons/button10.wav" )

end

function GM:OnUndo( name, strCustomString )

	local text = strCustomString
	local overwritten = false

	if ( !text ) then
		local strId = "#Undone_" .. name
		text = language.GetPhrase( strId )
		if ( strId == text ) then
			-- No custom translation available, make a generic one
			text = language.FormatPhrase( "hint.undoneX", language.GetPhrase( name ) )
			overwritten = true
		end
	end

	if ( !overwritten ) then
		-- HACK: Try to translate existing English-only translations
		local strMatch = string.match( text, "^Undone (.*)$" )
		if ( strMatch ) then
			text = language.FormatPhrase( "hint.undoneX", language.GetPhrase( strMatch ) )
		end
	end

	self:AddNotify( text, NOTIFY_UNDO, 2 )

	-- Find a better sound :X
	surface.PlaySound( "buttons/button15.wav" )

end

function GM:OnCleanup( name )

	local str = "#Cleaned_" .. name
	local translated = language.GetPhrase( str )
	if ( str == translated ) then
		-- No translation available, apply our own
		translated = language.FormatPhrase( "hint.cleanedX", language.GetPhrase( name ) )
	end

	self:AddNotify( translated, NOTIFY_CLEANUP, 5 )

	-- Find a better sound :X
	surface.PlaySound( "buttons/button15.wav" )

end

function GM:UnfrozeObjects( num )

	self:AddNotify( language.FormatPhrase( "hint.unfrozeX", num ), NOTIFY_GENERIC, 3 )

	-- Find a better sound :X
	surface.PlaySound( "npc/roller/mine/rmine_chirp_answer1.wav" )

end

function GM:HUDPaint()

	self:PaintWorldTips()

	-- Draw all of the default stuff
	BaseClass.HUDPaint( self )

	self:PaintNotes()

	if ( self:IsGameplay() ) then self:PaintRound() end

end

--[[---------------------------------------------------------
	Name: gamemode:RoundWinAnnounce()
	Desc: The server says a round is over (round_manager's
	      teamplay_round_win); winner is TF_TEAM_UNASSIGNED for
	      a stalemate
-----------------------------------------------------------]]
function GM:RoundWinAnnounce( winner )

	local text = "Stalemate"
	if ( winner ~= TF_TEAM_UNASSIGNED ) then text = team.GetName( winner ) .. " wins the round" end
	LocalPlayer():PrintMessage( HUD_PRINTCENTER, text )

end

net2.Listen( "teamplay_round_win", "sandcastle_round_win", function( fields )

	hook.Run( "RoundWinAnnounce", fields.team )

end )

local ROUND_LABELS = {
	[ ROUND_WAITING ] = "Waiting for players",
	[ ROUND_PREPARE ] = "Get ready",
	[ ROUND_ACTIVE ] = "",
	[ ROUND_OVER ] = "Round over"
}

function GM:PaintRound()

	local text = ROUND_LABELS[ self:GetRoundState() ]
	local roundEnd = self:GetRoundEnd()

	if ( roundEnd > 0 ) then
		text = text .. " " .. string.FormattedTime( math.max( 0, roundEnd - CurTime() ), "%02i:%02i" )
	end

	local score = team.GetName( TEAM_RED ) .. " " .. team.GetScore( TEAM_RED ) .. " - " .. team.GetScore( TEAM_BLUE ) .. " " .. team.GetName( TEAM_BLUE )

	draw.SimpleTextOutlined( text, "DermaLarge", ScrW() / 2, 16, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 2, color_black )
	draw.SimpleTextOutlined( score, "DermaDefaultBold", ScrW() / 2, 52, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 1, color_black )

end

--[[---------------------------------------------------------
	Draws on top of VGUI..
-----------------------------------------------------------]]
function GM:PostRenderVGUI()

	BaseClass.PostRenderVGUI( self )

end

local PhysgunHalos = {}

--[[---------------------------------------------------------
	Name: gamemode:DrawPhysgunBeam()
	Desc: Return false to override completely
-----------------------------------------------------------]]
function GM:DrawPhysgunBeam( ply, weapon, bOn, target, boneid, pos )

	if ( physgun_halo:GetInt() == 0 ) then return true end

	if ( IsValid( target ) ) then
		PhysgunHalos[ ply ] = target
	end

	return true

end

hook.Add( "PreDrawHalos", "AddPhysgunHalos", function()

	if ( !PhysgunHalos || table.IsEmpty( PhysgunHalos ) ) then return end

	for k, v in pairs( PhysgunHalos ) do

		if ( !IsValid( k ) ) then continue end

		local size = math.random( 1, 2 )
		local colr = k:GetWeaponColor() + VectorRand() * 0.3

		halo.Add( PhysgunHalos, Color( colr.x * 255, colr.y * 255, colr.z * 255 ), size, size, 1, true, false )

	end

	PhysgunHalos = {}

end )


--[[---------------------------------------------------------
	Name: gamemode:NetworkEntityCreated()
	Desc: Entity is created over the network
-----------------------------------------------------------]]
function GM:NetworkEntityCreated( ent )

	--
	-- If the entity wants to use a spawn effect
	-- then create a propspawn effect if the entity was
	-- created within the last second (this function gets called
	-- on every entity when joining a server)
	--

	if ( ent:GetSpawnEffect() && ent:GetCreationTime() > ( CurTime() - 1.0 ) ) then

		local ed = EffectData()
			ed:SetOrigin( ent:GetPos() )
			ed:SetEntity( ent )
		util.Effect( "propspawn", ed, true, true )

	end

end
