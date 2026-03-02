-- GALAXY helper functions for music selection

-- ===== RODIN FONT PATHS =====
-- Weight keys: "l" (Light), "m" (Medium), "db" (DemiBold),
--              "b" (Bold), "eb" (ExtraBold), "ub" (UltraBold)
local _RodinPaths = {}
function RodinPath(weight)
	weight = weight or "m"
	if not _RodinPaths[weight] then
		_RodinPaths[weight] = THEME:GetPathF("", "rodin/rodin_" .. weight .. ".otf")
	end
	return _RodinPaths[weight]
end

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
