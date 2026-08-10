-- Shows a reminder when the player can still buy bonus rolls this week.
local addonName = ...
local Addon = _G[addonName]
if not Addon then return end

local L = Addon.L or {}

local function GetBonusRollCurrencyID()
    local tracking = Addon.TRACKING or {}
    return tonumber(tracking.bonusRollCurrencyID) or 0
end

local reminderFrame
local reminderState = {
    lastInstanceKey = nil,
    lastProgressKey = nil,
}
local autoHideToken = 0
local scratchSnapshot

local function DisableReminderForever()
    Addon:EnsurePrefs().raidBonusRollReminderDisabled = true
end

local function ApplyReminderTheme()
    if Addon.RefreshAddonModalTheme then
        Addon:RefreshAddonModalTheme("raid_bonus_roll_reminder")
    end
end

function Addon:RefreshRaidBonusRollReminderTheme()
    ApplyReminderTheme()
end

local function HideReminder()
    autoHideToken = autoHideToken + 1
    if Addon.HideAddonModal then
        Addon:HideAddonModal("raid_bonus_roll_reminder")
    elseif reminderFrame and reminderFrame.holder then
        reminderFrame.holder:Hide()
    end
end

local function GetCurrentReminderKey()
    local inInstance, instanceType = IsInInstance()
    if not inInstance then return nil end

    local name, _, difficultyID, difficultyName, _, _, _, instanceID = GetInstanceInfo()
    difficultyID = tonumber(difficultyID) or 0

    local isSupportedRaid = instanceType == "raid" and (difficultyID == 15 or difficultyID == 16)
    local isSupportedDungeon = instanceType == "party" and (difficultyID == 8 or difficultyID == 23)
    if not (isSupportedRaid or isSupportedDungeon) then
        return nil
    end

    return table.concat({
        tostring(instanceType or ""),
        tostring(instanceID or 0),
        tostring(difficultyID or 0),
        tostring(name or ""),
        tostring(difficultyName or ""),
    }, ":")
end

local function GetBonusRollProgress()
    if not (C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo) then return nil end

    local bonusRollCurrencyID = GetBonusRollCurrencyID()
    if bonusRollCurrencyID <= 0 then return nil end

    local info = C_CurrencyInfo.GetCurrencyInfo(bonusRollCurrencyID)
    if type(info) ~= "table" then return nil end

    local weeklyCap = tonumber(info.maxWeeklyQuantity) or 0
    local walletCap = tonumber(info.maxQuantity) or 0
    -- Weekly-cap currencies must use weekly-earned counters (not wallet-held)
    -- so spending purchased rolls never re-triggers the reminder as "unpurchased".
    local earned = tonumber(info.quantityEarnedThisWeek)
        or tonumber(info.weeklyQuantity)
    local held = tonumber(info.quantity) or 0

    if weeklyCap <= 0 then
        weeklyCap = walletCap
    end
    if weeklyCap <= 0 then return nil end

    -- If the API cannot report weekly-earned for this currency, suppress reminder
    -- rather than showing a false positive for already purchased/spent rolls.
    if earned == nil then
        if held >= weeklyCap then
            earned = weeklyCap
        else
            return nil
        end
    end

    earned = math.max(0, tonumber(earned) or 0)

    return {
        id = bonusRollCurrencyID,
        name = info.name or (L.RAID_BONUS_ROLL_REMINDER_TITLE or "Bonus Rolls"),
        earned = earned,
        cap = weeklyCap,
        remaining = math.max(0, weeklyCap - earned),
        held = held,
    }
end

local function GetCurrentSnapshot()
    if not Addon.BuildTrackingSnapshot then return nil end
    scratchSnapshot = scratchSnapshot or {}
    Addon:BuildTrackingSnapshot(scratchSnapshot)
    return scratchSnapshot
end

local function HasWatermarkedUpgradeNeed()
    local snap = GetCurrentSnapshot()
    if type(snap) ~= "table" then return true end

    local gearSlots = Addon.GetUpgradeGearSlots and Addon:GetUpgradeGearSlots(snap)
                   or (type(snap.bestGearSlots) == "table" and snap.bestGearSlots or snap.gearSlots)
    if type(gearSlots) ~= "table" then return true end

    local slotIDs = Addon.TRACKING and Addon.TRACKING.gearSlotIDs
    if type(slotIDs) ~= "table" then return true end

    local sawGear = false
    for _, slotID in ipairs(slotIDs) do
        local slotData = gearSlots[slotID]
        local effectiveMax = Addon.GetSlotEffectiveMax and Addon:GetSlotEffectiveMax(slotData)
        local rank = type(slotData) == "table" and tonumber(slotData.rank) or nil
        if rank and effectiveMax then
            sawGear = true
            local tierIdx = tonumber(slotData.tierIdx)
            local isLimited = Addon.IsSlotLimitedCrafted and Addon:IsSlotLimitedCrafted(slotData, effectiveMax)
            if tierIdx and rank < effectiveMax and not isLimited then
                local cost = Addon.GetCrestSlotUpgradeCost
                    and Addon:GetCrestSlotUpgradeCost(slotID, slotData, snap, tierIdx, effectiveMax)
                    or 0
                if cost > 0 then return true end
            end
        end
    end

    -- If gear APIs did not give us usable data, keep the old currency-only behavior.
    return not sawGear
end

local function EnsureReminderFrame()
    if reminderFrame then return reminderFrame end
    local modal = Addon:EnsureAddonModal("raid_bonus_roll_reminder", {
        width = 360,
        minHeight = 108,
        topOffset = -220,
        maxButtons = 1,
        buttonWidth = 170,
        buttonHeight = 24,
        justifyH = "LEFT",
    })
    modal.onClose = function()
        DisableReminderForever()
        HideReminder()
        if Addon.RefreshSettingsCheckboxes then Addon:RefreshSettingsCheckboxes() end
        if Addon.SyncGearPopup then Addon:SyncGearPopup() end
    end

    reminderFrame = {
        holder = modal.holder,
        label = modal.label,
        closeBtn = modal.closeBtn,
        disableBtn = modal.buttons and modal.buttons[1] or nil,
    }
    ApplyReminderTheme()
    return reminderFrame
end

function Addon:UpdateRaidBonusRollReminder()
    local prefs = self:EnsurePrefs()
    if prefs.raidBonusRollReminderDisabled then
        HideReminder()
        return
    end

    local instanceKey = GetCurrentReminderKey()
    if not instanceKey then
        prefs.raidBonusRollReminderLastShownInstanceKey = nil
        reminderState.lastInstanceKey = nil
        reminderState.lastProgressKey = nil
        HideReminder()
        return
    end

    -- Persist this gate so /reload inside the same instance does not re-show.
    if prefs.raidBonusRollReminderLastShownInstanceKey == instanceKey then
        return
    end

    local progress = GetBonusRollProgress()
    if not progress or progress.remaining <= 0 then
        reminderState.lastProgressKey = nil
        HideReminder()
        return
    end

    local progressKey = tostring(progress.earned) .. "/" .. tostring(progress.cap)
    if reminderState.lastInstanceKey == instanceKey and reminderState.lastProgressKey == progressKey then
        return
    end

    reminderState.lastInstanceKey = instanceKey
    reminderState.lastProgressKey = progressKey
    prefs.raidBonusRollReminderLastShownInstanceKey = instanceKey

    EnsureReminderFrame()
    Addon:ShowAddonModal("raid_bonus_roll_reminder", {
        width = 360,
        minHeight = 108,
        topOffset = -220,
        text = L.RAID_BONUS_ROLL_REMINDER_MSG or "You have bonus rolls available for purchase.",
        buttons = {
            {
                text = L.RAID_BONUS_ROLL_REMINDER_DISABLE_BTN or "Hide Bonus Rolls Reminder",
                tooltip = L.RAID_BONUS_ROLL_REMINDER_DISABLE_TOOLTIP or "Disable future raid-entry bonus-roll reminders.",
                onClick = function(_, modal)
                    DisableReminderForever()
                    modal.holder:Hide()
                    if Addon.RefreshSettingsCheckboxes then Addon:RefreshSettingsCheckboxes() end
                    if Addon.SyncGearPopup then Addon:SyncGearPopup() end
                end,
            },
        },
        onClose = function()
            DisableReminderForever()
            HideReminder()
            if Addon.RefreshSettingsCheckboxes then Addon:RefreshSettingsCheckboxes() end
            if Addon.SyncGearPopup then Addon:SyncGearPopup() end
        end,
    })

    autoHideToken = autoHideToken + 1
    local myToken = autoHideToken
    if C_Timer and C_Timer.After then
        C_Timer.After(10, function()
            if myToken ~= autoHideToken then return end
            HideReminder()
        end)
    end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
eventFrame:SetScript("OnEvent", function()
    if C_Timer and C_Timer.After then
        C_Timer.After(0.5, function()
            if Addon.UpdateRaidBonusRollReminder then
                Addon:UpdateRaidBonusRollReminder()
            end
        end)
    elseif Addon.UpdateRaidBonusRollReminder then
        Addon:UpdateRaidBonusRollReminder()
    end
end)
