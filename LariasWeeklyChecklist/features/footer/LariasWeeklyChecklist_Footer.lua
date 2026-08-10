-- Footer module: status banner, slider visibility, and opacity management.
-- Exposes the Addon: methods that manage the bottom chrome of the main frame.
local addonName = ...
local Addon = _G[addonName]
if not Addon then return end

local LOCALE_REGISTRY_KEY = Addon.LOCALE_REGISTRY_KEY

-- Banner sizing constants (kept here close to the functions that use them).
local BANNER_H   = 14  -- banner height in scaled frame pixels
local BANNER_PAD = 3   -- gap between banner bottom and frame bottom edge

-- Returns how many numeric version steps myVer trails newestVer.
-- Works on any freeform string; uses the last integer found ("Week 5" → 5).
local function SheetVersionsBehind(myVer, newestVer)
    local function lastNum(s)
        local n = 0
        for m in tostring(s or ""):gmatch("%d+") do n = tonumber(m) or n end
        return n
    end
    local diff = lastNum(newestVer) - lastNum(myVer)
    return diff > 0 and diff or 0
end

-- Applies all three label properties at once; avoids repeating the triple
-- SetJustifyH / SetText / SetTextColor pattern inside UpdateStatusBanner.
local function SetBannerLabel(lbl, text, r, g, b, a)
    lbl:SetJustifyH("CENTER")
    lbl:SetText(text)
    lbl:SetTextColor(r, g, b, a or 1)
end

-- ── Addon:CreateStatusBanner ──────────────────────────────────────────────────
-- Creates the one-line informational bar at the very bottom of the main frame.
-- Called once from CreateTrackingPanel (features/body/LariasWeeklyChecklist_Currency.lua).
function Addon:CreateStatusBanner(parentFrame)
    if self._statusBanner then return end
    local inset = Addon.UI.sectionInsetX or 14
    local bannerFrame = CreateFrame("Frame", nil, parentFrame)
    bannerFrame:SetHeight(BANNER_H)
    bannerFrame:SetPoint("BOTTOMLEFT",  parentFrame, "BOTTOMLEFT",   inset,  BANNER_PAD)
    bannerFrame:SetPoint("BOTTOMRIGHT", parentFrame, "BOTTOMRIGHT", -inset,  BANNER_PAD)
    -- Always shown so it permanently reserves its space; content changes, not visibility.
    bannerFrame:Show()
    local lbl = bannerFrame:CreateFontString(nil, "OVERLAY")
    lbl:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    lbl:SetAllPoints(bannerFrame)
    lbl:SetJustifyH("CENTER")
    lbl:SetJustifyV("MIDDLE")
    lbl:SetWordWrap(false)
    bannerFrame._label    = lbl
    self._statusBanner    = bannerFrame
    self._statusBannerH   = BANNER_H
    self._statusBannerPad = BANNER_PAD
end

-- ── Addon:UpdateStatusBanner ──────────────────────────────────────────────────
-- Redraws the banner with the highest-priority message.  Priority order:
--   1. Red   – a newer addon version is available.
--   2. Amber – the client locale has no translation.
--   3. Gray  – a translation exists (encourage contributors).
--   4. Dim   – attribution credit (right-aligned, enUS default state).
function Addon:UpdateStatusBanner()
    local banner = self._statusBanner
    if not banner then return end
    local db     = self:EnsurePrefs()
    local charDb = self:EnsureDB()   -- for per-character version tracking data
    local L  = self.L or {}

    -- Priority 1a: spreadsheet data is newer than ours (English only – other
    -- locales use translated data bundles that may lag behind the sheet).
    local _effectiveLocale = (self.GetEffectiveLocaleCode and self:GetEffectiveLocaleCode())
                          or (GetLocale and GetLocale())
                          or "enUS"
    if db.hideUpdateNotice ~= true and _effectiveLocale == "enUS"
    and self.ShouldShowSheetUpdateNotice and self:ShouldShowSheetUpdateNotice() then
        local reg    = _G[LOCALE_REGISTRY_KEY]
        local mySV   = (reg and type(reg.sheet_version) == "string" and reg.sheet_version) or ""
        local newSV  = tostring(charDb._newestSeenRemoteSheetVersion or "")
        local behind = SheetVersionsBehind(mySV, newSV)
        local fmt    = L.STATUS_SHEET_UPDATE_FMT
                    or "Spreadsheet Update Detected - You are %d version(s) behind the spreadsheet"
        SetBannerLabel(banner._label, string.format(fmt, behind), 1, 0.65, 0.0)
        return
    end

    -- Priority 1b: addon update available (no sheet-version info or sheet is current).
    if db.hideUpdateNotice ~= true and self.ShouldShowUpdateNotice and self:ShouldShowUpdateNotice() then
        local txt = L.UPDATE_AVAILABLE_TEXT or "New version available"
        SetBannerLabel(banner._label, txt, 1, 0.2, 0.2)
        return
    end

    -- Priority 2/3: locale status notice for non-English clients.
    -- GetEffectiveLocaleCode() falls back to GetLocale() when no override is set.
    -- Suppressed by the same hideUpdateNotice flag as the version warnings.
    local wowLocale = _effectiveLocale
    if db.hideUpdateNotice ~= true and wowLocale ~= "enUS" then
        local reg = _G[LOCALE_REGISTRY_KEY]
        local hasLocale = reg
            and type(reg.strings) == "table"
            and type(reg.strings[wowLocale]) == "table"
        if not hasLocale then
            local fmt = L.STATUS_NO_TRANSLATION_FMT
                     or "No translation available for %s. Consider contributing!"
            SetBannerLabel(banner._label, string.format(fmt, wowLocale), 0.9, 0.7, 0.3)
        else
            local txt = L.STATUS_TRANSLATION_NOTICE
                     or "This is a translation of the English guide. Notice any issues? Consider contributing!"
            SetBannerLabel(banner._label, txt, 0.65, 0.65, 0.65, 0.8)
        end
        return
    end

    -- Default (enUS, no notices): clear the banner.
    banner._label:SetText("")
end

-- ── Addon:ApplyScaleSliderVisibility ─────────────────────────────────────────
-- Re-anchors the tracking panel at the bottom of the main frame.
-- Sliders were moved to the options menus; no in-frame slider exists.
function Addon:ApplyScaleSliderVisibility()
    local bannerExtra = self._statusBanner
        and ((self._statusBannerH or BANNER_H) + (self._statusBannerPad or BANNER_PAD))
        or 0
    local tf = self._trackingFrame
    if tf then
        local inset  = Addon.UI.sectionInsetX  or 14
        local botPad = (Addon.UI.sliderBottomPad or 4) + bannerExtra
        tf:ClearAllPoints()
        tf:SetPoint("BOTTOMLEFT",  tf:GetParent(), "BOTTOMLEFT",  inset,  botPad)
        tf:SetPoint("BOTTOMRIGHT", tf:GetParent(), "BOTTOMRIGHT", -inset, botPad)
    end
    if self.ApplyScrollLayout then self:ApplyScrollLayout() end
end

-- ── Addon:ApplyOpacity ────────────────────────────────────────────────────────
function Addon:GetUIOpacityAlpha()
    local pct = (self.db and self.db.global and tonumber(self.db.global.uiOpacityPct)) or 65
    return math.max(0.5, math.min(1.0, pct / 100))
end

-- Sets the background texture alpha from the saved opacity percentage.
-- Drives only the dedicated bg texture so child widgets remain fully opaque,
-- except the status banner which fades proportionally with the background.
function Addon:ApplyOpacity()
    local alpha = self:GetUIOpacityAlpha()
    if self.RefreshWindowSurfaces then self:RefreshWindowSurfaces() end
    if self._statusBanner then
        self._statusBanner:SetAlpha(alpha)
    end
    local sf = self._inFrameScaleSlider
    if sf and sf.SyncOpacity then sf.SyncOpacity() end
end
