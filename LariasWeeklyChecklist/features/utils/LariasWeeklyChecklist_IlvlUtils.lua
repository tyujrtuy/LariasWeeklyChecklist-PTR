-- IlvlUtils: shared helpers for item-level tier lookup and crest-palette colouring.
-- Must be loaded before any feature module that uses tier colours.
--
-- Exposes Addon.IlvlUtils:
--   GetTier(ilvl)          → crest tier index 1-5, or nil
--   GetRank(ilvl, tier)    → upgrade rank 1-6 within the tier, or nil
--   GetColorHex(ilvl)      → "ffRRGGBB" string ready for |c colour codes
--   GetEscapePrefix(tier)  → "|cFFRRGGBB" WoW colour-escape prefix
--   GetTrackLabel(ilvl)    → e.g. "Champion 1", or nil

local addonName = ...
local Addon = _G[addonName]
if not Addon then return end

local IlvlUtils = {}
Addon.IlvlUtils = IlvlUtils

-- Returns the crest tier index (1-5) matching the given ilvl.
function IlvlUtils.GetTier(ilvl)
    local t    = Addon.TRACKING
    local base = t and t.ilvlBase
    local step = t and t.ilvlTrackStep
    local ids  = t and t.crestCurrencyIDs
    if not (base and step and ids) or (ilvl or 0) <= 0 then return nil end
    for i = #ids, 1, -1 do
        if ilvl >= base + step * (i - 1) then return i end
    end
    return 1
end

-- Returns the upgrade rank (1-6) within a tier for a given ilvl.
function IlvlUtils.GetRank(ilvl, tier)
    local t       = Addon.TRACKING
    local base    = t and t.ilvlBase
    local step    = t and t.ilvlTrackStep
    local offsets = t and t.ilvlRankOffsets
    if not (base and step and offsets and tier) then return nil end
    local rel = (ilvl or 0) - (base + step * (tier - 1))
    for r = #offsets, 1, -1 do
        if rel >= (offsets[r] or 0) then return r end
    end
    return 1
end

-- Returns an 8-char "ffRRGGBB" hex string for |c colour codes (lowercase prefix).
-- Falls back to opaque white if the tier cannot be determined.
function IlvlUtils.GetColorHex(ilvl)
    local tier   = IlvlUtils.GetTier(ilvl)
    local colors = Addon.TRACKING and Addon.TRACKING.crestColors
    if tier and colors and colors[tier] then
        return "ff" .. colors[tier]
    end
    return "ffffffff"
end

-- Returns a "|cFFRRGGBB" WoW colour-escape prefix for the given tier index.
-- Falls back to opaque white.
function IlvlUtils.GetEscapePrefix(tier)
    local colors = Addon.TRACKING and Addon.TRACKING.crestColors
    if tier and colors and colors[tier] then
        return "|cFF" .. colors[tier]
    end
    return "|cFFFFFFFF"
end

-- Returns the track name for a given tier index, derived from the currency name
-- (e.g. GetCurrencyName(3383) = "Adventurer Dawncrest" → "Adventurer").
function IlvlUtils.GetCrestTrackName(tier)
    local ids = Addon.TRACKING and Addon.TRACKING.crestCurrencyIDs
    local id  = ids and ids[tier]
    if not id then return nil end
    if not (C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo) then return nil end
    local info = C_CurrencyInfo.GetCurrencyInfo(id)
    local fullName = info and info.name
    if not fullName then return nil end
    return fullName:match("^(%S+)")
end

-- Returns a human-readable track+rank label for a given ilvl, e.g. "Champion 1".
-- Returns nil if the tier or rank cannot be determined.
function IlvlUtils.GetTrackLabel(ilvl)
    local tier = IlvlUtils.GetTier(ilvl)
    local rank = IlvlUtils.GetRank(ilvl, tier)
    if not (tier and rank) then return nil end
    local name = IlvlUtils.GetCrestTrackName(tier)
    if not name then return nil end
    return name .. " " .. rank
end
