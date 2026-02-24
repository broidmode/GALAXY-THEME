-- ScreenClear background: blank screen used during boot
return Def.ActorFrame{
	Def.Quad{
		InitCommand=function(self)
			self:FullScreen():diffuse(Color.Black)
		end,
	},
}
