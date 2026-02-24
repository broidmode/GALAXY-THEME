-- ScreenWarning background
return Def.ActorFrame{
	Def.Quad{
		InitCommand=function(self)
			self:FullScreen():diffuse(Color.Black)
		end,
	},
	Def.BitmapText{
		Font="_eurostile normal",
		Text="GALAXY\nA DDR-inspired theme for Project OutFox",
		InitCommand=function(self)
			self:Center():zoom(1.5):diffuse(Color.White):shadowlength(2)
		end,
	},
}
