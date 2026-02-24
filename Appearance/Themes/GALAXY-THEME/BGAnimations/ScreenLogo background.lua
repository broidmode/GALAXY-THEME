-- ScreenLogo background
return Def.ActorFrame{
	Def.Quad{
		InitCommand=function(self)
			self:FullScreen():diffuse(color("#0a0a2e"))
		end,
	},
	Def.BitmapText{
		Font="_eurostile normal",
		Text="G A L A X Y",
		InitCommand=function(self)
			self:Center():zoom(3):diffuse(color("#00ccff")):shadowlength(3)
		end,
		OnCommand=function(self)
			self:diffusealpha(0):sleep(0.5):linear(1):diffusealpha(1)
		end,
	},
}
