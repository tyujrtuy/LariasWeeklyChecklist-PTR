-- Addon communications + update notice logic.
--
-- Message format:
-- - "Q" query
-- - "V\taddonVersion\tsheetVersion" version reply
--
-- Performance:
-- - Broadcast/query/reply are throttled (timers) to avoid chat spam.
local addonName = ...
local Addon = _G[addonName]
if not Addon then return end

Addon.COMM_PREFIX = Addon.COMM_PREFIX or "LWMC"

local BROADCAST_THROTTLE_SECONDS = 30
local REPLY_THROTTLE_SECONDS = 5
local SENDER_THROTTLE_SECONDS = 2
local OBSERVATION_TTL_SECONDS = 14 * 24 * 60 * 60
local MAX_MESSAGE_LENGTH = 128
local MAX_VERSION_LENGTH = 32
local MAX_SHEET_VERSION_LENGTH = 64

Addon.COMM_OBSERVATION_TTL_SECONDS = OBSERVATION_TTL_SECONDS

local broadcastTimerActive = false
local replyTimerActive = false
local queryTimerActive = false
local commFrame
local senderLastMessageAt = {}
local senderThrottleCount = 0
local Core = Addon.CoreLogic

local function RunLater(delay, callback)
    if C_Timer and C_Timer.After then
        C_Timer.After(delay, callback)
    else
        callback()
    end
end

-- Version handling notes:
-- - We only care about prompting updates for "live" releases.
-- - Remote prerelease versions (e.g. "1.0.18-alpha") are ignored for prompting.
-- - Numeric comparison is required (string compare breaks: "1.0.10" vs "1.0.2").
local IsLiveVersion = Core.IsLiveVersion
local CompareVersions = Core.CompareVersions

local function GetNow()
    return tonumber(time and time()) or 0
end

local function IsSafeSheetVersion(value)
    return type(value) == "string"
        and #value <= MAX_SHEET_VERSION_LENGTH
        and not value:find("[%c]")
end

local function SerializeCommMessage(tbl)
    if type(tbl) ~= "table" then return nil end
    if tbl.t == "Q" then
        return "Q"
    elseif tbl.t == "V" then
        local version = Core.ParseLiveVersion(tbl.v, MAX_VERSION_LENGTH)
        if not version then return nil end
        local sheetVersion = tostring(tbl.sv or "")
        if not IsSafeSheetVersion(sheetVersion) then sheetVersion = "" end
        return table.concat({ "V", version, sheetVersion }, "\t")
    end
    return nil
end

local function DeserializeCommMessage(message)
    if type(message) ~= "string" or #message > MAX_MESSAGE_LENGTH then return nil end
    if message == "Q" then return { t = "Q" } end

    local version, sheetVersion = message:match("^V\t([^\t]+)\t([^\t]*)$")
    version = Core.ParseLiveVersion(version, MAX_VERSION_LENGTH)
    if not version or not IsSafeSheetVersion(sheetVersion) then return nil end
    return { t = "V", v = version, sv = sheetVersion }
end

local function SafeSendCommMessage(msg, channel)
    -- Guarded send: comms should never hard-error.
    if not channel or channel == "" then return end
    if C_ChatInfo and C_ChatInfo.SendAddonMessage then
        pcall(C_ChatInfo.SendAddonMessage, Addon.COMM_PREFIX, msg, channel)
    elseif SendAddonMessage then
        pcall(SendAddonMessage, Addon.COMM_PREFIX, msg, channel)
    end
end

local function GetGroupChannel()
    -- Prefer instance chat when applicable; otherwise raid/party.
    local instCat = (LE_PARTY_CATEGORY_INSTANCE ~= nil) and LE_PARTY_CATEGORY_INSTANCE or 2
    if IsInGroup and IsInGroup(instCat) then return "INSTANCE_CHAT" end
    if IsInRaid and IsInRaid() then return "RAID" end
    if IsInGroup and IsInGroup() then return "PARTY" end
    return nil
end

local function GetAddonVersion(name)
    -- Read version from addon metadata.
    if C_AddOns and C_AddOns.GetAddOnMetadata then
        return tostring(C_AddOns.GetAddOnMetadata(name, "Version") or "")
    end
    if GetAddOnMetadata then
        return tostring(GetAddOnMetadata(name, "Version") or "")
    end
    return ""
end

local LOCALE_REGISTRY_KEY_COMMS = Addon.LOCALE_REGISTRY_KEY

local function GetMySheetVersion()
    local reg = _G[LOCALE_REGISTRY_KEY_COMMS]
    return (reg and type(reg.sheet_version) == "string" and reg.sheet_version) or ""
end

-- Prefer an explicit "Week N" marker, then fall back to the first integer.
-- e.g. "Week 5 - Apr 14" → 5,  "Pre-Season Week 2" → 2
local function SheetVersionToNum(s)
    local value = tostring(s or "")
    local week = value:lower():match("week%s*(%d+)")
    if week then return tonumber(week) or 0 end
    return tonumber(value:match("%d+")) or 0
end

local function IsObservationExpired(observedAt)
    local timestamp = tonumber(observedAt) or 0
    local now = GetNow()
    return timestamp <= 0 or (now >= timestamp and now - timestamp > OBSERVATION_TTL_SECONDS)
end

local function ClearVersionObservation(database)
    database._newestSeenRemoteVersion = ""
    database._newestSeenRemoteSender = ""
    database._newestSeenRemoteVersionAt = nil
end

local function ClearSheetObservation(database)
    database._newestSeenRemoteSheetVersion = ""
    database._newestSeenRemoteSheetVersionAt = nil
end

local function IsSenderThrottled(sender)
    if type(sender) ~= "string" or sender == "" then return false end
    local key = sender:lower()
    local now = GetNow()
    local previous = tonumber(senderLastMessageAt[key])
    if previous and now >= previous and now - previous < SENDER_THROTTLE_SECONDS then
        return true
    end
    if not previous then
        senderThrottleCount = senderThrottleCount + 1
        if senderThrottleCount > 200 then
            senderLastMessageAt = {}
            senderThrottleCount = 1
        end
    end
    senderLastMessageAt[key] = now
    return false
end

local function IsSelfSender(sender)
    if type(sender) ~= "string" or sender == "" or not UnitName then return false end
    local me = UnitName("player")
    if not me or me == "" then return false end
    local senderName = Ambiguate and Ambiguate(sender, "none") or sender
    return senderName == me
end

local function IsStaleSheetVersionAfterReset(mySheetVersion, remoteSheetVersion)
    local myNum = SheetVersionToNum(mySheetVersion)
    local remoteNum = SheetVersionToNum(remoteSheetVersion)
    return myNum > 0 and myNum <= 5 and (remoteNum - myNum) >= 10
end

function Addon:GetMyVersion()
    -- Cached in CommsOnEnable.
    return self._myVersion or ""
end

function Addon:ShouldShowSheetUpdateNotice()
    -- Returns true when a group/guild member has broadcast a newer sheet version.
    local database = self:EnsureDB()
    local myVer = self:GetMyVersion()
    if myVer == "" or not IsLiveVersion(myVer) then return false end
    local newestSV = tostring(database._newestSeenRemoteSheetVersion or "")
    if newestSV == "" then return false end
    if IsObservationExpired(database._newestSeenRemoteSheetVersionAt) then
        ClearSheetObservation(database)
        return false
    end
    if IsStaleSheetVersionAfterReset(GetMySheetVersion(), newestSV) then
        ClearSheetObservation(database)
        return false
    end
    return SheetVersionToNum(newestSV) > SheetVersionToNum(GetMySheetVersion())
end

function Addon:ShouldShowUpdateNotice()
    -- Update notice is driven by the newest *live* version seen on comms.
    local database = self:EnsureDB()
    local myVersion = self:GetMyVersion()
    -- If the user is on a prerelease build, don't nag about updates.
    if myVersion == "" or not IsLiveVersion(myVersion) then return false end
    local newestSeenVersion = tostring(database._newestSeenRemoteVersion or "")
    if newestSeenVersion == "" or myVersion == "" then return false end
    if IsObservationExpired(database._newestSeenRemoteVersionAt) then
        ClearVersionObservation(database)
        return false
    end
    if CompareVersions(newestSeenVersion, myVersion) <= 0 then return false end
    return true
end

function Addon:BroadcastVersion(force)
    -- Broadcast our version to group/guild.
    -- force=true bypasses the broadcast throttle.
    if not force then
        if broadcastTimerActive then
            return
        end
    end

    local myVersion = self:GetMyVersion()
    if myVersion == "" then return end
    local payloadStructured = SerializeCommMessage({ t = "V", v = myVersion, sv = GetMySheetVersion() })
    if not payloadStructured then return end

    local channel = GetGroupChannel()
    if channel then
        SafeSendCommMessage(payloadStructured, channel)
    end
    if IsInGuild and IsInGuild() then
        SafeSendCommMessage(payloadStructured, "GUILD")
    end

    if not force then
        broadcastTimerActive = true
        RunLater(BROADCAST_THROTTLE_SECONDS, function() broadcastTimerActive = false end)
    end
end

function Addon:RequestVersions(force)
    -- Ask others to reply with their version (they reply after a small random delay).
    if not force then
        if queryTimerActive then
            return
        end
    end

    local payloadStructured = SerializeCommMessage({ t = "Q" })
    if not payloadStructured then return end

    local channel = GetGroupChannel()
    if channel then
        SafeSendCommMessage(payloadStructured, channel)
    end
    if IsInGuild and IsInGuild() then
        SafeSendCommMessage(payloadStructured, "GUILD")
    end

    if not force then
        queryTimerActive = true
        RunLater(BROADCAST_THROTTLE_SECONDS, function() queryTimerActive = false end)
    end
end

function Addon:OnAddonMessage(prefix, message, sender)
    -- Native addon-message entry point.
    -- We ignore unknown messages to avoid legacy/backcompat complexity.
    if prefix ~= self.COMM_PREFIX then return end
    if type(message) ~= "string" then return end

    local decoded = DeserializeCommMessage(message)
    if not decoded then
        return
    end

    if IsSelfSender(sender) or IsSenderThrottled(sender) then return end

    if decoded.t == "Q" then
        -- Query received: reply with version (throttled; delay jitter to avoid bursts).
        if replyTimerActive then
            return
        end

        replyTimerActive = true
        RunLater(REPLY_THROTTLE_SECONDS, function() replyTimerActive = false end)

        local delay = (math.random() * 2.0)
        RunLater(delay, function()
            self:BroadcastVersion(true)
        end)
        return
    end

    if decoded.t ~= "V" then
        return
    end

    local remoteVersion = decoded.v

    local myVersion = self:GetMyVersion()
    if myVersion == "" then return end

    if CompareVersions(remoteVersion, myVersion) > 0 then
        local database = self:EnsureDB()
        local newestSeenVersion = tostring(database._newestSeenRemoteVersion or "")
        if newestSeenVersion == "" or CompareVersions(remoteVersion, newestSeenVersion) > 0 then
            database._newestSeenRemoteVersion = remoteVersion
            database._newestSeenRemoteSender = tostring(sender or "")
            database._newestSeenRemoteVersionAt = GetNow()
            -- Immediately refresh the status banner so the update notice appears.
            if Addon.UpdateStatusBanner then Addon:UpdateStatusBanner() end
        elseif remoteVersion == newestSeenVersion then
            database._newestSeenRemoteVersionAt = GetNow()
        end
    end

    -- Track remote sheet version for spreadsheet-update notices.
    local remoteSV = (type(decoded.sv) == "string" and decoded.sv ~= "") and decoded.sv or nil
    if remoteSV then
        local database = self:EnsureDB()
        local mySV = GetMySheetVersion()
        if not IsStaleSheetVersionAfterReset(mySV, remoteSV)
        and SheetVersionToNum(remoteSV) > SheetVersionToNum(mySV) then
            local storedSV = tostring(database._newestSeenRemoteSheetVersion or "")
            if storedSV == "" or SheetVersionToNum(remoteSV) > SheetVersionToNum(storedSV) then
                database._newestSeenRemoteSheetVersion = remoteSV
                database._newestSeenRemoteSheetVersionAt = GetNow()
                if Addon.UpdateStatusBanner then Addon:UpdateStatusBanner() end
            elseif SheetVersionToNum(remoteSV) == SheetVersionToNum(storedSV) then
                database._newestSeenRemoteSheetVersionAt = GetNow()
            end
        end
    end
end

function Addon:OnCommReceived(prefix, messageText, _, sender)
    -- Backward-compatible wrapper for callers that still use the old shape.
    self:OnAddonMessage(prefix, messageText, sender)
end

function Addon:CommsOnEnable()
    -- Called from Addon:OnEnable.
    self._myVersion = GetAddonVersion(addonName)

    -- Auto-clear a stale _newestSeenRemoteVersion if our version has caught up
    -- (e.g. the user installed an update since the last session, or a dev build
    -- wrote a higher version string that is now obsolete).  This prevents the
    -- update notice from firing forever on a version that is already installed.
    local database = self:EnsureDB()
    local myVer    = self._myVersion
    if myVer ~= "" and IsLiveVersion(myVer) then
        local stored = tostring(database._newestSeenRemoteVersion or "")
        if stored ~= "" and (CompareVersions(stored, myVer) <= 0
                or IsObservationExpired(database._newestSeenRemoteVersionAt)) then
            ClearVersionObservation(database)
        end
    end

    local mySheetVersion = GetMySheetVersion()
    local storedSheetVersion = tostring(database._newestSeenRemoteSheetVersion or "")
    if storedSheetVersion ~= "" and (IsStaleSheetVersionAfterReset(mySheetVersion, storedSheetVersion)
            or IsObservationExpired(database._newestSeenRemoteSheetVersionAt)) then
        ClearSheetObservation(database)
    end

    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        pcall(C_ChatInfo.RegisterAddonMessagePrefix, self.COMM_PREFIX)
    elseif RegisterAddonMessagePrefix then
        pcall(RegisterAddonMessagePrefix, self.COMM_PREFIX)
    end

    if not commFrame then
        commFrame = CreateFrame("Frame")
        commFrame:RegisterEvent("CHAT_MSG_ADDON")
        commFrame:SetScript("OnEvent", function(_, _, prefix, message, _, sender)
            Addon:OnAddonMessage(prefix, message, sender)
        end)
    end

    self:BroadcastVersion(true)
end
