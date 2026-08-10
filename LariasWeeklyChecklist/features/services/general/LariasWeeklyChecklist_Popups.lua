-- Popup/modal framework, dev-only season override + tracking dump tooling,
-- guide-announcement popups, the right-click context menu, and the full
-- list/style reset action.
--
-- This was previously part of the root LariasWeeklyChecklist.lua file. None
-- of it runs at file-load time (everything here is only ever called later,
-- from user actions or lifecycle events), so it was safe to move out without
-- touching the season-resolution code that InitConstants calls synchronously
-- during the root file's own load.
local addonName = ...
local Addon = _G[addonName]
if not Addon then return end

-- ── Shared theme-color definitions ───────────────────────────────────────────
-- Single source of truth for background / text / header color entries.
-- Used by both GearPopup (compact swatches) and Settings (full-size swatches).
-- Each entry exposes :get() → r,g,b; :save(r,g,b); :reset() so callers
-- don't need to duplicate db-access logic.
Addon.THEME_COLOR_DEFS = {
    { labelKey = "COLOR_PICKER_BG",   label = "Background", rk = "bgR",     gk = "bgG",     bk = "bgB",     dr = 0.10, dg = 0.10, db = 0.10 },
    { labelKey = "COLOR_PICKER_TEXT", label = "Text",       rk = "textR",   gk = "textG",   bk = "textB",   dr = 1.00, dg = 1.00, db = 1.00 },
    { labelKey = "COLOR_PICKER_HDR",  label = "Header",     rk = "headerR", gk = "headerG", bk = "headerB", dr = 1.00, dg = 0.82, db = 0.00 },
}
for _, d in ipairs(Addon.THEME_COLOR_DEFS) do
    function d:get()
        local gdb = Addon.EnsurePrefs and Addon:EnsurePrefs() or (Addon.db and Addon.db.global) or {}
        local tc = gdb.themeColors or {}
        local r = (tc[self.rk] ~= nil) and tc[self.rk] or ((gdb[self.rk] ~= nil) and gdb[self.rk] or self.dr)
        local g = (tc[self.gk] ~= nil) and tc[self.gk] or ((gdb[self.gk] ~= nil) and gdb[self.gk] or self.dg)
        local b = (tc[self.bk] ~= nil) and tc[self.bk] or ((gdb[self.bk] ~= nil) and gdb[self.bk] or self.db)
        return r, g, b
    end
    function d:save(r, g, b)
        local gdb = Addon.EnsurePrefs and Addon:EnsurePrefs() or (Addon.db and Addon.db.global)
        if not gdb then return end
        if gdb.themeColors == nil then
            gdb.themeColors = {}
        end
        local tc = gdb.themeColors
        tc[self.rk] = r; tc[self.gk] = g; tc[self.bk] = b
        gdb[self.rk] = r; gdb[self.gk] = g; gdb[self.bk] = b
        if Addon.ApplyThemeColors then Addon:ApplyThemeColors() end
    end
    function d:reset()
        local gdb = Addon.EnsurePrefs and Addon:EnsurePrefs() or (Addon.db and Addon.db.global)
        if gdb and gdb.themeColors then
            gdb.themeColors[self.rk] = nil; gdb.themeColors[self.gk] = nil; gdb.themeColors[self.bk] = nil
        end
        if gdb then
            gdb[self.rk] = nil; gdb[self.gk] = nil; gdb[self.bk] = nil
        end
        if Addon.ApplyThemeColors then Addon:ApplyThemeColors() end
    end
end

-- ── Shared support links ──────────────────────────────────────────────────────
-- Returns the three support resource entries as a table-of-tables so callers
-- can iterate without duplicating URL resolution.  Resolved lazily at call
-- time so changes to TRACKING.supportLinks (set during OnInitialize) are
-- reflected correctly.
function Addon:GetSupportLinks()
    local sl = self.TRACKING and self.TRACKING.supportLinks or {}
    local _L = self.L or {}
    return {
        { label = _L.SUPPORT_BTN_GUIDE_DOC or "Guide Doc",  url = sl.doc       or "" },
        { label = _L.SUPPORT_BTN_CHECKLIST  or "Checklist",  url = sl.checklist or "" },
        { label = _L.SUPPORT_BTN_DISCORD    or "Discord",    url = sl.discord   or "" },
    }
end

function Addon:ApplyThemedStaticPopup(popupFrame)
    if not popupFrame then return end

    -- StaticPopup frames are small and content-dense; avoid the heavy
    -- window-surface gradients used by large custom panels.
    self:ApplyTheme(popupFrame)
    self:ApplyPopupBorder(popupFrame)
    if popupFrame.SetBackdropColor and self.THEME and self.THEME.bg then
        local bg = self.THEME.bg
        popupFrame:SetBackdropColor(bg.r, bg.g, bg.b, 0.96)
    end
    if popupFrame._lariaBgTex then popupFrame._lariaBgTex:Hide() end
    if popupFrame._lariasSurfaceTop then popupFrame._lariasSurfaceTop:Hide() end
    if popupFrame._lariasSurfaceBottom then popupFrame._lariasSurfaceBottom:Hide() end

    local txt = self.THEME and self.THEME.text or { r = 1, g = 1, b = 1, a = 1 }

    if popupFrame._lariasBrandFill then popupFrame._lariasBrandFill:Hide() end
    if popupFrame._lariasBrandGlow then popupFrame._lariasBrandGlow:Hide() end
    if popupFrame._lariasBrandDivider then popupFrame._lariasBrandDivider:Hide() end
    if popupFrame._lariasBrandFS then popupFrame._lariasBrandFS:Hide() end

    if popupFrame.text and popupFrame.text.SetTextColor then
        popupFrame.text:SetTextColor(txt.r, txt.g, txt.b, txt.a or 1)
        if popupFrame.text.SetSpacing then
            popupFrame.text:SetSpacing(2)
        end
    end
    for i = 1, 3 do
        local btn = popupFrame["button" .. i]
        if btn then
            if self.Controls and self.Controls.StyleButton then
                self.Controls.StyleButton(btn)
            end
            local fs = btn.Text or (btn.GetFontString and btn:GetFontString())
            if fs and fs.SetTextColor then
                fs:SetTextColor(txt.r, txt.g, txt.b, txt.a or 1)
            end
        end
    end

    local eb = popupFrame.editBox
    if eb then
        self:ApplyTheme(eb)
        if eb.SetBackdropColor and self.THEME and self.THEME.bg then
            local bg = self.THEME.bg
            eb:SetBackdropColor(bg.r, bg.g, bg.b, 0.95)
        end
        if eb.SetBackdropBorderColor and self.THEME and self.THEME.border then
            local bd = self.THEME.border
            eb:SetBackdropBorderColor(bd.r, bd.g, bd.b, 0.9)
        end
        if eb.SetTextColor then
            eb:SetTextColor(txt.r, txt.g, txt.b, txt.a or 1)
        end
    end
end

-- Shared re-init cascade run any time Addon.TRACKING is rebuilt after the
-- addon has already started (dev season override, or a real season boundary
-- crossed mid-session). Keeping this in one place means both call sites stay
-- in sync instead of two copies of the same list of "things to redo" drifting
-- apart over time.
--
-- skipTrackedCurrencyConfigReset: pass true when this reinit is only
-- reconciling an unreliable startup guess with a now-confident season read
-- (see RefreshSeasonalTrackingIfNeeded below) rather than a real season
-- change, so the user's tracked-currency selection isn't rebuilt for no
-- reason.
function Addon:ReapplyAfterTrackingReinit(skipTrackedCurrencyConfigReset)
    if not skipTrackedCurrencyConfigReset and self.ResetTrackedCurrencyConfigForActiveSeason then
        self:ResetTrackedCurrencyConfigForActiveSeason()
    end
    if self.ApplyThemeColors then self:ApplyThemeColors() end
    if self.ApplyUIScale then self:ApplyUIScale() end
    if self.ApplyOpacity then self:ApplyOpacity() end
    if self.ReleaseTrackingPanelRuntimeCaches then
        self:ReleaseTrackingPanelRuntimeCaches()
    elseif self.ReleaseCurrencyRuntimeCaches then
        self:ReleaseCurrencyRuntimeCaches()
    end
    self._cachedListData = nil
    self._dataSig = ""
    if self.MarkAltsSummaryDirty then self:MarkAltsSummaryDirty(true) end
    if self.RequestTrackingUpdate then self:RequestTrackingUpdate() end
end

-- Re-resolves the active season from the current tracking data and re-runs
-- the tracking cascade if the resolved season actually changed since the
-- last resolve (e.g. a real Mythic+ season boundary crossed while logged in).
-- Returns true if a re-init happened, false otherwise.
--
-- IMPORTANT: Addon:InitConstants() runs once synchronously while this addon's
-- files are still loading -- well before PLAYER_ENTERING_WORLD -- and at that
-- point C_MythicPlus.GetCurrentSeason() frequently has not returned real data
-- from the server yet. This function's first call each session (from
-- OnPlayerEnteringWorld) is therefore very often just *correcting* that
-- early best-guess once real season data becomes available, not reacting to
-- an actual season boundary being crossed. Treat that one-time correction as
-- non-destructive: skip the tracked-currency-config reset for it, and only
-- run the full reset cascade for genuine changes detected after that first
-- confident read this session (e.g. a real weekly reset while logged in, or
-- the dev season-override toggle, which calls ReapplyAfterTrackingReinit
-- directly and always resets).
function Addon:RefreshSeasonalTrackingIfNeeded()
    local tracking = self.TRACKING
    if type(tracking) ~= "table" then return false end
    local resolved = self.ResolveSeasonVariantSelection and self:ResolveSeasonVariantSelection(tracking)
    if not resolved then return false end

    local sameSelection
    if resolved.selected == nil then
        sameSelection = (tracking._activeSeasonNumber == nil and tracking._activeSeasonStartsAt == nil)
    else
        sameSelection = (resolved.selectedMPlusSeason == tracking._activeSeasonNumber)
            and (resolved.selectedStart == tracking._activeSeasonStartsAt)
    end

    -- "Confident" means the live Mythic+ API actually returned a real season
    -- number (as opposed to falling back to timestamp gating because the API
    -- wasn't ready yet). Only the *first* confident read each session gets
    -- the non-destructive treatment; anything after that is a real change.
    local isFirstConfidentResolution = resolved.usedMPlusSeason
        and not self._seasonConfidentlyResolvedThisSession

    if sameSelection then
        -- Nothing changed structurally, but keep the detected-season fields
        -- fresh since GetDetectedCurrentMPlusSeason reads them.
        tracking._resolvedCurrentMPlusSeason = resolved.currentMPlusSeason
        tracking._resolvedCurrentMPlusSeasonSource = resolved.currentMPlusSeasonSource
        if resolved.usedMPlusSeason then
            self._seasonConfidentlyResolvedThisSession = true
        end
        return false
    end

    self:InitConstants(addonName)
    self:ReapplyAfterTrackingReinit(isFirstConfidentResolution)
    if resolved.usedMPlusSeason then
        self._seasonConfidentlyResolvedThisSession = true
    end
    return true
end

-- Returns the currently detected Mythic+ season number and its source
-- ("dev-override" or "api"), or nil, nil if it cannot be determined.
function Addon:GetDetectedCurrentMPlusSeason()
    local resolved = self.ResolveSeasonVariantSelection and self:ResolveSeasonVariantSelection(self.TRACKING)
    if not resolved then return nil, nil end
    return resolved.currentMPlusSeason, resolved.currentMPlusSeasonSource
end

function Addon:ApplyDevSeasonOverride(seasonNumber)
    local prefs = self:EnsurePrefs()
    local seasonValue = tonumber(seasonNumber)
    if seasonValue and seasonValue > 0 then
        prefs.devSeasonOverride = seasonValue
    else
        prefs.devSeasonOverride = nil
    end
    self:InitConstants(addonName)
    self:ReapplyAfterTrackingReinit()
    if self.RequestRefresh then
        self:RequestRefresh()
    elseif self.Refresh then
        self:Refresh()
    end
end

function Addon:CycleDevSeasonOverride()
    local tracking = self.TRACKING or {}
    local variants = tracking.seasonVariants
    if type(variants) ~= "table" or #variants == 0 then return end

    local seasons = {}
    local seen = {}
    for i = 1, #variants do
        local candidate = variants[i]
        local seasonNumber = tonumber(candidate and (candidate.mythicPlusSeason or candidate.seasonNumber))
        if seasonNumber and not seen[seasonNumber] then
            seen[seasonNumber] = true
            seasons[#seasons + 1] = seasonNumber
        end
    end
    table.sort(seasons)
    if #seasons == 0 then return end

    local prefs = self:EnsurePrefs()
    local current = tonumber(prefs.devSeasonOverride) or tonumber(tracking._activeSeasonNumber) or seasons[1]
    local nextSeason = seasons[1]
    for i = 1, #seasons do
        if seasons[i] == current then
            nextSeason = seasons[(i % #seasons) + 1]
            break
        elseif seasons[i] > current then
            nextSeason = seasons[i]
            break
        end
    end

    self:ApplyDevSeasonOverride(nextSeason)
end

function Addon:ShowThemedStaticPopup(popupKey, textArg1, textArg2, data)
    local frame = StaticPopup_Show(popupKey, textArg1, textArg2, data)
    if frame and self.ApplyThemedStaticPopup then
        self:ApplyThemedStaticPopup(frame)
    end
    return frame
end

function Addon:HideAddonModal(modalKey)
    local registry = self._addonModalRegistry
    local modal = registry and registry[modalKey]
    if modal and modal.holder then
        modal.holder:Hide()
    end
end

function Addon:RefreshAddonModalTheme(modalKey)
    local registry = self._addonModalRegistry
    local modal = registry and registry[modalKey]
    if not modal then return end

    local txt = self.THEME and self.THEME.text
    local hdr = self.THEME and self.THEME.header
    local bg = self.THEME and self.THEME.bg
    local vs = self.VISUAL_STYLE or {}
    if modal.headerDivider and hdr then
        modal.headerDivider:SetColorTexture(hdr.r, hdr.g, hdr.b, (vs.dividerA or 0.22) + 0.12)
    end
    if modal.holder and modal.holder._lariasSurfaceTop then
        modal.holder._lariasSurfaceTop:Hide()
    end
    if modal.title and modal.title.SetTextColor and hdr then
        modal.title:SetTextColor(hdr.r, hdr.g, hdr.b, 1)
        if modal.title.SetShadowColor and bg then
            modal.title:SetShadowColor(bg.r, bg.g, bg.b, vs.textShadowA or bg.a or 1)
        end
    end
    if modal.label and modal.label.SetTextColor and txt then
        modal.label:SetTextColor(txt.r, txt.g, txt.b, txt.a or 1)
        if modal.label.SetShadowColor and bg then
            modal.label:SetShadowColor(bg.r, bg.g, bg.b, vs.textShadowA or bg.a or 1)
        end
    end
    if modal.buttons then
        for i = 1, #modal.buttons do
            local btn = modal.buttons[i]
            if btn and self.Controls and self.Controls.StyleButton then
                self.Controls.StyleButton(btn)
            end
        end
    end
end

function Addon:EnsureAddonModal(modalKey, opts)
    self._addonModalRegistry = self._addonModalRegistry or {}
    local modal = self._addonModalRegistry[modalKey]
    if modal then return modal end

    opts = opts or {}
    local pad = tonumber(opts.pad) or 14
    local buttonHeight = tonumber(opts.buttonHeight) or 24
    local width = tonumber(opts.width) or 320
    local minHeight = tonumber(opts.minHeight) or 108
    local topOffset = tonumber(opts.topOffset) or -220
    local buttonGap = tonumber(opts.buttonGap) or 10
    local maxButtons = math.max(1, tonumber(opts.maxButtons) or 2)

    local holder = self:NewThemedFrame(nil, UIParent)
    holder:SetFrameStrata("DIALOG")
    holder:SetFrameLevel(210)
    holder:SetSize(width, minHeight)
    holder:SetPoint("TOP", UIParent, "TOP", 0, topOffset)
    holder:SetClampedToScreen(true)
    holder:EnableMouse(true)
    holder:SetMovable(true)
    holder:RegisterForDrag("LeftButton")
    holder:SetScript("OnDragStart", holder.StartMoving)
    holder:SetScript("OnDragStop", holder.StopMovingOrSizing)
    self:RegisterWindowSurface(holder, {
        opacityMode = "opaque",
        borderStyle = "popup",
        surfaceTopA = 0,
    })
    holder:Hide()

    local closeBtn = self.Controls.NewCloseButton(holder, function()
        if modal and modal.onClose then
            modal.onClose()
        else
            holder:Hide()
        end
    end)
    closeBtn:SetPoint("TOPRIGHT", holder, "TOPRIGHT", -2, -2)

    local headerDivider = holder:CreateTexture(nil, "OVERLAY")
    headerDivider:SetPoint("TOPLEFT", holder, "TOPLEFT", 1, -28)
    headerDivider:SetPoint("TOPRIGHT", holder, "TOPRIGHT", -1, -28)
    headerDivider:SetHeight(1)

    local title = holder:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", holder, "TOPLEFT", pad, -10)
    title:SetPoint("TOPRIGHT", holder, "TOPRIGHT", -28, -10)
    title:SetJustifyH("LEFT")
    title:SetShadowOffset(1, -1)

    local label = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("TOPLEFT", holder, "TOPLEFT", pad, -(pad + 24))
    label:SetPoint("TOPRIGHT", holder, "TOPRIGHT", -pad, -(pad + 24))
    label:SetJustifyH(opts.justifyH or "LEFT")
    label:SetJustifyV("TOP")
    label:SetWordWrap(true)
    label:SetSpacing(1)
    label:SetShadowOffset(1, -1)

    local buttons = {}
    for i = 1, maxButtons do
        local btn = self.Controls.NewActionButton(holder, tonumber(opts.buttonWidth) or 132, buttonHeight)
        btn:Hide()
        buttons[i] = btn
    end

    modal = {
        holder = holder,
        headerDivider = headerDivider,
        title = title,
        label = label,
        closeBtn = closeBtn,
        buttons = buttons,
        pad = pad,
        buttonGap = buttonGap,
        buttonHeight = buttonHeight,
        minHeight = minHeight,
        topOffset = topOffset,
        width = width,
        justifyH = opts.justifyH or "LEFT",
        onClose = nil,
        payload = nil,
    }
    self._addonModalRegistry[modalKey] = modal
    self:RefreshAddonModalTheme(modalKey)
    return modal
end

function Addon:ShowAddonModal(modalKey, opts)
    opts = opts or {}
    local modal = self:EnsureAddonModal(modalKey, opts)
    if not modal then return nil end

    local holder = modal.holder
    local label = modal.label
    local pad = tonumber(opts.pad) or modal.pad or 14
    local buttonGap = tonumber(opts.buttonGap) or modal.buttonGap or 10
    local buttonHeight = tonumber(opts.buttonHeight) or modal.buttonHeight or 24
    local minHeight = tonumber(opts.minHeight) or modal.minHeight or 108
    local topOffset = tonumber(opts.topOffset) or modal.topOffset or -220
    local bodyTop = tonumber(opts.bodyTop) or (pad + 24)
    local buttons = type(opts.buttons) == "table" and opts.buttons or {}

    modal.onClose = opts.onClose
    modal.payload = opts.payload
    modal.pad = pad
    modal.buttonGap = buttonGap
    modal.buttonHeight = buttonHeight
    modal.minHeight = minHeight
    modal.topOffset = topOffset

    holder:SetWidth(tonumber(opts.width) or modal.width or 320)
    holder:ClearAllPoints()
    holder:SetPoint("TOP", UIParent, "TOP", 0, topOffset)

    if modal.title then
        modal.title:SetText(tostring(opts.title or self.DISPLAY_NAME or (self.L and self.L.DISPLAY_NAME) or "Larias' Weekly Checklist"))
    end

    label:ClearAllPoints()
    label:SetPoint("TOPLEFT", holder, "TOPLEFT", pad, -bodyTop)
    label:SetPoint("TOPRIGHT", holder, "TOPRIGHT", -pad, -bodyTop)
    label:SetJustifyH(opts.justifyH or modal.justifyH or "LEFT")
    label:SetText(tostring(opts.text or ""))

    local textHeight = math.max(24, math.ceil(label:GetStringHeight() or 24))

    for i = 1, #modal.buttons do
        local btn = modal.buttons[i]
        local btnSpec = buttons[i]
        if btn and btnSpec then
            btn:SetWidth(tonumber(btnSpec.width) or tonumber(opts.buttonWidth) or btn:GetWidth())
            btn:SetHeight(tonumber(btnSpec.height) or buttonHeight)
            btn:SetText(tostring(btnSpec.text or ""))
            btn:SetScript("OnClick", function(self_)
                if btnSpec.onClick then
                    btnSpec.onClick(self_, modal)
                else
                    holder:Hide()
                end
            end)
            btn:SetScript("OnEnter", nil)
            btn:SetScript("OnLeave", nil)
            if btnSpec.tooltip then
                btn:SetScript("OnEnter", function(self_)
                    Addon.AddonUtils.SetTooltip(self_, btnSpec.tooltip, btnSpec.tooltipAnchor or "ANCHOR_BOTTOM")
                end)
                btn:SetScript("OnLeave", Addon.AddonUtils.HideTooltip)
            end
            btn:Show()
        elseif btn then
            btn:Hide()
        end
    end

    if #buttons == 1 and modal.buttons[1] then
        local btn = modal.buttons[1]
        btn:ClearAllPoints()
        btn:SetPoint("BOTTOM", holder, "BOTTOM", 0, pad)
    elseif #buttons >= 2 and modal.buttons[1] and modal.buttons[2] then
        modal.buttons[1]:ClearAllPoints()
        modal.buttons[1]:SetPoint("BOTTOMRIGHT", holder, "BOTTOM", -(buttonGap / 2), pad)
        modal.buttons[2]:ClearAllPoints()
        modal.buttons[2]:SetPoint("BOTTOMLEFT", holder, "BOTTOM", buttonGap / 2, pad)
    end

    local panelHeight = math.max(minHeight, bodyTop + textHeight + buttonHeight + (pad * 2) - 4)
    holder:SetHeight(panelHeight)
    self:RefreshAddonModalTheme(modalKey)
    holder:Show()
    return modal
end

function Addon:IsDevBuild()
    local versionText = tostring(self._myVersion or "")
    if versionText:find("-", 1, true) then
        return true
    end
    local getMeta = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
    local tocVersion = tostring((getMeta and getMeta(addonName, "Version")) or "")
    return tocVersion:find("-", 1, true) ~= nil
end

local function SerializeDevDumpValue(value, depth, seen)
    depth = tonumber(depth) or 0
    seen = seen or {}
    local valueType = type(value)
    if valueType == "nil" then return "nil" end
    if valueType == "number" or valueType == "boolean" then return tostring(value) end
    if valueType == "string" then
        return string.format("%q", value)
    end
    if valueType ~= "table" then
        return "<" .. valueType .. ">"
    end
    if seen[value] then return "<cycle>" end
    if depth >= 4 then return "<max-depth>" end

    seen[value] = true
    local parts = {}
    local isArray = true
    local expectedIndex = 1
    for key in pairs(value) do
        if type(key) ~= "number" or key ~= expectedIndex then
            isArray = false
            break
        end
        expectedIndex = expectedIndex + 1
    end

    if isArray and expectedIndex > 1 then
        for i = 1, expectedIndex - 1 do
            parts[#parts + 1] = SerializeDevDumpValue(value[i], depth + 1, seen)
        end
        seen[value] = nil
        return "{ " .. table.concat(parts, ", ") .. " }"
    end

    local keys = {}
    for key in pairs(value) do
        keys[#keys + 1] = key
    end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for i = 1, #keys do
        local key = keys[i]
        parts[#parts + 1] = "[" .. SerializeDevDumpValue(key, depth + 1, seen) .. "] = " .. SerializeDevDumpValue(value[key], depth + 1, seen)
    end
    seen[value] = nil
    return "{ " .. table.concat(parts, ", ") .. " }"
end

local function CountDevDumpLines(text)
    text = tostring(text or "")
    if text == "" then return 1 end
    local count = 1
    local start = 1
    while true do
        local pos = string.find(text, "\n", start, true)
        if not pos then break end
        count = count + 1
        start = pos + 1
    end
    return count
end

function Addon:BuildDevTrackingDumpText()
    local tracking = self.TRACKING or {}
    local prefs = self:EnsurePrefs() or {}
    local svGlobal = self.db and self.db.sv and self.db.sv.global or nil
    local themeColors = prefs.themeColors or nil
    local svThemeColors = svGlobal and svGlobal.themeColors or nil
    local trackedConfig = self.GetTrackedCurrencyConfig and self:GetTrackedCurrencyConfig() or {}
    local trackedEntries = self.GetTrackedCurrencyEntries and self:GetTrackedCurrencyEntries(false) or {}
    local builtInEntries = self.GetTrackedCurrencyEntries and self:GetTrackedCurrencyEntries(true) or {}
    local currentMPlusSeason = tonumber(prefs.devSeasonOverride)
    local currentMPlusSeasonSource = currentMPlusSeason and "dev-override" or nil
    local rawApiSeason = C_MythicPlus and C_MythicPlus.GetCurrentSeason and tonumber(C_MythicPlus.GetCurrentSeason()) or nil
    local ownKey = self.GetCurrentProfileKey and self:GetCurrentProfileKey() or ""
    local charDb = self.db and self.db.global and self.db.global.chars and self.db.global.chars[ownKey]
    local snapshot = charDb and charDb.trackingSnapshot or nil
    local theme = self.THEME or {}
    local themeBg = theme.bg or {}

    local lines = {
        "LariasWeeklyChecklist Dev Tracking Dump",
        "date=" .. tostring(date("%Y-%m-%d %H:%M:%S")),
        "version=" .. tostring(self._myVersion or ""),
        "currentProfileKey=" .. tostring(ownKey or ""),
        "currentMPlusSeason=" .. tostring(currentMPlusSeason),
        "currentMPlusSeasonSource=" .. tostring(currentMPlusSeasonSource),
        "rawApiCurrentSeason=" .. tostring(rawApiSeason),
        "devSeasonOverride=" .. tostring(prefs.devSeasonOverride),
        "prefs.bgR=" .. tostring(prefs.bgR),
        "prefs.bgG=" .. tostring(prefs.bgG),
        "prefs.bgB=" .. tostring(prefs.bgB),
        "prefs.themeColors=" .. SerializeDevDumpValue(themeColors),
        "prefs==svGlobal=" .. tostring(prefs == svGlobal),
        "sv.bgR=" .. tostring(svGlobal and svGlobal.bgR),
        "sv.bgG=" .. tostring(svGlobal and svGlobal.bgG),
        "sv.bgB=" .. tostring(svGlobal and svGlobal.bgB),
        "sv.themeColors=" .. SerializeDevDumpValue(svThemeColors),
        "theme.bg=" .. SerializeDevDumpValue({
            r = themeBg.r,
            g = themeBg.g,
            b = themeBg.b,
            a = themeBg.a,
        }),
        "activeSeasonName=" .. tostring(tracking._activeSeasonName),
        "activeSeasonNumber=" .. tostring(tracking._activeSeasonNumber),
        "resolvedCurrentMPlusSeason=" .. tostring(tracking._resolvedCurrentMPlusSeason),
        "resolvedCurrentMPlusSeasonSource=" .. tostring(tracking._resolvedCurrentMPlusSeasonSource),
        "crestCurrencyIDs=" .. SerializeDevDumpValue(tracking.crestCurrencyIDs),
        "catalystCurrencyID=" .. tostring(tracking.catalystCurrencyID),
        "sparkCurrencyID=" .. tostring(tracking.sparkCurrencyID),
        "cofferKeysCurrencyID=" .. tostring(tracking.cofferKeysCurrencyID),
        "cofferKeysDisplayCurrencyID=" .. tostring(tracking.cofferKeysDisplayCurrencyID),
        "bonusRollCurrencyID=" .. tostring(tracking.bonusRollCurrencyID),
        "weaponUpgrade=" .. SerializeDevDumpValue(tracking.weaponUpgrade),
        "trackedCurrencyConfig=" .. SerializeDevDumpValue(trackedConfig),
        "trackedCurrencyEntries(false)=" .. SerializeDevDumpValue(trackedEntries),
        "trackedCurrencyEntries(true)=" .. SerializeDevDumpValue(builtInEntries),
        "snapshot.activeSeasonName=" .. tostring(snapshot and snapshot.activeSeasonName),
        "snapshot.activeSeasonNumber=" .. tostring(snapshot and snapshot.activeSeasonNumber),
        "snapshot.currentMPlusSeason=" .. tostring(snapshot and snapshot.currentMPlusSeason),
    }
    return table.concat(lines, "\n")
end

function Addon:ShowDevTrackingDumpModal()
    local modal = self:EnsureAddonModal("dev_tracking_dump", {
        width = 760,
        minHeight = 420,
        maxButtons = 2,
        buttonWidth = 132,
    })
    if not modal then return nil end

    local holder = modal.holder
    local pad = 14
    local bodyTop = 52
    local buttonsTopPad = 42

    if not modal.scrollFrame then
        local scrollFrame = CreateFrame("ScrollFrame", nil, holder, "UIPanelScrollFrameTemplate")
        scrollFrame:SetPoint("TOPLEFT", holder, "TOPLEFT", pad, -bodyTop)
        scrollFrame:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", -30, pad + buttonsTopPad)

        local editBox = CreateFrame("EditBox", nil, scrollFrame)
        editBox:SetMultiLine(true)
        editBox:SetAutoFocus(false)
        editBox:SetFontObject("ChatFontNormal")
        editBox:SetWidth(680)
        editBox:SetScript("OnEscapePressed", function()
            holder:Hide()
        end)
        editBox:SetScript("OnTextChanged", function(self_)
            self_:HighlightText()
        end)
        scrollFrame:SetScrollChild(editBox)

        modal.scrollFrame = scrollFrame
        modal.editBox = editBox
    end

    local dumpText = self:BuildDevTrackingDumpText()
    self:ShowAddonModal("dev_tracking_dump", {
        title = "Dev Tracking Dump",
        text = "Copy this dump and send it back. It includes the active season, tracked config, tracked entries, and current snapshot season markers.",
        width = 760,
        minHeight = 420,
        bodyTop = bodyTop,
        buttons = {
            {
                text = "Refresh Dump",
                onClick = function()
                    self:ShowDevTrackingDumpModal()
                end,
            },
            {
                text = CLOSE or "Close",
                onClick = function()
                    holder:Hide()
                end,
            },
        },
    })

    local editBox = modal.editBox
    local scrollFrame = modal.scrollFrame
    if editBox then
        self:ApplyTheme(editBox)
        if editBox.SetBackdropColor and self.THEME and self.THEME.bg then
            local bg = self.THEME.bg
            editBox:SetBackdropColor(bg.r, bg.g, bg.b, 0.92)
        end
        if editBox.SetBackdropBorderColor and self.THEME and self.THEME.border then
            local bd = self.THEME.border
            editBox:SetBackdropBorderColor(bd.r, bd.g, bd.b, 0.9)
        end
        if editBox.SetTextColor and self.THEME and self.THEME.text then
            local txt = self.THEME.text
            editBox:SetTextColor(txt.r, txt.g, txt.b, txt.a or 1)
        end
        editBox:SetText(dumpText)
        editBox:SetWidth((scrollFrame and scrollFrame:GetWidth() or 680) - 8)
        local _, fontSize = editBox:GetFont()
        local lineCount = CountDevDumpLines(dumpText)
        editBox:SetHeight(math.max(240, math.ceil((tonumber(fontSize) or 14) * (lineCount + 3))))
        editBox:SetFocus()
        editBox:HighlightText()
    end
    return modal
end

function Addon:MaybeShowGuideUpdatePopup()
    local gdb = self:EnsurePrefs()
    if type(gdb) ~= "table" then return false end
    if self._guidePopupShownThisSession then return false end

    local supportLinks = self.TRACKING and self.TRACKING.supportLinks or nil
    local currentGuideUrl = tostring((supportLinks and supportLinks.doc) or "")
    if currentGuideUrl == "" then return false end

    local lastSeenGuideUrl = tostring(gdb._seenGuideDocUrl or "")
    if lastSeenGuideUrl == "" then
        gdb._seenGuideDocUrl = currentGuideUrl
        return false
    end
    if lastSeenGuideUrl == currentGuideUrl then return false end

    -- Record immediately so this URL change prompts only once.
    gdb._seenGuideDocUrl = currentGuideUrl

    local locale = self.L or {}
    local bodyText = locale.GUIDE_UPDATE_POPUP_TEXT or "A new guide is available. Open it now?"
    self:ShowAddonModal("guide_announcement", {
        width = 360,
        minHeight = 108,
        topOffset = -220,
        text = bodyText,
        payload = { url = currentGuideUrl },
        buttons = {
            {
                text = locale.GUIDE_UPDATE_OPEN_BTN or "Open Guide",
                onClick = function(_, modal)
                    local targetUrl = modal and modal.payload and modal.payload.url or currentGuideUrl
                    modal.holder:Hide()
                    if Addon.OpenSupportLink and targetUrl and targetUrl ~= "" then
                        Addon.OpenSupportLink(targetUrl)
                    end
                end,
            },
            {
                text = locale.GUIDE_UPDATE_LATER_BTN or "Later",
                onClick = function(_, modal)
                    modal.holder:Hide()
                end,
            },
        },
        onClose = function()
            Addon:HideAddonModal("guide_announcement")
        end,
    })
    self._guidePopupShownThisSession = true
    return true

    -- NOTE: Intentional early return above. We only show one guide-related popup
    -- per login trigger to avoid stacking dialogs.
end

function Addon:MaybeShowFutureSeasonGuidePopup()
    local gdb = self:EnsurePrefs()
    if type(gdb) ~= "table" then return false end
    if self._guidePopupShownThisSession then return false end

    local currentMPlusSeason = self.GetDetectedCurrentMPlusSeason and self:GetDetectedCurrentMPlusSeason() or nil
    if not (currentMPlusSeason and currentMPlusSeason > 0) then return false end

    local tracking = self.TRACKING
    local currentGuideUrl = tostring((((tracking or {}).supportLinks or {}).doc) or "")
    local variants = tracking and tracking.seasonVariants
    if type(variants) ~= "table" or #variants == 0 then return false end

    local bestSeason = nil
    local bestVariant = nil
    local bestGuideUrl = ""

    for i = 1, #variants do
        local candidate = variants[i]
        if type(candidate) == "table" then
            local seasonNumber = tonumber(candidate.mythicPlusSeason or candidate.seasonNumber)
            if seasonNumber and seasonNumber > currentMPlusSeason and (bestSeason == nil or seasonNumber < bestSeason) then
                local data = type(candidate.data) == "table" and candidate.data or candidate
                local links = type(data.supportLinks) == "table" and data.supportLinks
                    or (type(candidate.supportLinks) == "table" and candidate.supportLinks)
                    or nil
                local futureGuideUrl = tostring((links and links.doc) or "")
                if futureGuideUrl ~= "" and futureGuideUrl ~= currentGuideUrl then
                    bestSeason = seasonNumber
                    bestVariant = candidate
                    bestGuideUrl = futureGuideUrl
                end
            end
        end
    end

    if not bestSeason or bestGuideUrl == "" then return false end

    gdb._seenFutureGuideAnnouncements = type(gdb._seenFutureGuideAnnouncements) == "table" and gdb._seenFutureGuideAnnouncements or {}
    local announcementKey = tostring(bestSeason) .. "|" .. bestGuideUrl
    if gdb._seenFutureGuideAnnouncements[announcementKey] then return false end

    -- Record immediately so this future guide prompt is one-time.
    gdb._seenFutureGuideAnnouncements[announcementKey] = true

    local locale = self.L or {}
    local seasonLabel = tostring((bestVariant and bestVariant.name) or (locale.ILVLREF_SEASON_LABEL_FMT or "Season %d"):format(bestSeason))
    local bodyText = (locale.GUIDE_FUTURE_POPUP_TEXT_FMT or "A new guide for %s is available. Open it now?"):format(seasonLabel)
    self:ShowAddonModal("guide_announcement", {
        width = 360,
        minHeight = 108,
        topOffset = -220,
        text = bodyText,
        payload = { url = bestGuideUrl },
        buttons = {
            {
                text = locale.GUIDE_UPDATE_OPEN_BTN or "Open Guide",
                onClick = function(_, modal)
                    local targetUrl = modal and modal.payload and modal.payload.url or bestGuideUrl
                    modal.holder:Hide()
                    if Addon.OpenSupportLink and targetUrl and targetUrl ~= "" then
                        Addon.OpenSupportLink(targetUrl)
                    end
                end,
            },
            {
                text = locale.GUIDE_UPDATE_LATER_BTN or "Later",
                onClick = function(_, modal)
                    modal.holder:Hide()
                end,
            },
        },
        onClose = function()
            Addon:HideAddonModal("guide_announcement")
        end,
    })
    self._guidePopupShownThisSession = true
    return true
end

-- ── Context menu ────────────────────────────────────────────────────────────
-- Lightweight right-click context menu.  items = {{text=string, onClick=fn}, ...}
-- Re-uses a single singleton popup panel so only one menu is open at a time.
local _rcCtxPanel
local _rcCtxBtns = {}

local function HideContextMenu()
    if _rcCtxPanel then _rcCtxPanel:Hide() end
end
Addon.HideContextMenu = HideContextMenu

function Addon:ShowContextMenu(anchor, items)
    if not (items and #items > 0) then return end
    if not _rcCtxPanel then
        _rcCtxPanel = Addon.Controls.NewPopupPanel("DIALOG", 0.10)
        _rcCtxPanel:SetWidth(180)
    end
    local anchorStrata = anchor and anchor.GetFrameStrata and anchor:GetFrameStrata() or "DIALOG"
    local anchorLevel = anchor and anchor.GetFrameLevel and anchor:GetFrameLevel() or 1
    local panelLevel = math.max(anchorLevel + 20, _rcCtxPanel:GetFrameLevel() or 1, 1)
    if _rcCtxPanel.SetFrameStrata then
        _rcCtxPanel:SetFrameStrata(anchorStrata)
    end
    _rcCtxPanel:SetFrameLevel(panelLevel)
    for _, b in ipairs(_rcCtxBtns) do b:Hide() end
    _rcCtxBtns = {}
    local ROW_H = 22
    local PAD   = 6
    local y     = -PAD
    for _, item in ipairs(items) do
        local btn = CreateFrame("Button", nil, _rcCtxPanel, "UIPanelButtonTemplate")
        btn:SetPoint("TOPLEFT",  _rcCtxPanel, "TOPLEFT",  PAD,  y)
        btn:SetPoint("TOPRIGHT", _rcCtxPanel, "TOPRIGHT", -PAD, y)
        btn:SetHeight(ROW_H)
        btn:SetText(item.text or "")
        if btn.RegisterForClicks then
            btn:RegisterForClicks("LeftButtonUp")
        end
        if Addon.Controls and Addon.Controls.StyleButton then
            Addon.Controls.StyleButton(btn)
        end
        local _cb = item.onClick
        btn:SetScript("OnClick", function()
            HideContextMenu()
            if _cb then _cb() end
        end)
        btn:Show()
        y = y - ROW_H - 2
        table.insert(_rcCtxBtns, btn)
    end
    _rcCtxPanel:SetHeight(-y + PAD)
    _rcCtxPanel:ClearAllPoints()
    _rcCtxPanel:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4)
    _rcCtxPanel:Show()
end

-- ── List/style reset ──────────────────────────────────────────────────────────
-- Resets the current character's list data (checked items, collapsed sections,
-- week pointer) and all UI display settings (position, scale, opacity, theme
-- colors) back to their defaults. Character tracking data, hidden tracking
-- rows, class/level metadata, and alt-summary snapshots are kept.
-- Called by both the GearPopup and Settings panel reset buttons.
function Addon:PerformFullReset()
    local currentKey = self.GetCurrentProfileKey and self:GetCurrentProfileKey()
    if currentKey then
        local chars = self.db and self.db.global and self.db.global.chars
        if chars and chars[currentKey] then
            local cdb = chars[currentKey]
            if wipe then
                wipe(cdb.checked           or {})
                wipe(cdb.collapsedSections or {})
                wipe(cdb.sectionCompleted  or {})
            else
                cdb.checked           = {}
                cdb.collapsedSections = {}
                cdb.sectionCompleted  = {}
            end
            cdb.startAtSectionId = ""
        end
    end

    local gdb = self.db and self.db.global
    if gdb then
        gdb.mainFramePos  = nil
        gdb.mainFrameSize = nil
        gdb.ilvlRefPos    = nil
        gdb.ilvlRefSize   = nil
        gdb.uiScalePct    = 100
        gdb.uiOpacityPct  = 65
        if gdb.themeColors then wipe(gdb.themeColors) end
        if gdb.mainFrameWin then wipe(gdb.mainFrameWin) end
        if gdb.altSummaryWin then wipe(gdb.altSummaryWin) end
        if gdb.currencyConfigWin then wipe(gdb.currencyConfigWin) end
        if gdb.crestConvertWin then wipe(gdb.crestConvertWin) end
    end
    if self.ApplyThemeColors then self:ApplyThemeColors() end
    if self.ApplyUIScale     then self:ApplyUIScale()     end
    if self.ApplyOpacity     then self:ApplyOpacity()     end
    local mf = self._mainFrame
    if mf then
        mf:ClearAllPoints()
        mf:SetPoint("CENTER")
        mf:SetSize(self.UI.frameW, self.UI.frameH)
        local LW = LibStub("LibWindow-1.1", true)
        if LW then LW.SavePosition(mf) end
        if self.ApplyScrollLayout then self:ApplyScrollLayout() end
    end
    local asf = self._altsSummaryFrame
    if asf then
        asf._wasMoved = nil
        asf:ClearAllPoints()
        asf:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
    end
    local irf = self._ilvlRefWindow
    if irf then
        irf:ClearAllPoints()
        if mf then
            irf:SetPoint("TOPLEFT", mf, "TOPRIGHT", 4, 0)
        else
            irf:SetPoint("CENTER", UIParent, "CENTER", 260, 0)
        end
    end
    local ccf = self._currencyConfigPopup
    if ccf then
        ccf:ClearAllPoints()
        ccf:SetPoint("CENTER", UIParent, "CENTER")
    end
    local ccp = self._crestConvertPanel
    if ccp then
        ccp:ClearAllPoints()
        if MerchantFrame then
            ccp:SetPoint("LEFT", MerchantFrame, "RIGHT", 5, 0)
        else
            ccp:SetPoint("CENTER", UIParent, "CENTER", 350, 0)
        end
    end
    if self.LayoutHeaderButtons then self:LayoutHeaderButtons() end
    if self.SyncGearPopup       then self:SyncGearPopup()       end
    if self.RequestRefresh then self:RequestRefresh() else self:Refresh() end
end
