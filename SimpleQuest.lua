-- SimpleQuest: Core module
-- Handles settings, events, and utility functions

local addonName, SS = ...
local version = "v0.6"
local addonloaded = false

-- ============================================================================
-- Default Settings
-- ============================================================================
SS.Settings = SS_Settings or {
    hideAllTracked = false,          -- Hide all tracked quests from quest log view
    autoTrackZone = true,            -- Auto-track quests relevant to current zone
    sortMode = "recent",             -- "recent" or "distance"
    sortOrder = "desc",              -- "desc" = newest/closest first
    autoAccept = true,              -- Auto-accept quests from NPCs
    autoTurnIn = true,               -- Auto turn-in completed quests at NPCs
    hasWelcomed = false,             -- Whether welcome message has been shown
}

-- ============================================================================
-- Internal State
-- ============================================================================
SS.QuestCache = {}                -- Cached quest data for sorting
SS.ActiveQuestIDs = {}            -- Table of known quest IDs (from events)
SS.LastZone = ""                  -- Previous zone for zone-change detection
SS.AutoTrackCooldown = false      -- Prevent spam on zone change
SS.PlayerLoaded = false           -- Tracks whether player has entered the world

-- ============================================================================
-- Frame & Events
-- ============================================================================
SS.Frame = CreateFrame("Frame")
SS.Frame:RegisterEvent("ADDON_LOADED")
SS.Frame:RegisterEvent("QUEST_ACCEPTED")
-- SS.Frame:RegisterEvent("QUEST_COMPLETE") -- QUEST_COMPLETE is not always reliable; use QUEST_TURNED_IN
SS.Frame:RegisterEvent("QUEST_TURNED_IN")
SS.Frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
SS.Frame:RegisterEvent("QUEST_LOG_UPDATE")
SS.Frame:RegisterEvent("PLAYER_REGEN_ENABLED")
SS.Frame:RegisterEvent("PLAYER_ENTERING_WORLD")

SS.Frame:SetScript("OnEvent", function(self, event, arg1)
    SS_OnEvent(event, arg1)
end)

-- ============================================================================
-- Slash Command Registration (must be at top-level, before file finishes loading)
-- ============================================================================
SLASH_SIMPLEQUEST1 = "/sq"
SLASH_SIMPLEQUEST2 = "/simplequest"

SlashCmdList["SIMPLEQUEST"] = function(argString)
    SS_HandleChatCommand(argString)
end

-- ============================================================================
-- Event Handler
-- ============================================================================
function SS_OnEvent(event, arg1)
    -- Load saved variables when addon loads
    if event == "ADDON_LOADED" and arg1 == addonName then
        SS_SettingsLoaded()
        addonloaded = true
        return
    end

    -- Quest gained / completed
    if event == "QUEST_ACCEPTED" then
        SS_OnQuestAccepted(arg1)
    elseif event == "QUEST_TURNED_IN" then
        SS_OnQuestComplete(arg1)
    end

    -- Zone changed
    if event == "ZONE_CHANGED_NEW_AREA" then
        SS_OnZoneChanged()
    end

    -- Quest log updated (progress changes, etc.)
    if event == "QUEST_LOG_UPDATE" then
        SS_OnQuestLogUpdate()
    end

    -- Re-entering world (loading screens, reloading UI)
    if event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_ENTERING_WORLD" then
        SS_OnZoneChanged()
    end
    
    -- First time entering the world (apply settings, show welcome)
    if event == "PLAYER_ENTERING_WORLD" and not SS.PlayerLoaded then
        SS.PlayerLoaded = true
        SS_OnPlayerEnteredWorld()
    end
end

-- ============================================================================
-- Settings Persistence
-- ============================================================================
function SS_SettingsLoaded()
    if not SS.Settings then
        SS.Settings = {
            hideAllTracked = false,
            autoTrackZone = true,
            sortMode = "recent",
            sortOrder = "desc",
        }
    end

    -- Apply saved settings (deferred until player is in world)
    -- SS_ApplySettings() is called from SS_OnPlayerEnteredWorld()

    -- Note: UI initialization and zone scan happen in SimpleQuest_UI.lua
    -- after all modules have loaded (deferred initialization)
end

-- Called when the player actually enters the world (APIs are safe to use)
function SS_OnPlayerEnteredWorld()
    -- Apply saved settings now that player is loaded
    SS_ApplySettings()

    -- Welcome message (first load only, or after reload)
    if not SS.Settings.hasWelcomed then
        SS_PrintChat("|cff3fcf7fSimpleQuest|r: Addon loaded successfully! "..version.."|cff3fcf7f|r Type /sq for help.")
        SS.Settings.hasWelcomed = true
    end

    -- Scan for existing quests in the log (quests accepted before addon load)
    SS_ScanExistingQuests()

    -- Untrack all quests before applying auto-track logic, to avoid duplicates or stale tracking
    SS_UntrackOutofZoneQuests()

    -- Do initial zone scan
    SS_OnZoneChanged()

    -- Auto-accept is driven by QUEST_DETAIL in SimpleQuest_TurnIn.lua (deferred
    -- action queue). The old QuestFrame OnShow hook fired AcceptQuest() on any
    -- quest panel (greeting/progress/reward), which could break NPC dialogue.
end

-- ============================================================================
-- Scan Existing Quests on First Load
-- ============================================================================
function SS_ScanExistingQuests()
    local foundCount = 0

    -- Iterate the quest log using the supported C_QuestLog API.
    -- C_QuestLog.GetInfo returns a QuestInfo table per log entry; grouping/zone
    -- header entries have isHeader set and no questID, so they yield no entry.
    local numEntries = SS_GetNumQuestLogEntries()
    for i = 1, numEntries do
        local entry = SS_GetQuestLogEntryByIndex(i)
        if entry then
            SS.ActiveQuestIDs[entry.questId] = true
            foundCount = foundCount + 1
        end
    end

    -- Fall back to scanning Quest Tracker frames if no quests were found
    if foundCount == 0 then
        foundCount = SS_ScanQuestTrackerFrames()
    end
--[[ 
    if foundCount > 0 then
        SS_PrintChat(string.format("|cff3fcf7fSimpleQuest|r: Found %d existing quests in log.", foundCount))
    end
 ]]
    return foundCount
end

-- ============================================================================
-- Fallback: Scan Quest Tracker Frames for Tracked Quests
-- ============================================================================
function SS_ScanQuestTrackerFrames()
    local foundCount = 0

    -- Scan the QuestFrame (tracker that shows tracked quests)
    if QuestFrame and QuestFrame.Questes then
        local numChildren = QuestFrame.Questes:GetNumChildren()
        for i = 1, numChildren do
            local questButton = QuestFrame.Questes:GetChild(i)
            if questButton and questButton.questID then
                SS.ActiveQuestIDs[questButton.questID] = true
                foundCount = foundCount + 1
            end
        end
    end

    -- Also try QuestLogFrame (quest log list)
    if QuestLogFrame and QuestLogFrame.Quests then
        local numChildren = QuestLogFrame.Quests:GetNumChildren()
        for i = 1, numChildren do
            local questButton = QuestLogFrame.Quests:GetChild(i)
            if questButton and questButton.questID then
                SS.ActiveQuestIDs[questButton.questID] = true
                foundCount = foundCount + 1
            end
        end
    end

    return foundCount
end

function SS_SaveSettings()
    -- In Retail, we can use C_AddOns.SetAddonMetadata or a SavedVariables
    -- For simplicity, we store in a global table that persists across reloads
    -- The TOC should declare: ## SavedVariables: SS_SavedSettings
end

-- ============================================================================
-- Apply Settings to Game State
-- ============================================================================
function SS_ApplySettings()
    local s = SS.Settings

    if s.hideAllTracked then
        SS_HideAllTracked()
    else
        SS_ShowAllTracked()
    end

    -- Apply sort mode
    SS_UpdateQuestLogSort()
end

-- ============================================================================
-- Quest Event Handlers
-- Helper: Track Quest by Quest ID
-- ============================================================================
function SS_TrackQuestByID(questId)
    if not questId then return false end

    -- Check the current watch state; nil means the quest is not being watched
    local okWatch, watchType = pcall(C_QuestLog.GetQuestWatchType, questId)
    if okWatch and watchType ~= nil then
        -- Already tracked
        return true
    end

    -- Add the quest to the quest watch list (same API the in-game tracker uses)
    local okAdd = pcall(C_QuestLog.AddQuestWatch, questId)
    return okAdd and true or false
end

-- ============================================================================
-- Helper: Untrack Quest by Quest ID
-- ============================================================================
function SS_UntrackQuestByID(questId)
    if not questId then return false end
    local okRemove = pcall(C_QuestLog.RemoveQuestWatch, questId)
    return okRemove and true or false
end

function SS_OnQuestAccepted(questId)
    -- Track this quest ID in our internal state
    SS.ActiveQuestIDs[questId] = true
    
    -- Invalidate cache so sorting picks up the new quest
    SS_QuestCache = {}

    -- Auto-track if enabled
    if SS.Settings.autoTrackZone then
        -- Use a timer to defer tracking until the quest is fully registered in the log
        C_Timer.After(0.15, function()
            local tracked = SS_TrackQuestByID(questId)
            if tracked then
                -- Get quest name via the supported title API (wrapped in pcall)
                local nameSuccess, questTitle = pcall(C_QuestLog.GetTitleForQuestID, questId)
                local questName = nameSuccess and questTitle or tostring(questId)
                --SS_PrintChat(string.format("|cff3fcf7fSimpleQuest|r: Auto-tracked quest %s.", questName))
            end
        end)
    end

    -- Update zone tracking
    SS_OnZoneChanged()
end

function SS_OnQuestComplete(questId)
    -- If triggered by QUEST_COMPLETE, questId is nil, so GetQuestID() fetches the open dialog's quest ID
    questId = questId or GetQuestID()
    
    if not questId or questId == 0 then return end

    if SS.ActiveQuestIDs then
        SS.ActiveQuestIDs[questId] = nil
    end
    SS_QuestCache = {}

    if SS.Settings and SS.Settings.autoTrackZone then
        SS_AutoTrackNextInZone()
    end
end

--[[ function SS_OnQuestComplete(questId)
    -- Remove completed quest from tracked list
    SS.ActiveQuestIDs[questId] = nil
    SS_QuestCache = {}

    -- Auto-track next quest in zone if available
    if SS.Settings.autoTrackZone then
        SS_AutoTrackNextInZone()
    end
end
 ]]

-- ============================================================================
-- Zone Change Handler
-- ============================================================================
function SS_OnZoneChanged()
    if not addonloaded then return end
    local zoneName = SS_GetCurrentZone()
    
    -- Only re-process if zone actually changed
    if zoneName == SS.LastZone then
        return
    end

    SS.LastZone = zoneName
    SS_QuestCache = {}

    -- Auto-track quests in this zone
    if SS.Settings.autoTrackZone then
        SS_AutoTrackZoneQuests(zoneName)
        -- Untrack any tracked quests that are not in the current zone
        SS_UntrackOutofZoneQuests()
    end
end

-- ============================================================================
-- Quest Log Update Handler (progress changes)
-- ============================================================================
function SS_OnQuestLogUpdate()
    -- Refresh cache for sorting
    if SS.Settings.sortMode == "recent" then
        SS_BuildRecentCache()
    elseif SS.Settings.sortMode == "distance" then
        SS_BuildDistanceCache()
    end

    -- Refresh UI if visible
    if SS_UIFrame and SS_UIFrame:IsVisible() then
        SS_UpdateQuestList()
    end
end

-- ============================================================================
-- Zone Name Helper
-- ============================================================================
function SS_GetCurrentZone()
    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID then return "" end
    
    local zoneInfo = C_Map.GetMapInfo(mapID)
    return zoneInfo and zoneInfo.name or ""
end

-- ============================================================================
-- Quest Log Entry Helper
-- Safe Quest Log Entry Count (wrapper for unavailable API)
-- ============================================================================
function SS_GetNumQuestLogEntries()
    local ok, numEntries, numQuests = pcall(C_QuestLog.GetNumQuestLogEntries)
    if ok and numEntries then
        -- Returns (numShownEntries, numQuests); we iterate over the shown entries
        return numEntries
    end
    -- Fallback: return count of tracked quest IDs
    local count = 0
    for _ in pairs(SS.ActiveQuestIDs) do
        count = count + 1
    end
    return count
end

-- Returns a normalized quest entry for the quest log entry at the given index.
-- Grouping/zone header entries have isHeader set and no questID, so they return nil.
function SS_GetQuestLogEntryByIndex(index)
    if not index or index < 1 then return nil end

    local ok, info = pcall(C_QuestLog.GetInfo, index)
    if not ok or not info then return nil end
    if info.isHeader then return nil end

    local questId = info.questID
    if not questId then return nil end

    local title = info.title
    if not title then
        local okTitle, questTitle = pcall(C_QuestLog.GetTitleForQuestID, questId)
        title = okTitle and questTitle or tostring(questId)
    end

    local isWatched = false
    local okWatch, watchType = pcall(C_QuestLog.GetQuestWatchType, questId)
    if okWatch then isWatched = (watchType ~= nil) end

    local completed = false
    local okComplete, complete = pcall(C_QuestLog.IsComplete, questId)
    if okComplete then completed = complete end

    -- Build a normalized entry from the supported QuestInfo fields returned by
    -- C_QuestLog.GetInfo. Raw QuestInfo does not carry watch/completion state, so
    -- isTracked / isComplete are recomputed via the quest watch and quest state APIs.
    return {
        questId = questId,
        title = title,
        questLogIndex = index,
        level = info.level or 0,
        isHeader = info.isHeader or false,
        isCollapsed = info.isCollapsed or false,
        isOnMap = info.isOnMap or false,
        isTask = info.isTask or false,
        isBounty = info.isBounty or false,
        isStory = info.isStory or false,
        isScaling = info.isScaling or false,
        isAutoComplete = info.isAutoComplete or false,
        isInternalOnly = info.isInternalOnly or false,
        isAbandonOnDisable = info.isAbandonOnDisable or false,
        isTracked = isWatched or false,
        isComplete = completed or false,
        quality = info.quality or 0,
        timeCompleted = info.timeCompleted or 0,
        timeCompletedForLog = info.timeCompletedForLog or 0,
    }
end

function SS_GetZoneContinent()
    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID then return "" end
    
    local info = C_Map.GetMapInfo(mapID)
    if not info then return "" end
    
    -- Walk up the map hierarchy to get the continent/zone name
    local parentID = info.parentMapID
    while parentID do
        local parentInfo = C_Map.GetMapInfo(parentID)
        if parentInfo and parentInfo.parentMapID == nil then
            return parentInfo.name
        end
        local parentMapInfo = C_Map.GetMapInfo(parentID)
        if not parentMapInfo then break end
        parentID = parentMapInfo.parentMapID
    end
    
    local zoneInfo = C_Map.GetMapInfo(mapID)
    return zoneInfo and zoneInfo.name or ""
end

-- ============================================================================
-- Hiding / Showing Tracked Quests
-- ============================================================================
function SS_HideAllTracked()
    local numQuests = SS_GetNumQuestLogEntries()

    for i = 1, numQuests do
        local entry = SS_GetQuestLogEntryByIndex(i)
        if entry and entry.questId and entry.isTracked then
            SS_UntrackQuestByID(entry.questId)
        end
    end
end

function SS_ShowAllTracked()
    -- Restore tracking to all untracked active quests
    local numQuests = SS_GetNumQuestLogEntries()

    for i = 1, numQuests do
        local entry = SS_GetQuestLogEntryByIndex(i)
        if entry and entry.questId and not entry.isTracked then
            SS_TrackQuestByID(entry.questId)
        end
    end
end

-- ============================================================================
-- Auto-Track Quests in Current Zone
-- ============================================================================
function SS_AutoTrackZoneQuests(zoneName)
    if not zoneName or zoneName == "" then return end
    
    local numQuests = SS_GetNumQuestLogEntries()
    local trackedCount = 0
    
    for i = 1, numQuests do
        local entry = SS_GetQuestLogEntryByIndex(i)
        if entry and entry.questId then
            -- Skip already tracked quests
            if entry.isTracked then
                trackedCount = trackedCount + 1
            else
                -- Check if quest objectives are in the current zone
                local zoneMatch = SS_QuestIsInZone(entry.questId, zoneName, i)
                
                if zoneMatch then
                    SS_TrackQuestByID(entry.questId)
                    trackedCount = trackedCount + 1
                end
            end
        end
    end
    
    --[[if trackedCount > 0 then
        SS_PrintChat(string.format("|cff3fcf7fSimpleQuest|r: Tracked %d quest(s) in %s.", trackedCount, zoneName))
    end]]
end

function SS_AutoTrackNextInZone()
    local zoneName = SS_GetCurrentZone()
    if not zoneName then return end
    
    local numQuests = SS_GetNumQuestLogEntries()
    
    for i = 1, numQuests do
        local entry = SS_GetQuestLogEntryByIndex(i)
        if entry and entry.questId and not entry.isTracked then
            if SS_QuestIsInZone(entry.questId, zoneName, i) then
                SS_TrackQuestByID(entry.questId)
                --SS_PrintChat(string.format("|cff3fcf7fSimpleQuest|r: Auto-tracked next quest: %s.", entry.title))
                return
            end
        end
    end
end

-- ============================================================================
-- Check if a Quest Belongs to a Zone
-- ============================================================================
-- Uses the quest's UI map to match a quest to the current zone.
-- Returns true if the quest's zone matches the given zoneName.
function SS_QuestIsInZone(questId, zoneName, index)
    if not zoneName or zoneName == "" then return false end

    -- Resolve the quest's zone via its UI map and compare names (case-insensitive)
    local questZone = SS_GetQuestZoneName(questId)
    if questZone and questZone ~= "" then
        return string.lower(questZone) == string.lower(zoneName)
    end

    -- Fall back to checking whether the quest is on the current map
    local entry = SS_GetQuestLogEntryByIndex(index)
    if entry and entry.isOnMap then
        return true
    end

    return false
end

-- ============================================================================
-- Zone Name Helper
-- ============================================================================
function SS_GetQuestZoneName(questId)
    if not questId then return nil end

    local okMapID, mapID = pcall(GetQuestUiMapID, questId, false)
    if not okMapID or not mapID or mapID <= 0 then return nil end

    local okMapInfo, mapInfo = pcall(C_Map.GetMapInfo, mapID)
    if okMapInfo and mapInfo and mapInfo.name then
        return mapInfo.name
    end

    return nil
end

-- ============================================================================
-- Sorting: Recent Progress Changes
-- ============================================================================
function SS_BuildRecentCache()
    SS_QuestCache = {}
    
    local numQuests = SS_GetNumQuestLogEntries()
    
    for i = 1, numQuests do
        local entry = SS_GetQuestLogEntryByIndex(i)
        if entry and entry.questId then
            table.insert(SS_QuestCache, {
                questId = entry.questId,
                title = entry.title,
                quality = entry.quality or 0,
                isTracked = entry.isTracked,
                isComplete = entry.isComplete,
                timeCompleted = entry.timeCompleted or 0,
                timeCompletedForLog = entry.timeCompletedForLog or 0,
            })
        end
    end
    
    -- Sort by most recently changed
    table.sort(SS_QuestCache, function(a, b)
        local timeA = math.max(a.timeCompleted or 0, a.timeCompletedForLog or 0)
        local timeB = math.max(b.timeCompleted or 0, b.timeCompletedForLog or 0)
        
        if SS.Settings.sortOrder == "desc" then
            return timeA > timeB
        else
            return timeA < timeB
        end
    end)
end

-- ============================================================================
-- Sorting: Distance to Objective
-- ============================================================================
function SS_BuildDistanceCache()
    SS_QuestCache = {}
    
    local playerPos = C_Map.GetPlayerMapPosition(C_Map.GetBestMapForUnit("player"), "player")
    
    local numQuests = SS_GetNumQuestLogEntries()
    
    for i = 1, numQuests do
        local entry = SS_GetQuestLogEntryByIndex(i)
        if entry and entry.questId then
            local distance = SS_GetQuestDistance(entry.questId)
            
            table.insert(SS_QuestCache, {
                questId = entry.questId,
                title = entry.title,
                quality = entry.quality or 0,
                isTracked = entry.isTracked,
                isComplete = entry.isComplete,
                distance = distance,
            })
        end
    end
    
    -- Sort by distance
    table.sort(SS_QuestCache, function(a, b)
        if SS.Settings.sortOrder == "desc" then
            return a.distance > b.distance
        else
            return a.distance < b.distance
        end
    end)
end

-- ============================================================================
-- Get Quest Objective Distance
-- ============================================================================
-- Note: Retail WoW doesn't expose direct distance API for regular quests.
-- This is a stub that returns -1 (unknown). World quest distance can be
-- calculated via C_TaskInfo.GetActiveWorldQuests() if needed.
function SS_GetQuestDistance(questId)
    -- Stub: returns -1 (unknown distance) for all quests
    -- TODO: Implement proper distance calculation using C_TaskInfo for world quests
    return -1
end

-- ============================================================================
-- Calculate Distance Between Two Map Points
-- ============================================================================
function SS_CalculateDistance(pointA, pointB)
    local dx = pointB.x - pointA.x
    local dy = pointB.y - pointA.y
    return math.sqrt(dx * dx + dy * dy)
end

-- ============================================================================
-- Update Quest Log Sort
-- ============================================================================
function SS_UpdateQuestLogSort()
    -- Retail doesn't expose a direct "sort quest log" API,
    -- but we can rebuild the cache and update the UI
    if SS.Settings.sortMode == "recent" then
        SS_BuildRecentCache()
    else
        SS_BuildDistanceCache()
    end
    
    if SS_UIFrame and SS_UIFrame:IsVisible() then
        SS_UpdateQuestList()
    end
end

-- ============================================================================
-- Chat Print Helper
-- ============================================================================
function SS_PrintChat(message)
    DEFAULT_CHAT_FRAME:AddMessage(message, 0.3, 0.8, 0.5)
end

-- ============================================================================
-- Get Active Quests List (for UI / external use)
-- ============================================================================
function SS_GetActiveQuests()
    -- Use cached data if available
    if #SS_QuestCache > 0 then
        return SS_QuestCache
    end
    
    -- Build fresh cache
    local quests = {}
    local numQuests = SS_GetNumQuestLogEntries()
    
    for i = 1, numQuests do
        local entry = SS_GetQuestLogEntryByIndex(i)
        if entry and entry.questId then
            table.insert(quests, {
                questId = entry.questId,
                title = entry.title,
                quality = entry.quality or 0,
                isTracked = entry.isTracked,
                isComplete = entry.isComplete,
            })
        end
    end
    
    return quests
end

-- ============================================================================
-- Auto-Accept Logic
-- ============================================================================
function SS_AutoAcceptQuest()
    if not SS.Settings.autoAccept then return end

    -- Disable if Shift is held
    if IsShiftKeyDown() then
        return
    end

    -- Ensure the quest detail panel is actively shown before attempting to accept
    if QuestFrame and QuestFrame:IsShown() and (not QuestFrameDetailPanel or QuestFrameDetailPanel:IsShown()) then
        AcceptQuest()
    end
end

-- ============================================================================
-- Toggle Functions (called by UI)
-- ============================================================================
function SS_ToggleHideAllTracked()
    SS.Settings.hideAllTracked = not SS.Settings.hideAllTracked
    
    if SS.Settings.hideAllTracked then
        SS_HideAllTracked()
        SS_PrintChat("|cff3fcf7fSimpleQuest|r: All tracked quests hidden.")
    else
        SS_ShowAllTracked()
        SS_PrintChat("|cff3fcf7fSimpleQuest|r: All tracked quests shown.")
    end
    
    -- Update UI toggle state
    if SS_CheckboxHideAll then
        SS_CheckboxHideAll:SetChecked(SS.Settings.hideAllTracked)
    end
end

function SS_ToggleAutoTrackZone()
    SS.Settings.autoTrackZone = not SS.Settings.autoTrackZone
    
    if SS.Settings.autoTrackZone then
        SS_PrintChat("|cff3fcf7fSimpleQuest|r: Auto-track zone quests ENABLED.")
        SS_AutoTrackZoneQuests(SS_GetCurrentZone())
    else
        SS_PrintChat("|cff3fcf7fSimpleQuest|r: Auto-track zone quests DISABLED.")
    end
    
    if SS_CheckboxAutoTrack then
        SS_CheckboxAutoTrack:SetChecked(SS.Settings.autoTrackZone)
    end
end

function SS_ToggleAutoAccept()
    SS.Settings.autoAccept = not SS.Settings.autoAccept
    
    if SS.Settings.autoAccept then
        SS_PrintChat("|cff3fcf7fSimpleQuest|r: Auto-accept quests ENABLED (Hold Shift to disable).")
    else
        SS_PrintChat("|cff3fcf7fSimpleQuest|r: Auto-accept quests DISABLED.")
    end
    
    if SS_CheckboxAutoAccept then
        SS_CheckboxAutoAccept:SetChecked(SS.Settings.autoAccept)
    end
end

function SS_ToggleSortMode()
    if SS.Settings.sortMode == "recent" then
        SS.Settings.sortMode = "distance"
        SS_PrintChat("|cff3fcf7fSimpleQuest|r: Sorting by distance.")
    else
        SS.Settings.sortMode = "recent"
        SS_PrintChat("|cff3fcf7fSimpleQuest|r: Sorting by recent progress.")
    end
    
    -- Refresh cache
    SS_OnQuestLogUpdate()
    
    -- Update UI
    if SS_ButtonSortMode then
        if SS.Settings.sortMode == "recent" then
            SS_ButtonSortMode:SetText("Sort: Recent")
        else
            SS_ButtonSortMode:SetText("Sort: Distance")
        end
    end
end

function SS_ToggleSortOrder()
    if SS.Settings.sortOrder == "desc" then
        SS.Settings.sortOrder = "asc"
        SS_PrintChat("|cff3fcf7fSimpleQuest|r: Sort order: Newest / Closest first.")
    else
        SS.Settings.sortOrder = "desc"
        SS_PrintChat("|cff3fcf7fSimpleQuest|r: Sort order: Oldest / Furthest first.")
    end
    
    SS_OnQuestLogUpdate()
end
