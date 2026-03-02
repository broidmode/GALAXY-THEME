-- GALAXY helper functions for music selection

-- ===== FONT SIZE TIERS (DPI-aware) =====
-- Base sizes are designed for 1080p (the theme's virtual ScreenHeight).
-- At higher display resolutions the engine upscales everything via its
-- projection matrix, which would magnify the glyph textures and make text
-- slightly soft.  We counter this by rasterizing at the real display DPI
-- and applying a uniform FONT_ZOOM so text stays the same virtual size.
--
--   1080p → scale 1.0   FONT_ZOOM 1.0   (pixel-perfect, no zoom)
--   1440p → scale 1.333  FONT_ZOOM 0.75  (27 px raster → 27 display px)
--   2160p → scale 2.0   FONT_ZOOM 0.5   (40 px raster → 40 display px)

local _displayH = PREFSMAN:GetPreference("DisplayHeight") or 1080
local _dpiScale = _displayH / SCREEN_HEIGHT   -- display px per virtual px

FONT_S = math.floor(14 * _dpiScale + 0.5)  -- Small:  data labels, score panel, hints
FONT_M = math.floor(20 * _dpiScale + 0.5)  -- Medium: UI text, menu items, card titles
FONT_L = math.floor(30 * _dpiScale + 0.5)  -- Large:  headings, main score, profile names

FONT_ZOOM = 1 / _dpiScale   -- apply to every Def.Text to keep virtual-coord layout

-- Exact DPI-scaled font size for a given virtual-pixel height.
-- Use this when a preset tier (S/M/L) doesn't match the intended size.
-- Each unique return value creates its own glyph atlas, so prefer the
-- tier constants for common sizes and reserve this for fine-tuning.
function FontSize(virtualPx)
	return math.floor(virtualPx * _dpiScale + 0.5)
end

-- Convenience: maxwidth in virtual pixels, auto-adjusted for DPI rasterization
function FontMaxWidth(virtualPx)
	return virtualPx / FONT_ZOOM
end

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
