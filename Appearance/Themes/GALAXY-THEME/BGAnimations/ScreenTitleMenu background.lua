-- ScreenTitleMenu background
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
			self:Center():addy(-90):zoom(2.5):diffuse(color("#00ccff")):shadowlength(3)
		end,
	},
	Def.BitmapText{
		Font="_eurostile normal",
		Text="Press START",
		InitCommand=function(self)
			self:Center():addy(50):zoom(1.2):diffuse(Color.White)
		end,
		OnCommand=function(self)
			self:diffusealpha(0):sleep(0.5):linear(0.3):diffusealpha(1)
				:linear(0.8):diffusealpha(0.3):linear(0.8):diffusealpha(1)
				:queuecommand("Loop")
		end,
		LoopCommand=function(self)
			self:linear(0.8):diffusealpha(0.3):linear(0.8):diffusealpha(1)
				:queuecommand("Loop")
		end,
	},
}
