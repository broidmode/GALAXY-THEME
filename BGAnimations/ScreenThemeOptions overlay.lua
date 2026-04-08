-- ScreenThemeOptions overlay
-- Persists ThemePrefs to disk when the user exits the options screen,
-- then re-applies the active timing preset so changes take effect immediately.

return Def.ActorFrame{
	OffCommand = function(self)
		if ThemePrefs and ThemePrefs.Save then
			ThemePrefs.Save()
		end
		ApplyTimingPreset(GetGalaxyPref("TimingMode"))
	end,
}
