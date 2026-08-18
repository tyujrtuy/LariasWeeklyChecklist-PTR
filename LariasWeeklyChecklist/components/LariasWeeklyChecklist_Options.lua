local addonName = ...
local Addon = _G[addonName]
if not Addon then return end

function Addon:SyncOptionsTabControls()
    -- Options tab removed; keep as stub so existing call-sites don't error.
    if self.SyncGearPopup then self:SyncGearPopup() end
end

function Addon:UpdateOptionsLocalizedUI()
    -- Refresh gear popup labels when locale changes.
    if self.SyncGearPopup then self:SyncGearPopup() end
end

-- CreateBlizzOptionsPanel: no longer registers with Blizzard Interface -> AddOns.
-- Options are now accessed via the gear icon / minimap right-click (gear popup).
function Addon:CreateBlizzOptionsPanel()
    -- Intentionally a no-op; kept so call-sites don't error.
end

-- ════════════════════════════════════════════════════════════════════════════
-- Shared options pane builders
-- Used by both the floating GearPopup and the Interface→AddOns Settings panel.
-- ════════════════════════════════════════════════════════════════════════════

Addon.OptionsPane = {}

-- Calls both UIs' sync closures so either open panel stays up to date.
local function _applyAll()
    if Addon.SyncGearPopup            then Addon:SyncGearPopup()             end
    if Addon.RefreshSettingsCheckboxes then Addon:RefreshSettingsCheckboxes() end
end

-- ── Display tab row definitions ───────────────────────────────────────────────
Addon.OptionsPane.DISPLAY_ROWS = {
    {
        field    = "cbHideCompletedTasks",
        labelKey = "OPTIONS_HIDE_COMPLETED_TASKS",  default = "Hide Completed Tasks",
        tipKey   = "OPTIONS_TOOLTIP_HIDE_COMPLETED_TASKS",
        getVal   = function(d) return d.hideCompletedTasks and true or false end,
        onChange = function(v)
            local d = Addon:EnsurePrefs()
            d.hideCompletedTasks = v
            _applyAll()
            if Addon.LayoutHeaderButtons then Addon:LayoutHeaderButtons() end
            if Addon.RequestRefresh then Addon:RequestRefresh() else Addon:Refresh() end
        end,
    },
    {
        field    = "cbHideGreatVault",
        labelKey = "OPTIONS_HIDE_GREAT_VAULT",      default = "Hide Great Vault",
        tipKey   = "OPTIONS_TOOLTIP_HIDE_GREAT_VAULT",
        getVal   = function(d) return not d.showGreatVault end,
        onChange = function(v)
            Addon:EnsurePrefs().showGreatVault = not v
            _applyAll()
            if Addon.RequestRefresh then Addon:RequestRefresh() else Addon:Refresh() end
        end,
    },
    {
        field    = "cbHideCurrency",
        labelKey = "OPTIONS_HIDE_CURRENCY",         default = "Hide Currency",
        tipKey   = "OPTIONS_TOOLTIP_HIDE_CURRENCY",
        getVal   = function(d) return not d.showCurrency end,
        onChange = function(v)
            Addon:EnsurePrefs().showCurrency = not v
            _applyAll()
            if Addon.RequestRefresh then Addon:RequestRefresh() else Addon:Refresh() end
        end,
    },
    {
        field    = "cbHideIlvlRef",
        labelKey = "OPTIONS_HIDE_ILVL_REF_BTN",     default = "Hide Ilvl Reference",
        tipKey   = "OPTIONS_TOOLTIP_HIDE_ILVL_REF_BTN",
        getVal   = function(d) return d.showIlvlRefBtn == false end,
        onChange = function(v)
            Addon:EnsurePrefs().showIlvlRefBtn = not v
            _applyAll()
            if Addon.LayoutHeaderButtons then Addon:LayoutHeaderButtons() end
        end,
    },
    {
        field    = "cbHideMinimapBtn",
        labelKey = "OPTIONS_HIDE_MINIMAP_BTN",      default = "Hide Minimap Button",
        tipKey   = "OPTIONS_TOOLTIP_HIDE_MINIMAP_BTN",
        getVal   = function(_d)
            local g = Addon.db and Addon.db.global
            return g and g.minimap and g.minimap.hide and true or false
        end,
        onChange = function(v)
            local g = Addon.db and Addon.db.global
            if g then g.minimap = g.minimap or {}; g.minimap.hide = v or nil end
            local ok, icon = pcall(function() return LibStub("LibDBIcon-1.0") end)
            if ok and icon then if v then icon:Hide(addonName) else icon:Show(addonName) end end
            _applyAll()
        end,
    },
    {
        field    = "cbHideAltSummary",
        labelKey = "OPTIONS_HIDE_ALT_SUMMARY",      default = "Hide Alt Summary Button",
        tipKey   = nil,
        getVal   = function(d) return d.showAltSummaryBtn == false end,
        onChange = function(v)
            Addon:EnsurePrefs().showAltSummaryBtn = not v
            _applyAll()
            if Addon.LayoutHeaderButtons then Addon:LayoutHeaderButtons() end
            if Addon.CharPicker and Addon.CharPicker.Populate then Addon.CharPicker.Populate() end
        end,
    },
}

-- ── Warnings tab row definitions ──────────────────────────────────────────────
Addon.OptionsPane.WARNING_ROWS = {
    {
        field    = "cbHideUpdateNotice",
        labelKey = "OPTIONS_HIDE_UPDATE_NOTICE",    default = "Hide Update Notices",
        tipKey   = "OPTIONS_TOOLTIP_HIDE_UPDATE_NOTICE",
        getVal   = function(d) return d.hideUpdateNotice and true or false end,
        onChange = function(v)
            Addon:EnsurePrefs().hideUpdateNotice = v
            if not v then if Addon.RequestVersions then Addon:RequestVersions(false) end end
            _applyAll()
            if Addon.UpdateStatusBanner then Addon:UpdateStatusBanner() end
        end,
    },
    {
        field    = "cbDisableUpgradeWarn",
        labelKey = "OPTIONS_DISABLE_UPGRADE_WARN",  default = "Hide Upgrade Warnings",
        tipKey   = "OPTIONS_TOOLTIP_DISABLE_UPGRADE_WARN",
        getVal   = function(d) return d.upgradeWarnDisabled and true or false end,
        onChange = function(v)
            Addon:EnsurePrefs().upgradeWarnDisabled = v or nil
            _applyAll()
            if Addon.CheckUpgradeWarning then Addon:CheckUpgradeWarning() end
        end,
    },
    {
        field    = "cbDisableRaidBonusRollReminder",
        labelKey = "OPTIONS_DISABLE_RAID_BONUS_ROLL_REMINDER", default = "Hide Raid Bonus Roll Reminder",
        tipKey   = "OPTIONS_TOOLTIP_DISABLE_RAID_BONUS_ROLL_REMINDER",
        getVal   = function(d) return d.raidBonusRollReminderDisabled and true or false end,
        onChange = function(v)
            Addon:EnsurePrefs().raidBonusRollReminderDisabled = v or nil
            _applyAll()
            if Addon.UpdateRaidBonusRollReminder then Addon:UpdateRaidBonusRollReminder() end
        end,
    },
    {
        field    = "cbDisableCrestConvert",
        labelKey = "OPTIONS_DISABLE_CREST_CONVERT", default = "Hide Crest Conversion Panel",
        tipKey   = nil,
        getVal   = function(d) return d.crestConvertDisabled and true or false end,
        onChange = function(v)
            Addon:EnsurePrefs().crestConvertDisabled = v or nil
            _applyAll()
        end,
    },
}

-- ── BuildDisplay(parent, opts) ────────────────────────────────────────────────
-- Creates: Reset button, divider, display checkboxes, and an
-- optional Restore Hidden Rows button.  Returns a refs table with .sync().
-- opts: { pad, btnH, tileH, width, restoreClickFn }
function Addon.OptionsPane.BuildDisplay(parent, opts)
    opts = opts or {}
    local pad   = opts.pad   or 10
    local btnH  = opts.btnH  or 22
    local tileH = opts.tileH or 28
    local width = opts.width or 340
    local AU    = Addon.AddonUtils
    local refs  = {}
    local ROWS  = Addon.OptionsPane.DISPLAY_ROWS

    -- Reset List button (full width).
    local resetBtn = Addon.Controls.NewActionButton(parent, nil, btnH)
    resetBtn:SetPoint("TOPLEFT",  parent, "TOPLEFT",  pad,  -pad)
    resetBtn:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -pad, -pad)
    resetBtn:SetScript("OnClick", function() Addon:PerformFullReset() end)
    refs.resetBtn = resetBtn

    -- Divider below reset button.
    Addon.Controls.NewDivider(parent, -(pad + btnH + 4), pad, pad)

    -- 6 checkboxes: 5 in the left column, 1 in the right column.
    local COL_W = math.floor((width - 2 * pad) / 2)
    local cbsY  = pad + btnH + 4 + 1 + 6   -- px from parent top to first tile

    for i, row in ipairs(ROWS) do
        local col      = (i <= 5) and 0 or 1
        local ri       = (i <= 5) and (i - 1) or (i - 6)
        local colX     = pad + col * COL_W
        local tileTopY = -(cbsY + ri * tileH)
        local _row     = row

        local cb = Addon.Controls.NewCheckBox(parent, function(v) _row.onChange(v) end)
        cb:SetPoint("TOPLEFT", parent, "TOPLEFT", colX, tileTopY)
        cb:SetHeight(tileH)
        if cb._label then
            cb._label:SetText((Addon.L or {})[_row.labelKey] or _row.default)
            cb._label:SetPoint("RIGHT", parent, "TOPLEFT", colX + COL_W - 4, 0)
            local t = Addon.THEME and Addon.THEME.text
            if t and cb._label.SetTextColor then
                cb._label:SetTextColor(t.r, t.g, t.b, t.a or 1)
            end
        end
        if _row.tipKey then
            local _tipKey = _row.tipKey
            cb:SetScript("OnEnter", function(self_)
                local tip = Addon.L and Addon.L[_tipKey]
                if tip then AU.SetTooltip(self_, tip) end
            end)
            cb:SetScript("OnLeave", AU.HideTooltip)
        end
        if cb._hit then
            cb._hit:SetPoint("TOPLEFT",  parent, "TOPLEFT", colX,          tileTopY)
            cb._hit:SetPoint("TOPRIGHT", parent, "TOPLEFT", colX + COL_W,  tileTopY)
            cb._hit:SetHeight(tileH)
        end
        refs[_row.field] = cb
    end

    -- Optional "Restore Hidden Rows" button (shown only when hidden rows exist).
    if opts.restoreClickFn then
        local restoreY = cbsY + 5 * tileH + 4   -- below left column's 5th row
        local rb = Addon.Controls.NewActionButton(parent, nil, btnH)
        rb:SetPoint("TOPLEFT",  parent, "TOPLEFT",  pad,  -restoreY)
        rb:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -pad, -restoreY)
        rb:SetScript("OnClick", opts.restoreClickFn)
        rb:Hide()
        refs.restoreHiddenBtn = rb
    end

    refs.sync = function()
        local d = Addon:EnsurePrefs()
        local L = Addon.L or {}
        local t = Addon.THEME and Addon.THEME.text
        for _, row in ipairs(ROWS) do
            local cb = refs[row.field]
            if cb then
                cb:SetChecked(row.getVal(d))
                if cb._label then
                    cb._label:SetText(L[row.labelKey] or row.default)
                    if t and cb._label.SetTextColor then
                        cb._label:SetTextColor(t.r, t.g, t.b, t.a or 1)
                    end
                end
            end
        end
        -- Reset button label (localizable).
        if refs.resetBtn then
            refs.resetBtn:SetText((Addon.L or {}).RESET_BUTTON or "Reset List")
        end
        -- Restore Hidden button: visible only when hidden rows exist.
        if refs.restoreHiddenBtn then
            local nGV    = Addon.GetHiddenGVBlockList  and #Addon:GetHiddenGVBlockList()  or 0
            local nQuest = Addon.GetHiddenQuestList    and #Addon:GetHiddenQuestList()    or 0
            local nItem  = Addon.GetHiddenItemList     and #Addon:GetHiddenItemList()     or 0
            local n      = nGV + nQuest + nItem
            refs.restoreHiddenBtn:SetShown(n > 0)
            if n > 0 then
                local L = Addon.L or {}
                local s = n == 1 and (L.HIDDEN_ROW_SINGULAR or "1 Hidden Row")
                    or ((L.HIDDEN_ROW_PLURAL_FMT or "%d Hidden Rows"):format(n))
                refs.restoreHiddenBtn:SetText((L.RESTORE_HIDDEN_BUTTON_FMT or "Restore %s"):format(s))
            end
        end
    end

    return refs
end

-- ── BuildWarnings(parent, opts) ───────────────────────────────────────────────
-- Creates: 4 full-width checkboxes.  Returns a refs table with .sync().
-- opts: { pad, tileH, width }
function Addon.OptionsPane.BuildWarnings(parent, opts)
    opts = opts or {}
    local pad   = opts.pad   or 10
    local tileH = opts.tileH or 28
    local AU    = Addon.AddonUtils
    local refs  = {}
    local ROWS  = Addon.OptionsPane.WARNING_ROWS

    for i, row in ipairs(ROWS) do
        local tileTopY = -(pad + (i - 1) * tileH)
        local _row = row

        local cb = Addon.Controls.NewCheckBox(parent, function(v) _row.onChange(v) end)
        cb:SetPoint("TOPLEFT", parent, "TOPLEFT", pad, tileTopY)
        cb:SetHeight(tileH)
        if cb._label then
            cb._label:SetText((Addon.L or {})[_row.labelKey] or _row.default)
            cb._label:SetPoint("RIGHT", parent, "TOPRIGHT", -pad, 0)
            local t = Addon.THEME and Addon.THEME.text
            if t and cb._label.SetTextColor then
                cb._label:SetTextColor(t.r, t.g, t.b, t.a or 1)
            end
        end
        if _row.tipKey then
            local _tipKey = _row.tipKey
            cb:SetScript("OnEnter", function(self_)
                local tip = Addon.L and Addon.L[_tipKey]
                if tip then AU.SetTooltip(self_, tip) end
            end)
            cb:SetScript("OnLeave", AU.HideTooltip)
        end
        if cb._hit then
            cb._hit:SetPoint("TOPLEFT",  parent, "TOPLEFT",  pad,  tileTopY)
            cb._hit:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -pad, tileTopY)
            cb._hit:SetHeight(tileH)
        end
        refs[_row.field] = cb
    end

    refs.sync = function()
        local d = Addon:EnsurePrefs()
        local L = Addon.L or {}
        for _, row in ipairs(ROWS) do
            local cb = refs[row.field]
            if cb then
                cb:SetChecked(row.getVal(d))
                if cb._label then
                    cb._label:SetText(L[row.labelKey] or row.default)
                end
            end
        end
    end

    return refs
end

-- ── BuildAppearance(parent, opts) ─────────────────────────────────────────────
-- Creates: full-width Scale + Opacity sliders, divider, 3 centered color
-- swatches, and (if opts.showLangBtn=true) a compact language toggle.
-- Returns a refs table with .sync(), .scaleSync, .opacSync, .colorSwatches[],
-- .langDiv, .langBtn.
-- opts: { pad, btnH, width, showLangBtn }
function Addon.OptionsPane.BuildAppearance(parent, opts)
    opts = opts or {}
    local pad   = opts.pad   or 10
    local btnH  = opts.btnH  or 22
    local width = opts.width or 340
    local refs  = {}

    local SROW_H    = (Addon.UI.sliderLabelH or 14) + 2 + math.max(16, Addon.UI.sliderH or 20)
    local SLIDER_W  = width - 2 * pad
    local SWATCH_SZ = 16
    local SWATCH_LW = 80
    local SWATCH_RH = 22
    local SWATCH_GW = SWATCH_SZ + 4 + SWATCH_LW
    local SWATCH_X  = math.floor((width - SWATCH_GW) / 2)

    -- Scale slider.
    local scaleFrame = CreateFrame("Frame", nil, parent)
    scaleFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", pad, -pad)
    scaleFrame:SetSize(SLIDER_W, SROW_H)
    scaleFrame:EnableMouse(true)
    refs.scaleSync = Addon:CreateSliderWidget(scaleFrame, {
        minV       = 50, maxV = 150, stepV = 1,
        getVal     = function()
            local gdb = Addon.db and Addon.db.global
            return (gdb and tonumber(gdb.uiScalePct)) or 100
        end,
        applyFn    = function(pct)
            local gdb = Addon.db and Addon.db.global
            if gdb then gdb.uiScalePct = pct end
            if Addon.ApplyUIScale then Addon:ApplyUIScale() end
        end,
        minLabel   = (Addon.L or {}).UI_SCALE_MIN_LABEL   or "50%",
        maxLabel   = (Addon.L or {}).UI_SCALE_MAX_LABEL   or "150%",
        fmtFn      = function(v) return math.floor(v + 0.5) .. "%" end,
        titleLabel = (Addon.L or {}).UI_SCALE_LABEL       or "Scale",
    })

    -- Opacity slider.
    local opacFrame = CreateFrame("Frame", nil, parent)
    opacFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", pad, -(pad + SROW_H + 8))
    opacFrame:SetSize(SLIDER_W, SROW_H)
    opacFrame:EnableMouse(true)
    refs.opacSync = Addon:CreateSliderWidget(opacFrame, {
        minV       = 50, maxV = 100, stepV = 5,
        getVal     = function()
            local gdb = Addon.db and Addon.db.global
            return math.max(50, (gdb and tonumber(gdb.uiOpacityPct)) or 65)
        end,
        applyFn    = function(pct)
            local gdb = Addon.db and Addon.db.global
            if gdb then gdb.uiOpacityPct = math.max(50, pct) end
            if Addon.ApplyOpacity then Addon:ApplyOpacity() end
        end,
        minLabel   = (Addon.L or {}).UI_OPACITY_MIN_LABEL or "50%",
        maxLabel   = (Addon.L or {}).UI_OPACITY_MAX_LABEL or "100%",
        fmtFn      = function(v) return math.floor(v + 0.5) .. "%" end,
        titleLabel = (Addon.L or {}).UI_OPACITY_LABEL     or "Opacity",
        liveApply  = true,
    })

    -- Divider below both sliders, then 3 centered color swatches.
    local colorDivY    = pad + SROW_H + 8 + SROW_H + 8
    Addon.Controls.NewDivider(parent, -colorDivY, pad, pad)
    local swatchStartY = colorDivY + 1 + 8
    local colorSwatches = {}

    for si, sd in ipairs(Addon.THEME_COLOR_DEFS) do
        local swTopY = -(swatchStartY + (si - 1) * SWATCH_RH)
        local _sd    = sd

        local sw = Addon.Controls.NewSwatch(parent, SWATCH_SZ)
        sw:SetPoint("TOPLEFT", parent, "TOPLEFT", SWATCH_X, swTopY)
        sw:SetColor(sd:get())
        sw:SetScript("OnClick", function()
            local cr, cg, cb = _sd:get()
            Addon.Controls.OpenColorPicker(cr, cg, cb,
                function(nr, ng, nb) _sd:save(nr, ng, nb); sw:SetColor(nr, ng, nb) end,
                function(pr, pg, pb) _sd:save(pr, pg, pb); sw:SetColor(pr, pg, pb) end
            )
        end)

        local lbl = parent:CreateFontString(nil, "OVERLAY")
        lbl:SetFont("Fonts\\FRIZQT__.TTF", 9, "")
        lbl:SetText((Addon.L or {})[sd.labelKey] or sd.label)
        lbl:SetTextColor(0.70, 0.70, 0.70, 1)
        lbl:SetWidth(SWATCH_LW)
        lbl:SetJustifyH("LEFT")
        lbl:SetPoint("LEFT", sw, "RIGHT", 4, 0)

        colorSwatches[si] = { swatch = sw, def = _sd, label = lbl }
    end
    refs.colorSwatches = colorSwatches

    -- Optional compact language toggle (GearPopup only; Settings has its own dropdown).
    if opts.showLangBtn then
        local LOCALE_NATIVE = {
            deDE = "Deutsch",   esES = "Español", esMX = "Español",
            frFR = "Français",  itIT = "Italiano", koKR = "한국어",
            ptBR = "Português", ruRU = "Русский",  trTR = "Türkçe",
            zhCN = "简体中文",
        }
        LOCALE_NATIVE.esES = "Español"
        LOCALE_NATIVE.esMX = "Español"
        LOCALE_NATIVE.frFR = "Français"
        LOCALE_NATIVE.koKR = "한국어"
        LOCALE_NATIVE.ptBR = "Português"
        LOCALE_NATIVE.ruRU = "Русский"
        LOCALE_NATIVE.trTR = "Türkçe"
        local langDivY    = swatchStartY + #Addon.THEME_COLOR_DEFS * SWATCH_RH + 8
        local langDivider = Addon.Controls.NewDivider(parent, -langDivY, pad, pad)
        langDivider:Hide()
        refs.langDiv = langDivider

        local langBtnY = langDivY + 1 + 6
        local langBtn  = Addon.Controls.NewActionButton(parent, nil, btnH)
        langBtn:SetPoint("TOPLEFT",  parent, "TOPLEFT",  pad,  -langBtnY)
        langBtn:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -pad, -langBtnY)
        langBtn:Hide()
        langBtn:SetScript("OnClick", function()
            if not Addon.SetLocaleOverride then return end
            local eff = (Addon.GetEffectiveLocaleCode and Addon:GetEffectiveLocaleCode()) or "enUS"
            if eff ~= "enUS" then
                Addon:SetLocaleOverride("enUS")
            else
                Addon:SetLocaleOverride("auto")
            end
            if Addon.SyncGearPopup then Addon:SyncGearPopup() end
            if Addon.RequestRefresh then Addon:RequestRefresh() else Addon:Refresh() end
        end)
        refs.langBtn = langBtn
        refs._LOCALE_NATIVE = LOCALE_NATIVE
    end

    refs.sync = function()
        if refs.scaleSync then refs.scaleSync() end
        if refs.opacSync  then refs.opacSync()  end
        local L = Addon.L or {}
        for _, sw in ipairs(colorSwatches) do
            local r, g, b = sw.def:get()
            sw.swatch:SetColor(r, g, b)
            if sw.label then sw.label:SetText(L[sw.def.labelKey] or sw.def.label) end
        end
        if refs.langBtn and refs.langDiv then
            local wowLocale = (GetLocale and GetLocale()) or "enUS"
            local effLocale = (Addon.GetEffectiveLocaleCode and Addon:GetEffectiveLocaleCode()) or "enUS"
            local showLang  = wowLocale ~= "enUS"
            refs.langBtn:SetShown(showLang)
            refs.langDiv:SetShown(showLang)
            if showLang then
                local btnText
                if effLocale ~= "enUS" then
                    btnText = (Addon.L or {}).GEAR_LANG_BTN_SWITCH_TO_ENGLISH or "Use English"
                else
                    btnText = (refs._LOCALE_NATIVE and refs._LOCALE_NATIVE[wowLocale]) or wowLocale
                end
                refs.langBtn:SetText(btnText)
            end
        end
    end

    return refs
end
