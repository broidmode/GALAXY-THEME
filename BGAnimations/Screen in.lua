-- Generic screen transition: fade in from black
return Def.ActorFrame{
	Def.Quad{
		InitCommand=function(self)
			self:FullScreen():diffuse(Color.Black)
		end,
		OnCommand=function(self)
			self:diffusealpha(1):linear(0.3):diffusealpha(0)
		end,
	},
}
