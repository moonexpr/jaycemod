// The engine's navigation mesh progress box (CNavProgress, shown while
// mp_nav_generate runs; wetsand/sv_nav.lua sends this file to clients).
// Centred, in Sandcastle's panel look: a dark box, a white border, white
// text. VGUI layouts have no white border to name, so the frame is white
// and a dark panel 2 px inside it ("Inner") makes the border; the bar's
// outline is drawn the same way.
"Resource/UI/NavProgress.res"
{
	"nav_progress"
	{
		"ControlName"		"CNavProgress"
		"fieldName"		"nav_progress"
		"xpos"			"c-204"
		"ypos"			"c-56"
		"wide"			"408"
		"tall"			"112"
		"autoResize"		"0"
		"pinCorner"		"0"
		"visible"		"1"
		"enabled"		"1"
		"tabPosition"		"0"
		"settitlebarvisible"	"0"
		"paintbackground"	"1"
		"bgcolor_override"	"255 255 255 255"
	}
	"Inner"
	{
		"ControlName"		"Panel"
		"fieldName"		"Inner"
		"xpos"			"2"
		"ypos"			"2"
		"zpos"			"-2"
		"wide"			"404"
		"tall"			"108"
		"visible"		"1"
		"enabled"		"1"
		"paintbackground"	"1"
		"bgcolor_override"	"24 24 28 255"
	}
	"TitleLabel"
	{
		"ControlName"		"Label"
		"fieldName"		"TitleLabel"
		"xpos"			"14"
		"ypos"			"12"
		"wide"			"380"
		"tall"			"20"
		"visible"		"1"
		"enabled"		"1"
		"labelText"		""
		"textAlignment"		"center"
		"font"			"DefaultBold"
		"fgcolor_override"	"255 255 255 255"
	}
	"TextLabel"
	{
		"ControlName"		"Label"
		"fieldName"		"TextLabel"
		"xpos"			"14"
		"ypos"			"36"
		"wide"			"380"
		"tall"			"20"
		"visible"		"1"
		"enabled"		"1"
		"labelText"		""
		"textAlignment"		"center"
		"font"			"Default"
		"fgcolor_override"	"220 220 225 255"
	}
	"ProgressBarBorder"
	{
		"ControlName"		"Panel"
		"fieldName"		"ProgressBarBorder"
		"xpos"			"22"
		"ypos"			"70"
		"zpos"			"-1"
		"wide"			"364"
		"tall"			"20"
		"visible"		"1"
		"enabled"		"1"
		"paintbackground"	"1"
		"bgcolor_override"	"255 255 255 255"
	}
	"ProgressBarBack"
	{
		"ControlName"		"Panel"
		"fieldName"		"ProgressBarBack"
		"xpos"			"24"
		"ypos"			"72"
		"zpos"			"0"
		"wide"			"360"
		"tall"			"16"
		"visible"		"1"
		"enabled"		"1"
		"paintbackground"	"1"
		"bgcolor_override"	"24 24 28 255"
	}
	"ProgressBarSizer"
	{
		"ControlName"		"Panel"
		"fieldName"		"ProgressBarSizer"
		"xpos"			"26"
		"ypos"			"74"
		"wide"			"356"
		"tall"			"12"
		"visible"		"0"
		"enabled"		"1"
	}
	"ProgressBar"
	{
		"ControlName"		"Panel"
		"fieldName"		"ProgressBar"
		"xpos"			"26"
		"ypos"			"74"
		"zpos"			"1"
		"wide"			"0"
		"tall"			"12"
		"visible"		"1"
		"enabled"		"1"
		"paintbackground"	"1"
		"bgcolor_override"	"255 255 255 255"
	}
}
