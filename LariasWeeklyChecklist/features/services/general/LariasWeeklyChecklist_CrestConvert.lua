-- LariasWeeklyChecklist_CrestConvert.lua
-- Shows crest conversion buttons next to the merchant window when the open
-- vendor sells the crest trade-up items (Adventurer→Veteran→Champion→Hero→Myth).
-- Each button triggers a confirmation dialog before executing the bulk purchase.
--
-- Trigger: MERCHANT_SHOW / MERCHANT_CLOSED events.
-- Per-tier items from TRACKING.crestConvertItemIDs are detected by scanning the merchant list.
-- The "Convert All" button converts every tier available from that vendor.
local addonName = ...
local Addon = _G[addonName]
if not Addon then return end

local L = Addon.L or {}

-- Locale keys for crest tier short-names, indexed 1-5 (mirrors UpgradeWarning).
local CREST_LOCALE_KEYS = {
    "ILVLREF_CREST_ADV",
    "ILVLREF_CREST_VET",
    "ILVLREF_CREST_CHAMP",
    "ILVLREF_CREST_HERO",
    "ILVLREF_CREST_MYTH",
}

-- ── Layout constants ──────────────────────────────────────────────────────────
local PAD     = 8
local TITLE_H = 22
local SEP     = 4
local BTN_H   = 22
local BTN_W   = 200
local PANEL_W = BTN_W + PAD * 2

-- Column x-offsets (from button LEFT edge) for the 3 aligned text columns:
--   Col 1: "Src -> Dst"  starts at BTN left pad
--   Col 2: "[cost->gain]" starts at COL_RATIO_X
--   Col 3: "Nx" (count)   starts at COL_COUNT_X
local COL_RATIO_X = 108   -- longest tier pair "Champ -> Hero" fits in 0..107
local COL_COUNT_X = 162   -- ratio "[30->10]" fits in 108..161

-- ── Module state ──────────────────────────────────────────────────────────────
local _panel          -- outer panel frame (created lazily on first merchant visit)
local _btns  = {}     -- [ci] = UIPanelButton for conversion tier ci (1-4)
local _allBtn         -- "Convert All" button
local _disableBtn     -- "Disable" button at the bottom of the panel
local _actions = {}
local _pendingConvert -- callback stored while the confirm dialog is open
local _conversionRunToken = 0

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function GetConvertItemIDs()
    return (Addon.TRACKING and Addon.TRACKING.crestConvertItemIDs) or {}
end

local function BuildItemIndex(values)
    if type(values) ~= "table" then return nil end
    local byItemID = {}
    local count = 0
    for idx, value in ipairs(values) do
        local n = tonumber(value)
        if n then
            byItemID[n] = idx
            count = count + 1
        end
    end
    return count > 0 and byItemID or nil
end

local function IsPlayerInInstance()
    if not IsInInstance then return false end
    local inInstance = IsInInstance()
    return inInstance and true or false
end

local function GetNpcIDFromGUID(guid)
    if type(guid) ~= "string" then return nil end
    local _, _, _, _, _, npcID = strsplit("-", guid)
    return tonumber(npcID)
end

local function IsCrestExchangeMerchant()
    local npcIDs = Addon.TRACKING and Addon.TRACKING.crestExchangeNpcIDs
    local allowed = BuildItemIndex(npcIDs)
    if not allowed then return true end

    local guid = UnitGUID and (UnitGUID("npc") or UnitGUID("target"))
    local npcID = GetNpcIDFromGUID(guid)
    return npcID and allowed[npcID] or false
end

local function ClearActions()
    for k in pairs(_actions) do _actions[k] = nil end
end

-- Returns a tier-coloured short crest name for use in warning text.
-- e.g. tier 1 → "|cFF1EFF00Adv|r"
local function GetCrestShort(tierIdx)
    local name = L[CREST_LOCALE_KEYS[tierIdx]] or CREST_LOCALE_KEYS[tierIdx]
    name = name:gsub("%.$", "")  -- strip any trailing period WoW may add
    return Addon.IlvlUtils.GetEscapePrefix(tierIdx) .. name .. "|r"
end

-- Returns the player's held quantity of crest currency for tier `tierIdx`.
local function GetCrestHeld(tierIdx)
    local ids = Addon.TRACKING and Addon.TRACKING.crestCurrencyIDs
    if not ids then return 0 end
    local id = ids[tierIdx]
    if not (id and C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo) then return 0 end
    local info = C_CurrencyInfo.GetCurrencyInfo(id)
    return info and (tonumber(info.quantity) or 0) or 0
end

local function GetCrestTierByCurrencyID(currencyID)
    local ids = Addon.TRACKING and Addon.TRACKING.crestCurrencyIDs
    local id = tonumber(currencyID)
    if not (id and type(ids) == "table") then return nil end
    for tierIdx, crestID in ipairs(ids) do
        if tonumber(crestID) == id then return tierIdx end
    end
    return nil
end

local function GetCurrencyIDFromLink(link)
    if type(link) ~= "string" then return nil end
    return tonumber(link:match("currency:(%d+)"))
end

local function GetMerchantCostDetails(merchantIdx)
    local costPer, costTier
    if merchantIdx and GetMerchantItemCostInfo and GetMerchantItemCostItem then
        local n = GetMerchantItemCostInfo(merchantIdx) or 0
        for j = 1, n do
            local _, qty, link = GetMerchantItemCostItem(merchantIdx, j)
            qty = tonumber(qty)
            if qty and qty > 0 and not costPer then costPer = qty end
            costTier = costTier or GetCrestTierByCurrencyID(GetCurrencyIDFromLink(link))
        end
    end
    local tb = Addon.TRACKING and Addon.TRACKING.crestTradeBatch
    return costPer or (tb and tonumber(tb[1])) or 30, costTier
end

-- Returns how many target crests each purchase produces (from crestTradeBatch[2]).
local function GetGainPerPurchase()
    local tb = Addon.TRACKING and Addon.TRACKING.crestTradeBatch
    return (tb and tonumber(tb[2])) or 10
end

-- Returns the maximum number of conversion-item purchases given current holdings.
local function GetMaxConv(action)
    if type(action) ~= "table" then return 0 end
    local held    = GetCrestHeld(action.sourceTier)
    local costPer = tonumber(action.costPer) or 0
    if costPer <= 0 then return 0 end
    return math.floor(held / costPer)
end

local function AddAction(action)
    if not (action and action.destTier) then return end
    _actions[#_actions + 1] = action
end

local function GetCurrentActions()
    return _actions
end

local function HasAnyActions()
    return #_actions > 0
end

local function BuildCascadingConversionPlan()
    return Addon.CoreLogic.BuildCascadingConversionPlan(GetCurrentActions(), GetCrestHeld)
end

local function ExecuteConversionPlan(plan, runToken)
    Addon.CoreLogic.RunConversionPlan(plan, {
        isCancelled = function()
            return runToken ~= _conversionRunToken
        end,
        isActionValid = function(action)
            local currentLink = GetMerchantItemLink and GetMerchantItemLink(action.merchantIdx)
            local currentItemID = currentLink and tonumber(currentLink:match("item:(%d+)")) or nil
            return not action.itemID or currentItemID == action.itemID
        end,
        getAvailableCount = GetMaxConv,
        buy = function(action, count)
            if BuyMerchantItem then BuyMerchantItem(action.merchantIdx, count) end
        end,
        schedule = function(delay, callback)
            if C_Timer and C_Timer.After then C_Timer.After(delay, callback) else callback() end
        end,
        onComplete = function()
            if Addon.RefreshCrestConvertPanel then Addon:RefreshCrestConvertPanel() end
        end,
        onAbort = function()
            if Addon.RefreshCrestConvertPanel then Addon:RefreshCrestConvertPanel() end
        end,
    })
end

-- Scans the open merchant and groups conversion rows by direction.
local function ScanMerchant()
    ClearActions()
    local convertItemIDs = GetConvertItemIDs()
    local tierByItemID = BuildItemIndex(convertItemIDs)
    if not tierByItemID then return end
    local n = GetMerchantNumItems and GetMerchantNumItems() or 0
    for i = 1, n do
        local link = GetMerchantItemLink and GetMerchantItemLink(i)
        if link then
            local itemID = tonumber(link:match("item:(%d+)"))
            local itemTierIdx = itemID and tierByItemID[itemID]
            local outputTier = itemTierIdx and itemTierIdx + 1
            if outputTier then
                local costPer, costTier = GetMerchantCostDetails(i)
                if (not costTier) or costTier < outputTier then
                    AddAction({
                        merchantIdx = i,
                        itemID      = itemID,
                        sourceTier  = costTier or itemTierIdx,
                        destTier    = outputTier,
                        costPer     = costPer,
                        gainPer     = GetGainPerPurchase(),
                    })
                end
            end
        end
    end
end

-- ── Confirmation dialog ───────────────────────────────────────────────────────
-- Registered once at load time (guarded by `or` so UI reloads don't overwrite
-- an in-progress dialog).
StaticPopupDialogs["LWMC_CREST_CONVERT"] = StaticPopupDialogs["LWMC_CREST_CONVERT"] or {
    text         = "%s",
    button1      = L.CREST_CONVERT_CONFIRM_BTN or "Convert",
    button2      = CANCEL or "Cancel",
    OnShow       = function(self)
        if Addon.ApplyThemedStaticPopup then
            Addon:ApplyThemedStaticPopup(self)
        end
    end,
    OnAccept     = function()
        local cb = _pendingConvert
        _pendingConvert = nil
        if cb then cb() end
    end,
    OnCancel     = function()
        _pendingConvert = nil
    end,
    timeout      = 0,
    whileDead    = false,
    hideOnEscape = true,
    preferredIndex = 3,
}

local function ShowConfirm(warnText, callback)
    _pendingConvert = callback
    if Addon.ShowThemedStaticPopup then
        Addon:ShowThemedStaticPopup("LWMC_CREST_CONVERT", warnText)
    else
        StaticPopup_Show("LWMC_CREST_CONVERT", warnText)
    end
end

-- ── Panel creation ────────────────────────────────────────────────────────────
-- Called lazily the first time a crest-conversion vendor is opened.
local function BuildPanel()
    if _panel then return end

    local holder = Addon:NewThemedFrame(nil, UIParent)
    holder:SetFrameStrata("DIALOG")
    holder:SetFrameLevel(150)
    holder:SetSize(PANEL_W, 100)  -- height resized dynamically in Refresh
    holder:SetClampedToScreen(true)
    holder:EnableMouse(true)
    holder:SetMovable(true)
    holder:Hide()

    Addon:ApplyWarningPanelTheme(holder, {
        title = L.CREST_CONVERT_TITLE or "Crest Conversion",
        pad = PAD,
        bodyTop = 42,
        titleTop = 10,
    })

    -- Anchor to the right edge of MerchantFrame when it exists.
    if MerchantFrame then
        holder:SetPoint("LEFT", MerchantFrame, "RIGHT", 5, 0)
    else
        holder:SetPoint("CENTER", UIParent, "CENTER", 350, 0)
    end

    local gdb = Addon:EnsurePrefs()
    gdb.crestConvertWin = gdb.crestConvertWin or {}
    local LW = LibStub("LibWindow-1.1")
    LW.RegisterConfig(holder, gdb.crestConvertWin)
    LW.MakeDraggable(holder)
    if gdb.crestConvertWin.x ~= nil and gdb.crestConvertWin.y ~= nil then
        LW.RestorePosition(holder)
    end

    -- Create one button per visible conversion row; shown/positioned in Refresh.
    -- Each button uses 3 FontStrings at fixed x offsets so columns stay aligned
    -- regardless of tier-name length (proportional font requires this approach).
    local convertItemIDs = GetConvertItemIDs()
    for ci = 1, #convertItemIDs do
        local btn = Addon.Controls.NewActionButton(holder, BTN_W, BTN_H)
        btn:SetText("")
        -- Col 1: "Src -> Dst" – reuse the button's own FS so SetEnabled tints it.
        local fs1 = btn:GetFontString()
        fs1:SetJustifyH("LEFT")
        fs1:ClearAllPoints()
        fs1:SetPoint("LEFT",  btn, "LEFT", 8, 0)
        fs1:SetPoint("RIGHT", btn, "LEFT", COL_RATIO_X, 0)
        -- Col 2: "[cost->gain]"
        local fs2 = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        fs2:SetJustifyH("LEFT")
        fs2:SetPoint("LEFT",  btn, "LEFT", COL_RATIO_X, 0)
        fs2:SetPoint("RIGHT", btn, "LEFT", COL_COUNT_X, 0)
        -- Col 3: count "Nx"
        local fs3 = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        fs3:SetJustifyH("LEFT")
        fs3:SetPoint("LEFT",  btn, "LEFT", COL_COUNT_X, 0)
        fs3:SetPoint("RIGHT", btn, "RIGHT", -4, 0)
        btn._fs2 = fs2
        btn._fs3 = fs3
        btn:Hide()
        local capturedRow = ci
        btn:SetScript("OnClick", function()
            local action = GetCurrentActions()[capturedRow]
            if not action then return end
            local maxConv = GetMaxConv(action)
            if maxConv <= 0 then return end
            local costPer   = action.costPer
            local gainPer   = action.gainPer
            local srcName   = GetCrestShort(action.sourceTier)
            local dstName   = GetCrestShort(action.destTier)
            local totalCost = maxConv * costPer
            local totalGain = maxConv * gainPer
            local fmt = L.CREST_CONVERT_WARN_SINGLE
                or "|cffff9900Warning:|r\n\nThis will convert %d %s crests into %d %s crests.\n\nThis cannot be undone."
            local warnText = string.format(fmt, totalCost, srcName, totalGain, dstName)
            ShowConfirm(warnText, function()
                if BuyMerchantItem then
                    BuyMerchantItem(action.merchantIdx, maxConv)
                end
                C_Timer.After(0.4, function()
                    Addon:RefreshCrestConvertPanel()
                end)
            end)
        end)
        _btns[ci] = btn
    end

    -- "Convert All" button — converts every available tier this vendor offers.
    local allBtn = Addon.Controls.NewActionButton(holder, BTN_W, BTN_H)
    allBtn:SetText(L.CREST_CONVERT_ALL_BTN or "Convert All")
    allBtn:Hide()
    allBtn:SetScript("OnClick", function()
        local plan    = BuildCascadingConversionPlan()
        local lines   = {}
        for _, step in ipairs(plan) do
            local action = step.action
            local maxConv = step.count
            local srcName   = GetCrestShort(action.sourceTier)
            local dstName   = GetCrestShort(action.destTier)
            local totalCost = maxConv * action.costPer
            local totalGain = maxConv * action.gainPer
            table.insert(lines, string.format(
                "%s -> %s  (%d -> %d)", srcName, dstName, totalCost, totalGain
            ))
        end
        if #plan == 0 then return end
        local hdrTxt  = L.CREST_CONVERT_WARN_ALL_HDR
            or "|cffff9900Warning:|r\n\nThe following conversions will be performed:\n\n"
        local footer  = "\n\n" .. (L.CREST_CONVERT_WARN_FOOTER or "These actions cannot be undone.")
        local warnText = hdrTxt .. table.concat(lines, "\n") .. footer
        ShowConfirm(warnText, function()
            _conversionRunToken = _conversionRunToken + 1
            ExecuteConversionPlan(plan, _conversionRunToken)
        end)
    end)
    _allBtn = allBtn

    -- "Disable" button: permanently hides the panel until re-enabled via Options.
    local disableBtn = Addon.Controls.NewActionButton(holder, BTN_W, BTN_H)
    disableBtn:SetText(L.CREST_CONVERT_DISABLE_BTN or "Disable Conversion Panel")
    disableBtn:SetScript("OnClick", function()
        Addon:EnsurePrefs().crestConvertDisabled = true
        _panel:Hide()
        if Addon.SyncGearPopup then Addon:SyncGearPopup() end
    end)
    disableBtn:SetScript("OnEnter", function(self_)
        Addon.AddonUtils.SetTooltip(self_, L.CREST_CONVERT_DISABLE_TOOLTIP or "")
    end)
    disableBtn:SetScript("OnLeave", Addon.AddonUtils.HideTooltip)
    _disableBtn = disableBtn

    _panel = holder
    Addon._crestConvertPanel = holder
end

-- ── Public refresh ────────────────────────────────────────────────────────────
-- Repositions and relabels all buttons based on what the current merchant sells
-- and the player's current crest holdings.  Also resizes the panel to fit.
function Addon:RefreshCrestConvertPanel()
    if not _panel then return end

    local visible = GetCurrentActions()
    local convertItemIDs = GetConvertItemIDs()

    -- Hide every button first.
    for ci = 1, #convertItemIDs do
        if _btns[ci] then _btns[ci]:Hide() end
    end
    if _allBtn then _allBtn:Hide() end

    if not HasAnyActions() then
        _panel:Hide()
        return
    end

    -- Layout: title sits at the top; buttons stack downward.
    local anyAvail = false
    local yOff     = -(PAD + TITLE_H + SEP)

    for rowIdx, action in ipairs(visible) do
        local btn      = _btns[rowIdx]
        if not btn then break end
        local maxConv  = GetMaxConv(action)
        local srcName  = GetCrestShort(action.sourceTier)
        local dstName  = GetCrestShort(action.destTier)
        local costPer  = action.costPer
        local gainPer  = action.gainPer
        local timesStr = "\195\151"   -- ×
        if maxConv > 0 then anyAvail = true end
        btn:ClearAllPoints()
        btn:SetPoint("TOP", _panel, "TOP", 0, yOff)
        -- Col 1: tier pair
        btn:SetText(srcName .. " -> " .. dstName)
        -- Col 2: ratio (always same dim-grey style)
        btn._fs2:SetText("|cff555555[" .. costPer .. "->" .. gainPer .. "]|r")
        -- Col 3: count, green when available, grey when not
        btn._fs3:SetText(maxConv > 0
            and ("|cff40ff40" .. maxConv .. timesStr .. "|r")
            or  ("|cff808080" .. "0"      .. timesStr .. "|r"))
        btn:SetEnabled(maxConv > 0)
        btn:Show()
        yOff = yOff - (BTN_H + SEP)
    end

    -- "Convert All" below a small extra gap.
    yOff = yOff - SEP
    _allBtn:ClearAllPoints()
    _allBtn:SetPoint("TOP", _panel, "TOP", 0, yOff)
    _allBtn:SetText(L.CREST_CONVERT_ALL_BTN or "Convert All")
    _allBtn:SetEnabled(anyAvail)
    _allBtn:Show()
    yOff = yOff - (BTN_H + SEP)

    -- "Disable" button always shown at the bottom of the panel.
    yOff = yOff - SEP
    _disableBtn:ClearAllPoints()
    _disableBtn:SetPoint("TOP", _panel, "TOP", 0, yOff)
    _disableBtn:Show()
    yOff = yOff - (BTN_H + SEP)

    -- Resize panel to fit its contents.
    local newH = -yOff + PAD
    _panel:SetSize(PANEL_W, newH)
    _panel:Show()
end

-- ── Event handling ────────────────────────────────────────────────────────────
local evFrame = CreateFrame("Frame")
evFrame:RegisterEvent("MERCHANT_SHOW")
evFrame:RegisterEvent("MERCHANT_CLOSED")
evFrame:SetScript("OnEvent", function(_, event)
    if event == "MERCHANT_SHOW" then
        _conversionRunToken = _conversionRunToken + 1
        ClearActions()
        if _panel then _panel:Hide() end
        if _pendingConvert then
            StaticPopup_Hide("LWMC_CREST_CONVERT")
            _pendingConvert = nil
        end

        -- Small delay so GetMerchantItemLink returns valid data on first open.
        C_Timer.After(0.05, function()
            local prefs = Addon.EnsurePrefs and Addon:EnsurePrefs()
            if prefs and prefs.crestConvertDisabled then return end
            if IsPlayerInInstance() then return end
            if not IsCrestExchangeMerchant() then return end

            ScanMerchant()
            if HasAnyActions() then
                BuildPanel()
                Addon:RefreshCrestConvertPanel()
            elseif _panel then
                _panel:Hide()
            end
        end)

    elseif event == "MERCHANT_CLOSED" then
        _conversionRunToken = _conversionRunToken + 1
        ClearActions()
        if _panel then _panel:Hide() end
        if _pendingConvert then
            StaticPopup_Hide("LWMC_CREST_CONVERT")
            _pendingConvert = nil
        end
    end
end)

-- ── Locale key reference (for translators) ────────────────────────────────────
-- L.CREST_CONVERT_TITLE         — Panel title text.
-- L.CREST_CONVERT_ALL_BTN       — "Convert All" button label.
-- L.CREST_CONVERT_WARN_SINGLE   — Warning for a single tier (fmt: cost, srcName, gain, dstName).
-- L.CREST_CONVERT_WARN_ALL_HDR  — Header for the "Convert All" confirmation.
-- L.CREST_CONVERT_WARN_FOOTER   — Footer appended to the "Convert All" warning.
-- L.CREST_CONVERT_CONFIRM_BTN   — Label for the confirm button in the dialog.
