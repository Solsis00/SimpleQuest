-- SimpleQuest_Tracking: Quest tracking module
-- Handles auto-tracking, zone detection, and quest visibility

local addonName, SS = ...

-- ============================================================================
-- Zone-Based Quest Detection
-- ============================================================================

-- Cache of known zone-to-quest mappings to avoid repeated API calls
-- NOTE: This cache is currently unused; zone matching is done directly
-- via SS_QuestIsInZone using the quest's resolved zone name.
-- Keeping for potential future expansion (e.g., world quest zone mapping).
SS.ZoneQuestCache = {}
SS.ZoneCacheTimestamp = 0
SS.ZONE_CACHE_LIFETIME = 30

-- ============================================================================
-- Refresh Zone Quest Cache
-- ============================================================================
function SS_RefreshZoneCache()
    -- Zone matching is now done directly via SS_QuestIsInZone.
    -- This function is kept as a no-op stub for potential future use.
    return SS.ZoneQuestCache
end

-- ============================================================================
-- Get Quests Belonging to a Specific Zone
-- ============================================================================
function SS_GetQuestsInZone(zoneName)
    local quests = {}
    
    -- Use direct zone matching via SS_QuestIsInZone
    local numQuests = SS_GetNumQuestLogEntries()
    
    for i = 1, numQuests do
        local entry = SS_GetQuestLogEntryByIndex(i)
        if entry and entry.questId then
            -- Check zone filter via SS_QuestIsInZone
            if SS_QuestIsInZone(entry.questId, zoneName, i) then
                table.insert(quests, {questId = entry.questId, index = i})
            end
        end
    end
    
    return quests
end

-- ============================================================================
-- Smart Auto-Track: Prioritize quests by relevance
-- ============================================================================
function SS_SmartAutoTrack()
    local zoneName = SS_GetCurrentZone()
    if not zoneName or zoneName == "" then return 0 end
    
    local trackedCount = 0
    local quests = SS_GetQuestsInZone(zoneName)
    
    -- Sort by questId (ascending) as fallback
    table.sort(quests, function(a, b)
        return a.questId < b.questId
    end)
    
    for _, questEntry in ipairs(quests) do
        local questId = questEntry.questId

        -- Check the current watch state; nil means the quest is not being watched
        local isTracked = false
        local okWatch, watchType = pcall(C_QuestLog.GetQuestWatchType, questId)
        if okWatch then isTracked = (watchType ~= nil) end

        -- Only track untracked quests
        if not isTracked then
            local tracked = SS_TrackQuestByID(questId)
            if tracked then
                trackedCount = trackedCount + 1

                -- Get quest name via the supported title API (wrapped in pcall)
                local nameSuccess, questTitle = pcall(C_QuestLog.GetTitleForQuestID, questId)
                local questName = nameSuccess and questTitle or tostring(questId)
                --SS_PrintChat(string.format("|cff3fcf7fSimpleQuest|r: Tracked \"%s\" in %s.", questName, zoneName))
            end
        end
    end
    
    return trackedCount
end

-- ============================================================================
-- Untrack Quests Not in Current Zone
-- ============================================================================
function SS_UntrackOutofZoneQuests()
    local zoneName = SS_GetCurrentZone()
    if not zoneName then return 0 end
    
    local untrackedCount = 0
    local numQuests = SS_GetNumQuestLogEntries()
    
    for i = 1, numQuests do
        local entry = SS_GetQuestLogEntryByIndex(i)
        if entry and entry.questId and entry.isTracked then
            -- Check if this quest belongs to current zone (pass index)
            if not SS_QuestIsInZone(entry.questId, zoneName, i) then
                -- Only untrack if it's not a main/important quest
                -- (We leave tracked quests that span multiple zones)
                local untracked = SS_UntrackQuestByID(entry.questId)
                if untracked then
                    untrackedCount = untrackedCount + 1
                end
            end
        end
    end
    
    return untrackedCount
end

-- ============================================================================
-- Manual Track Individual Quest
-- ============================================================================
function SS_TrackQuest(questId)
    if not questId then return false end
    
    local tracked = SS_TrackQuestByID(questId)
    
    if tracked then
        -- Get quest name via the supported title API (wrapped in pcall)
        local nameSuccess, questTitle = pcall(C_QuestLog.GetTitleForQuestID, questId)
        local questName = nameSuccess and questTitle or tostring(questId)
        SS_PrintChat(string.format("|cff3fcf7fSimpleQuest|r: Manually tracked \"%s\".", questName))
    end
    
    return tracked
end

-- ============================================================================
-- Manual Untrack Individual Quest
-- ============================================================================
function SS_UntrackQuest(questId)
    if not questId then return false end
    
    -- Untrack via the quest watch API using the quest ID
    local untracked = SS_UntrackQuestByID(questId)
    
    -- Get quest name via the supported title API (wrapped in pcall)
    local nameSuccess, questTitle = pcall(C_QuestLog.GetTitleForQuestID, questId)
    local questName = nameSuccess and questTitle or tostring(questId)
    SS_PrintChat(string.format("|cff3fcf7fSimpleQuest|r: Untracked \"%s\".", questName))
    
    return untracked
end

-- ============================================================================
-- Bulk Track All Quests
-- ============================================================================
function SS_TrackAllQuests()
    local numQuests = SS_GetNumQuestLogEntries()
    local trackedCount = 0
    
    for i = 1, numQuests do
        local entry = SS_GetQuestLogEntryByIndex(i)
        if entry and entry.questId and not entry.isTracked then
            local tracked = SS_TrackQuestByID(entry.questId)
            if tracked then
                trackedCount = trackedCount + 1
            end
        end
    end
    
    if trackedCount > 0 then
        SS_PrintChat(string.format("|cff3fcf7fSimpleQuest|r: Tracked %d quest(s).", trackedCount))
    else
        SS_PrintChat("|cff3fcf7fSimpleQuest|r: No untracked quests found.")
    end
    
    return trackedCount
end

-- ============================================================================
-- Bulk Untrack All Quests
-- ============================================================================
function SS_UntrackAllQuests()
    local numQuests = SS_GetNumQuestLogEntries()
    local untrackedCount = 0
    
    for i = 1, numQuests do
        local entry = SS_GetQuestLogEntryByIndex(i)
        if entry and entry.questId and entry.isTracked then
            local untracked = SS_UntrackQuestByID(entry.questId)
            if untracked then
                untrackedCount = untrackedCount + 1
            end
        end
    end
    
    if untrackedCount > 0 then
        SS_PrintChat(string.format("|cff3fcf7fSimpleQuest|r: Untracked %d quest(s).", untrackedCount))
    else
        SS_PrintChat("|cff3fcf7fSimpleQuest|r: No tracked quests found.")
    end
    
    return untrackedCount
end

-- ============================================================================
-- Chat Command Handler
-- ============================================================================
SS.ChatCommandFrame = SS.Frame or CreateFrame("Frame")

function SS_HandleChatCommand(argString)
    local args = {}
    for arg in string.gmatch(argString or "", "[^%s]+") do
        table.insert(args, arg)
    end
    
    local command = args[1] and string.lower(args[1]) or ""
    
    if command == "hide" or command == "untrack" then
        SS_HideAllTracked()
        SS.Settings.hideAllTracked = true
    elseif command == "show" or command == "track" then
        SS_ShowAllTracked()
        SS.Settings.hideAllTracked = false
    elseif command == "autotrack" or command == "at" then
        SS.Settings.autoTrackZone = not SS.Settings.autoTrackZone
        if SS.Settings.autoTrackZone then
            SS_SmartAutoTrack()
            SS_PrintChat("|cff3fcf7fSimpleQuest|r: Auto-track ENABLED.")
        else
            SS_PrintChat("|cff3fcf7fSimpleQuest|r: Auto-track DISABLED.")
        end
    elseif command == "turnin" or command == "ti" then
        SS_ToggleAutoTurnIn()
    elseif command == "sort" then
        SS_ToggleSortMode()
    elseif command == "status" or command == "info" then
        SS_PrintStatus()
    elseif command == "help" then
        SS_PrintHelp()
    else
        SS_PrintHelp()
    end
end

function SS_PrintStatus()
    SS_PrintChat("|cff3fcf7fSimpleQuest|r: --- Status ---")
    SS_PrintChat(string.format("  Hide All Tracked: %s", SS.Settings.hideAllTracked and "ON" or "OFF"))
    SS_PrintChat(string.format("  Auto-Track Zone: %s", SS.Settings.autoTrackZone and "ON" or "OFF"))
    SS_PrintChat(string.format("  Auto Turn-In: %s", SS.Settings.autoTurnIn and "ON" or "OFF"))
    SS_PrintChat(string.format("  Sort Mode: %s", SS.Settings.sortMode))
    SS_PrintChat(string.format("  Sort Order: %s", SS.Settings.sortOrder))
    
    local zoneName = SS_GetCurrentZone()
    SS_PrintChat(string.format("  Current Zone: %s", zoneName or "Unknown"))
    
    local numQuests = SS_GetNumQuestLogEntries()
    local trackedCount = 0
    for i = 1, numQuests do
        local entry = SS_GetQuestLogEntryByIndex(i)
        if entry and entry.isTracked then trackedCount = trackedCount + 1 end
    end
    SS_PrintChat(string.format("  Active Quests: %d (Tracked: %d)", numQuests, trackedCount))
end

function SS_PrintHelp()
    SS_PrintChat("|cff3fcf7fSimpleQuest|r: Commands:")
    SS_PrintChat("  /sq help          - Show this help")
    SS_PrintChat("  /sq status        - Show addon status")
    SS_PrintChat("  /sq hide          - Hide all tracked quests")
    SS_PrintChat("  /sq show          - Show all tracked quests")
    SS_PrintChat("  /sq autotrack     - Toggle auto-track zone quests")
    SS_PrintChat("  /sq turnin        - Toggle auto turn-in of completed quests")
    SS_PrintChat("  /sq sort          - Toggle sort mode (recent/distance)")
end
