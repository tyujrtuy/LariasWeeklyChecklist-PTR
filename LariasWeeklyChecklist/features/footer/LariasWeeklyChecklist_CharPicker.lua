local addonName = ...
local Addon = _G[addonName]
if not Addon then return end

-- ── Character profile helpers ────────────────────────────────────────────────

-- Returns a sorted list of all characters that have ever logged in with the addon.
-- Primary source: AceDB's sv.profileKeys (populated on every login automatically).
-- Secondary: global.chars keys (in case a char only has the new-format data).
local function CountKeys(t)
    if type(t) ~= "table" then return 0 end
    local n = 0
    for _ in pairs(t) do
        n = n + 1
    end
    return n
end

local function IsCharacterProfileKey(charKey)
    if type(charKey) ~= "string" then return false end
    local name, realm = charKey:match("^%s*(.-)%s%-%s(.-)%s*$")
    return name ~= nil and realm ~= nil and name ~= "" and realm ~= ""
end

local function PruneInvalidCharacterKeys(self)
    local db = self.db
    if not db then return end

    local currentKey = self.GetCurrentProfileKey and self:GetCurrentProfileKey() or nil
    local removedAny = false

    local function PruneMap(map)
        if type(map) ~= "table" then return end
        for charKey in pairs(map) do
            if charKey ~= currentKey and not IsCharacterProfileKey(charKey) then
                map[charKey] = nil
                removedAny = true
            end
        end
    end

    local gdb = db.global
    PruneMap(gdb and gdb.charClasses)
    PruneMap(gdb and gdb.charLevels)
    PruneMap(gdb and gdb.hiddenChars)
    PruneMap(gdb and gdb.trackedLootChars)

    if removedAny then
        self._charProfileKeysCache = nil
    end
end

function Addon:GetCharProfileKeys()
    PruneInvalidCharacterKeys(self)

    local sv = self.db and self.db.sv
    local profileKeys = sv and sv.profileKeys
    local chars = self.db and self.db.global and self.db.global.chars
    local profileKeyCount = CountKeys(profileKeys)
    local charCount = CountKeys(chars)

    local cache = self._charProfileKeysCache
    if cache
       and cache.profileKeysRef == profileKeys
       and cache.charsRef == chars
       and cache.profileKeyCount == profileKeyCount
       and cache.charCount == charCount then
        return cache.keys
    end

    local seen = {}
    local keys = {}

    if profileKeys then
        for charKey in pairs(profileKeys) do
            if IsCharacterProfileKey(charKey) and not seen[charKey] then
                seen[charKey] = true
                tinsert(keys, charKey)
            end
        end
    end

    -- Also include any chars that exist in global.chars but not in sv.profileKeys.
    if chars then
        for charKey in pairs(chars) do
            if IsCharacterProfileKey(charKey) and not seen[charKey] then
                seen[charKey] = true
                tinsert(keys, charKey)
            end
        end
    end

    table.sort(keys)
    self._charProfileKeysCache = {
        profileKeysRef = profileKeys,
        charsRef = chars,
        profileKeyCount = profileKeyCount,
        charCount = charCount,
        keys = keys,
    }
    return keys
end

local function GetMaxCharacterLevel()
    if type(GetMaxPlayerLevel) == "function" then
        local lvl = tonumber(GetMaxPlayerLevel())
        if lvl and lvl > 0 then return lvl end
    end
    if type(GetMaxLevelForLatestExpansion) == "function" then
        local lvl = tonumber(GetMaxLevelForLatestExpansion())
        if lvl and lvl > 0 then return lvl end
    end
    local lvl = tonumber(MAX_PLAYER_LEVEL)
    if lvl and lvl > 0 then return lvl end
    return nil
end

local function IsOwnProfileKey(profileKey, ownKey)
    if not (profileKey and ownKey) then return false end
    return profileKey == ownKey or profileKey:lower() == ownKey:lower()
end

function Addon:IsMaxLevelChar(profileKey)
    if not profileKey then return false end
    local gdb = self.db and self.db.global
    local lvl = gdb and gdb.charLevels and tonumber(gdb.charLevels[profileKey])
    local maxLevel = GetMaxCharacterLevel()
    if not (lvl and maxLevel) then return false end
    return lvl >= maxLevel
end

local function SnapshotHasUsableData(snap)
    if type(snap) ~= "table" then return false end
    if snap.leftLines ~= nil then return true end
    if type(snap.rightRows) ~= "table" then return false end
    for _, row in ipairs(snap.rightRows) do
        if row.qty and row.qty > 0 then return true end
    end
    return false
end

local function IsPickableChar(self, profileKey, ownKey, gdb)
    if IsOwnProfileKey(profileKey, ownKey) then return false end
    if gdb and gdb.hiddenChars and gdb.hiddenChars[profileKey] then return false end
    if not self:IsMaxLevelChar(profileKey) then return false end
    return true
end

-- Switches the viewed character.  profileKey=nil means own character.
-- Character data lives in db.global.chars[key] so no profile switching is
-- needed \u2014 just update _viewingChar and refresh the UI.
function Addon:SetViewingChar(profileKey)
    -- Clear any shared popup blockers before rebuilding the view.
    if self.HideSummaryOverlays then
        self:HideSummaryOverlays()
    elseif self.HideContextMenu then
        self:HideContextMenu()
    end
    local ownKey = self:GetCurrentProfileKey()
    if profileKey == nil or profileKey == ownKey then
        self._viewingChar = nil
    else
        self._viewingChar = profileKey
    end
    if self._cpUpdateLabel then self._cpUpdateLabel() end
    -- Switch to list tab in case the user was on the Options tab.
    if self.SelectMainTab and not self._inLayoutHeaderButtons then
        self:SelectMainTab(1)
    end
    -- Guard against re-entry: LayoutHeaderButtons_ may reset _viewingChar directly
    -- to avoid this exact call, but protect here too in case other callers exist.
    if not self._inLayoutHeaderButtons then
        if self.LayoutHeaderButtons then self:LayoutHeaderButtons() end
    end
    if self.RequestRefresh then self:RequestRefresh() else self:Refresh() end
end

-- Returns true when there is at least one character the picker can switch to.
-- Used by LayoutHeaderButtons_ and SyncGearPopup to decide visibility.
function Addon:HasPickableChars()
    if self._viewingChar then return true end  -- "back to me" row is available
    if not (self.GetCharProfileKeys and self.GetCurrentProfileKey) then return false end
    local ownKey = self:GetCurrentProfileKey()
    local gdb    = self.db and self.db.global
    for _, charKey in ipairs(self:GetCharProfileKeys()) do
        if IsPickableChar(self, charKey, ownKey, gdb) then
            local classToken = gdb and gdb.charClasses and gdb.charClasses[charKey]
            local snap = gdb and gdb.chars and gdb.chars[charKey] and gdb.chars[charKey].trackingSnapshot
            if classToken and SnapshotHasUsableData(snap) then return true end
        end
    end
    return false
end

-- ── UI construction ───────────────────────────────────────────────────────────
-- Called once from CreateFrame (main file) after StyleMainTabButton is available.
-- Installs behaviour hooks on Addon so LayoutHeaderButtons_ can call them without
-- keeping direct upvalue references to the closures below.
function Addon:InitCharPickerUI(frame, styleFunc)
    local L = Addon.L or {}
    local CPICK_PAD   = 6
    local CPICK_ROW_H = 20

    local charPickerBtn   -- lazy Button on `frame`
    local charPickerPanel -- floating dropdown Frame

    -- ── Button ────────────────────────────────────────────────────────────────
    -- Adjust button width to fit text content dynamically.
    local function AdjustButtonWidth(btn)
        local tr = Addon.Controls.GetButtonFontString(btn)
        if tr and tr.GetStringWidth then
            local textW = tr:GetStringWidth()
            -- Add padding: 6px left margin + 6px right margin + extra for arrow spacing
            local minW = 70  -- minimum comfortable width
            local w = max(minW, textW + 12)
            btn:SetWidth(w)
        end
    end

    local function EnsureBtn()
        if charPickerBtn then return charPickerBtn end
        local btn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        btn:SetHeight(22)
        btn:SetWidth(108)  -- initial width; will be adjusted when text is set
        if styleFunc then styleFunc(btn) end
        charPickerBtn              = btn
        frame._lariasCharPickerBtn = btn
        local tr = Addon.Controls.GetButtonFontString(btn)
        if tr and tr.ClearAllPoints and tr.SetPoint then
            tr:ClearAllPoints()
            tr:SetPoint("CENTER", btn, "CENTER", 0, 0)
            if tr.SetJustifyH then tr:SetJustifyH("CENTER") end
            if tr.SetJustifyV then tr:SetJustifyV("MIDDLE") end
        end
        btn:SetScript("OnEnter", function(self_)
            local L = Addon.L or {}
            GameTooltip:SetOwner(self_, "ANCHOR_BOTTOMLEFT")
            GameTooltip:SetText(L.CHAR_PICKER_BUTTON or "Swap Profile", 1, 1, 1)
            GameTooltip:AddLine(L.CHAR_PICKER_BUTTON_TOOLTIP or "Click to switch to another character view.", 0.7, 0.7, 0.7, true)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        return btn
    end

    local function UpdateLabel()
        local btn = charPickerBtn
        if not btn then return end
        local L   = Addon.L or {}
        local panelOpen = charPickerPanel and charPickerPanel.IsShown and charPickerPanel:IsShown()
        local arrowTex  = panelOpen
            and "|TInterface\\Buttons\\UI-ScrollBar-ScrollUpButton-Up:10:10|t"
            or  "|TInterface\\Buttons\\UI-ScrollBar-ScrollDownButton-Up:10:10|t"
        local tr = Addon.Controls.GetButtonFontString(btn)
        if Addon._viewingChar then
            -- Show the viewed character's name (class-colored) instead of "Swap Profile".
            local charName = (Addon._viewingChar:match("^(.-)%s*%-") or Addon._viewingChar)
                              :gsub("^%s+",""):gsub("%s+$","")
            if charName == "" then charName = Addon._viewingChar end
            btn:SetText(charName .. " " .. arrowTex)
            local gdb = Addon.db and Addon.db.global
            local cls  = gdb and gdb.charClasses and gdb.charClasses[Addon._viewingChar]
            local cc   = cls and RAID_CLASS_COLORS and RAID_CLASS_COLORS[cls]
            if cc and tr and tr.SetTextColor then
                tr:SetTextColor(cc.r, cc.g, cc.b, 1)
            else
                Addon.Controls.ApplyThemeTextColor(tr)
            end
        else
            local myName = (UnitName and UnitName("player")) or (L.CHAR_PICKER_BUTTON or "Swap Profile")
            btn:SetText(myName .. " " .. arrowTex)
            local myClassToken
            if UnitClass then _, myClassToken = UnitClass("player") end
            local myCC = myClassToken and RAID_CLASS_COLORS and RAID_CLASS_COLORS[myClassToken]
            if myCC and tr and tr.SetTextColor then
                tr:SetTextColor(myCC.r, myCC.g, myCC.b, 1)
            else
                Addon.Controls.ApplyThemeTextColor(tr)
            end
        end
        -- Adjust button width to fit the new text content.
        AdjustButtonWidth(btn)
    end

    -- ── Panel ─────────────────────────────────────────────────────────────────
    local function EnsurePanel()
        if charPickerPanel then return charPickerPanel end
        local p = Addon.Controls.NewPopupPanel("HIGH", 0.15)
        p:SetSize(160, 40)
        p._buttons    = {}
        p._buttonPool = {}
        charPickerPanel = p
        -- Keep the toggle-button arrow in sync with panel visibility.
        p:HookScript("OnShow", function() UpdateLabel() end)
        p:HookScript("OnHide", function() UpdateLabel() end)
        return p
    end

    local function ReleaseBtns(p)
        if not (p and p._buttons and p._buttonPool) then return end
        for i = #p._buttons, 1, -1 do
            local btn = p._buttons[i]
            p._buttons[i] = nil
            if btn then
                btn:Hide()
                btn:ClearAllPoints()
                btn:SetScript("OnClick", nil)
                btn:SetScript("OnEnter", nil)
                btn:SetScript("OnLeave", nil)
                tinsert(p._buttonPool, btn)
            end
        end
        p._buttons = {}
    end

    local function AcquireBtn(p)
        local btn = tremove(p._buttonPool)
        if not btn then
            btn = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
            btn:SetFrameStrata("HIGH")
            if styleFunc then styleFunc(btn) end
            -- StyleMainTabButton resets backdrop colors; re-apply theme after it runs.
            Addon:ApplyTheme(btn)
            local tr = Addon.Controls.GetButtonFontString(btn)
            if tr then
                if tr.SetJustifyH then tr:SetJustifyH("LEFT") end
                if tr.SetJustifyV then tr:SetJustifyV("MIDDLE") end
                -- Allow text to expand naturally without RIGHT constraint to prevent overlap.
                if tr.ClearAllPoints and tr.SetPoint then
                    tr:ClearAllPoints()
                    tr:SetPoint("LEFT",  btn, "LEFT",  6, 0)
                end
            end
        end
        btn:Show()
        return btn
    end

    -- Helper: look up class token for a charKey.
    -- Only direct charKey lookups are used; profile-name fallbacks are
    -- intentionally omitted to avoid inheriting colours from shared AceDB
    -- profiles (e.g. "Default") which may belong to a different class.
    local function classFor(charKey)
        local gdb = Addon.db and Addon.db.global
        if not (gdb and gdb.charClasses) then return nil end
        return gdb.charClasses[charKey] or nil
    end

    -- Helper: returns true only if the char has enough saved data to be
    -- worth showing.  A char with only all-zero currency rows (e.g. first
    -- login before doing any weeklies) is treated as having no usable data.
    local function hasUsableData(charKey)
        local gdb = Addon.db and Addon.db.global
        local cdb = gdb and gdb.chars and gdb.chars[charKey]
        return cdb and SnapshotHasUsableData(cdb.trackingSnapshot) or false
    end

    -- ── Right-click context menu (hide / show a character) ────────────────────
    local rcMenu       -- lazy popup panel
    local function ShowRightClickMenu(srcBtn, profileKey)
        local gdb = Addon.db and Addon.db.global
        if not gdb then return end

        if not rcMenu then
            rcMenu = Addon.Controls.NewPopupPanel("DIALOG", 0.10)
            rcMenu:SetSize(160, 32)
        end

        local charName = (profileKey:match("^(.-)%s*%-") or profileKey):gsub("^%s+",""):gsub("%s+$","")
        local isHidden = (gdb.hiddenChars and gdb.hiddenChars[profileKey]) and true or false

        if not rcMenu._rcActionBtn then
            local ab = Addon.Controls.NewActionButton(rcMenu, 148, 20)
            Addon:ApplyTheme(ab)
            ab:ClearAllPoints()
            ab:SetPoint("TOPLEFT",  rcMenu, "TOPLEFT",  6, -6)
            ab:SetPoint("TOPRIGHT", rcMenu, "TOPRIGHT", -6, -6)
            rcMenu._rcActionBtn = ab
        end
        local ab = rcMenu._rcActionBtn
        ab:SetText(isHidden
            and ((L.CHAR_PICKER_SHOW_FMT or "Show %s"):format(charName))
            or ((L.CHAR_PICKER_HIDE_FMT or "Hide %s"):format(charName)))
        local tr = Addon.Controls.GetButtonFontString(ab)
        if tr then
            if isHidden then tr:SetTextColor(0.5, 1, 0.5, 1)
            else             tr:SetTextColor(1, 0.5, 0.5, 1) end
        end
        ab:Show()
        ab:SetScript("OnClick", function()
            rcMenu:Hide()
            gdb.hiddenChars = gdb.hiddenChars or {}
            if isHidden then
                gdb.hiddenChars[profileKey] = nil
            else
                gdb.hiddenChars[profileKey] = true
                -- If viewing the now-hidden char, reset to own character.
                if Addon._viewingChar == profileKey then
                    Addon:SetViewingChar(nil)
                end
            end
            if Addon.CharPicker and Addon.CharPicker.Populate then Addon.CharPicker.Populate() end
            if Addon.LayoutHeaderButtons then Addon:LayoutHeaderButtons() end
            if Addon.RefreshAltsSummary  then Addon:RefreshAltsSummary()  end
        end)

        rcMenu:ClearAllPoints()
        rcMenu:SetPoint("TOPLEFT", srcBtn, "BOTTOMLEFT", 0, -4)
        rcMenu:Show()
    end

    local function Populate()
        local CHECK = "|TInterface\\RaidFrame\\ReadyCheck-Ready:12:12|t"
        local p       = EnsurePanel()
        ReleaseBtns(p)
        local ownKey  = Addon:GetCurrentProfileKey()
        local allKeys = Addon:GetCharProfileKeys()
        local gdb     = Addon.db and Addon.db.global
        local posY    = -CPICK_PAD

        -- When viewing another character, show a "back to me" entry first.
        if Addon._viewingChar then
            local myName = (UnitName and UnitName("player")) or (L.CHAR_PICKER_MY_CHARACTER or "My character")
            local btn = AcquireBtn(p)
            btn:ClearAllPoints()
            btn:SetPoint("TOPLEFT",  p, "TOPLEFT",  0, posY)
            btn:SetPoint("TOPRIGHT", p, "TOPRIGHT", 0, posY)
            btn:SetHeight(CPICK_ROW_H)
            btn:SetText((L.CHAR_PICKER_BACK_FMT or "<< %s"):format(myName))  -- back to own char
            local tr = Addon.Controls.GetButtonFontString(btn)
            local th = Addon.THEME.text
            if tr then tr:SetTextColor(th.r, th.g, th.b, 0.7) end
            btn:SetScript("OnEnter", function(self_)
                local fs = Addon.Controls.GetButtonFontString(self_)
                if fs then fs:SetTextColor(1, 1, 0, 1) end
                GameTooltip:SetOwner(self_, "ANCHOR_RIGHT")
                GameTooltip:SetText(L.CHAR_PICKER_MY_CHARACTER or "My character", 1, 1, 1)
                GameTooltip:AddLine(L.CHAR_PICKER_BACK_TOOLTIP or "Returns to your current character's checklist.", 0.7, 0.7, 0.7, true)
                GameTooltip:Show()
            end)
            btn:SetScript("OnLeave", function(self_)
                local fs = Addon.Controls.GetButtonFontString(self_)
                if fs then fs:SetTextColor(th.r, th.g, th.b, 0.7) end
                GameTooltip:Hide()
            end)
            btn:SetScript("OnClick", function()
                p:Hide()
                Addon:SetViewingChar(nil)
            end)
            tinsert(p._buttons, btn)
            posY = posY - CPICK_ROW_H
        end

        for _, profileKey in ipairs(allKeys) do
            local isViewing = (profileKey == Addon._viewingChar)
            if IsPickableChar(Addon, profileKey, ownKey, gdb) then
                local classToken = classFor(profileKey)
                -- Skip chars with no class entry or no saved snapshot data.
                if classToken and hasUsableData(profileKey) then
                local charName = (profileKey:match("^(.-)%s*%-") or profileKey):gsub("^%s+",""):gsub("%s+$","")
                if charName == "" then charName = profileKey end

                local r, g, b = 1, 1, 1
                local cc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classToken]
                if cc then r, g, b = cc.r, cc.g, cc.b end

                local btn = AcquireBtn(p)
                btn:ClearAllPoints()
                -- Name button spans the full panel width.
                btn:SetPoint("TOPLEFT",  p, "TOPLEFT",  0, posY)
                btn:SetPoint("TOPRIGHT", p, "TOPRIGHT", 0, posY)
                btn:SetHeight(CPICK_ROW_H)

                -- Helper: build and show a tooltip for a character button.
                local function ShowCharTooltip(self_, pk, isCurrentlyViewing)
                    local gdb2  = Addon.db and Addon.db.global
                    local cdb   = gdb2 and gdb2.chars and gdb2.chars[pk]
                    local cls   = gdb2 and gdb2.charClasses and gdb2.charClasses[pk]
                    local lvl   = gdb2 and gdb2.charLevels  and gdb2.charLevels[pk]
                    local ilvl  = cdb and tonumber(cdb.ilvl) or 0
                    local realm = pk:match("%s*%-%s*(.+)$") or ""
                    local cname = (pk:match("^(.-)%s*%-") or pk):gsub("^%s+",""):gsub("%s+$","")
                    if cname == "" then cname = pk end
                    GameTooltip:SetOwner(self_, "ANCHOR_RIGHT")
                    -- Name line in class color.
                    local tr2, tg2, tb2 = 1, 1, 1
                    local cc2 = cls and RAID_CLASS_COLORS and RAID_CLASS_COLORS[cls]
                    if cc2 then tr2, tg2, tb2 = cc2.r, cc2.g, cc2.b end
                    GameTooltip:SetText(cname, tr2, tg2, tb2)
                    if realm ~= "" then
                        GameTooltip:AddLine(realm, 0.7, 0.7, 0.7)
                    end
                    if cls then
                        local clsName = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[cls])
                                     or (LOCALIZED_CLASS_NAMES_FEMALE and LOCALIZED_CLASS_NAMES_FEMALE[cls])
                                     or (cls:sub(1,1) .. cls:sub(2):lower())
                        if lvl and lvl > 0 then
                            local lvlFmt = L.CHAR_PICKER_LEVEL_CLASS_FMT or "%s %d %s"
                            local lvlLabel = _G.LEVEL or "Level"
                            GameTooltip:AddLine(lvlFmt:format(lvlLabel, lvl, clsName), 0.85, 0.85, 0.85)
                        else
                            GameTooltip:AddLine(clsName, 0.85, 0.85, 0.85)
                        end
                    end
                    if ilvl > 0 then
                        local ilvlFmt = L.CHAR_PICKER_ITEM_LEVEL_FMT or "Item Level %d"
                        GameTooltip:AddLine(ilvlFmt:format(math.floor(ilvl)), 0.90, 0.82, 0.55)
                    end
                    if isCurrentlyViewing then
                        GameTooltip:AddLine(L.CHAR_PICKER_CURRENTLY_VIEWING or "Currently viewing", 0.3, 1, 0.3)
                    else
                        GameTooltip:AddLine(L.CHAR_PICKER_TOOLTIP_ACTIONS or "Click to view  |  Right-click to hide", 0.5, 0.5, 0.5)
                    end
                    GameTooltip:Show()
                end

                if isViewing then
                    -- Currently viewed: show ✔ prefix, disable clicking; no X.
                    btn:SetText(CHECK .. " " .. charName)
                    btn:SetEnabled(false)
                    local tr = Addon.Controls.GetButtonFontString(btn)
                    if tr then tr:SetTextColor(0, 1, 0, 0.9) end
                    btn:SetScript("OnClick", nil)
                    local _pk2 = profileKey
                    btn:SetScript("OnEnter", function(self_) ShowCharTooltip(self_, _pk2, true) end)
                    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
                else
                    btn:SetText(charName)
                    btn:SetEnabled(true)
                    local tr = Addon.Controls.GetButtonFontString(btn)
                    if tr then tr:SetTextColor(r, g, b, 1) end

                    local _r, _g, _b, _pk = r, g, b, profileKey
                    btn:SetScript("OnMouseDown", function(self_, button)
                        if button == "RightButton" then
                            ShowRightClickMenu(self_, _pk)
                        end
                    end)
                    btn:SetScript("OnEnter", function(self_)
                        local fs = Addon.Controls.GetButtonFontString(self_)
                        if fs then fs:SetTextColor(1, 1, 0, 1) end
                        ShowCharTooltip(self_, _pk, false)
                    end)
                    btn:SetScript("OnLeave", function(self_)
                        local fs = Addon.Controls.GetButtonFontString(self_)
                        if fs then fs:SetTextColor(_r, _g, _b, 1) end
                        GameTooltip:Hide()
                    end)
                    btn:SetScript("OnClick", function(self_, button)
                        if button == "RightButton" then return end
                        p:Hide()
                        Addon:SetViewingChar(_pk)
                    end)
                end
                tinsert(p._buttons, btn)
                posY = posY - CPICK_ROW_H
                end  -- classToken guard
            end
        end

        -- "≡ Alt Summary" button — shown at the bottom unless the user disabled it.
        local _showAltSum = Addon:EnsurePrefs().showAltSummaryBtn ~= false
        if _showAltSum then
            local smBtn = AcquireBtn(p)
            smBtn:ClearAllPoints()
            smBtn:SetPoint("TOPLEFT",  p, "TOPLEFT",  0, posY)
            smBtn:SetPoint("TOPRIGHT", p, "TOPRIGHT", 0, posY)
            smBtn:SetHeight(CPICK_ROW_H)
            smBtn:SetText(L.ALT_SUMMARY_TITLE or "Alt Summary")
            smBtn:SetEnabled(true)
            local tr = Addon.Controls.GetButtonFontString(smBtn)
            if tr then tr:SetTextColor(0.70, 0.70, 1, 1) end
            smBtn:SetScript("OnEnter", function(self_)
                local fs = Addon.Controls.GetButtonFontString(self_)
                if fs then fs:SetTextColor(1, 1, 0.6, 1) end
                GameTooltip:SetOwner(self_, "ANCHOR_RIGHT")
                GameTooltip:SetText(L.ALT_SUMMARY_TITLE or "Alt Summary", 1, 1, 1)
                GameTooltip:AddLine(L.CHAR_PICKER_ALT_SUMMARY_TOOLTIP or "Opens an account-wide summary for all tracked characters.", 0.7, 0.7, 0.7, true)
                GameTooltip:Show()
            end)
            smBtn:SetScript("OnLeave", function(self_)
                local fs = Addon.Controls.GetButtonFontString(self_)
                if fs then fs:SetTextColor(0.70, 0.70, 1, 1) end
                GameTooltip:Hide()
            end)
            smBtn:SetScript("OnClick", function()
                p:Hide()
                if Addon.ToggleAltsSummary then
                    Addon:ToggleAltsSummary(charPickerBtn)
                end
            end)
            tinsert(p._buttons, smBtn)
            posY = posY - CPICK_ROW_H
        end  -- _showAltSum guard

        p:SetHeight(math.max(40, -posY + CPICK_PAD))

        if C_Timer and C_Timer.After then
            C_Timer.After(0, function()
                if not (p and p.IsShown and p:IsShown()) then return end
                local bestW = 0
                for _, b in ipairs(p._buttons) do
                    local tr = b.Text or (b.GetFontString and b:GetFontString())
                    local w
                    if tr then
                        if tr.GetUnboundedStringWidth then w = tonumber(tr:GetUnboundedStringWidth())
                        elseif tr.GetStringWidth      then w = tonumber(tr:GetStringWidth()) end
                    end
                    if not w and b.GetTextWidth then w = tonumber(b:GetTextWidth()) end
                    if w and w > bestW then bestW = w end
                end
                -- Buttons fill via TOPLEFT+TOPRIGHT anchors; only panel width needed.
                -- +10 for text insets (LEFT+6, RIGHT-4). X sits outside panel.
                local totalW = math.max(90, math.min(260, math.ceil(bestW) + 10))
                p:SetWidth(totalW)
            end)
        end
    end  -- end Populate

    -- ── OnClick for the header button ─────────────────────────────────────────
    local function OnPickerBtnClick()
        local p = EnsurePanel()
        if p and p.IsShown and p:IsShown() then
            p:Hide()
            return
        end
        local btn = EnsureBtn()
        p:ClearAllPoints()
        p:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -4)
        p:Show()
        if C_Timer and C_Timer.After then
            C_Timer.After(0, Populate)
        else
            Populate()
        end
    end

    -- ── Expose CharPicker API on Addon.CharPicker namespace ───────────────────
    -- Centralising these under a single table avoids polluting Addon with
    -- many underscored "private" keys and makes ownership clear at a glance.
    Addon.CharPicker = Addon.CharPicker or {}
    Addon.CharPicker.EnsureBtn   = EnsureBtn
    Addon.CharPicker.UpdateLabel = UpdateLabel
    Addon.CharPicker.Populate    = Populate
    Addon.CharPicker.OnClick     = OnPickerBtnClick
    Addon.CharPicker.Close       = function()
        if charPickerPanel and charPickerPanel.IsShown and charPickerPanel:IsShown() then
            charPickerPanel:Hide()
        end
        if rcMenu and rcMenu.IsShown and rcMenu:IsShown() then
            rcMenu:Hide()
        end
    end
    -- Compatibility aliases (referenced by older call sites before namespace was introduced).
    Addon._cpEnsureBtn           = Addon.CharPicker.EnsureBtn
    Addon._cpUpdateLabel         = Addon.CharPicker.UpdateLabel
    Addon._cpPopulate            = Addon.CharPicker.Populate
    Addon._cpOnClick             = Addon.CharPicker.OnClick
    Addon._cpClose               = Addon.CharPicker.Close
    Addon.UpdateCharPickerBtnLabel = UpdateLabel
end
