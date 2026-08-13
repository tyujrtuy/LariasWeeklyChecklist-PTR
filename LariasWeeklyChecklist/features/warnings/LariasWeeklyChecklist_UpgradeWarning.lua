-- Watches the item-upgrade UI and warns when a player is about to upgrade an
-- item that is still at rank 1 of its upgrade track.
local addonName = ...
local Addon = _G[addonName]
if not Addon then return end

local L = Addon.L or {}

-- DEV is true when the TOC version contains a hyphen, e.g. "2.1.2-dev".
local _devChecked, _devValue
local function IsDevBuild()
    if not _devChecked then
        _devChecked = true
        local getMeta = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
        local ver = (getMeta and getMeta(addonName, "Version")) or ""
        _devValue = ver:find("-") ~= nil
    end
    return _devValue
end

local _warn  -- { holder, label, disableBtn }

local function ApplyUpgradeWarningTheme()
    if not _warn then return end
    local txt = Addon.THEME and Addon.THEME.text
    local bg = Addon.THEME and Addon.THEME.bg
    local vs = Addon.VISUAL_STYLE or {}
    if _warn.label and _warn.label.SetTextColor then
        if txt then
            _warn.label:SetTextColor(txt.r, txt.g, txt.b, txt.a or 1)
        end
        if _warn.label.SetShadowColor and bg then
            _warn.label:SetShadowColor(bg.r, bg.g, bg.b, vs.textShadowA or bg.a or 1)
        end
    end
    if _warn.disableBtn and Addon.Controls and Addon.Controls.StyleButton then
        Addon.Controls.StyleButton(_warn.disableBtn)
    end
end

function Addon:RefreshUpgradeWarningTheme()
    ApplyUpgradeWarningTheme()
end

local CREST_LOCALE_KEYS = {
    "ILVLREF_CREST_ADV",
    "ILVLREF_CREST_VET",
    "ILVLREF_CREST_CHAMP",
    "ILVLREF_CREST_HERO",
    "ILVLREF_CREST_MYTH",
}

local function GetCrestShort(tierIdx)
    local name = L[CREST_LOCALE_KEYS[tierIdx]] or CREST_LOCALE_KEYS[tierIdx]
    name = name:gsub("%.$", "")
    return Addon.IlvlUtils.GetEscapePrefix(tierIdx) .. name .. "|r"
end

function Addon:CheckUpgradeWarning()
    if _warn then _warn.holder:Hide() end

    local prefs = self:EnsurePrefs()
    if prefs.upgradeWarnDisabled then return end
    if not _warn then return end

    if not (C_ItemUpgrade and C_ItemUpgrade.GetItemUpgradeItemInfo) then return end

    local info = C_ItemUpgrade.GetItemUpgradeItemInfo()
    if not info then return end

    local currentLevel = tonumber(info.currUpgrade)
    local maxLevel     = tonumber(info.maxUpgrade)
    if not (currentLevel and maxLevel) then return end

    if maxLevel < 2 or currentLevel > 1 then return end

    local tracking = Addon.TRACKING
    local crestIDs = tracking and tracking.crestCurrencyIDs
    if not crestIDs then return end

    local lvlInfos = info.upgradeLevelInfos
    local step = lvlInfos and (lvlInfos[currentLevel + 1] or lvlInfos[currentLevel])
    local costs = step and step.currencyCostsToUpgrade
    local tierIdx, upgradeCurrencyID, upgradeCount = self:GetCrestTierFromCosts(costs)

    local isDev = IsDevBuild()
    if not upgradeCurrencyID and not isDev then return end

    if not isDev and (not tierIdx or tierIdx < 2) then return end
    if not tierIdx then tierIdx = 1 end

    local upgradeCost = upgradeCount or 0
    if upgradeCost <= 0 then return end

    local currentName = GetCrestShort(tierIdx)
    local prevName    = GetCrestShort(math.max(tierIdx - 1, 1))
    local fmt = L.UPGRADE_WARN_MSG or "Upgrading a 1/6 %s item is a waste of %d crests.\nYou should upgrade a 5/6 %s item instead"
    _warn.label:SetText(string.format(fmt, currentName, upgradeCost, prevName))
    _warn.holder:Show()
end

local function SetupHooks()
    if ItemUpgradeFrame then
        local PAD_W   = 16
        local BTN_H   = 24
        local PANEL_H = 120

        local holder = Addon:NewThemedFrame(nil, UIParent)
        holder:SetFrameStrata("DIALOG")
        holder:SetFrameLevel(200)
        holder:SetSize(430, PANEL_H)
        holder:SetClampedToScreen(true)
        holder:EnableMouse(true)
        holder:SetPoint("TOP", ItemUpgradeFrame, "BOTTOM", 0, -6)
        local bodyTop = Addon:ApplyWarningPanelTheme(holder, {
            title = L.UPGRADE_WARN_TITLE or "Upgrade Advice",
            pad = PAD_W,
            bodyTop = 52,
        })
        holder:Hide()

        local label = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        label:SetPoint("TOPLEFT",  holder, "TOPLEFT",  PAD_W,  -bodyTop)
        label:SetPoint("TOPRIGHT", holder, "TOPRIGHT", -PAD_W, -bodyTop)
        label:SetHeight(42)
        label:SetJustifyH("CENTER")
        label:SetJustifyV("MIDDLE")
        label:SetSpacing(2)
        label:SetWordWrap(true)
        label:SetShadowOffset(1, -1)

        local disableBtn = Addon.Controls.NewActionButton(holder, 220, BTN_H)
        disableBtn:SetPoint("BOTTOM", holder, "BOTTOM", 0, 10)
        disableBtn:SetText(L.UPGRADE_WARN_DISABLE_BTN or "Hide Upgrade Warning")
        disableBtn:SetScript("OnEnter", function(self)
            Addon.AddonUtils.SetTooltip(self, L.UPGRADE_WARN_DISABLE_TOOLTIP or "Check Larias' guide for more information.", "ANCHOR_BOTTOM")
        end)
        disableBtn:SetScript("OnLeave", Addon.AddonUtils.HideTooltip)
        disableBtn:SetScript("OnClick", function()
            Addon:EnsurePrefs().upgradeWarnDisabled = true
            holder:Hide()
            if Addon.RefreshSettingsCheckboxes then Addon:RefreshSettingsCheckboxes() end
            if Addon.SyncGearPopup then Addon:SyncGearPopup() end
        end)

        _warn = { holder = holder, label = label, disableBtn = disableBtn }
        ApplyUpgradeWarningTheme()

        hooksecurefunc(ItemUpgradeFrame, "Show", function()
            C_Timer.After(0, function()
                Addon:CheckUpgradeWarning()
            end)
        end)
        hooksecurefunc(ItemUpgradeFrame, "Hide", function()
            if _warn then _warn.holder:Hide() end
        end)
    end

    local slotFrame = CreateFrame("Frame")
    slotFrame:RegisterEvent("ITEM_UPGRADE_MASTER_SET_ITEM")
    slotFrame:SetScript("OnEvent", function()
        Addon:CheckUpgradeWarning()
    end)
end

if ItemUpgradeFrame then
    SetupHooks()
else
    local setupFrame = CreateFrame("Frame")
    setupFrame:RegisterEvent("ADDON_LOADED")
    setupFrame:SetScript("OnEvent", function(_, _, loadedAddon)
        if loadedAddon ~= "Blizzard_ItemUpgradeUI" then return end
        setupFrame:UnregisterAllEvents()
        SetupHooks()
    end)
end
