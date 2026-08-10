-- LariasWeeklyChecklist_Tracking.lua
-- Owns tracking events, update coalescing, and snapshot persistence.
local addonName = ...
local Addon = _G[addonName]
if not Addon then return end

local trackingEventFrame
local trackingUIParent
local backgroundTrackingEnabled
local scheduledUpdates = {}
local pendingPanelDirty = {}
local pendingBackgroundDirty = {}
local Core = Addon.CoreLogic

local function TakeDirtyDomains(current)
    local result = current
    if result == pendingPanelDirty then
        pendingPanelDirty = {}
    elseif result == pendingBackgroundDirty then
        pendingBackgroundDirty = {}
    end
    return result
end

local function SafeRegisterEvent(frame, eventName)
    if not (frame and eventName) then return false end
    return pcall(frame.RegisterEvent, frame, eventName)
end

local function IsShown(frame)
    return frame and frame.IsShown and frame:IsShown()
end

local function OnTrackingEvent(_, eventName, unit)
    if eventName == "UNIT_INVENTORY_CHANGED" and unit ~= "player" then return end
    if IsShown(trackingUIParent) and IsShown(Addon._trackingFrame) then
        Addon:RequestTrackingUpdate(eventName)
    else
        Addon:RequestBackgroundSnapshotUpdate(eventName)
    end
end

function Addon:HasTrackingSnapshot()
    if not (self.db and self.db.global) then return false end
    local ownKey = self:GetCurrentProfileKey()
    local charDB = self.db.global.chars and self.db.global.chars[ownKey]
    local snap = charDB and charDB.trackingSnapshot
    return type(snap) == "table" and (snap.leftLines ~= nil or snap.rightRows ~= nil)
end

function Addon:ConfigureTrackingEvents(parentFrame, showGreatVault, showCurrency)
    trackingEventFrame = trackingEventFrame or CreateFrame("Frame")
    trackingEventFrame:UnregisterAllEvents()
    if parentFrame then
        trackingUIParent = parentFrame
    else
        backgroundTrackingEnabled = (showGreatVault or showCurrency) and true or false
    end

    local trackGreatVault = backgroundTrackingEnabled or showGreatVault
    local trackCurrency = backgroundTrackingEnabled or showCurrency
    if not (trackGreatVault or trackCurrency) then return end

    trackingEventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    if trackGreatVault then
        trackingEventFrame:RegisterEvent("WEEKLY_REWARDS_UPDATE")
    end
    if trackCurrency then
        trackingEventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
        SafeRegisterEvent(trackingEventFrame, "UNIT_INVENTORY_CHANGED")
        trackingEventFrame:RegisterEvent("CURRENCY_DISPLAY_UPDATE")
        trackingEventFrame:RegisterEvent("BAG_UPDATE_DELAYED")
        trackingEventFrame:RegisterEvent("QUEST_TURNED_IN")
        SafeRegisterEvent(trackingEventFrame, "CATALYST_CHARGES_UPDATED")
        SafeRegisterEvent(trackingEventFrame, "CATALYST_UPDATE")
        SafeRegisterEvent(trackingEventFrame, "ITEM_INTERACTION_ITEM_SELECTION_UPDATED")
    end

    trackingEventFrame:SetScript("OnEvent", OnTrackingEvent)
end

function Addon:SuspendTrackingUI()
    trackingUIParent = nil
    backgroundTrackingEnabled = false
    if trackingEventFrame then
        trackingEventFrame:UnregisterAllEvents()
        trackingEventFrame:SetScript("OnEvent", nil)
    end
end

local function ScheduleOnce(updateKey, callback)
    local state = scheduledUpdates[updateKey]
    if not state then
        state = {}
        scheduledUpdates[updateKey] = state
    end
    if state.pending then return end
    state.pending = true
    if not state.runner then
        state.runner = function()
            state.pending = false
            callback(Addon)
        end
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(0.2, state.runner)
    else
        state.runner()
    end
end

function Addon:RequestBackgroundSnapshotUpdate(eventName)
    if not backgroundTrackingEnabled then return end
    Core.MergeDirtyDomains(pendingBackgroundDirty, eventName)
    ScheduleOnce("background", function(addon)
        addon:UpdateSnapshotBackground(TakeDirtyDomains(pendingBackgroundDirty))
    end)
end

function Addon:StartBackgroundTracking()
    -- Keep closed-window background usage as low as possible.
    -- Live tracking events are enabled only while the main checklist UI is open;
    -- callers that need a snapshot while closed should request one on demand.
    backgroundTrackingEnabled = false
    if trackingEventFrame then
        trackingEventFrame:UnregisterAllEvents()
        trackingEventFrame:SetScript("OnEvent", nil)
    end
end

function Addon:SaveTrackingSnapshot(db, dirtyDomains)
    if not db then return nil end
    local snap = db.trackingSnapshot
    if type(snap) ~= "table" then
        snap = {}
        db.trackingSnapshot = snap
    end
    self:BuildTrackingSnapshot(snap, dirtyDomains)
    snap.updatedAt = time()
    if self.MarkAltsSummaryDirty then self:MarkAltsSummaryDirty(false) end
    return snap
end

function Addon:UpdateSnapshotBackground(dirtyDomains)
    -- EnsureDB normally follows the selected alt; background capture always
    -- belongs to the character currently logged in.
    local viewedCharacter = self._viewingChar
    self._viewingChar = nil
    local db = self:EnsureDB()
    self._viewingChar = viewedCharacter
    self:SaveTrackingSnapshot(db, dirtyDomains)
end

function Addon:RequestTrackingUpdate(eventName)
    Core.MergeDirtyDomains(pendingPanelDirty, eventName)
    ScheduleOnce("panel", function(addon)
        local dirtyDomains = TakeDirtyDomains(pendingPanelDirty)
        if not (IsShown(trackingUIParent) and IsShown(addon._trackingFrame)) then return end
        if addon.UpdateTracking then addon:UpdateTracking(dirtyDomains) end
    end)
end
