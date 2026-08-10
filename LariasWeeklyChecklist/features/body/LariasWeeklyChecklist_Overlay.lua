-- LariasWeeklyChecklist_Overlay.lua
-- Owns the tracking panel frame, event routing, snapshot persistence and
-- all UI rendering.  Pure data computation lives in GreatVault.lua and
-- Currency.lua; this file wires them together through the Addon: API.
local addonName = ...
local Addon = _G[addonName]
if not Addon then return end

if Addon.InitConstants then
    Addon:InitConstants(addonName)
end

local THEME = Addon.THEME
local UI    = Addon.UI
local L     = Addon.L or {}

local tonumber, tostring, type = tonumber, tostring, type
local floor, max, abs = math.floor, math.max, math.abs
local tinsert, tconcat = table.insert, table.concat

--  Module-level state 
Addon.TRACKING = Addon.TRACKING or {}

-- TrackingUI owns every sub-frame/FontString created by CreateTrackingPanel.
local TrackingUI = { left = {}, right = {} }

-- Key lists for ResizeTrackingCols to iterate without allocating.
local LEFT_LINE_KEYS  = { "line1","line2","line3","line4","line5","line6","line7","line8","line9" }
local RIGHT_LINE_COUNT = Addon.RIGHT_LINE_COUNT or 10
local RIGHT_ROW_KEYS  = {}
for _i = 1, RIGHT_LINE_COUNT do RIGHT_ROW_KEYS[_i] = "line" .. _i end
local EnsureRightRowCount
local SNAPSHOT_ROW_BY_KEY = {}
local SNAPSHOT_NON_CURRENCY_ROWS = {}
local SNAPSHOT_FALLBACK_ROWS = {}

-- GV layout constants (sourced from Addon.GV_LAYOUT set by GreatVault.lua).
local _GL           = Addon.GV_LAYOUT
local GV_LABEL_W    = _GL.LABEL_W
local GV_LABEL_GAP  = _GL.LABEL_GAP
local GV_GRID_X     = _GL.GRID_X
local GV_ROW_H      = _GL.ROW_H
local GV_GRID_H     = _GL.GRID_H
local GV_BLOCK_STEP = _GL.BLOCK_STEP
local GV_BLOCK_Y    = _GL.BLOCK_Y
local GV_CELL_W     = _GL.CELL_W
local GV_GRID_W     = _GL.GRID_W

--  Shared mini-utilities 
local AU             = Addon.AddonUtils
local COLORS         = AU.COLORS
local ColorWrap      = AU.ColorWrap
local Wipe           = AU.Wipe
local IsNonEmptyText = AU.IsNonEmptyText
local FormatXY       = AU.FormatXY
local ColorForXY     = AU.ColorForXY
local GetCurrencyName = AU.GetCurrencyName
local GetItemName     = AU.GetItemName
local GetFrameCursorOffset = AU.GetFrameCursorOffset
local CreateDragReorderController = AU.CreateDragReorderController

local function SetTextIfChanged(fs, text)
    if not fs then return end
    text = text or ""
    if fs._lariasText ~= text then
        fs._lariasText = text
        fs:SetText(text)
    end
end

local function SetShownIfChanged(region, shown)
    if not (region and region.IsShown and region.SetShown) then return end
    local want = shown and true or false
    if region:IsShown() ~= want then region:SetShown(want) end
end

local IsFrameShown = AU.IsFrameShown

local function WipeKeyedTable(t)
    for k in pairs(t) do
        t[k] = nil
    end
    return t
end

local function WipeArrayTable(t)
    for i = #t, 1, -1 do
        t[i] = nil
    end
    return t
end

local function MakeCurrencySnapshotKey(rowType, id)
    return tostring(rowType or "") .. ":" .. tostring(tonumber(id) or 0)
end

local function BottomFor(obj)
    if not obj then return 0 end
    if obj.IsShown and not IsFrameShown(obj) then return 0 end
    local y = tonumber(obj._lariasBaseY) or 0
    local h = 0
    if obj.GetStringHeight then h = tonumber(obj:GetStringHeight()) or 0 end
    if h <= 0 and obj.GetHeight then h = tonumber(obj:GetHeight()) or 0 end
    if h <= 0 then h = 16 end
    return abs(y) + h
end

local function IsMainFrameOnListTab()
    local main = _G and _G["LariasWeeklyChecklistFrame"]
    local selectedTab = main and tonumber(main._lariasSelectedTab)
    return (selectedTab == nil) or (selectedTab == 1)
end

--  Rendering helpers 

local function ApplyGreatVaultGrid(gridBlocks)
    local grids = TrackingUI.left.gvGrids
    if not grids then return end
    local function setGridVisible(grid, shown)
        local function sv(obj) if obj then if shown then obj:Show() else obj:Hide() end end end
        sv(grid.header); sv(grid.topLine); sv(grid.botLine)
        sv(grid.vLeft);  sv(grid.vRight);  sv(grid.vMid1); sv(grid.vMid2)
        if grid.cells then
            for col = 1, 3 do
                local cell = grid.cells[col]
                if cell then sv(cell.bot); sv(cell.hit) end
            end
        end
        -- _hoverZone shows/hides with the block; _xBtn appears on hover only
        sv(grid._hoverZone)
        if grid._xBtn then grid._xBtn:Hide() end
    end
    for bi = 1, 3 do
        local grid  = grids[bi]
        local block = gridBlocks and gridBlocks[bi]
        if not (grid and grid.cells) then break end
        if Addon:IsGVBlockHidden(bi) then
            setGridVisible(grid, false)
        else
            setGridVisible(grid, true)
            if block and block.available then
                local done = block.complete or 0
                if grid.header then grid.header:SetTextColor(1, 1, 1, 1) end
                for col = 1, 3 do
                    local slot     = block.slots and block.slots[col]
                    local ilvl     = slot and slot.ilvl or 0
                    local unlocked = done >= col
                    local cell     = grid.cells[col]
                    local txt
                    if unlocked and ilvl > 0 then
                        txt = ColorWrap(Addon.IlvlUtils.GetColorHex(ilvl), tostring(ilvl))
                        if cell.hit then
                            cell.hit._lariasTooltipText = Addon.IlvlUtils.GetTrackLabel(ilvl)
                        end
                    else
                        txt = ColorWrap(COLORS.dim, "-")
                        if cell.hit then cell.hit._lariasTooltipText = nil end
                    end
                    SetTextIfChanged(cell.bot, txt)
                end
            else
                if grid.header then grid.header:SetTextColor(0.5, 0.5, 0.5, 1.0) end
                for col = 1, 3 do
                    local cell = grid.cells[col]
                    SetTextIfChanged(cell.bot, ColorWrap(COLORS.dim, "-"))
                    if cell.hit then cell.hit._lariasTooltipText = nil end
                end
            end
        end
    end
end

local function SetRightRowPair(i, rowLabel, rowValue, iconFileID, currencyID, tooltipText, amountTooltipText, itemID, questKey)
    if EnsureRightRowCount then EnsureRightRowCount(i) end
    local row = TrackingUI.right[RIGHT_ROW_KEYS[i]]
    if not (row and row.label and row.value) then return end
    rowLabel = rowLabel or ""; rowValue = rowValue or ""
    local txt = Addon.THEME and Addon.THEME.text
    if txt then
        row.label:SetTextColor(txt.r, txt.g, txt.b, txt.a or 1)
        row.value:SetTextColor(txt.r, txt.g, txt.b, txt.a or 1)
    end
    SetTextIfChanged(row.label, rowLabel)
    SetTextIfChanged(row.value, rowValue)
    local showRow = IsNonEmptyText(rowLabel) or IsNonEmptyText(rowValue)
    SetShownIfChanged(row.frame or row.label, showRow)
    if row.frame then
        row.frame._lariasTooltipText       = tooltipText or nil
        row.frame._lariasAmountTooltipText = amountTooltipText or nil
    end
    if row.icon then
        if showRow and iconFileID and iconFileID ~= 0 then
            if row.icon._tex then row.icon._tex:SetTexture(iconFileID) end
            row.icon._lariasIconCurrencyID = (not itemID) and currencyID or nil
            row.icon._lariasIconItemID     = itemID or nil
            row.icon._lariasIconQuestKey   = questKey or nil
            SetShownIfChanged(row.icon, true)
        else
            if row.icon._tex then row.icon._tex:SetTexture(nil) end
            row.icon._lariasIconCurrencyID = nil
            row.icon._lariasIconItemID     = nil
            row.icon._lariasIconQuestKey   = nil
            SetShownIfChanged(row.icon, false)
        end
    end
    if row.frame then
        row.frame._lariasRightClickCurrencyID = (showRow and currencyID) and currencyID or nil
        row.frame._lariasRightClickItemID     = (showRow and itemID) and itemID or nil
        row.frame._lariasRightClickQuestKey   = (showRow and questKey) and questKey or nil
    end
end

local function ApplyRightColumnAsPairs()
    -- Delegates to Currency module for the row data.
    local panelRows = Addon:GetCurrencyPanelRows()
    if EnsureRightRowCount then EnsureRightRowCount(max(RIGHT_LINE_COUNT, #panelRows)) end
    for i, row in ipairs(panelRows) do
        SetRightRowPair(i, row.label, row.value, row.iconID, row.currencyID, row.tooltipText, row.amountTooltipText, row.itemID, row.questKey)
    end
    for i = #panelRows + 1, RIGHT_LINE_COUNT do
        SetRightRowPair(i, "", "")
    end
end

local function ResizeTrackingPanelToContent(addon)
    local trackingFrame = addon._trackingFrame
    if not (trackingFrame and trackingFrame.GetHeight and trackingFrame.SetHeight) then return end

    local bottomRight = 0
    for i = 1, RIGHT_LINE_COUNT do
        local row = TrackingUI.right[RIGHT_ROW_KEYS[i]]
        if type(row) == "table" then
            bottomRight = max(bottomRight, BottomFor(row.frame or row.label))
        else
            bottomRight = max(bottomRight, BottomFor(row))
        end
    end

    -- Reflow GV rows: use natural cell height (squares stay square) and centre
    -- the blocks vertically.  targetH drives how much space to centre within;
    -- at least naturalGvH so currency shrinking never collapses the GV.
    if Addon._reflowGVGrid then
        local GAP        = 8
        local nVisible   = 0
        for bi = 1, 3 do
            if not addon:IsGVBlockHidden(bi) then nVisible = nVisible + 1 end
        end
        local naturalGvH = nVisible * GV_GRID_H + max(0, nVisible - 1) * GAP
        local targetGvH  = max(naturalGvH, bottomRight)
        Addon._reflowGVGrid(targetGvH > 0 and targetGvH or nil)
    end

    local bottomLeft = max(0, BottomFor(TrackingUI.left._gvSentinel))
    local contentH   = max(bottomLeft, bottomRight)
    local topOffset  = 32
    local bottomPad  = 10
    local minH       = 90
    local targetH    = max(minH, topOffset + contentH + bottomPad)
    do
        local main = addon._mainFrame
        local frameH = (main and main.GetHeight and tonumber(main:GetHeight())) or UI.frameH or 737
        local trackingBottomY = (UI.sliderBottomPad or 4) + (UI.sliderH or 20)
        local minScrollH = 44
        local maxH = frameH
            - trackingBottomY
            - (UI.scrollTop or 38)
            - (UI.trackTopPad or 10)
            - minScrollH
        targetH = math.min(targetH, max(minH, maxH))
    end
    local curH       = tonumber(trackingFrame:GetHeight()) or 0
    if abs(curH - targetH) <= 1 then return end

    trackingFrame:SetHeight(targetH)
    if trackingFrame._lariasLeftCol  and trackingFrame._lariasLeftCol.SetHeight  then trackingFrame._lariasLeftCol:SetHeight(max(1, targetH - 40))  end
    if trackingFrame._lariasRightCol and trackingFrame._lariasRightCol.SetHeight then trackingFrame._lariasRightCol:SetHeight(max(1, targetH - 40)) end
    if addon.ApplyScrollLayout then addon:ApplyScrollLayout() end
end

local function ComputeWantTrackingPanel(prefs)
    local wantPanel = (prefs.showGreatVault or prefs.showCurrency) and true or false
    if wantPanel and not IsMainFrameOnListTab() then wantPanel = false end
    return wantPanel
end

local function EnsureTrackingPanelCreatedIfNeeded(wantPanel)
    if not wantPanel or Addon._trackingFrame then return end
    local main = _G["LariasWeeklyChecklistFrame"]
    if main then
        Addon:CreateTrackingPanel(main)
        Addon:ApplyScrollLayout()
    end
end

local _currencyConfigPopup
local _currencyConfigShowHidden = false
local CURRENCY_CONFIG_DRAG_THRESHOLD = 10
local CURRENCY_CONFIG_MIN_HEIGHT = 430

local function GetConfiguredPopupEntryLabel(entry)
    if type(entry) ~= "table" then return "" end

    local itemID = tonumber(entry.itemID)
    if itemID then
        local itemName = GetItemName and GetItemName(itemID)
        if itemName and itemName ~= "" then
            return itemName
        end
        return entry.label or tostring(itemID)
    end

    local id = tonumber(entry.id)
    if not id then return tostring(entry.id or "") end
    local name = Addon.GetCurrencyName and Addon:GetCurrencyName(id)
    if name and name ~= "" then
        return name .. " (" .. id .. ")"
    end
    local fmt = (Addon.L and Addon.L.CURRENCY_CONFIG_CURRENCY_FMT) or "Currency %d"
    return fmt:format(id)
end

local function FindTrackedCurrencyConfigIndex(cfg, currencyID)
    local targetID = tonumber(currencyID)
    if not (type(cfg) == "table" and targetID) then return nil end
    for i = 1, #cfg do
        if tonumber(cfg[i] and cfg[i].id) == targetID then
            return i
        end
    end
    return nil
end

local function GetPopupEntryKey(entry)
    if type(entry) ~= "table" then return nil end
    local itemID = tonumber(entry.itemID)
    if itemID then return "item:" .. itemID end
    local id = tonumber(entry.id)
    if id then return "currency:" .. id end
    return nil
end

local function FindTrackedCurrencyConfigIndexByKey(cfg, targetKey)
    if type(cfg) ~= "table" or not targetKey then return nil end
    for i = 1, #cfg do
        if GetPopupEntryKey(cfg[i]) == targetKey then
            return i
        end
    end
    return nil
end

local function MoveTrackedCurrencyConfigEntryByVisibleOrder(cfg, displayEntries, movingKey, targetVisibleIdx)
    if not (type(cfg) == "table" and type(displayEntries) == "table" and movingKey) then return cfg end

    local visibleKeys = {}
    for i = 1, #displayEntries do
        local visibleKey = GetPopupEntryKey(displayEntries[i])
        if visibleKey and visibleKey ~= movingKey then
            visibleKeys[#visibleKeys + 1] = visibleKey
        end
    end

    targetVisibleIdx = max(1, min(#visibleKeys + 1, tonumber(targetVisibleIdx) or 1))
    table.insert(visibleKeys, targetVisibleIdx, movingKey)

    local movingCfgIdx = FindTrackedCurrencyConfigIndexByKey(cfg, movingKey)
    if not movingCfgIdx or not cfg[movingCfgIdx] then return cfg end

    local movingEntry = table.remove(cfg, movingCfgIdx)
    if not movingEntry then return cfg end

    local insertedPos
    for i = 1, #visibleKeys do
        if visibleKeys[i] == movingKey then
            insertedPos = i
            break
        end
    end
    if not insertedPos then return cfg end

    local nextVisibleKey = visibleKeys[insertedPos + 1]
    if nextVisibleKey then
        local nextCfgIdx = FindTrackedCurrencyConfigIndexByKey(cfg, nextVisibleKey)
        if nextCfgIdx then
            table.insert(cfg, nextCfgIdx, movingEntry)
            return cfg
        end
    end

    local prevVisibleKey = visibleKeys[insertedPos - 1]
    if prevVisibleKey then
        local prevCfgIdx = FindTrackedCurrencyConfigIndexByKey(cfg, prevVisibleKey)
        if prevCfgIdx then
            table.insert(cfg, prevCfgIdx + 1, movingEntry)
            return cfg
        end
    end

    table.insert(cfg, 1, movingEntry)
    return cfg
end

local function BuildCurrencyConfigDisplayEntries(showHidden)
    local cfg = Addon:GetTrackedCurrencyConfig()
    local entries = {}
    local seen = {}
    local hiddenCount = 0

    for i = 1, #cfg do
        local entry = cfg[i]
        local id = tonumber(entry and entry.id)
        local itemID = tonumber(entry and entry.itemID)
        local entryKey = GetPopupEntryKey(entry)
        if entryKey and not seen[entryKey] then
            seen[entryKey] = true
            local isItem = itemID and true or false
            local isHidden = isItem and (Addon.IsItemHidden and Addon:IsItemHidden(itemID) or false) or false
            if isHidden then
                hiddenCount = hiddenCount + 1
            end
            if showHidden or not isHidden then
                entries[#entries + 1] = {
                    id = id,
                    itemID = itemID,
                    enabled = entry.enabled ~= false,
                    hidden = isHidden,
                    source = entry.source or "custom",
                    kind = entry.kind,
                }
            end
        end
    end

    if showHidden then
        local hiddenCurrencies = Addon.GetHiddenCurrencyList and Addon:GetHiddenCurrencyList() or {}
        for i = 1, #hiddenCurrencies do
            local id = tonumber(hiddenCurrencies[i].id)
            local key = id and ("currency:" .. id) or nil
            if key and not seen[key] then
                seen[key] = true
                hiddenCount = hiddenCount + 1
                entries[#entries + 1] = {
                    id = id,
                    enabled = false,
                    hidden = true,
                    source = (Addon.IsBuiltInTrackedCurrencyID and Addon:IsBuiltInTrackedCurrencyID(id)) and "builtin" or "custom",
                }
            end
        end

        local hiddenItems = Addon.GetHiddenItemList and Addon:GetHiddenItemList() or {}
        for i = 1, #hiddenItems do
            local itemID = tonumber(hiddenItems[i].id)
            local key = itemID and ("item:" .. itemID) or nil
            if key and not seen[key] then
                seen[key] = true
                hiddenCount = hiddenCount + 1
                entries[#entries + 1] = {
                    itemID = itemID,
                    enabled = false,
                    hidden = true,
                    source = "builtin-item",
                    kind = "item",
                }
            end
        end
    end

    return entries, cfg, hiddenCount
end

local function CurrencyConfigHideDragIndicator(popup)
    if popup and popup._dragInsertTex then
        popup._dragInsertTex:Hide()
    end
end

local function CurrencyConfigRestoreDraggedRowVisual(state)
    local row = state and state.row
    if row and row.SetAlpha then
        row:SetAlpha(1)
    end
end

local function CurrencyConfigApplyDraggedRowVisual(state)
    local row = state and state.row
    if row and row.SetAlpha then
        row:SetAlpha(0.4)
    end
end

local function CurrencyConfigGetDropIndex(popup, cursorPopupY)
    local displayEntries = popup and popup._displayEntries
    local draggableCount = type(displayEntries) == "table" and #displayEntries or 0
    if draggableCount <= 0 then return nil end

    local rowsAnchorTop = popup._rowsAnchor and popup._rowsAnchor:GetTop()
    local popupTop = popup.GetTop and popup:GetTop()
    if not (rowsAnchorTop and popupTop) then return nil end

    local rowH = popup._rowHeight or 26
    local rowsAnchorOffset = popupTop - rowsAnchorTop
    local relativeY = (cursorPopupY or 0) - rowsAnchorOffset
    local idx = floor((relativeY + (rowH * 0.5)) / rowH) + 1
    return max(1, min(draggableCount + 1, idx))
end

local function CurrencyConfigShowDragIndicator(popup, targetIdx)
    if not (popup and popup._dragInsertTex and popup._rowsAnchor) then return end

    local rowH = popup._rowHeight or 26
    local themeHeader = Addon.THEME and Addon.THEME.header or { r = 1, g = 0.82, b = 0, a = 1 }
    local lineY = -((targetIdx - 1) * rowH)
    popup._dragInsertTex:SetColorTexture(themeHeader.r, themeHeader.g, themeHeader.b, 0.9)
    popup._dragInsertTex:ClearAllPoints()
    popup._dragInsertTex:SetPoint("TOPLEFT", popup._rowsAnchor, "TOPLEFT", 0, lineY)
    popup._dragInsertTex:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -12, lineY)
    popup._dragInsertTex:SetHeight(2)
    popup._dragInsertTex:Show()
end

local function CurrencyConfigShowRowTooltip(popup, row, owner)
    local current = row and row._entryData
    local L = Addon.L or {}
    if not current then return end

    GameTooltip:SetOwner(owner or row, "ANCHOR_RIGHT")
    GameTooltip:SetText(GetConfiguredPopupEntryLabel(current), 1, 0.82, 0)
    if current.kind == "item" then
        if current.hidden then
            GameTooltip:AddLine(L.CURRENCY_CONFIG_TOOLTIP_RESTORE_FRONT or "Alt+left-click restores it and moves it to the front.", 0.75, 0.75, 0.75, true)
        else
            GameTooltip:AddLine(L.CURRENCY_CONFIG_TOOLTIP_REORDER or "Alt+left-click moves this currency to the front.", 0.75, 0.75, 0.75, true)
            GameTooltip:AddLine(L.CURRENCY_CONFIG_TOOLTIP_HIDE or "Right-click hides this currency.", 0.75, 0.75, 0.75, true)
        end
        GameTooltip:Show()
        return
    end

    if current.hidden then
        GameTooltip:AddLine(L.CURRENCY_CONFIG_TOOLTIP_RESTORE_FRONT or "Alt+left-click restores it and moves it to the front.", 0.75, 0.75, 0.75, true)
    else
        GameTooltip:AddLine(L.CURRENCY_CONFIG_TOOLTIP_REORDER or "Alt+left-click moves this currency to the front.", 0.75, 0.75, 0.75, true)
        GameTooltip:AddLine(L.CURRENCY_CONFIG_TOOLTIP_HIDE or "Right-click hides this currency.", 0.75, 0.75, 0.75, true)
    end
    if tostring(current.source or ""):find("^custom") then
        GameTooltip:AddLine(L.CURRENCY_CONFIG_TOOLTIP_DELETE or "Click the X to permanently delete this custom currency.", 0.75, 0.75, 0.75, true)
    end
    GameTooltip:Show()
end

local function CurrencyConfigTryEnableEntry(popup, entry)
    if not entry then return false end
    local currentCfg = Addon:GetTrackedCurrencyConfig()
    local entryID = tonumber(entry.id)
    local entryKey = GetPopupEntryKey(entry)
    local limit = popup and popup._trackedCurrencyLimit or Addon:GetTrackedCurrencyLimit()
    local currentEnabledCount = Addon.GetTrackedCurrencyEnabledCount and Addon:GetTrackedCurrencyEnabledCount(currentCfg) or 0
    local currentIdx = entryKey and FindTrackedCurrencyConfigIndexByKey(currentCfg, entryKey) or nil
    local alreadyEnabled = currentIdx and currentCfg[currentIdx] and currentCfg[currentIdx].enabled ~= false
    if not alreadyEnabled and currentEnabledCount >= limit then
        Addon:RefreshCurrencyConfigPopup((Addon.L or {}).CURRENCY_CONFIG_ENABLE_LIMIT or "Can only track up to 12 currencies.")
        return false
    end
    if currentIdx and currentCfg[currentIdx] then
        currentCfg[currentIdx].enabled = true
    elseif entry.kind == "item" and tonumber(entry.itemID) then
        currentCfg[#currentCfg + 1] = {
            itemID = tonumber(entry.itemID),
            enabled = true,
            source = entry.source or "builtin-item",
            kind = entry.kind or "item",
        }
    elseif entryID then
        currentCfg[#currentCfg + 1] = { id = entryID, enabled = true, source = entry.source or "custom" }
    else
        return false
    end
    if entry.hidden then
        if entry.kind == "item" then
            Addon:SetItemHidden(entry.itemID, false)
        elseif entryID then
            Addon:SetCurrencyHidden(entryID, false)
        end
    end
    Addon:SetTrackedCurrencyConfig(currentCfg)
    return true
end

local function CurrencyConfigHandleRowMouse(popup, row, button)
    local entry = row and row._entryData
    if not entry then return false end

    if button == "LeftButton" then
        if entry.hidden then
            CurrencyConfigTryEnableEntry(popup, entry)
        end
        return true
    end

    if button == "RightButton" then
        if entry.hidden then return true end
        if entry.kind == "item" then
            local nextCfg = Addon:GetTrackedCurrencyConfig()
            local currentIdx = FindTrackedCurrencyConfigIndexByKey(nextCfg, GetPopupEntryKey(entry))
            if currentIdx and nextCfg[currentIdx] then
                nextCfg[currentIdx].enabled = false
                Addon:SetTrackedCurrencyConfig(nextCfg)
            end
            Addon:SetItemHidden(entry.itemID, true)
            return true
        end

        local nextCfg = Addon:GetTrackedCurrencyConfig()
        local currentIdx = FindTrackedCurrencyConfigIndex(nextCfg, entry.id)
        if not currentIdx or not nextCfg[currentIdx] then return true end
        nextCfg[currentIdx].enabled = false
        Addon:SetCurrencyHidden(entry.id, true)
        Addon:SetTrackedCurrencyConfig(nextCfg)
        return true
    end

    return false
end

local function CurrencyConfigBeginRowDrag(popup, row)
    if not (popup and row and IsAltKeyDown and IsAltKeyDown()) then return end

    local entry = row._entryData
    local dragController = popup._dragReorderController
    if not entry or entry.hidden or not dragController then return end

    dragController:Begin({
        sourceIdx = row._displayIndex or 1,
        targetIdx = row._displayIndex or 1,
        row = row,
        entryID = entry.id,
        itemID = entry.itemID,
        entryKind = entry.kind,
        entryKey = GetPopupEntryKey(entry),
    })
end

function Addon:RefreshCurrencyConfigPopup(statusText)
    local p = _currencyConfigPopup
    if not p then return end

    local L = self.L or {}
    local themeHeader = self.THEME and self.THEME.header or { r = 1, g = 0.82, b = 0, a = 1 }
    local themeText = self.THEME and self.THEME.text or { r = 1, g = 1, b = 1, a = 1 }
    local displayEntries, cfg, hiddenCount = BuildCurrencyConfigDisplayEntries(_currencyConfigShowHidden)
    local limit = self:GetTrackedCurrencyLimit()
    local enabledCount = self.GetTrackedCurrencyEnabledCount and self:GetTrackedCurrencyEnabledCount(cfg) or 0
    local rowH = p._rowHeight or 26
    local textRightPad = 12
    p._displayEntries = displayEntries
    p._trackedCurrencyCfg = cfg
    p._trackedCurrencyLimit = limit

    if p._titleFS then
        p._titleFS:SetText(L.CURRENCY_CONFIG_TITLE or "Configure Currencies")
        p._titleFS:SetTextColor(themeHeader.r, themeHeader.g, themeHeader.b, themeHeader.a or 1)
    end
    if p._titleBg then
        p._titleBg:ClearAllPoints()
        p._titleBg:SetPoint("TOPLEFT", p._titleFS, "TOPLEFT", -8, 4)
        p._titleBg:SetPoint("BOTTOMRIGHT", p._titleFS, "BOTTOMRIGHT", 8, -4)
        p._titleBg:SetColorTexture(0, 0, 0, 0)
        p._titleBg:Hide()
    end
    if p._helpFS then
        p._helpFS:Hide()
    end
    if p._countFS then
        local countFmt = L.CURRENCY_CONFIG_COUNT_FMT or "%d/%d enabled"
        p._countFS:SetText(countFmt:format(enabledCount, limit))
        p._countFS:SetTextColor(themeText.r, themeText.g, themeText.b, 0.85)
    end
    if p._addLabelFS then
        p._addLabelFS:SetText(L.CURRENCY_CONFIG_ADD_LABEL or "Currency ID")
        p._addLabelFS:SetTextColor(themeText.r, themeText.g, themeText.b, 0.85)
    end
    if p._addBtn then
        p._addBtn:SetText(L.CURRENCY_CONFIG_ADD_BUTTON or "Add")
    end
    if p._statusFS then
        p._statusFS:SetText(statusText or "")
        p._statusFS:SetTextColor(themeHeader.r, themeHeader.g, themeHeader.b, 1)
    end
    if p._addBox then
        if self.ApplyTheme then self:ApplyTheme(p._addBox) end
        p._addBox:SetTextColor(themeText.r, themeText.g, themeText.b, themeText.a or 1)
    end
    if p._showHiddenChk then
        if self.ApplyTheme then self:ApplyTheme(p._showHiddenChk._box) end
        if hiddenCount > 0 then
            p._showHiddenChk:SetChecked(_currencyConfigShowHidden)
            p._showHiddenChk:ClearAllPoints()
            p._showHiddenChk:SetPoint("TOPLEFT", p._dragBar, "BOTTOMLEFT", 4, -8)
            p._showHiddenChk:Show()
            if p._showHiddenChk._label then
                p._showHiddenChk._label:SetText(L.CURRENCY_CONFIG_SHOW_HIDDEN or "Show hidden")
                p._showHiddenChk._label:SetTextColor(themeText.r, themeText.g, themeText.b, themeText.a or 1)
                p._showHiddenChk._label:Show()
            end
            if p._showHiddenChk._hit then p._showHiddenChk._hit:Show() end
        else
            _currencyConfigShowHidden = false
            p._showHiddenChk:Hide()
            if p._showHiddenChk._label then p._showHiddenChk._label:Hide() end
            if p._showHiddenChk._hit then p._showHiddenChk._hit:Hide() end
        end
    end
    if p._rowsAnchor then
        p._rowsAnchor:ClearAllPoints()
        if p._showHiddenChk and hiddenCount > 0 then
            p._rowsAnchor:SetPoint("TOPLEFT", p._showHiddenChk, "BOTTOMLEFT", 0, -8)
        else
            p._rowsAnchor:SetPoint("TOPLEFT", p._dragBar, "BOTTOMLEFT", 4, -6)
        end
        p._rowsAnchor:SetPoint("TOPRIGHT", p, "TOPRIGHT", -12, 0)
    end

    p._rowFrames = p._rowFrames or {}
    for i = 1, #p._rowFrames do
        p._rowFrames[i]:Hide()
    end

    local rowAnchor = p._rowsAnchor or p

    for i = 1, #displayEntries do
        local row = p._rowFrames[i]
        if not row then
            row = CreateFrame("Frame", nil, p)
            row:SetHeight(rowH)

            row._cb = Addon.Controls.NewCheckBox(row, nil, 14)
            row._deleteBtn = Addon.Controls.NewCloseButton(row, function()
                local entry = row._entryData
                if not (entry and tostring(entry.source or ""):find("^custom")) then return end
                local nextCfg = Addon:GetTrackedCurrencyConfig()
                local currentIdx = FindTrackedCurrencyConfigIndexByKey(nextCfg, GetPopupEntryKey(entry))
                if currentIdx and nextCfg[currentIdx] then
                    table.remove(nextCfg, currentIdx)
                    Addon:SetTrackedCurrencyConfig(nextCfg)
                end
                if entry.itemID then
                    Addon:SetItemHidden(entry.itemID, false)
                elseif entry.id then
                    Addon:SetCurrencyHidden(entry.id, false)
                end
            end)
            row._deleteBtn:SetSize(16, 16)
            row._deleteBtn:SetPoint("RIGHT", row, "RIGHT", 0, 0)
            row._deleteBtn:SetScript("OnEnter", function(self_)
                GameTooltip:SetOwner(self_, "ANCHOR_RIGHT")
                GameTooltip:SetText(L.CURRENCY_CONFIG_DELETE_BUTTON or "Delete custom currency", 1, 0.82, 0)
                GameTooltip:AddLine(L.CURRENCY_CONFIG_DELETE_BUTTON_TOOLTIP or "Removes this custom currency from the list entirely.", 1, 1, 1, true)
                GameTooltip:Show()
            end)
            row._deleteBtn:SetScript("OnLeave", function()
                GameTooltip:Hide()
            end)
            row._cb:SetPoint("LEFT", row, "LEFT", 0, 0)
            row:EnableMouse(true)
            row:SetScript("OnEnter", function(self_)
                CurrencyConfigShowRowTooltip(p, row, self_)
            end)
            row:SetScript("OnLeave", function()
                GameTooltip:Hide()
            end)
            row:SetScript("OnMouseDown", function(_, button)
                if button == "LeftButton" then
                    CurrencyConfigBeginRowDrag(p, row)
                end
            end)
            row:SetScript("OnMouseUp", function(_, button)
                local dragController = p._dragReorderController
                local dragState = dragController and dragController:GetState()
                if button == "LeftButton" and dragState
                        and dragState.entryKey == GetPopupEntryKey(row._entryData) then
                    dragController:Finish()
                    return
                end
                CurrencyConfigHandleRowMouse(p, row, button)
            end)
            row._cb:SetScript("OnClick", function(self_)
                local dragController = p._dragReorderController
                if (dragController and dragController:GetState()) or (IsAltKeyDown and IsAltKeyDown()) then return end
                local entry = row._entryData
                if not entry then return end
                if entry.hidden then
                    CurrencyConfigTryEnableEntry(p, entry)
                    return
                end
                if entry.kind == "item" then
                    local newVal = not self_:GetChecked()
                    local nextCfg = Addon:GetTrackedCurrencyConfig()
                    local currentIdx = FindTrackedCurrencyConfigIndexByKey(nextCfg, GetPopupEntryKey(entry))
                    if newVal
                            and Addon.GetTrackedCurrencyEnabledCount
                            and (not (currentIdx and nextCfg[currentIdx] and nextCfg[currentIdx].enabled ~= false))
                            and Addon:GetTrackedCurrencyEnabledCount(nextCfg) >= (p._trackedCurrencyLimit or limit) then
                        self_:SetChecked(false)
                        Addon:RefreshCurrencyConfigPopup(L.CURRENCY_CONFIG_ENABLE_LIMIT or "Can only track up to 12 currencies.")
                        return
                    end
                    self_:SetChecked(newVal)
                    if currentIdx and nextCfg[currentIdx] then
                        nextCfg[currentIdx].enabled = newVal and true or false
                        Addon:SetTrackedCurrencyConfig(nextCfg)
                    end
                    return
                end
                self_:SetChecked(not self_:GetChecked())
                local nextCfg = Addon:GetTrackedCurrencyConfig()
                local currentIdx = FindTrackedCurrencyConfigIndex(nextCfg, entry.id)
                if self_:GetChecked()
                        and Addon.GetTrackedCurrencyEnabledCount
                        and (not (currentIdx and nextCfg[currentIdx] and nextCfg[currentIdx].enabled ~= false))
                        and Addon:GetTrackedCurrencyEnabledCount(nextCfg) >= (p._trackedCurrencyLimit or limit) then
                    self_:SetChecked(false)
                    Addon:RefreshCurrencyConfigPopup(L.CURRENCY_CONFIG_ENABLE_LIMIT or "Can only track up to 12 currencies.")
                    return
                end
                if currentIdx and nextCfg[currentIdx] then
                    nextCfg[currentIdx].enabled = self_:GetChecked() and true or false
                    Addon:SetTrackedCurrencyConfig(nextCfg)
                end
            end)
            row._cb:SetScript("OnMouseDown", function(_, button)
                if button == "LeftButton" then
                    CurrencyConfigBeginRowDrag(p, row)
                end
            end)
            row._cb:SetScript("OnMouseUp", function(_, button)
                local dragController = p._dragReorderController
                local dragState = dragController and dragController:GetState()
                if button == "LeftButton" and dragState
                        and dragState.entryKey == GetPopupEntryKey(row._entryData) then
                    dragController:Finish()
                    return
                end
                if button == "RightButton" then
                    CurrencyConfigHandleRowMouse(p, row, button)
                end
            end)
            row._cb:SetScript("OnEnter", function(self_)
                CurrencyConfigShowRowTooltip(p, row, self_)
            end)
            row._cb:SetScript("OnLeave", function()
                GameTooltip:Hide()
            end)
            if row._cb._hit then
                row._cb._hit:SetScript("OnClick", function()
                    local dragController = p._dragReorderController
                    if (dragController and dragController:GetState()) or (IsAltKeyDown and IsAltKeyDown()) then return end
                    local entry = row._entryData
                    if not entry then return end
                    if entry.hidden then
                        CurrencyConfigTryEnableEntry(p, entry)
                        return
                    end
                    local newVal = not row._cb:GetChecked()
                    if entry.kind == "item" then
                        local nextCfg = Addon:GetTrackedCurrencyConfig()
                        local currentIdx = FindTrackedCurrencyConfigIndexByKey(nextCfg, GetPopupEntryKey(entry))
                        if newVal
                                and Addon.GetTrackedCurrencyEnabledCount
                                and (not (currentIdx and nextCfg[currentIdx] and nextCfg[currentIdx].enabled ~= false))
                                and Addon:GetTrackedCurrencyEnabledCount(nextCfg) >= (p._trackedCurrencyLimit or limit) then
                            Addon:RefreshCurrencyConfigPopup(L.CURRENCY_CONFIG_ENABLE_LIMIT or "Can only track up to 12 currencies.")
                            return
                        end
                        row._cb:SetChecked(newVal)
                        if currentIdx and nextCfg[currentIdx] then
                            nextCfg[currentIdx].enabled = newVal and true or false
                            Addon:SetTrackedCurrencyConfig(nextCfg)
                        end
                        return
                    end
                    local nextCfg = Addon:GetTrackedCurrencyConfig()
                    local currentIdx = FindTrackedCurrencyConfigIndex(nextCfg, entry.id)
                    if newVal
                            and Addon.GetTrackedCurrencyEnabledCount
                            and (not (currentIdx and nextCfg[currentIdx] and nextCfg[currentIdx].enabled ~= false))
                            and Addon:GetTrackedCurrencyEnabledCount(nextCfg) >= (p._trackedCurrencyLimit or limit) then
                        Addon:RefreshCurrencyConfigPopup(L.CURRENCY_CONFIG_ENABLE_LIMIT or "Can only track up to 12 currencies.")
                        return
                    end
                    row._cb:SetChecked(newVal)
                    if currentIdx and nextCfg[currentIdx] then
                        nextCfg[currentIdx].enabled = newVal and true or false
                        Addon:SetTrackedCurrencyConfig(nextCfg)
                    end
                end)
                row._cb._hit:SetScript("OnMouseDown", function(_, button)
                    if button == "LeftButton" then
                        CurrencyConfigBeginRowDrag(p, row)
                    end
                end)
                row._cb._hit:SetScript("OnMouseUp", function(_, button)
                    local dragController = p._dragReorderController
                    local dragState = dragController and dragController:GetState()
                    if button == "LeftButton" and dragState
                            and dragState.entryKey == GetPopupEntryKey(row._entryData) then
                        dragController:Finish()
                        return
                    end
                    if button == "RightButton" then
                        CurrencyConfigHandleRowMouse(p, row, button)
                    end
                end)
                row._cb._hit:SetScript("OnEnter", function(self_)
                    CurrencyConfigShowRowTooltip(p, row, self_)
                end)
                row._cb._hit:SetScript("OnLeave", function()
                    GameTooltip:Hide()
                end)
            end

            p._rowFrames[i] = row
        end

        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", rowAnchor, "TOPLEFT", 0, -((i - 1) * rowH))
        row:SetPoint("TOPRIGHT", rowAnchor, "TOPRIGHT", 0, -((i - 1) * rowH))
        row:Show()

        local entry = displayEntries[i]
        row._entryData = entry
        row._displayIndex = i
        row._cb:SetChecked(entry.enabled ~= false)
        row._cb:SetPoint("LEFT", row, "LEFT", 0, 0)
        local labelRightPad = (tostring(entry.source or ""):find("^custom")) and 28 or textRightPad
        if row._cb._label then
            row._cb._label:ClearAllPoints()
            row._cb._label:SetPoint("LEFT", row._cb._box, "RIGHT", 6, 0)
            row._cb._label:SetPoint("RIGHT", row, "RIGHT", -labelRightPad, 0)
            row._cb._label:SetText(GetConfiguredPopupEntryLabel(entry))
            if entry.hidden then
                row._cb._label:SetTextColor(themeText.r, themeText.g, themeText.b, 0.35)
            elseif entry.enabled == false then
                row._cb._label:SetTextColor(themeText.r, themeText.g, themeText.b, 0.55)
            else
                row._cb._label:SetTextColor(themeText.r, themeText.g, themeText.b, themeText.a or 1)
            end
        end
        if row._cb._hit then
            row._cb._hit:ClearAllPoints()
            row._cb._hit:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
            row._cb._hit:SetPoint("BOTTOMRIGHT", row, "RIGHT", -labelRightPad, 0)
        end
        if row._deleteBtn then
            if tostring(entry.source or ""):find("^custom") then
                row._deleteBtn:Show()
            else
                row._deleteBtn:Hide()
            end
        end
    end

    if p._addLabelFS and p._addBox and p._addBtn then
        local footerPad = 10
        p._addLabelFS:ClearAllPoints()
        p._addLabelFS:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", 12, footerPad + 26)

        p._addBox:ClearAllPoints()
        p._addBox:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", 12, footerPad)

        p._addBtn:ClearAllPoints()
        p._addBtn:SetPoint("LEFT", p._addBox, "RIGHT", 6, 0)

        if p._statusFS then
            p._statusFS:ClearAllPoints()
            p._statusFS:SetPoint("BOTTOMLEFT", p._addLabelFS, "TOPLEFT", 0, 6)
            p._statusFS:SetPoint("RIGHT", p, "RIGHT", -12, 0)
        end
    end

    local widestRowW = 0
    for i = 1, #displayEntries do
        local row = p._rowFrames[i]
        if row and row._cb and row._cb._label and row._cb._label.GetStringWidth then
            local rowW = (row._cb._label:GetStringWidth() or 0)
                + ((displayEntries[i].source == "custom") and 54 or 26)
            if rowW > widestRowW then
                widestRowW = rowW
            end
        end
    end
    local headerW = 0
    if p._titleFS and p._countFS then
        headerW = (p._titleFS:GetStringWidth() or 0) + (p._countFS:GetStringWidth() or 0) + 54
    end
    local addRowW = 0
    if p._addBox and p._addBtn then
        addRowW = (p._addBox:GetWidth() or 0) + (p._addBtn:GetWidth() or 0) + 22
    end
    local showHiddenW = 0
    if p._showHiddenChk and p._showHiddenChk:IsShown() and p._showHiddenChk._label and p._showHiddenChk._label.GetStringWidth then
        showHiddenW = (p._showHiddenChk._label:GetStringWidth() or 0) + 28
    end
    local desiredW = max(292, min(360, max(widestRowW + 40, headerW, addRowW + 24, showHiddenW + 24)))
    p:SetWidth(desiredW)

    local rowsTopOffset = hiddenCount > 0 and 42 or 30
    local totalH = rowsTopOffset + (#displayEntries * rowH) + 108
    p:SetHeight(max(CURRENCY_CONFIG_MIN_HEIGHT, totalH))
end

function Addon:ToggleCurrencyConfigPopup(anchor)
    local p = _currencyConfigPopup
    local L = self.L or {}
    if p and p.IsShown and p:IsShown() then
        p:Hide()
        return
    end

    if not p then
        p = Addon.Controls.NewPopupPanel("DIALOG", 0.12)
        Addon:RegisterWindowSurface(p, {
            opacityMode = "ui",
            borderStyle = "popup",
            surfaceTopA = 0,
            surfaceBottomA = 0.05,
            bgAlpha = Addon.POPUP_BG_ALPHA_FACTOR or 1.5,
        })
        _G["LariasCurrencyConfigFrame"] = p
        tinsert(UISpecialFrames, "LariasCurrencyConfigFrame")
        p:SetSize(320, CURRENCY_CONFIG_MIN_HEIGHT)
        p:SetMovable(true)
        p:SetClampedToScreen(true)
        local gdb = self:EnsurePrefs()
        gdb.currencyConfigWin = gdb.currencyConfigWin or {}
        p._windowConfig = gdb.currencyConfigWin
        p._windowLib = LibStub("LibWindow-1.1")
        p._windowLib.RegisterConfig(p, p._windowConfig)
        p._windowLib.MakeDraggable(p)
        p._closeOnOutsideClick = false
        p._rowHeight = 26

        local dragBar = CreateFrame("Frame", nil, p)
        dragBar:SetPoint("TOPLEFT", p, "TOPLEFT", 8, -8)
        dragBar:SetPoint("TOPRIGHT", p, "TOPRIGHT", -8, -8)
        dragBar:SetHeight(24)
        dragBar:EnableMouse(true)
        dragBar:RegisterForDrag("LeftButton")
        dragBar:SetScript("OnDragStart", function()
            p:StartMoving()
        end)
        dragBar:SetScript("OnDragStop", function()
            p:StopMovingOrSizing()
            p._windowLib.SavePosition(p)
        end)
        p._dragBar = dragBar

        local dragInsert = p:CreateTexture(nil, "OVERLAY")
        dragInsert:Hide()
        p._dragInsertTex = dragInsert
        p._dragUpdate = function(self_)
            if self_._dragReorderController then
                self_._dragReorderController:Update()
            end
        end
        p._dragReorderController = CreateDragReorderController(p, {
            threshold = CURRENCY_CONFIG_DRAG_THRESHOLD,
            getCursorValue = function(self_)
                return GetFrameCursorOffset(self_, "y")
            end,
            hideIndicator = function(frame_)
                CurrencyConfigHideDragIndicator(frame_)
            end,
            restoreDragVisual = function(state)
                CurrencyConfigRestoreDraggedRowVisual(state)
            end,
            applyDragVisual = function(state)
                CurrencyConfigApplyDraggedRowVisual(state)
            end,
            onActivate = function()
                GameTooltip:Hide()
            end,
            getDropIndex = function(cursorY, _, frame_)
                return CurrencyConfigGetDropIndex(frame_, cursorY)
            end,
            showIndicator = function(targetIdx, _, frame_)
                CurrencyConfigShowDragIndicator(frame_, targetIdx)
            end,
            onCommit = function(frame_, state, targetIdx)
                local nextCfg = Addon:GetTrackedCurrencyConfig()
                MoveTrackedCurrencyConfigEntryByVisibleOrder(nextCfg, frame_._displayEntries, state.entryKey, targetIdx)
                Addon:SetTrackedCurrencyConfig(nextCfg)
            end,
            setUpdating = function(frame_, enabled)
                frame_:SetScript("OnUpdate", enabled and frame_._dragUpdate or nil)
            end,
        })
        p:HookScript("OnHide", function(self_)
            if self_._dragReorderController then
                self_._dragReorderController:Clear()
            end
            if self_._dragInsertTex then
                self_._dragInsertTex:Hide()
            end
            self_._displayEntries = nil
            self_._trackedCurrencyCfg = nil
        end)

        local closeBtn = Addon.Controls.NewCloseButton(p, function() p:Hide() end)
        closeBtn:SetPoint("TOPRIGHT", p, "TOPRIGHT", -4, -4)
        p._closeBtn = closeBtn

        local titleFS = p:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        titleFS:SetPoint("TOPLEFT", dragBar, "TOPLEFT", 4, 0)
        titleFS:SetJustifyH("LEFT")
        p._titleFS = titleFS

        local titleBg = p:CreateTexture(nil, "ARTWORK")
        p._titleBg = titleBg

        local countFS = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        countFS:SetPoint("RIGHT", closeBtn, "LEFT", -8, 0)
        countFS:SetJustifyH("RIGHT")
        p._countFS = countFS

        local helpFS = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        helpFS:SetPoint("TOPLEFT", dragBar, "BOTTOMLEFT", 4, -8)
        helpFS:SetPoint("TOPRIGHT", p, "TOPRIGHT", -12, -6)
        helpFS:SetJustifyH("LEFT")
        helpFS:SetTextColor(0.75, 0.75, 0.75, 1)
        if helpFS.SetWordWrap then helpFS:SetWordWrap(true) end
        helpFS:Hide()
        p._helpFS = helpFS

        local addLabelFS = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        addLabelFS:SetJustifyH("LEFT")
        p._addLabelFS = addLabelFS

        local addBox = CreateFrame("EditBox", nil, p, "InputBoxTemplate")
        addBox:SetAutoFocus(false)
        addBox:SetSize(118, 20)
        addBox:SetScript("OnEscapePressed", function(self_) self_:ClearFocus() end)
        p._addBox = addBox

        local addBtn = Addon.Controls.NewActionButton(p, 64, 20)
        p._addBtn = addBtn

        local statusFS = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        statusFS:SetJustifyH("LEFT")
        statusFS:SetTextColor(1.0, 0.82, 0.0, 1)
        if statusFS.SetWordWrap then statusFS:SetWordWrap(true) end
        p._statusFS = statusFS

        local showHiddenChk = Addon.Controls.NewCheckBox(p, function(v)
            _currencyConfigShowHidden = v and true or false
            Addon:RefreshCurrencyConfigPopup()
        end, 14)
        if showHiddenChk._label then
            showHiddenChk._label:SetPoint("LEFT", showHiddenChk._box, "RIGHT", 6, 0)
            showHiddenChk._label:SetText(L.CURRENCY_CONFIG_SHOW_HIDDEN or "Show hidden")
        end
        if showHiddenChk._hit then
            showHiddenChk._hit:SetPoint("TOPLEFT", showHiddenChk, "TOPLEFT", 0, 0)
            showHiddenChk._hit:SetPoint("BOTTOMRIGHT", showHiddenChk, "RIGHT", 140, 0)
            showHiddenChk._hit:SetHeight(18)
        end
        showHiddenChk:SetScript("OnEnter", function(self_)
            GameTooltip:SetOwner(self_, "ANCHOR_RIGHT")
            GameTooltip:SetText(L.CURRENCY_CONFIG_SHOW_HIDDEN or "Show hidden", 1, 0.82, 0)
            GameTooltip:AddLine(L.CURRENCY_CONFIG_SHOW_HIDDEN_TOOLTIP_RESTORE or L.CURRENCY_CONFIG_SHOW_HIDDEN_TOOLTIP or "", 1, 1, 1, true)
            GameTooltip:Show()
        end)
        showHiddenChk:SetScript("OnLeave", function() GameTooltip:Hide() end)
        p._showHiddenChk = showHiddenChk

        local rowsAnchor = CreateFrame("Frame", nil, p)
        rowsAnchor:SetPoint("TOPLEFT", dragBar, "BOTTOMLEFT", 4, -6)
        rowsAnchor:SetPoint("TOPRIGHT", p, "TOPRIGHT", -12, 0)
        rowsAnchor:SetHeight(1)
        p._rowsAnchor = rowsAnchor

        local function SubmitAdd()
            local raw = p._addBox and p._addBox:GetText() or ""
            local id = tonumber(raw)
            if not (id and id > 0) then
                Addon:RefreshCurrencyConfigPopup(L.CURRENCY_CONFIG_INVALID_ID or "Enter a valid currency ID.")
                return
            end
            local cfg = Addon:GetTrackedCurrencyConfig()
            for i = 1, #cfg do
                if tonumber(cfg[i].id) == id then
                    Addon:RefreshCurrencyConfigPopup(L.CURRENCY_CONFIG_DUPLICATE or "That currency is already configured.")
                    return
                end
            end
            if Addon.GetTrackedCurrencyEnabledCount
                    and Addon:GetTrackedCurrencyEnabledCount(cfg) >= Addon:GetTrackedCurrencyLimit() then
                Addon:RefreshCurrencyConfigPopup(L.CURRENCY_CONFIG_ENABLE_LIMIT or "Can only track up to 12 currencies.")
                return
            end
            cfg[#cfg + 1] = { id = id, enabled = true, source = "custom" }
            Addon:SetCurrencyHidden(id, false)
            if p._addBox then p._addBox:SetText("") end
            Addon:SetTrackedCurrencyConfig(cfg)
        end

        addBtn:SetScript("OnClick", SubmitAdd)
        addBox:SetScript("OnEnterPressed", function()
            SubmitAdd()
        end)

        _currencyConfigPopup = p
        Addon._currencyConfigPopup = p
    end

    self:RefreshCurrencyConfigPopup()

    if not p._shownOnce then
        p:ClearAllPoints()
        if p._windowConfig.x ~= nil and p._windowConfig.y ~= nil then
            p._windowLib.RestorePosition(p)
        else
            p:SetPoint("CENTER", UIParent, "CENTER")
        end
        p._shownOnce = true
    end
    p:Show()
end

--  Panel creation 
function Addon:CreateTrackingPanel(parentFrame)
    if self._trackingFrame then return end
    local db = self:EnsurePrefs()

    local trackingFrame = CreateFrame("Frame", nil, parentFrame)
    local trackingBottomY = (UI.sliderBottomPad or 4) + (UI.sliderH or 20)
    trackingFrame:SetPoint("BOTTOMLEFT",  parentFrame, "BOTTOMLEFT",  UI.sectionInsetX,  trackingBottomY)
    trackingFrame:SetPoint("BOTTOMRIGHT", parentFrame, "BOTTOMRIGHT", -UI.sectionInsetX, trackingBottomY)
    trackingFrame:SetHeight(UI.trackH)
    self:RegisterWindowSurface(trackingFrame, {
        opacityMode = "ui",
        borderStyle = "panel",
        surfaceTopA = 0,
    })

    local title = trackingFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", trackingFrame, "TOPLEFT", 10, -8)
    title:SetTextColor(THEME.header.r, THEME.header.g, THEME.header.b, THEME.header.a)
    title:SetText(L.TRACKING_GREAT_VAULT_TITLE or "Great Vault")
    trackingFrame._lariasLeftTitle = title

    local padL, padR = 10, 10
    local colGap = 12
    local innerW = (UI.frameW - (UI.sectionInsetX * 2) - padL - padR)
    local colW   = math.floor((innerW - colGap) / 2)
    trackingFrame._lariasPadL    = padL
    trackingFrame._lariasPadR    = padR
    trackingFrame._lariasColGap  = colGap
    trackingFrame._lariasColW    = colW

    local leftCol = CreateFrame("Frame", nil, trackingFrame)
    leftCol:SetPoint("TOPLEFT", trackingFrame, "TOPLEFT", padL, -32)
    leftCol:SetSize(colW, UI.trackH - 40)
    trackingFrame._lariasLeftCol = leftCol

    local rightCol = CreateFrame("Frame", nil, trackingFrame)
    rightCol:SetPoint("TOPLEFT", leftCol, "TOPRIGHT", colGap, 0)
    rightCol:SetSize(colW, UI.trackH - 40)
    trackingFrame._lariasRightCol = rightCol

    local BOX_PAD = 6

    local function MakeTitleButton(col, tipText, onClick)
        local btn = CreateFrame("Button", nil, trackingFrame)
        btn:SetPoint("TOPLEFT",     col, "TOPLEFT",  -BOX_PAD,  24 + BOX_PAD)
        btn:SetPoint("BOTTOMRIGHT", col, "TOPRIGHT",  BOX_PAD,  BOX_PAD)
        btn:EnableMouse(true)
        local hl = btn:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.07)
        btn:SetScript("OnEnter", function(self) AU.SetTooltip(self, tipText, "ANCHOR_TOP") end)
        btn:SetScript("OnLeave", AU.HideTooltip)
        btn:RegisterForClicks("AnyUp")
        if onClick then
            btn:SetScript("OnClick", function(self_, button)
                if button == "RightButton" then return end
                onClick()
            end)
        end
        return btn
    end

    -- Vertical separator shown between the two columns.
    local colSep = trackingFrame:CreateTexture(nil, "ARTWORK")
    colSep:SetColorTexture(THEME.border.r, THEME.border.g, THEME.border.b,
        (Addon.VISUAL_STYLE and Addon.VISUAL_STYLE.strongDividerA) or 0.65)
    colSep:SetWidth(1)
    colSep:SetPoint("TOPLEFT",    leftCol, "TOPRIGHT",    floor(colGap / 2), 24 + BOX_PAD)
    colSep:SetPoint("BOTTOMLEFT", leftCol, "BOTTOMRIGHT", floor(colGap / 2), -BOX_PAD)
    colSep:Hide()
    trackingFrame._lariasColSep = colSep

    trackingFrame._lariasLeftTitleBtn = MakeTitleButton(leftCol,
        L.TOOLTIP_OPEN_GREAT_VAULT or "Click to open the Great Vault",
        function()
            Addon:ToggleGreatVault()
        end)

    local currencyTip = L.TOOLTIP_OPEN_CURRENCIES or "Click to open the Currency panel"
    local configureTip = L.TOOLTIP_CONFIGURE_CURRENCIES or "Right-click to configure tracked currencies"
    trackingFrame._lariasRightTitleBtn = MakeTitleButton(rightCol,
        currencyTip .. "\n" .. configureTip,
        function() ToggleCharacter("TokenFrame") end)
    trackingFrame._lariasRightTitleBtn:HookScript("OnClick", function(self_, button)
        if button ~= "RightButton" then return end
        Addon:ToggleCurrencyConfigPopup(self_)
    end)

    local rightTitle = trackingFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    rightTitle:SetPoint("TOPLEFT", trackingFrame, "TOPLEFT", padL + colW + colGap, -8)
    rightTitle:SetTextColor(THEME.header.r, THEME.header.g, THEME.header.b, THEME.header.a)
    rightTitle:SetText(L.TRACKING_CURRENCY_TITLE or "Currency")
    trackingFrame._lariasRightTitle = rightTitle

    title:ClearAllPoints()
    title:SetPoint("TOP", leftCol, "TOP", 0, 24)
    title:SetWidth(colW); title:SetJustifyH("CENTER")

    rightTitle:ClearAllPoints()
    rightTitle:SetPoint("TOP", rightCol, "TOP", 0, 24)
    rightTitle:SetWidth(colW); rightTitle:SetJustifyH("CENTER")

    --  Great Vault grids 
    local GV_SECTION_KEYS   = { "TRACKING_GV_RAID", "TRACKING_GV_DUNGEONS", "TRACKING_GV_WORLD" }
    local GV_SECTION_LABELS = { "Raid", "Dungeons", "World" }
    local GRID_BOR_A = (Addon.VISUAL_STYLE and Addon.VISUAL_STYLE.trackingBorderA) or 0.55
    local GRID_MID_A = (Addon.VISUAL_STYLE and Addon.VISUAL_STYLE.trackingInnerA) or 0.30
    local CELL_INSET = 4

    local function MakeHLine(yOff, alpha, xOff, w)
        local t = leftCol:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(THEME.border.r, THEME.border.g, THEME.border.b, alpha)
        t:SetHeight(1)
        t:SetPoint("TOPLEFT", leftCol, "TOPLEFT", xOff or 0, yOff)
        if w then t:SetWidth(w) else t:SetPoint("TOPRIGHT", leftCol, "TOPRIGHT", 0, yOff) end
        t._lariasBaseY = yOff
        return t
    end

    local function MakeVLine(xOff, yOff, alpha)
        local t = leftCol:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(THEME.border.r, THEME.border.g, THEME.border.b, alpha)
        t:SetSize(1, GV_GRID_H)
        t:SetPoint("TOPLEFT", leftCol, "TOPLEFT", xOff, yOff)
        return t
    end

    local function MakeCellFS(xOff, yOff, w)
        local fs = leftCol:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        fs:SetPoint("TOPLEFT", leftCol, "TOPLEFT", xOff, yOff)
        fs:SetSize(w, GV_ROW_H); fs:SetJustifyH("CENTER"); fs:SetJustifyV("MIDDLE")
        if fs.SetWordWrap then fs:SetWordWrap(false) end
        fs:SetText("")
        return fs
    end

    local gvGrids = {}
    for bi = 1, 3 do
        local blockY   = GV_BLOCK_Y[bi]
        local gridBotY = blockY - 1 - GV_ROW_H
        local cellW    = GV_CELL_W

        local topLine = MakeHLine(blockY,   GRID_BOR_A, GV_GRID_X, GV_GRID_W)
        local botLine = MakeHLine(gridBotY, GRID_BOR_A, GV_GRID_X, GV_GRID_W)
        botLine._lariasBaseY = gridBotY

        local hdr = leftCol:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        hdr:SetPoint("TOPLEFT", leftCol, "TOPLEFT", 0, blockY)
        hdr:SetSize(GV_LABEL_W, GV_GRID_H); hdr:SetJustifyH("LEFT"); hdr:SetJustifyV("MIDDLE")
        if hdr.SetWordWrap then hdr:SetWordWrap(false) end
        hdr:SetTextColor(THEME.header.r, THEME.header.g, THEME.header.b, THEME.header.a)
        hdr:SetText(L[GV_SECTION_KEYS[bi]] or GV_SECTION_LABELS[bi])

        local vLeft  = MakeVLine(GV_GRID_X,           blockY, GRID_BOR_A)
        local vRight = MakeVLine(GV_GRID_X + GV_GRID_W, blockY, GRID_BOR_A)
        local vMid1  = MakeVLine(GV_GRID_X + cellW,     blockY, GRID_MID_A)
        local vMid2  = MakeVLine(GV_GRID_X + cellW * 2, blockY, GRID_MID_A)

        local cells = {}
        for col = 1, 3 do
            local cellX = GV_GRID_X + (col - 1) * cellW + CELL_INSET
            local cw    = cellW - CELL_INSET * 2
            local bot   = MakeCellFS(cellX, blockY - 1, cw)
            local hit   = CreateFrame("Frame", nil, leftCol)
            hit:SetAllPoints(bot)
            hit:EnableMouse(true)
            hit:SetScript("OnEnter", function(self)
                if self._lariasTooltipText then AU.SetTooltip(self, self._lariasTooltipText, "ANCHOR_TOP") end
            end)
            hit:SetScript("OnLeave", AU.HideTooltip)
            cells[col] = { bot = bot, hit = hit }
        end

        gvGrids[bi] = {
            header = hdr, topLine = topLine, botLine = botLine,
            vLeft  = vLeft, vRight = vRight, vMid1 = vMid1, vMid2 = vMid2,
            cells  = cells, gridTopY = blockY,
        }

        -- (right-click to hide removed)
        do
            local hz = CreateFrame("Frame", nil, leftCol)
            hz:SetPoint("TOPLEFT", leftCol, "TOPLEFT", 0, blockY)
            hz:SetSize(GV_GRID_X - 2, GV_GRID_H)
            gvGrids[bi]._hoverZone = hz
        end
    end
    TrackingUI.left.gvGrids    = gvGrids
    TrackingUI.left._gvSentinel = gvGrids[3] and gvGrids[3].botLine
    trackingFrame._lariasGvGrids = gvGrids

    -- ReflowGVGrid: repositions all GV elements to fill available vertical space.
    local function ReflowGVGrid(targetH)
        local grds = TrackingUI.left.gvGrids
        if not grds then return end
        local GAP = 8; local BORDER = 1; local CINSET = 4
        if targetH and targetH > 0 then
            TrackingUI.left._lastGvH = targetH
        else
            targetH = TrackingUI.left._lastGvH
            if not (targetH and targetH > 0) then return end
        end
        -- When Great Vault is the only visible column, let the grid stretch to
        -- fill the available width; otherwise preserve the designed 3-cell size.
        local leftW = (leftCol and leftCol.GetWidth and tonumber(leftCol:GetWidth())) or 0
        local availGridW = max(0, floor(leftW - GV_GRID_X))
        local gridW = GV_GRID_W
        if not (Addon._trackingFrame and Addon._trackingFrame._lariasShowBoth) and availGridW > GV_GRID_W then
            gridW = availGridW
        end
        local cellW = max(1, floor(gridW / 3))
        gridW = cellW * 3

        -- Count visible (non-hidden) blocks so row heights fill available space.
        local nVisible = 0
        for bi = 1, 3 do
            if not Addon:IsGVBlockHidden(bi) then nVisible = nVisible + 1 end
        end
        local GAP_TOTAL = max(0, nVisible - 1) * GAP
        -- Use the natural GV row height so Currency can never shrink the grid.
        local gridH   = GV_GRID_H
        local rowH    = GV_ROW_H
        -- Vertically centre the blocks; equal whitespace above and below.
        local naturalH = nVisible * gridH + GAP_TOTAL
        local vOffset  = max(0, floor((max(0, targetH) - naturalH) / 2))

        local visRow = 0
        TrackingUI.left._gvSentinel = nil
        for bi = 1, 3 do
            local grid = grds[bi]
            if not grid then break end
            local function h(obj) if obj and obj.Hide then obj:Hide() end end
            if Addon:IsGVBlockHidden(bi) then
                -- Hide every element of this block.
                h(grid.header); h(grid.topLine); h(grid.botLine)
                h(grid.vLeft);  h(grid.vRight);  h(grid.vMid1); h(grid.vMid2)
                if grid.cells then
                    for col = 1, 3 do
                        local c = grid.cells[col]
                        if c then h(c.bot); h(c.hit) end
                    end
                end
                h(grid._xBtn)
                h(grid._hoverZone)
            else
                local blockY   = -(vOffset + visRow * (gridH + GAP))
                local gridBotY = blockY - BORDER - rowH
                visRow = visRow + 1

                local function setHL(t, y)
                    if not t then return end
                    t:ClearAllPoints()
                    t:SetPoint("TOPLEFT", leftCol, "TOPLEFT", GV_GRID_X, y)
                    t:SetWidth(gridW); t._lariasBaseY = y
                    t:Show()
                end
                setHL(grid.topLine, blockY); setHL(grid.botLine, gridBotY)

                if grid.header then
                    grid.header:ClearAllPoints()
                    grid.header:SetPoint("TOPLEFT", leftCol, "TOPLEFT", 0, blockY)
                    grid.header:SetSize(GV_LABEL_W, gridH)
                    grid.header:Show()
                end

                if grid._xBtn then
                    grid._xBtn:ClearAllPoints()
                    grid._xBtn:SetPoint("TOPLEFT", leftCol, "TOPLEFT", GV_GRID_X - 16, blockY)
                    -- hidden until hovered; shown via _hoverZone
                end
                if grid._hoverZone then
                    grid._hoverZone:ClearAllPoints()
                    grid._hoverZone:SetPoint("TOPLEFT", leftCol, "TOPLEFT", 0, blockY)
                    grid._hoverZone:SetSize(GV_GRID_X - 2, gridH)
                    grid._hoverZone:Show()
                end

                TrackingUI.left._gvSentinel = grid.botLine

                local function setVL(t, x, y)
                    if not t then return end
                    t:ClearAllPoints(); t:SetPoint("TOPLEFT", leftCol, "TOPLEFT", x, y)
                    t:SetSize(1, gridH); t:Show()
                end
                setVL(grid.vLeft,  GV_GRID_X,             blockY)
                setVL(grid.vRight, GV_GRID_X + gridW,     blockY)
                setVL(grid.vMid1,  GV_GRID_X + cellW,     blockY)
                setVL(grid.vMid2,  GV_GRID_X + cellW * 2, blockY)

                for col = 1, 3 do
                    local cellX = GV_GRID_X + (col - 1) * cellW + CINSET
                    local cw    = cellW - CINSET * 2
                    local cell  = grid.cells and grid.cells[col]
                    if cell and cell.bot then
                        cell.bot:ClearAllPoints()
                        cell.bot:SetPoint("TOPLEFT", leftCol, "TOPLEFT", cellX, blockY - BORDER)
                        cell.bot:SetSize(cw, rowH)
                        cell.bot:Show()
                    end
                    if cell and cell.hit then cell.hit:Show() end
                end
                grid.gridTopY = blockY
            end
        end
    end
    Addon._reflowGVGrid = ReflowGVGrid

    --  Right column: currency rows 
    local ROW_ICON_SZ  = 14
    local ROW_ICON_GAP = 3

    local function MakeLinePair(parent, y, template)
        local row = CreateFrame("Frame", nil, parent)
        row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
        row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, y)
        row:SetHeight(16); row._lariasBaseY = y

        local icon = CreateFrame("Button", nil, row)
        icon:SetSize(ROW_ICON_SZ, ROW_ICON_SZ)
        icon:SetPoint("LEFT", row, "LEFT", 0, 0); icon:Hide(); icon:EnableMouse(true)
        local iconTex = icon:CreateTexture(nil, "ARTWORK")
        iconTex:SetAllPoints(icon); icon._tex = iconTex
        icon:SetScript("OnEnter", function(self)
            if self._lariasIconItemID then
                GameTooltip:SetOwner(self, "ANCHOR_LEFT")
                GameTooltip:SetItemByID(self._lariasIconItemID)
                GameTooltip:Show()
            elseif self._lariasIconCurrencyID then
                GameTooltip:SetOwner(self, "ANCHOR_LEFT")
                GameTooltip:SetCurrencyByID(self._lariasIconCurrencyID)
                GameTooltip:Show()
            end
        end)
        icon:SetScript("OnLeave", function() GameTooltip:Hide() end)
        icon:SetScript("OnMouseDown", function(self, button)
            if button ~= "RightButton" then return end
            local qk = self._lariasIconQuestKey
            local itemID = self._lariasIconItemID
            if itemID then
                Addon:ShowContextMenu(self, {
                    { text = (L.CONTEXT_HIDE_THIS_ITEM_FMT or "Hide %s"):format(GetItemName(itemID) or tostring(itemID)), onClick = function()
                        Addon:SetItemHidden(itemID, true)
                    end },
                })
            elseif qk then
                Addon:ShowContextMenu(self, {
                    { text = L.CONTEXT_HIDE_THIS_ROW or "Hide this row", onClick = function()
                        Addon:SetQuestHidden(qk, true)
                    end },
                })
            end
        end)

        -- Right-side hit area: shows "Accurately tracks" tooltip over the quantity numbers.
        local valueHit = CreateFrame("Frame", nil, row)
        valueHit:SetPoint("TOPRIGHT",    row, "TOPRIGHT",    0,  0)
        valueHit:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0,  0)
        valueHit:SetWidth(80)
        valueHit:EnableMouse(true)
        valueHit:SetScript("OnEnter", function(self)
            local tip = row._lariasAmountTooltipText
            if type(tip) == "table" then
                AU.SetTooltipLines(self, tip, "ANCHOR_TOP")
            elseif tip and tip ~= "" then
                AU.SetTooltip(self, tip, "ANCHOR_TOP")
            end
        end)
        valueHit:SetScript("OnLeave", AU.HideTooltip)
        valueHit:SetScript("OnMouseDown", function(_, button)
            if button ~= "RightButton" then return end
            local qk  = row._lariasRightClickQuestKey
            local itemID = row._lariasRightClickItemID
            if itemID then
                Addon:ShowContextMenu(row, {
                    { text = (L.CONTEXT_HIDE_THIS_ITEM_FMT or "Hide %s"):format(GetItemName(itemID) or tostring(itemID)), onClick = function()
                        Addon:SetItemHidden(itemID, true)
                    end },
                })
            elseif qk then
                Addon:ShowContextMenu(row, {
                    { text = L.CONTEXT_HIDE_THIS_ROW or "Hide this row", onClick = function()
                        Addon:SetQuestHidden(qk, true)
                    end },
                })
            end
        end)
        row._lariasValueHit = valueHit

        -- Full row: shows the convert tooltip when hovering over the label side.
        -- (valueHit captures mouse on the right, so OnEnter here fires on the label area only.)
        row:EnableMouse(true)
        row:SetScript("OnEnter", function(self)
            local tip = self._lariasTooltipText
            if type(tip) == "table" then
                AU.SetTooltipLines(self, tip, "ANCHOR_TOP")
            elseif tip and tip ~= "" then
                AU.SetTooltip(self, tip, "ANCHOR_TOP")
            end
        end)
        row:SetScript("OnLeave", function(self)
            AU.HideTooltip()
        end)
        row:SetScript("OnMouseDown", function(self, button)
            if button ~= "RightButton" then return end
            local qk = self._lariasRightClickQuestKey
            local itemID = self._lariasRightClickItemID
            if itemID then
                Addon:ShowContextMenu(self, {
                    { text = (L.CONTEXT_HIDE_THIS_ITEM_FMT or "Hide %s"):format(GetItemName(itemID) or tostring(itemID)), onClick = function()
                        Addon:SetItemHidden(itemID, true)
                    end },
                })
            elseif qk then
                Addon:ShowContextMenu(self, {
                    { text = L.CONTEXT_HIDE_THIS_ROW or "Hide this row", onClick = function()
                        Addon:SetQuestHidden(qk, true)
                    end },
                })
            end
        end)

        local label = row:CreateFontString(nil, "OVERLAY", template or "GameFontHighlightSmall")
        label:SetPoint("LEFT", row, "LEFT", ROW_ICON_SZ + ROW_ICON_GAP, 0)
        label:SetJustifyH("LEFT")
        if label.SetWordWrap then label:SetWordWrap(false) end
        label:SetTextColor(THEME.text.r, THEME.text.g, THEME.text.b, THEME.text.a)
        label:SetText("")

        local value = row:CreateFontString(nil, "OVERLAY", template or "GameFontHighlightSmall")
        value:SetPoint("RIGHT", row, "RIGHT", 0, 0); value:SetJustifyH("RIGHT")
        if value.SetWordWrap then value:SetWordWrap(false) end
        value:SetTextColor(THEME.text.r, THEME.text.g, THEME.text.b, THEME.text.a)
        value:SetText("")

        label:SetPoint("RIGHT", value, "LEFT", -6, 0)

        return { frame = row, icon = icon, label = label, value = value }
    end

    EnsureRightRowCount = function(count)
        count = max(tonumber(count) or 0, Addon.RIGHT_LINE_COUNT or 10)
        for i = RIGHT_LINE_COUNT + 1, count do
            RIGHT_ROW_KEYS[i] = "line" .. i
        end
        for i = 1, count do
            local key = RIGHT_ROW_KEYS[i] or ("line" .. i)
            RIGHT_ROW_KEYS[i] = key
            if not TrackingUI.right[key] then
                TrackingUI.right[key] = MakeLinePair(rightCol, -18 * (i - 1), "GameFontHighlight")
            end
        end
        RIGHT_LINE_COUNT = max(RIGHT_LINE_COUNT, count)
    end
    EnsureRightRowCount(RIGHT_LINE_COUNT)

    for i = 1, RIGHT_LINE_COUNT do
        local row = TrackingUI.right[RIGHT_ROW_KEYS[i]]
        if row and row.frame then row.frame:Show() end
    end

    trackingFrame:SetShown((db.showGreatVault or db.showCurrency) and IsMainFrameOnListTab())
    self._trackingFrame = trackingFrame

    if trackingFrame.SetScript then
        trackingFrame:SetScript("OnShow", function()
            local database = Addon:EnsurePrefs()
            Addon:ConfigureTrackingEvents(parentFrame, database.showGreatVault and true or false, database.showCurrency and true or false)
            Addon:RequestTrackingUpdate()
        end)
        trackingFrame:SetScript("OnHide", function()
            Addon:SuspendTrackingUI()
        end)
    end

    if IsFrameShown(parentFrame) and IsFrameShown(trackingFrame) then
        self:ConfigureTrackingEvents(parentFrame, db.showGreatVault and true or false, db.showCurrency and true or false)
    end
    if self.CreateStatusBanner then
        self:CreateStatusBanner(parentFrame)
        if self.ApplyScaleSliderVisibility then self:ApplyScaleSliderVisibility() end
        if self.UpdateStatusBanner then self:UpdateStatusBanner() end
    end
end

--  Options / visibility 
function Addon:ApplyTrackingPanelOptions()
    local trackingFrame = self._trackingFrame
    if not trackingFrame then return end
    local mainFrame = _G["LariasWeeklyChecklistFrame"]
    if not IsFrameShown(mainFrame) then
        trackingFrame:Hide()
        self:SuspendTrackingUI()
        return
    end

    local db    = self:EnsureDB()
    local prefs = self:EnsurePrefs()
    local showGreatVault = prefs.showGreatVault and true or false
    local showCurrency   = prefs.showCurrency   and true or false
    -- Suppress the currency column when tracking data exists but every currency
    -- has been individually hidden (GetCurrencyPanelRows returns nothing to show).
    if showCurrency and self.TRACKING and #self:GetCurrencyPanelRows() == 0 then
        showCurrency = false
    end
    -- Suppress the GV column when all 3 blocks have been individually hidden.
    if showGreatVault and Addon:IsGVBlockHidden(1) and Addon:IsGVBlockHidden(2) and Addon:IsGVBlockHidden(3) then
        showGreatVault = false
    end

    local wantPanel
    wantPanel = (showGreatVault or showCurrency) and IsMainFrameOnListTab()

    trackingFrame:SetShown(wantPanel)
    if not wantPanel then
        self:SuspendTrackingUI()
        if self.ApplyScrollLayout then self:ApplyScrollLayout() end
        return
    end

    self:ConfigureTrackingEvents(_G["LariasWeeklyChecklistFrame"], showGreatVault, showCurrency)

    local leftCol    = trackingFrame._lariasLeftCol
    local rightCol   = trackingFrame._lariasRightCol
    local leftTitle  = trackingFrame._lariasLeftTitle
    local rightTitle = trackingFrame._lariasRightTitle
    local padL   = tonumber(trackingFrame._lariasPadL)   or 10
    local padR2  = tonumber(trackingFrame._lariasPadR)   or 10
    local colGap = tonumber(trackingFrame._lariasColGap) or 12

    SetShownIfChanged(leftCol,    showGreatVault)
    SetShownIfChanged(rightCol,   showCurrency)
    SetShownIfChanged(leftTitle,  showGreatVault)
    SetShownIfChanged(rightTitle, showCurrency)

    SetShownIfChanged(trackingFrame._lariasColSep, showGreatVault and showCurrency)

    if leftCol  and leftCol.ClearAllPoints  then leftCol:ClearAllPoints()  end
    if rightCol and rightCol.ClearAllPoints then rightCol:ClearAllPoints() end

    if showGreatVault and showCurrency then
        trackingFrame._lariasShowBoth = true
        if leftCol  then leftCol:SetPoint("TOPLEFT", trackingFrame, "TOPLEFT", padL, -32) end
        if rightCol and leftCol then rightCol:SetPoint("TOPLEFT", leftCol, "TOPRIGHT", colGap, 0) end
    else
        local tfW = tonumber(trackingFrame:GetWidth())
        if not tfW or tfW < 10 then tfW = max(10, (UI.frameW or 520) - 2 * (UI.sectionInsetX or 14)) end
        local fullW = max(10, floor(tfW - padL - padR2))
        trackingFrame._lariasShowBoth = false
        if showGreatVault then
            if leftCol then
                leftCol:ClearAllPoints()
                leftCol:SetWidth(fullW)
                leftCol:SetPoint("TOPLEFT", trackingFrame, "TOPLEFT", padL, -32)
            end
        else
            if rightCol then
                rightCol:ClearAllPoints()
                rightCol:SetWidth(fullW)
                rightCol:SetPoint("TOPLEFT", trackingFrame, "TOPLEFT", padL, -32)
            end
        end
    end

    if showGreatVault and leftTitle and leftCol then
        leftTitle:ClearAllPoints()
        leftTitle:SetPoint("TOP", leftCol, "TOP", 0, 24)
    end
    if showCurrency and rightTitle and rightCol then
        rightTitle:ClearAllPoints()
        rightTitle:SetPoint("TOP", rightCol, "TOP", 0, 24)
    end

    if self.ApplyScrollLayout then self:ApplyScrollLayout() end
end

--  Snapshot 
local function RenderSnapshotIntoPanel(snap)
    -- Apply a stored snapshot into the tracking panel.
    ApplyGreatVaultGrid(snap.leftGrid or nil)

    if snap.rightRows then
        local idx = 1
        local ST = Addon.SNAP_TYPES or {}
        local tracking = Addon.TRACKING

        local byKey = WipeKeyedTable(SNAPSHOT_ROW_BY_KEY)
        local nonCurrencyRows = WipeArrayTable(SNAPSHOT_NON_CURRENCY_ROWS)

        for _, row in ipairs(snap.rightRows) do
            if (row.type == ST.CREST or row.type == ST.CATALYST
                    or row.type == ST.SPARKS or row.type == ST.COFFERKEYS
                    or row.type == ST.MISC) and row.id then
                byKey[MakeCurrencySnapshotKey(row.type, row.id)] = row
            else
                nonCurrencyRows[#nonCurrencyRows + 1] = row
            end
        end

        for _, entry in ipairs(Addon:GetTrackedCurrencyEntries(false)) do
            local id = tonumber(entry.id)
            if id and id > 0 then
                local key = MakeCurrencySnapshotKey(entry.type, id)
                local row = byKey[key]
                if not row then
                    row = SNAPSHOT_FALLBACK_ROWS[key]
                    if not row then
                        row = {}
                        SNAPSHOT_FALLBACK_ROWS[key] = row
                    end
                    row.type = entry.type
                    row.id = id
                    row.qty = 0
                    row.cap = 0
                    row.held = 0
                end
                local lbl, val = Addon:RenderCurrencySnapshotRow(row)
                if IsNonEmptyText(lbl) or IsNonEmptyText(val) then
                    SetRightRowPair(idx, lbl, val, Addon:GetCurrencyIcon(id), id)
                    idx = idx + 1
                end
            end
        end

        -- Remaining rows (catalyst, sparks, misc currencies, quests).
        for _, row in ipairs(nonCurrencyRows) do
            local lbl, val
            if row.type then
                lbl, val = Addon:RenderCurrencySnapshotRow(row)
            else
                lbl = row.label or ""; val = row.value or ""
            end
            local iconID = nil
            local currencyID = nil
            local itemID = nil
            local questKey = nil
            if row.type == "sparks" or row.type == "cofferkeys" or row.type == "misc" then
                currencyID = row.id
                iconID = Addon:GetCurrencyIcon(currencyID)
            elseif row.type == "catalyst" then
                currencyID = tracking and tracking.catalystCurrencyID
                iconID = Addon:GetCurrencyIcon(currencyID)
            elseif row.type == "quest" then
                questKey = row.key
                itemID = tracking and tracking.questItemIDs and tonumber(tracking.questItemIDs[questKey]) or nil
                if itemID and itemID > 0 then
                    local _, _, _, _, _, _, _, _, _, itemTexture = GetItemInfo(itemID)
                    iconID = itemTexture
                end
            elseif row.type == "weapupg" then
                itemID = Addon.GetWeaponUpgradeCombinedItemID and Addon:GetWeaponUpgradeCombinedItemID() or nil
                if itemID and itemID > 0 then
                    local _, _, _, _, _, _, _, _, _, itemTexture = GetItemInfo(itemID)
                    iconID = itemTexture
                end
            end
            if (not questKey or not Addon:IsQuestHidden(questKey))
                    and (not itemID or not Addon:IsItemHidden(itemID))
                    and (IsNonEmptyText(lbl) or IsNonEmptyText(val)) then
                SetRightRowPair(idx, lbl, val, iconID, currencyID, nil, nil, itemID, questKey)
                idx = idx + 1
            end
        end

        for i = idx, RIGHT_LINE_COUNT do SetRightRowPair(i, "", "") end
    end
end

--  Main entry points 
function Addon:UpdateTracking(dirtyDomains)
    if not IsFrameShown(_G["LariasWeeklyChecklistFrame"]) then
        if self.SuspendTrackingUI then self:SuspendTrackingUI() end
        return
    end

    local db    = self:EnsureDB()
    local prefs = self:EnsurePrefs()

    local wantPanel = ComputeWantTrackingPanel(prefs)
    EnsureTrackingPanelCreatedIfNeeded(wantPanel)

    if self.ApplyTrackingPanelOptions then self:ApplyTrackingPanelOptions() end

    if not (wantPanel and self._trackingFrame and self._trackingFrame:IsShown()) then
        if self.ApplyScrollLayout then self:ApplyScrollLayout() end
        return
    end

    -- When viewing an alt, render their stored snapshot instead of live data.
    local viewKey = self._viewingChar
    if viewKey then
        local altCdb  = self.db and self.db.global and self.db.global.chars and self.db.global.chars[viewKey]
        local altSnap = altCdb and altCdb.trackingSnapshot
        if altSnap then
            RenderSnapshotIntoPanel(altSnap)
        else
            ApplyGreatVaultGrid(nil)
            for i = 1, RIGHT_LINE_COUNT do SetRightRowPair(i, "", "") end
        end
        ResizeTrackingPanelToContent(self)
        return  -- Do not overwrite own snapshot when viewing an alt.
    end

    -- Event-driven updates only touch the domains that can have changed. Calls
    -- without dirty-domain metadata retain the original full-refresh behavior.
    local refreshAll = type(dirtyDomains) ~= "table" or dirtyDomains.full == true
    local snap = self:SaveTrackingSnapshot(db, dirtyDomains)
    if refreshAll or dirtyDomains.vault == true then
        ApplyGreatVaultGrid(snap and snap.leftGrid or nil)
    end
    if refreshAll or dirtyDomains.currency == true or dirtyDomains.gear == true then
        ApplyRightColumnAsPairs()
    end
    ResizeTrackingPanelToContent(self)
end

function Addon:ReleaseTrackingPanelRuntimeCaches()
    if self._trackingFrame then
        ApplyGreatVaultGrid(nil)
        for i = 1, RIGHT_LINE_COUNT do
            SetRightRowPair(i, "", "")
        end
    end
    WipeKeyedTable(SNAPSHOT_ROW_BY_KEY)
    WipeArrayTable(SNAPSHOT_NON_CURRENCY_ROWS)
    WipeKeyedTable(SNAPSHOT_FALLBACK_ROWS)
    if self.ReleaseCurrencyRuntimeCaches then
        self:ReleaseCurrencyRuntimeCaches()
    end
end

function Addon:ResizeTrackingCols()
    local tf = self._trackingFrame
    if not tf then return end

    local frameW  = tonumber(tf:GetWidth()) or UI.frameW
    local padL    = tonumber(tf._lariasPadL)   or 10
    local padR    = tonumber(tf._lariasPadR)   or 10
    local colGap  = tonumber(tf._lariasColGap) or 12
    local leftCol  = tf._lariasLeftCol
    local rightCol = tf._lariasRightCol
    local leftShown  = leftCol  and leftCol.IsShown  and leftCol:IsShown()  or false
    local rightShown = rightCol and rightCol.IsShown and rightCol:IsShown() or false
    local bothShown  = tf._lariasShowBoth and leftShown and rightShown

    local newColW
    if bothShown then
        newColW = max(10, floor((frameW - padL - padR - colGap) / 2))
    else
        newColW = max(10, floor(frameW - padL - padR))
    end

    if leftShown  and leftCol.SetWidth  then leftCol:SetWidth(newColW)  end
    if rightShown and rightCol.SetWidth then rightCol:SetWidth(newColW) end
    if bothShown and leftCol and rightCol then
        rightCol:ClearAllPoints()
        rightCol:SetPoint("TOPLEFT", leftCol, "TOPRIGHT", colGap, 0)
    elseif leftShown and leftCol then
        leftCol:ClearAllPoints()
        leftCol:SetPoint("TOPLEFT", tf, "TOPLEFT", padL, -32)
    elseif rightShown and rightCol then
        rightCol:ClearAllPoints()
        rightCol:SetPoint("TOPLEFT", tf, "TOPLEFT", padL, -32)
    end

    for _, k in ipairs(LEFT_LINE_KEYS) do
        local fs = TrackingUI.left[k]
        if fs and fs.SetWidth then fs:SetWidth(newColW) end
    end

    local leftTitle  = tf._lariasLeftTitle
    local rightTitle = tf._lariasRightTitle
    if leftTitle  and leftTitle.SetWidth  then leftTitle:SetWidth(newColW) end
    if rightTitle and rightTitle.SetWidth then
        rightTitle:SetWidth(newColW)
        if rightCol then
            rightTitle:ClearAllPoints()
            rightTitle:SetPoint("TOP", rightCol, "TOP", 0, 24)
        end
    end

    if leftShown and Addon._reflowGVGrid then Addon._reflowGVGrid(nil) end
    tf._lariasColW = newColW
end
