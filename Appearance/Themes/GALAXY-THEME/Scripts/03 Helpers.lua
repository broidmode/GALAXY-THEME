-- GALAXY helper functions
-- See !Docs/outline.md § Font Strategy for architecture overview.
-- See !Docs/pixel-perfect-text-research.md for engine-level details.

-- ===== PER-WEIGHT FONT SIZE TABLE =====
-- Base sizes are in *virtual* pixels, designed for the theme's 1080p
-- ScreenHeight.  At runtime each value is multiplied by
--     _scale = displayHeight / 1080
-- so the FreeType rasterizer generates glyph textures that map 1:1 to
-- real display pixels.  FONT_ZOOM (= 1/_scale) is then applied to every
-- Def.Text to shrink the quad back to its intended on-screen proportion.
--
-- Result: crisp text at any resolution, with no magnification blur.
--
-- >>> EDIT THE TABLE BELOW to tweak font sizes per weight. <<<
--
-- Currently every screen uses rodin_db (DemiBold) uniformly.
-- When we add custom fonts for different UI sections, each weight can
-- have independent S/M/L values — heavier strokes read larger at the
-- same pixel size, so you can dial Bold down a couple of virtual px.
--
-- Weight key reference (Rodin family):
--   l  = Light     m  = Medium    db = DemiBold
--   b  = Bold      eb = ExtraBold ub = UltraBold
--
-- Tier usage:
--   S (14 vp) — data labels, score panel cells, hints, footer text
--   M (20 vp) — card titles, menu items, section headings
--   L (30 vp) — main score, profile names, screen headings

local _FontBase = {
--              S    M    L          -- tier usage
	l  = { S = 14, M = 20, L = 30 },  -- Light
	m  = { S = 14, M = 20, L = 30 },  -- Medium
	db = { S = 14, M = 20, L = 30 },  -- DemiBold
	b  = { S = 14, M = 20, L = 30 },  -- Bold
	eb = { S = 14, M = 20, L = 30 },  -- ExtraBold
	ub = { S = 14, M = 20, L = 30 },  -- UltraBold
}

local _displayH = PREFSMAN:GetPreference("DisplayHeight") or 1080
local _scale    = _displayH / SCREEN_HEIGHT   -- display px per virtual px

FONT_ZOOM = 1 / _scale   -- apply to every Def.Text to keep virtual-coord layout

-- ---------------------------------------------------------------------------
-- Scaled size getters
-- Usage:   Font = RodinPath("db"), Size = FontM("db")
-- The weight arg ("db") selects the row from _FontBase; if we later
-- add a second font family, the same size table still applies.
-- ---------------------------------------------------------------------------
function FontS(w)  return math.floor(_FontBase[w].S * _scale + 0.5) end
function FontM(w)  return math.floor(_FontBase[w].M * _scale + 0.5) end
function FontL(w)  return math.floor(_FontBase[w].L * _scale + 0.5) end

-- ---------------------------------------------------------------------------
-- Convenience: maxwidth in virtual pixels, auto-adjusted for DPI rasterization.
-- Because the glyph atlas is rasterized at _scale× native, and the quad is
-- zoomed by 1/_scale, the maxwidth the engine sees must compensate.
-- ---------------------------------------------------------------------------
function FontMaxWidth(virtualPx)
	return virtualPx / FONT_ZOOM
end

-- ===== RODIN FONT PATHS =====
-- Resolves and caches the on-disk path for a given Rodin weight.
--
-- Currently the entire theme uses "db" (DemiBold) uniformly.
-- When custom per-section fonts are introduced, call RodinPath with the
-- appropriate weight key.
--
-- Weight keys: "l" (Light), "m" (Medium), "db" (DemiBold),
--              "b" (Bold), "eb" (ExtraBold), "ub" (UltraBold)
local _RodinPaths = {}
function RodinPath(weight)
	weight = weight or "m"
	-- "db" is aliased to "b" — Bold is the theme-wide default weight.
	if weight == "db" then weight = "b" end
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
