-- GALAXY Theme Colors
-- Defines the color palette for the theme

Color = {
	Black       = color("0,0,0,1"),
	White       = color("1,1,1,1"),
	Red         = color("#ed1c24"),
	Blue        = color("#00aeef"),
	Green       = color("#39b54a"),
	Yellow      = color("#fff200"),
	Orange      = color("#f7941d"),
	Purple      = color("#92278f"),
	Outline     = color("0,0,0,0.5"),
	Invisible   = color("1,1,1,0"),
	Stealth     = color("0,0,0,0"),

	Alpha = function(c, fAlpha)
		return { c[1], c[2], c[3], fAlpha }
	end,
}

setmetatable(Color, { __call = function(self, c) return self[c] end })

GameColor = {
	PlayerColors = {
		PLAYER_1 = color("#1ed0c2"),
		PLAYER_2 = color("#f253ed"),
	},
	Difficulty = {
		Beginner            = color("#1ed6ff"),
		Easy                = color("#ffaa19"),
		Medium              = color("#ff1e3c"),
		Hard                = color("#32eb19"),
		Challenge           = color("#eb1eff"),
		Edit                = color("#afafaf"),
		Couple              = color("#ed0972"),
		Routine             = color("#ff9a00"),
		Difficulty_Beginner = color("#1ed6ff"),
		Difficulty_Easy     = color("#ffaa19"),
		Difficulty_Medium   = color("#ff1e3c"),
		Difficulty_Hard     = color("#32eb19"),
		Difficulty_Challenge= color("#eb1eff"),
		Difficulty_Edit     = color("#afafaf"),
		Difficulty_Couple   = color("#ed0972"),
		Difficulty_Routine  = color("#ff9a00"),
	},
	Stage = {
		Stage_1st     = color("#00ffc7"),
		Stage_2nd     = color("#58ff00"),
		Stage_3rd     = color("#f400ff"),
		Stage_4th     = color("#00ffda"),
		Stage_5th     = color("#ed00ff"),
		Stage_6th     = color("#73ff00"),
		Stage_Next    = color("#73ff00"),
		Stage_Final   = color("#ff0707"),
		Stage_Extra1  = color("#fafa00"),
		Stage_Extra2  = color("#ff0707"),
		Stage_Nonstop = color("#FFFFFF"),
		Stage_Oni     = color("#FFFFFF"),
		Stage_Endless = color("#FFFFFF"),
		Stage_Event   = color("#FFFFFF"),
		Stage_Demo    = color("#FFFFFF"),
	},
	Judgment = {},
}
