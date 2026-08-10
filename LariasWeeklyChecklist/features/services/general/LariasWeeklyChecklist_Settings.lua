-- LariasWeeklyChecklist_Settings.lua
-- Registers a panel under Interface -> AddOns using WoW's native Settings API
-- (retail 10.x+) with InterfaceOptions_AddCategory as a classic fallback.
-- No extra libraries required. Mirrors every option from the in-world gear popup.
local addonName = ...
local Addon = _G[addonName]
if not Addon then return end

-- Internal state
local panelFrame        -- outer canvas WoW hosts
local _displaySync      -- shared pane sync closure (Display tab)
local _warningsSync     -- shared pane sync closure (Warnings tab)
local _appearanceSync   -- shared pane sync closure (Appearance tab)
local _debugSync        -- settings-only debug checkbox/button sync
local _langDropdownBtn  -- reference to locale dropdown button; synced in OnShow
-- Holds the URL for the most-recently clicked support button so the
-- LARIAS_COPY_LINK popup can reliably display it (self.data can be nil
-- on some client builds when the popup fires before WoW assigns it).
-- _pendingCopyUrl lives on Addon so GearPopup can set it too.
-- Initialise only if not already set (file may reload).
Addon._pendingCopyUrl = Addon._pendingCopyUrl or ""

-- Reload-prompt shown after the player picks a different language.
-- Defined once at load time so StaticPopup_Show can reference it anywhere.
StaticPopupDialogs["LARIAS_LOCALE_RELOAD"] = StaticPopupDialogs["LARIAS_LOCALE_RELOAD"] or {
    text      = (Addon.L or {}).LOCALE_RELOAD_TEXT      or "Language change saved. Reload UI to apply the new language.",
    button1   = (Addon.L or {}).LOCALE_RELOAD_BTN_NOW   or "Reload Now",
    button2   = (Addon.L or {}).LOCALE_RELOAD_BTN_LATER or "Later",
    OnAccept  = function() ReloadUI() end,
    timeout   = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
    OnShow = function(self)
        if Addon.ApplyThemedStaticPopup then
            Addon:ApplyThemedStaticPopup(self)
        end
    end,
}

-- (GetSupportLinks removed; use Addon:GetSupportLinks() instead.)

-- Generic "copy link" popup used when C_Browser.OpenLink is unavailable.
-- Always redefined (no `or` guard) so the OnShow closure always captures
-- the current Addon reference and _pendingCopyUrl logic.
StaticPopupDialogs["LARIAS_COPY_LINK"] = {
    text         = (Addon.L or {}).COPY_LINK_POPUP_TEXT or "Press |cffffffffCtrl+C|r to copy, then close:",
    button1      = CLOSE or "Close",
    hasEditBox   = true,
    editBoxWidth = 320,
    timeout      = 0,
    whileDead    = true,
    hideOnEscape = true,
    preferredIndex = 5,
    OnShow = function(self)
        if Addon.ApplyThemedStaticPopup then
            Addon:ApplyThemedStaticPopup(self)
        end
        -- Defer one frame: WoW positions the editBox *after* calling OnShow.
        C_Timer.After(0, function()
            local eb = self.editBox or _G[self:GetName() and (self:GetName() .. "EditBox")]
            if not eb then return end
            eb:SetText(Addon._pendingCopyUrl or "")
            eb:SetFocus()
            eb:HighlightText()
            eb:SetScript("OnKeyDown", function(_, key)
                if key == "C" and IsControlKeyDown() then
                    C_Timer.After(0.05, function()
                        StaticPopup_Hide("LARIAS_COPY_LINK")
                    end)
                end
            end)
        end)
    end,
    EditBoxOnEscapePressed = function(self)
        self:GetParent():Hide()
    end,
    OnAccept = function() end,
}

--- Shared helper: opens a URL in the browser, or falls back to the copy-link
--- popup. Call this from any button in any file instead of duplicating the logic.
function Addon.OpenSupportLink(url)
    if not url or url == "" then return end
    if C_Browser and C_Browser.OpenLink then
        C_Browser.OpenLink(url)
    else
        Addon._pendingCopyUrl = url
        if Addon.ShowThemedStaticPopup then
            Addon:ShowThemedStaticPopup("LARIAS_COPY_LINK", nil, nil, url)
        else
            StaticPopup_Show("LARIAS_COPY_LINK", nil, nil, url)
        end
    end
end

-- (MakeSwatch removed; use Addon.Controls.NewSwatch(parent, 22) instead.)

-- Build the panel (lazy, called once)
local function BuildPanel()
    if panelFrame then return panelFrame end
    local L = Addon.L or {}

    panelFrame      = CreateFrame("Frame")
    panelFrame.name = L.DISPLAY_NAME or "Larias' Weekly Checklist"

    -- Inner canvas - WoW's Settings API sizes this for us; we just place widgets.
    local canvas = CreateFrame("Frame", nil, panelFrame)
    canvas:SetPoint("TOPLEFT")
    canvas:SetPoint("TOPRIGHT")

    -- Layout constants - intentionally match the GearPopup for visual parity.
    local PAD         = 10
    local BTN_H       = 22
    local TILE_H      = 28
    local PANE_W      = 600   -- reference content width fed to the shared builders
    local TAB_BTN_H   = BTN_H
    local TAB_GAP     = 6     -- gap between tab row bottom and first pane pixel
    local TAB_GAP_BTN = 4     -- gap between adjacent tab buttons
    local NUM_TABS    = 3
    local TAB_W       = math.floor((PANE_W - 2 * PAD - (NUM_TABS - 1) * TAB_GAP_BTN) / NUM_TABS)
    local PANE_H      = 220   -- tall enough for the Display pane (tallest content)

    local curY = -PAD   -- running Y (negative = downward from top)

    -- Page title
    local hdr     = Addon.THEME and Addon.THEME.header or { r = 1, g = 0.82, b = 0, a = 1 }
    local titleFS = canvas:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    titleFS:SetPoint("TOPLEFT", canvas, "TOPLEFT", PAD, curY)
    titleFS:SetText(L.DISPLAY_NAME or "Larias' Weekly Checklist")
    titleFS:SetTextColor(hdr.r, hdr.g, hdr.b, 1)
    curY = curY - 32

    -- Tab buttons
    local TAB_LABELS = {
        L.SETTINGS_TAB_DISPLAY    or "Display",
        L.SETTINGS_TAB_WARNINGS   or "Warnings",
        L.SETTINGS_TAB_APPEARANCE or "Appearance",
    }
    local tabs  = {}
    local panes = {}
    local tabsY = curY

    for i = 1, NUM_TABS do
        local tx = PAD + (i - 1) * (TAB_W + TAB_GAP_BTN)
        local tb = Addon.Controls.NewActionButton(canvas, TAB_W, TAB_BTN_H)
        tb:SetPoint("TOPLEFT", canvas, "TOPLEFT", tx, tabsY)
        tb:SetText(TAB_LABELS[i])
        local bar = tb:CreateTexture(nil, "OVERLAY")
        bar:SetColorTexture(hdr.r, hdr.g, hdr.b, 1)
        bar:SetPoint("BOTTOMLEFT",  tb, "BOTTOMLEFT",  2, 1)
        bar:SetPoint("BOTTOMRIGHT", tb, "BOTTOMRIGHT", -2, 1)
        bar:SetHeight(2)
        bar:Hide()
        tb._activeBar = bar
        tabs[i] = tb
    end
    curY = curY - TAB_BTN_H - TAB_GAP

    -- Tab pane frames
    for i = 1, NUM_TABS do
        local pane = CreateFrame("Frame", nil, canvas)
        pane:SetSize(PANE_W, PANE_H)
        pane:SetPoint("TOPLEFT", canvas, "TOPLEFT", 0, curY)
        pane:Hide()
        panes[i] = pane
    end

    -- ShowTab helper
    local _activeTab = 1
    local function ShowTab(idx)
        _activeTab = idx
        for i = 1, NUM_TABS do
            local tb = tabs[i]
            local pn = panes[i]
            local tr = Addon.Controls.GetButtonFontString(tb)
            if i == idx then
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
    for i = 1, NUM_TABS do
        local _i = i
        tabs[i]:SetScript("OnClick", function() ShowTab(_i) end)
    end

    -- Build pane content using shared builders
    local paneOpts = { pad = PAD, btnH = BTN_H, tileH = TILE_H, width = PANE_W,
                       restoreClickFn = function() Addon:ToggleRestoreHiddenCurrencies(panes[1]) end }
    local dr = Addon.OptionsPane.BuildDisplay(panes[1], paneOpts)
    _displaySync = dr.sync

    local wr = Addon.OptionsPane.BuildWarnings(panes[2], { pad = PAD, tileH = TILE_H, width = PANE_W })
    _warningsSync = wr.sync

    -- Appearance pane has no compact lang toggle - language has its own section below.
    local ar = Addon.OptionsPane.BuildAppearance(panes[3], { pad = PAD, btnH = BTN_H, width = PANE_W })
    _appearanceSync = ar.sync

    curY = curY - PANE_H

    -- Language section
    Addon.Controls.NewDivider(canvas, curY, PAD, PAD)
    curY = curY - 8

    local secLang = canvas:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    secLang:SetPoint("TOPLEFT", canvas, "TOPLEFT", PAD, curY)
    secLang:SetText(L.SETTINGS_SECTION_LANGUAGE or "Language")
    curY = curY - 20 - 4

    -- Ordered list of locales with friendly display names.
    local LOCALE_OPTIONS = {
        { code = "auto", name = L.SETTINGS_LANGUAGE_AUTO or "Auto (Client Default)" },
        { code = "enUS", name = "English"         },
        { code = "zhCN", name = "简体中文"        },
        { code = "deDE", name = "Deutsch"         },
        { code = "esES", name = "Español (EU)"    },
        { code = "esMX", name = "Español (MX)"    },
        { code = "frFR", name = "Français"        },
        { code = "itIT", name = "Italiano"        },
        { code = "koKR", name = "한국어"          },
        { code = "ptBR", name = "Português (BR)"  },
        { code = "ruRU", name = "Русский"         },
        { code = "trTR", name = "Türkçe"          },
    }

    local localeNameFixups = {
        esES = "Español (EU)",
        esMX = "Español (MX)",
        frFR = "Français",
        koKR = "한국어",
        ptBR = "Português (BR)",
        ruRU = "Русский",
        trTR = "Türkçe",
        zhCN = "简体中文",
    }
    for _, opt in ipairs(LOCALE_OPTIONS) do
        if localeNameFixups[opt.code] then
            opt.name = localeNameFixups[opt.code]
        end
    end

    local function GetLocaleFriendlyName(code)
        for _, opt in ipairs(LOCALE_OPTIONS) do
            if opt.code == code then return opt.name end
        end
        return code
    end

    -- Dropdown-style button showing the current selection.
    local langDropBtn = Addon.Controls.NewActionButton(canvas, 220, BTN_H)
    langDropBtn:SetPoint("TOPLEFT", canvas, "TOPLEFT", PAD, curY)

    -- Floating option-list popup (created lazily on first click).
    local langPopup
    local LANG_ITEM_H = 24
    local LANG_PAD    = 6

    local function GetOrBuildLangPopup()
        if langPopup then return langPopup end
        langPopup = Addon.Controls.NewPopupPanel("HIGH", 0.10)
        langPopup:SetWidth(220)
        langPopup:SetHeight(LANG_PAD * 2 + #LOCALE_OPTIONS * LANG_ITEM_H)
        for idx, opt in ipairs(LOCALE_OPTIONS) do
            local _code = opt.code
            local _name = opt.name
            local row = CreateFrame("Button", nil, langPopup)
            row:SetPoint("TOPLEFT",  langPopup, "TOPLEFT",  LANG_PAD, -(LANG_PAD + (idx - 1) * LANG_ITEM_H))
            row:SetPoint("TOPRIGHT", langPopup, "TOPRIGHT", -LANG_PAD, -(LANG_PAD + (idx - 1) * LANG_ITEM_H))
            row:SetHeight(LANG_ITEM_H)
            local rowHL = row:CreateTexture(nil, "HIGHLIGHT")
            rowHL:SetAllPoints(row)
            rowHL:SetColorTexture(1, 1, 1, 0.08)
            local rowLbl = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            rowLbl:SetPoint("LEFT", row, "LEFT", 4, 0)
            rowLbl:SetText(_name)
            row:SetScript("OnClick", function()
                langPopup:Hide()
                -- Save to db only; the change takes effect on the next reload.
                local gdb = Addon.db and Addon.db.global
                if gdb then
                    gdb.localeOverride = (_code == "auto") and "" or _code
                end
                langDropBtn:SetText(GetLocaleFriendlyName(_code))
                Addon.Controls.StyleButton(langDropBtn)
                if Addon.ShowThemedStaticPopup then
                    Addon:ShowThemedStaticPopup("LARIAS_LOCALE_RELOAD")
                else
                    StaticPopup_Show("LARIAS_LOCALE_RELOAD")
                end
            end)
        end
        return langPopup
    end

    langDropBtn:SetScript("OnClick", function()
        local p = GetOrBuildLangPopup()
        if p:IsShown() then p:Hide(); return end
        p:ClearAllPoints()
        p:SetPoint("TOPLEFT", langDropBtn, "BOTTOMLEFT", 0, -2)
        p:Show()
    end)

    -- Store reference so OnShow can sync the button text.
    _langDropdownBtn = langDropBtn

    curY = curY - BTN_H - 14

    -- Support links
    Addon.Controls.NewDivider(canvas, curY, PAD, PAD)
    curY = curY - 8

    local SUPP_BTN_W   = 150
    local SUPP_BTN_GAP = 8
    for si, sl in ipairs(Addon:GetSupportLinks()) do
        local _url = sl.url
        local btn = Addon.Controls.NewActionButton(canvas, SUPP_BTN_W, BTN_H)
        btn:SetPoint("TOPLEFT", canvas, "TOPLEFT", PAD + (si - 1) * (SUPP_BTN_W + SUPP_BTN_GAP), curY)
        btn:SetText(sl.label)
        btn:SetScript("OnClick", function() Addon.OpenSupportLink(_url) end)
    end
    curY = curY - BTN_H - 14

    -- Debug controls. The DEV action stays out of the in-world checklist and is
    -- only exposed here after the user explicitly enables debug mode.
    Addon.Controls.NewDivider(canvas, curY, PAD, PAD)
    curY = curY - 8

    local debugCb = Addon.Controls.NewCheckBox(canvas, function(v)
        local gdb = Addon:EnsurePrefs()
        gdb.debug = v or nil
        if _debugSync then _debugSync() end
    end)
    debugCb:SetPoint("TOPLEFT", canvas, "TOPLEFT", PAD, curY)
    debugCb:SetHeight(TILE_H)
    if debugCb._label then
        debugCb._label:SetText(L.SETTINGS_DEBUG_CHECKBOX or "Debug")
        debugCb._label:SetPoint("RIGHT", canvas, "TOPLEFT", PAD + 220, 0)
        local t = Addon.THEME and Addon.THEME.text
        if t and debugCb._label.SetTextColor then
            debugCb._label:SetTextColor(t.r, t.g, t.b, t.a or 1)
        end
    end
    if debugCb._hit then
        debugCb._hit:SetPoint("TOPLEFT", canvas, "TOPLEFT", PAD, curY)
        debugCb._hit:SetPoint("TOPRIGHT", canvas, "TOPLEFT", PAD + 220, curY)
        debugCb._hit:SetHeight(TILE_H)
    end
    debugCb:SetScript("OnEnter", function(self_)
        Addon.AddonUtils.SetTooltip(self_, L.SETTINGS_DEBUG_TOOLTIP or "Shows development/debug tools in this settings panel.", "ANCHOR_RIGHT")
    end)
    debugCb:SetScript("OnLeave", Addon.AddonUtils.HideTooltip)

    local devBtn = Addon.Controls.NewActionButton(canvas, 90, BTN_H)
    devBtn:SetPoint("LEFT", debugCb, "RIGHT", 120, 0)
    devBtn:SetText(L.SETTINGS_DEBUG_DEV_BUTTON or "DEV")
    devBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    devBtn:SetScript("OnEnter", function(self_)
        local tracking = Addon.TRACKING or {}
        local seasonNumber = tostring(tracking._activeSeasonNumber or "?")
        local seasonName = tostring(tracking._activeSeasonName or "Unknown")
        local tip = L.SETTINGS_DEBUG_DEV_TOOLTIP
            or "Left-click: cycle dev season override and refresh.\nRight-click: open the dev tracking dump."
        Addon.AddonUtils.SetTooltip(self_, tip .. "\nCurrent: " .. seasonName .. " (" .. seasonNumber .. ")", "ANCHOR_RIGHT")
    end)
    devBtn:SetScript("OnLeave", Addon.AddonUtils.HideTooltip)
    devBtn:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            if Addon.ShowDevTrackingDumpModal then Addon:ShowDevTrackingDumpModal() end
        elseif Addon.CycleDevSeasonOverride then
            Addon:CycleDevSeasonOverride()
        end
    end)

    _debugSync = function()
        local gdb = Addon:EnsurePrefs()
        local enabled = gdb and gdb.debug and true or false
        debugCb:SetChecked(enabled)
        if debugCb._label then
            debugCb._label:SetText((Addon.L or {}).SETTINGS_DEBUG_CHECKBOX or "Debug")
        end
        devBtn:SetShown(enabled)
        devBtn:SetText((Addon.L or {}).SETTINGS_DEBUG_DEV_BUTTON or "DEV")
    end
    _debugSync()

    curY = curY - TILE_H - PAD

    canvas:SetHeight(math.abs(curY) + PAD)

    -- Sync all controls every time the panel is shown
    panelFrame:SetScript("OnShow", function()
        if _displaySync    then _displaySync()    end
        if _warningsSync   then _warningsSync()   end
        if _appearanceSync then _appearanceSync() end
        if _debugSync      then _debugSync()      end
        if _langDropdownBtn then
            local savedCode = (Addon.db and Addon.db.global and Addon.db.global.localeOverride) or "auto"
            if savedCode == "" then savedCode = "auto" end
            _langDropdownBtn:SetText(GetLocaleFriendlyName(savedCode))
            Addon.Controls.StyleButton(_langDropdownBtn)
        end
        ShowTab(_activeTab)
    end)

    ShowTab(1)
    return panelFrame
end

-- Public API

--- Refreshes all color swatch buttons in the Settings panel to match the
--- current saved (or default) theme colors. Safe to call at any time;
--- no-op if the panel hasn't been built yet.
function Addon:RefreshSettingsSwatches()
    if _appearanceSync then _appearanceSync() end
end

--- Re-syncs all checkboxes in the Settings panel to the current saved prefs.
--- Safe to call at any time; no-op if the panel hasn't been built yet.
function Addon:RefreshSettingsCheckboxes()
    if _displaySync  then _displaySync()  end
    if _warningsSync then _warningsSync() end
    if _debugSync    then _debugSync()    end
end

--- Called from OnEnable to register the panel with the WoW UI.
function Addon:RegisterSettingsPanel()
    local ok, result = pcall(BuildPanel)
    if not ok then
        -- Print the error so it surfaces in the WoW chat frame for diagnosis.
        -- (panelFrame is left nil so we skip registration gracefully.)
        local fmt = (L and L.SETTINGS_PANEL_ERROR_FMT) or "|cffff4444%s|r Settings panel error: %s"
        print(fmt:format((L and L.DISPLAY_NAME) or "Larias' Weekly Checklist", tostring(result)))
        return
    end
    local frame = result
    if not frame then return end

    if Settings and Settings.RegisterCanvasLayoutCategory then
        -- Retail 10.0+ native Settings API.
        local cat = Settings.RegisterCanvasLayoutCategory(frame, frame.name)
        Settings.RegisterAddOnCategory(cat)
        Addon._settingsCategory = cat
    elseif InterfaceOptions_AddCategory then
        -- Classic / pre-10.0 fallback.
        InterfaceOptions_AddCategory(frame)
    end
end

--- Opens the panel programmatically (e.g. from a slash command).
function Addon:OpenSettingsPanel()
    if Addon._settingsCategory and Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(Addon._settingsCategory:GetID())
    elseif InterfaceOptionsFrame_OpenToCategory then
        InterfaceOptionsFrame_OpenToCategory(panelFrame and panelFrame.name)
    end
end
