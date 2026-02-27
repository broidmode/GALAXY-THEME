-- GALAXY helper functions for music selection

-- Resolve a jacket image path for a song or course, with fallback chain
function GetJacketPath(item, fallback)
	if item:HasJacket() then
		return item:GetJacketPath()
	elseif item:HasBackground() then
		return item:GetBackgroundPath()
	elseif item:HasBanner() then
		return item:GetBannerPath()
	else
		return fallback or THEME:GetPathG("Common", "fallback jacket")
	end
end
