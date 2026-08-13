-- Gear popup: small floating panel with the 8 display toggles.
-- Appears when the gear icon in the main window header is clicked.
local addonName = ...
local Addon = _G[addonName]
if not Addon then return end
local L = Addon.L or {}

-- (SetCheckText, OpenPopupColorPicker, LOCALE_NATIVE_NAMES moved / removed;
--  pane builders in LariasWeeklyChecklist_Options.lua handle all of this now.)

function Addon:SyncGearPopup()
    local p = self._gearPopup
    if not p then return end
    -- Delegate all pane-level syncing to the shared builder sync closures.
    if p._displaySync    then p._displaySync()    end
    if p._warningsSync   then p._warningsSync()   end
    if p._appearanceSync then p._appearanceSync() end
    -- Re-apply tab colours (active tab gets header colour, others are dimmed).
    if p._ShowTab then p._ShowTab(p._activeTab or 1) end
end

function Addon:ToggleGearPopup(anchor, growRight)
    local p = self._gearPopup
    if p and p.IsShown and p:IsShown() then
        p:Hide()
        return
    end

    -- Create lazily.
    if not p then
        p = Addon.Controls.NewPopupPanel("DIALOG", 0.12)
        Addon:ApplyPopupBorder(p)

        -- ── Layout constants ─────────────────────────────────────────────────
        local POPUP_W     = 340
        local POPUP_H     = 330
        local PAD         = 10
        local BTN_H       = 22
        local TILE_H      = 28    -- checkbox tile height (box + padding)
        local TAB_BTN_H   = 22
        local TAB_GAP     = 6     -- gap between tab-button row and pane content
        local PANE_TOP    = PAD + TAB_BTN_H + TAB_GAP   -- 38 px from popup top
        local BOTTOM_H    = 80    -- px reserved at bottom for support links + credit
        local NUM_TABS    = 3
        local TAB_GAP_BTN = 4     -- gap between adjacent tab buttons
        local TAB_W       = math.floor((POPUP_W - 2 * PAD - (NUM_TABS - 1) * TAB_GAP_BTN) / NUM_TABS)

        p:SetSize(POPUP_W, POPUP_H)

        -- ── Tab buttons ──────────────────────────────────────────────────────
        local TAB_LABELS = {
            L.SETTINGS_TAB_DISPLAY or "Display",
            L.SETTINGS_TAB_WARNINGS or "Warnings",
            L.SETTINGS_TAB_APPEARANCE or "Appearance",
        }
        p._tabs  = {}
        p._panes = {}

        for i = 1, NUM_TABS do
            local tx = PAD + (i - 1) * (TAB_W + TAB_GAP_BTN)
            local tb = Addon.Controls.NewActionButton(p, TAB_W, TAB_BTN_H)
            tb:SetPoint("TOPLEFT", p, "TOPLEFT", tx, -PAD)
            tb:SetText(TAB_LABELS[i])
            local _i = i
            tb:SetScript("OnClick", function()
                if p._ShowTab then p._ShowTab(_i) end
            end)
            -- Active indicator: thin gold bar at the bottom of the active tab button.
            local bar = tb:CreateTexture(nil, "OVERLAY")
            bar:SetColorTexture(Addon.THEME.header.r, Addon.THEME.header.g, Addon.THEME.header.b, 1)
            bar:SetPoint("BOTTOMLEFT",  tb, "BOTTOMLEFT",  2, 1)
            bar:SetPoint("BOTTOMRIGHT", tb, "BOTTOMRIGHT", -2, 1)
            bar:SetHeight(2)
            bar:Hide()
            tb._activeBar = bar
            p._tabs[i] = tb
        end

        -- ── Pane frames (one per tab, fills between tab row and bottom section) ──
        for i = 1, NUM_TABS do
            local pane = CreateFrame("Frame", nil, p)
            pane:SetPoint("TOPLEFT",     p, "TOPLEFT",     0, -PANE_TOP)
            pane:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", 0,  BOTTOM_H)
            pane:Hide()
            p._panes[i] = pane
        end
        local pane1, pane2, pane3 = p._panes[1], p._panes[2], p._panes[3]

        -- ── ShowTab helper ───────────────────────────────────────────────────
        local function ShowTab(tabIdx)
            p._activeTab = tabIdx
            local hdr = Addon.THEME.header
            for i = 1, NUM_TABS do
                local tb = p._tabs[i]
                local pn = p._panes[i]
                local tr = Addon.Controls.GetButtonFontString(tb)
                if i == tabIdx then
                    if tr then tr:SetTextColor(hdr.r, hdr.g, hdr.b, 1) end
                    if tb._activeBar then tb._activeBar:Show() end
                    if pn then pn:Show() end
                else
                    if tr then tr:SetTextColor(0.5, 0.5, 0.5, 1) end
                    if tb._activeBar then tb._activeBar:Hide() end
                    if pn then pn:Hide() end
                end
            end
        end
        p._ShowTab = ShowTab

        -- ── Pane 1: Display ──────────────────────────────────────────────────
        do
            local opts = { pad = PAD, btnH = BTN_H, tileH = TILE_H, width = POPUP_W,
                           restoreClickFn = function() Addon:ToggleRestoreHiddenCurrencies(p) end }
            local dr = Addon.OptionsPane.BuildDisplay(pane1, opts)
            p._displaySync = dr.sync
        end

        -- ── Pane 2: Warnings ─────────────────────────────────────────────────
        do
            local opts = { pad = PAD, tileH = TILE_H, width = POPUP_W }
            local wr = Addon.OptionsPane.BuildWarnings(pane2, opts)
            p._warningsSync = wr.sync
        end

        -- ── Pane 3: Appearance ────────────────────────────────────────────────
        do
            local opts = { pad = PAD, btnH = BTN_H, width = POPUP_W, showLangBtn = true }
            local ar = Addon.OptionsPane.BuildAppearance(pane3, opts)
            p._appearanceSync = ar.sync
        end

        -- ── Bottom section (always visible): divider, support links, credit ──
        do
            local _getMeta = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
            local _ver     = (_getMeta and _getMeta(addonName, "Version")) or ""
            local _locReg  = _G["LARIASWEEKLYCHECKLIST_LOCALE_REGISTRY"]
            local _dataVer = (_locReg and type(_locReg.sheet_version) == "string" and _locReg.sheet_version) or ""

            local creditLabel = p:CreateFontString(nil, "OVERLAY")
            creditLabel:SetFont("Fonts\\FRIZQT__.TTF", 9, "")
            creditLabel:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", 8, 5)
            creditLabel:SetJustifyH("LEFT")
            creditLabel:SetText(L.CREDIT_BUILT_BY or "Built by Dev  \226\128\162  Approved by Larias")
            creditLabel:SetTextColor(0.45, 0.45, 0.45, 0.6)

            local verLabel = p:CreateFontString(nil, "OVERLAY")
            verLabel:SetFont("Fonts\\FRIZQT__.TTF", 9, "")
            verLabel:SetPoint("BOTTOMLEFT", creditLabel, "TOPLEFT", 0, 2)
            verLabel:SetJustifyH("LEFT")
            do
                local parts = {}
                if _ver     ~= "" then parts[#parts + 1] = (L.VERSION_LABEL_FMT or "v%s"):format(_ver) end
                if _dataVer ~= "" then parts[#parts + 1] = (L.SPREADSHEET_VERSION_LABEL_FMT or "Spreadsheet v%s"):format(_dataVer) end
                verLabel:SetText(table.concat(parts, "  \226\128\162  "))
            end
            verLabel:SetTextColor(0.45, 0.45, 0.45, 0.6)

            -- Divider above support buttons.
            Addon.Controls.NewDivider(p, 76, PAD, PAD, "BOTTOM")

            -- Three support link buttons.
            local SUPP_BTN_W = math.floor((POPUP_W - 2 * PAD - 8) / 3)
            for si, sl in ipairs(Addon:GetSupportLinks()) do
                local _url = sl.url
                local sx   = PAD + (si - 1) * (SUPP_BTN_W + 4)
                local sbtn = Addon.Controls.NewActionButton(p, SUPP_BTN_W, 22)
                sbtn:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", sx, 48)
                sbtn:SetText(sl.label)
                sbtn:SetScript("OnClick", function() Addon.OpenSupportLink(_url) end)
            end
        end

        self._gearPopup = p
        -- Apply saved opacity to the new popup (created with alpha=1.0).
        if self.ApplyOpacity then self:ApplyOpacity() end
    end

    -- Sync current values and labels (also calls ShowTab(1) to set initial state).
    self:SyncGearPopup()

    -- Position below the anchor or center if no anchor.
    -- growRight=true  → popup grows rightward (TOPLEFT anchored to anchor BOTTOMLEFT)
    -- growRight=false → popup grows leftward  (TOPRIGHT anchored to anchor BOTTOMRIGHT)
    p:ClearAllPoints()
    if anchor then
        if growRight then
            p:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4)
        else
            p:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -4)
        end
    else
        p:SetPoint("CENTER", UIParent, "CENTER")
    end
    p:Show()
end

--- Opens (or rebuilds) the restore-hidden-currencies panel anchored to `anchor`.
--- If `anchor` is nil, keeps the panel's current position.
function Addon:OpenRestoreHiddenCurrencies(anchor)
    -- Build a unified list: hidden currencies, items, vault blocks, and quests.
    local combined = {}
    for _, e in ipairs(self.GetHiddenItemList and self:GetHiddenItemList() or {}) do
        local _id = e.id
        combined[#combined + 1] = {
            name      = e.name .. " |cff808080" .. (L.RESTORE_HIDDEN_ITEM_SUFFIX or "(Item)") .. "|r",
            onRestore = function() Addon:SetItemHidden(_id, false) end,
        }
    end
    for _, e in ipairs(self:GetHiddenGVBlockList()) do
        local _idx = e.idx
        combined[#combined + 1] = {
            name      = e.name .. " |cff808080" .. (L.RESTORE_HIDDEN_VAULT_SUFFIX or "(Vault)") .. "|r",
            onRestore = function() Addon:SetGVBlockHidden(_idx, false) end,
        }
    end
    for _, e in ipairs(self:GetHiddenQuestList()) do
        local _qk = e.key
        combined[#combined + 1] = {
            name      = e.name .. " |cff808080" .. (L.RESTORE_HIDDEN_QUEST_SUFFIX or "(Quest)") .. "|r",
            onRestore = function() Addon:SetQuestHidden(_qk, false) end,
        }
    end
    for _, e in ipairs(self.GetHiddenCrestAchievementList and self:GetHiddenCrestAchievementList() or {}) do
        local _tierIdx = e.tierIdx
        combined[#combined + 1] = {
            name      = e.name .. " |cff808080" .. (L.RESTORE_HIDDEN_ACHIEVEMENT_SUFFIX or "(Achievement)") .. "|r",
            onRestore = function() Addon:SetCrestAchievementHidden(_tierIdx, false) end,
        }
    end
    if #combined == 0 then
        if self._restoreHiddenFrame then self._restoreHiddenFrame:Hide() end
        return
    end

    local f = self._restoreHiddenFrame
    local ROW_H, PAD, BTN_W = 22, 8, 70

    if not f then
        f = CreateFrame("Frame", "LariasRestoreHiddenFrame", UIParent, "BackdropTemplate")
        f:SetFrameStrata("DIALOG")
        f:SetClampedToScreen(true)
        -- Close button
        local xClose = Addon.Controls.NewCloseButton(f, function() f:Hide() end)
        xClose:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
        f._rowFrames = {}
        self._restoreHiddenFrame = f
        -- Register with UISpecialFrames so ESC closes this window.
        tinsert(UISpecialFrames, "LariasRestoreHiddenFrame")
    end

    -- Apply theme backdrop.
    self:ApplyOpaquePopupTheme(f)

    -- Title
    if not f._titleFS then
        f._titleFS = f:CreateFontString(nil, "OVERLAY")
        f._titleFS:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
        f._titleFS:SetPoint("TOPLEFT",  f, "TOPLEFT",  PAD, -PAD)
        f._titleFS:SetPoint("TOPRIGHT", f, "TOPRIGHT", -20, -PAD)
        f._titleFS:SetHeight(16)
        f._titleFS:SetJustifyH("LEFT")
    end
    local hdr = self.THEME and self.THEME.header
    if hdr then f._titleFS:SetTextColor(hdr.r, hdr.g, hdr.b, 1) end
    f._titleFS:SetText(L.RESTORE_HIDDEN_TITLE or "Restore Hidden Currencies")

    -- Hide old row frames and rebuild.
    for _, rf in ipairs(f._rowFrames) do rf:Hide() end
    f._rowFrames = {}

    local th = self.THEME and self.THEME.text
    for ri, entry in ipairs(combined) do
        local rowY = -(PAD + 16 + 4 + (ri - 1) * ROW_H)
        local rf   = CreateFrame("Frame", nil, f)
        rf:SetPoint("TOPLEFT",  f, "TOPLEFT",  PAD, rowY)
        rf:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, rowY)
        rf:SetHeight(ROW_H)

        local nameFS = rf:CreateFontString(nil, "OVERLAY")
        nameFS:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
        nameFS:SetPoint("LEFT",  rf, "LEFT",  0, 0)
        nameFS:SetPoint("RIGHT", rf, "RIGHT", -(BTN_W + 4), 0)
        nameFS:SetJustifyH("LEFT")
        nameFS:SetJustifyV("MIDDLE")
        nameFS:SetText(entry.name)
        if th then nameFS:SetTextColor(th.r, th.g, th.b, 0.9) end

        local btn = Addon.Controls.NewActionButton(rf, nil, 18)
        btn:SetWidth(BTN_W)
        btn:SetPoint("RIGHT", rf, "RIGHT", 0, 0)
        btn:SetText(L.RESTORE_HIDDEN_BTN or "Restore")
        btn:SetScript("OnClick", function()
            entry.onRestore()
        end)
        if Addon._styleActionButton then Addon._styleActionButton(btn) end

        f._rowFrames[ri] = rf
    end

    local totalH = PAD + 16 + 4 + #combined * ROW_H + PAD
    f:SetSize(240, totalH)

    if anchor then
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 4, 0)
    elseif not (f.GetNumPoints and f:GetNumPoints() > 0) then
        f:SetPoint("CENTER")
    end
    f:Show()
end

--- Toggles the restore-hidden-currencies panel.
function Addon:ToggleRestoreHiddenCurrencies(anchor)
    local f = self._restoreHiddenFrame
    if f and f.IsShown and f:IsShown() then
        f:Hide()
    else
        self:OpenRestoreHiddenCurrencies(anchor)
    end
end
