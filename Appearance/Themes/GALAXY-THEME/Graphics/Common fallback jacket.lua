-- Fallback jacket: dark gray square with music note text
return Def.ActorFrame{
	Def.Quad{
		InitCommand=function(self)
			self:zoomto(128,128):diffuse(color("#1a1a1a"))
		end,
	},
	Def.Text{ Font = RodinPath("b"), Size = 40, Text = "?",
		InitCommand=function(self)
			self:zoom(2):diffuse(color("#444444"))
		end,
	},
}
