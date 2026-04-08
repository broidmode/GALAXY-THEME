-- Generic screen transition: fade out to black
return Def.ActorFrame{
	Def.Quad{
		InitCommand=function(self)
			self:FullScreen():diffuse(Color.Black)
		end,
		OnCommand=function(self)
			self:diffusealpha(0):linear(0.3):diffusealpha(1)
		end,
	},
}
