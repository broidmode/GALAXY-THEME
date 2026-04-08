-- Fallback jacket: dark gray square with music note text
return Def.ActorFrame{
	Def.Quad{
		InitCommand=function(self)
			self:zoomto(128,128):diffuse(color("#1a1a1a"))
		end,
	},
	Def.Text{ Font = RodinPath("db"), Size = FontL("db"), Text = "?",
		InitCommand=function(self)
			self:zoom(2 * FONT_ZOOM):diffuse(color("#444444"))
			self:SetTextureFiltering(false)
		end,
	},
}
