-- ScreenThemeOptions overlay
-- Persists ThemePrefs to disk when the user exits the options screen.

return Def.ActorFrame{
	OffCommand = function(self)
		if ThemePrefs and ThemePrefs.Save then
			ThemePrefs.Save()
		end
	end,
}
