-- ScreenSelectMusic background
return Def.ActorFrame{
	Def.Quad{
		InitCommand=function(self)
			self:FullScreen():diffuse(color("#0d0d3a"))
		end,
	},
}
